import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../configs/ranking_config.dart';
import '../models/ai_analysis_response.dart';
import '../models/date_phrase_config.dart';
import '../models/search_synonym.dart';
import '../models/smart_category.dart';
import 'app_check_http_helper.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'sync_version_utils.dart';

/// תוצאת התאמה מקומית — לשימוש AiAutoTaggerService
class AiAnalysisResult {
  final String category;
  final List<String> tags;

  const AiAnalysisResult({required this.category, required this.tags});
}

/// שירות מאוחד — synonyms + categories מ-smart_categories. מקור אמת יחיד: /api/dictionary/updates.
class CategoryManagerService {
  static CategoryManagerService? _instance;
  static CategoryManagerService get instance {
    _instance ??= CategoryManagerService._();
    return _instance!;
  }

  CategoryManagerService._();

  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app';
  static const String _dictionaryUpdatesPath = '/api/dictionary/updates';
  static const String _dictionaryVersionPath = '/api/dictionary/version';
  static const String _smartCategoriesPath = '/api/smart-categories';
  static const String _prefsKeyLastSyncTimestamp = 'dictionary_last_sync_timestamp';
  static const Duration _timeout = Duration(seconds: 15);

  final Map<String, List<String>> _synonymCache = {};
  final Map<String, SmartCategory> _categories = {};
  List<DatePhraseConfig> _datePhrases = [];
  Map<String, List<String>> _fileTypeKeywords = {};
  bool _initialized = false;

  Future<String?> get lastSyncTimestamp =>
      SyncVersionUtils.getTimestamp(_prefsKeyLastSyncTimestamp);

  Map<String, SmartCategory> get categories => Map.unmodifiable(_categories);
  List<DatePhraseConfig> get datePhrases => List.unmodifiable(_datePhrases);
  Map<String, List<String>> get fileTypeKeywords => Map.unmodifiable(_fileTypeKeywords);
  Map<String, List<String>> get synonymMap => Map.unmodifiable(_synonymCache);
  Set<String> get dictionary {
    final set = <String>{};
    for (final k in _synonymCache.keys) {
      set.add(k);
      set.add(k.toLowerCase());
    }
    for (final k in _fileTypeKeywords.keys) {
      set.add(k);
      set.add(k.toLowerCase());
    }
    return set;
  }

  /// מאתחל: assets → sync מ-dictionary/updates (synonyms + categories).
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _loadFromAssets();
      await _loadSynonymsFromIsarToCache();
      await syncWithServer();
      _initialized = true;
      appLog('CategoryManager: loaded synonyms=${_synonymCache.length} categories=${_categories.length}');
    } catch (e) {
      appLog('CategoryManager: initialize failed - $e, using fallbacks');
      _initFallbacks();
      _initialized = true;
    }
  }

  Future<void> _loadFromAssets() async {
    final json = await rootBundle.loadString('assets/smart_search_config.json');
    final map = jsonDecode(json) as Map<String, dynamic>;
    await _mergeSynonymsFromAssets(map);
    _loadDatePhrasesAndFileTypes(map);
  }

  Future<void> _mergeSynonymsFromAssets(Map<String, dynamic> map) async {
    final synonymsRaw = map['synonyms'] as Map<String, dynamic>? ?? {};
    final synonyms = <String, List<String>>{};
    for (final e in synonymsRaw.entries) {
      synonyms[e.key.toString().trim()] =
          (e.value as List<dynamic>).map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList();
    }
    await _mergeSynonymsToIsarAndCache(_normalizeSynonyms(synonyms));
  }

  void _loadDatePhrasesAndFileTypes(Map<String, dynamic> map) {
    final raw = map['datePhrases'] as List<dynamic>? ?? [];
    _datePhrases = raw.map((e) => DatePhraseConfig.fromJson(e as Map<String, dynamic>)).toList();
    final fileRaw = map['fileTypeKeywords'] as Map<String, dynamic>? ?? {};
    _fileTypeKeywords = <String, List<String>>{};
    for (final e in fileRaw.entries) {
      _fileTypeKeywords[e.key.toString()] =
          (e.value as List<dynamic>).map((x) => x.toString()).toList();
    }
  }

  void _initFallbacks() {
    _datePhrases = [
      DatePhraseConfig(pattern: r'\b(today|היום)\b', type: 'today'),
      DatePhraseConfig(pattern: r'\b(yesterday|אתמול)\b', type: 'yesterday'),
      DatePhraseConfig(pattern: r'\b(last\s+week|previous\s+week|שבוע\s+שעבר)\b', days: 7),
      DatePhraseConfig(pattern: r'\b(last\s+month|previous\s+month|חודש\s+שעבר)\b', days: 30),
      DatePhraseConfig(pattern: r'\b(last\s+year|שנה\s+שעברה)\b', days: 365),
    ];
    _fileTypeKeywords = {
      'תמונות': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'images': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'pdf': ['pdf'],
      'מסמך': ['pdf', 'doc', 'docx', 'txt'],
    };
  }

  Future<void> _loadSynonymsFromIsarToCache() async {
    try {
      final isar = DatabaseService.instance.isar;
      final q = isar.searchSynonyms.buildQuery<SearchSynonym>();
      final all = q.findAll();
      q.close();
      for (final s in all) {
        if (s.term.isEmpty || s.expansions.isEmpty) continue;
        final terms = s.expansions;
        _synonymCache[_keyFor(s.term)] = terms;
        _synonymCache[s.term] = terms;
      }
    } catch (e) {
      appLog('CategoryManager: _loadSynonymsFromIsarToCache failed - $e');
    }
  }

  Future<void> syncWithServer() async {
    try {
      final version = await SyncVersionUtils.fetchVersion('$_baseUrl$_dictionaryVersionPath');
      final localTs = await lastSyncTimestamp;
      if (version != null && localTs != null && localTs.isNotEmpty &&
          version.lastModified != null && version.lastModified == localTs) {
        appLog('[SYNC] No new updates. Using local cache.');
        return;
      }
      final data = await _fetchUpdates(since: localTs);
      if (data == null) return;
      await _applyUpdates(data);
      if (version?.lastModified != null) {
        await SyncVersionUtils.saveTimestamp(_prefsKeyLastSyncTimestamp, version!.lastModified!);
      }
    } catch (e) {
      appLog('CategoryManager: syncWithServer error - $e');
    }
  }

  Future<dynamic> _fetchUpdates({String? since}) async {
    final uri = since != null
        ? Uri.parse('$_baseUrl$_dictionaryUpdatesPath').replace(queryParameters: {'since': since})
        : Uri.parse('$_baseUrl$_dictionaryUpdatesPath');
    final headers = await AppCheckHttpHelper.getBackendHeaders();
    final r = await http.get(uri, headers: headers).timeout(_timeout);
    if (r.statusCode != 200) return null;
    return jsonDecode(r.body);
  }

  Future<void> _applyUpdates(dynamic data) async {
    if (data is! Map<String, dynamic>) return;
    final synonyms = _extractSynonyms(data);
    if (synonyms.isNotEmpty) {
      await _mergeSynonymsToIsarAndCache(synonyms);
    }
    _applyRankingConfig(data['rankingConfig']);
    _applySmartCategories(data['smartCategories']);
  }

  Map<String, List<String>> _extractSynonyms(Map<String, dynamic> map) {
    final synonymsRaw = map['synonyms'];
    if (synonymsRaw is List) return _parseSynonymsFromList(synonymsRaw);
    if (synonymsRaw is Map<String, dynamic>) {
      final synonyms = <String, List<String>>{};
      for (final e in synonymsRaw.entries) {
        final vals = e.value;
        synonyms[e.key.toString().trim()] = vals is List
            ? vals.map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList()
            : [vals.toString().trim()];
      }
      return _normalizeSynonyms(synonyms);
    }
    return {};
  }

  static (String, String)? _parseSynonymItem(dynamic item) {
    if (item is! Map<String, dynamic>) return null;
    final cat = item['category']?.toString().trim() ?? '';
    final term = item['term']?.toString().trim() ?? '';
    return (cat.isEmpty || term.isEmpty) ? null : (cat, term);
  }

  Map<String, List<String>> _parseSynonymsFromList(List list) {
    final synonyms = <String, List<String>>{};
    for (final item in list) {
      final parsed = _parseSynonymItem(item);
      if (parsed == null) continue;
      synonyms.putIfAbsent(parsed.$1, () => []).add(parsed.$2);
    }
    return _normalizeSynonyms(synonyms);
  }

  Map<String, List<String>> _normalizeSynonyms(Map<String, List<String>> synonyms) {
    final toMerge = <String, String>{};
    for (final k in synonyms.keys) {
      if (!k.contains(' / ')) continue;
      final short = k.split(' / ').first.trim();
      if (short.isEmpty || short == k) continue;
      if (synonyms.containsKey(short)) toMerge[short] = k;
    }
    for (final e in toMerge.entries) {
      final terms = synonyms.remove(e.key) ?? [];
      synonyms.putIfAbsent(e.value, () => []).addAll(terms);
    }
    final out = <String, List<String>>{};
    for (final e in synonyms.entries) {
      final terms = e.value.toSet().where((t) => t.isNotEmpty).toList();
      if (terms.isNotEmpty) out[e.key] = terms;
    }
    return out;
  }

  void _applyRankingConfig(dynamic raw) {
    if (raw is Map<String, dynamic>) {
      RankingConfig.instance.applyFromServer(raw);
    }
  }

  void _applySmartCategories(dynamic raw) {
    if (raw is! List) return;
    _categories.clear();
    for (final item in raw) {
      if (item is! Map<String, dynamic>) continue;
      final cat = SmartCategory.fromJson(item);
      if (cat.id.isNotEmpty) _categories[cat.id] = cat;
    }
  }

  Future<void> _mergeSynonymsToIsarAndCache(Map<String, List<String>> synonyms) async {
    final list = <SearchSynonym>[];
    for (final entry in synonyms.entries) {
      final category = entry.key;
      final terms = entry.value;
      if (category.isEmpty || terms.isEmpty) continue;
      for (final term in terms) {
        if (term.isEmpty) continue;
        list.add(SearchSynonym.fromMap(term, terms, category));
        _synonymCache[_keyFor(term)] = terms;
        _synonymCache[term] = terms;
      }
    }
    if (list.isEmpty) return;
    final isar = DatabaseService.instance.isar;
    isar.write((isar) => isar.searchSynonyms.putAll(list));
  }

  String _keyFor(String term) =>
      term.contains(RegExp(r'[a-zA-Z]')) ? term.toLowerCase() : term;

  /// טוען קטגוריות — קורא ל-initialize (סנכרון אחד).
  Future<void> loadCategories() async => await initialize();

  Future<bool> checkVersionAndSyncIfNeeded({bool silent = false}) async {
    try {
      invalidate();
      await syncWithServer();
      return true;
    } catch (e) {
      appLog('CategoryManager: checkVersionAndSyncIfNeeded error - $e');
      return false;
    }
  }

  void invalidate() {
    _categories.clear();
  }

  Future<List<String>> expandTerm(String term) async {
    await initialize();
    final key = _keyFor(term);
    return _synonymCache[key] ?? _synonymCache[term] ?? [];
  }

  List<String> getEnrichedTags(String categoryId) {
    final cat = _categories[categoryId];
    if (cat == null) return [categoryId];
    final out = <String>{categoryId};
    out.addAll(cat.labels.values.where((s) => s.isNotEmpty));
    out.addAll(cat.synonyms);
    return out.toList();
  }

  static bool _termMatchesWholeWord(String text, String term, {bool caseSensitive = false}) {
    if (term.isEmpty || text.isEmpty) return false;
    final escaped = RegExp.escape(term);
    return RegExp('(^|[^\\w])$escaped([^\\w]|\$)', unicode: true, caseSensitive: caseSensitive).hasMatch(text);
  }

  static bool _termMatches(String text, String term, bool useWholeWord) {
    final lower = text.toLowerCase();
    final t = term.toLowerCase();
    if (useWholeWord) return _termMatchesWholeWord(lower, t);
    return lower.contains(t);
  }

  /// Waterfall: synonyms → categories (keywords) → categories (regex).
  Future<AiAnalysisResult?> identifyCategory(String rawText) async {
    if (rawText.isEmpty) return null;
    await initialize();
    final lower = rawText.toLowerCase();

    for (final entry in _synonymCache.entries) {
      final term = entry.key;
      final expansions = entry.value;
      if (term.length < 2) continue;
      final shortTerm = term.length < 4;
      if (_termMatches(lower, term, shortTerm)) {
        return AiAnalysisResult(category: term, tags: expansions.take(5).toList());
      }
      for (final exp in expansions) {
        if (exp.length < 2) continue;
        if (_termMatches(lower, exp, exp.length < 4)) {
          return AiAnalysisResult(category: term, tags: expansions.take(5).toList());
        }
      }
    }

    for (final entry in _categories.entries) {
      for (final syn in entry.value.synonyms) {
        if (syn.length < 2) continue;
        if (_termMatches(lower, syn, syn.length < 4)) {
          return AiAnalysisResult(category: entry.key, tags: getEnrichedTags(entry.key));
        }
      }
    }

    for (final entry in _categories.entries) {
      for (final pattern in entry.value.regexPatterns) {
        if (pattern.isEmpty) continue;
        try {
          if (RegExp(pattern).hasMatch(rawText)) {
            return AiAnalysisResult(category: entry.key, tags: getEnrichedTags(entry.key));
          }
        } catch (_) {}
      }
    }
    return null;
  }

  Future<int> approveSuggestions(String categoryId, List<AiSuggestion> suggestions) async {
    if (categoryId.isEmpty || suggestions.isEmpty) return 0;
    final keywords = <String>{};
    final regexPatterns = <String>[];
    for (final s in suggestions) {
      for (final kw in s.suggestedKeywords) {
        final t = kw.trim();
        if (t.isNotEmpty) keywords.add(t);
      }
      final r = s.suggestedRegex?.trim();
      if (r != null && r.isNotEmpty && isRegexValid(r) && !regexPatterns.contains(r)) regexPatterns.add(r);
    }
    if (keywords.isEmpty && regexPatterns.isEmpty) return 0;
    try {
      final uri = Uri.parse('$_baseUrl$_smartCategoriesPath/${Uri.encodeComponent(categoryId)}/rules/batch');
      final headers = await AppCheckHttpHelper.getBackendHeaders(
        existing: {'Content-Type': 'application/json'},
      );
      final response = await http.post(uri, headers: headers, body: jsonEncode({
        'keywords': keywords.toList(),
        'regexPatterns': regexPatterns,
      })).timeout(_timeout);
      if (response.statusCode != 200) return 0;
      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final added = (decoded?['added'] as num?)?.toInt() ?? 0;
      if (added > 0) invalidate();
      return added;
    } catch (e) {
      appLog('CategoryManager: approveSuggestions error - $e');
      return 0;
    }
  }

  Future<bool> addRuleToCategory(String categoryId, String type, String rule) async {
    if (categoryId.isEmpty || rule.trim().isEmpty) return false;
    try {
      final uri = Uri.parse('$_baseUrl$_smartCategoriesPath/$categoryId/rules');
      final headers = await AppCheckHttpHelper.getBackendHeaders(
        existing: {'Content-Type': 'application/json'},
      );
      final response = await http.post(uri, headers: headers, body: jsonEncode({'type': type, 'value': rule.trim()})).timeout(_timeout);
      if (response.statusCode == 200) {
        final cat = _categories[categoryId];
        if (cat != null) {
          if (type.toLowerCase() == 'regex') {
            _categories[categoryId] = SmartCategory(id: cat.id, labels: cat.labels, synonyms: cat.synonyms, regexPatterns: [...cat.regexPatterns, rule.trim()]);
          } else {
            _categories[categoryId] = SmartCategory(id: cat.id, labels: cat.labels, synonyms: [...cat.synonyms, rule.trim()], regexPatterns: cat.regexPatterns);
          }
        }
        return true;
      }
      return false;
    } catch (e) {
      appLog('CategoryManager: addRuleToCategory error - $e');
      return false;
    }
  }

  Future<bool> hasKeywordInCategory(String categoryId, String keyword) async {
    await initialize();
    final cat = _categories[categoryId];
    if (cat == null) return false;
    final k = keyword.trim().toLowerCase();
    return cat.synonyms.any((s) => s.trim().toLowerCase() == k);
  }

  Future<bool> hasRegexInCategory(String categoryId, String pattern) async {
    await initialize();
    final cat = _categories[categoryId];
    if (cat == null) return false;
    return cat.regexPatterns.any((r) => r.trim() == pattern.trim());
  }

  static bool isRegexValid(String pattern) {
    try {
      RegExp(pattern);
      return true;
    } catch (_) {
      return false;
    }
  }
}
