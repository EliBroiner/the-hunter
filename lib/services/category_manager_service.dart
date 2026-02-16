import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../configs/ranking_config.dart';
import '../models/ai_analysis_response.dart';
import '../models/date_phrase_config.dart';
import '../models/rule_rank.dart';
import '../models/search_synonym.dart';
import '../models/smart_category.dart';
import 'app_check_http_helper.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'sync_version_utils.dart';

/// מועמד התאמה — ל־knockout logic
class _MatchCandidate {
  final String category;
  final List<String> tags;
  final RuleRank rank;

  _MatchCandidate(this.category, this.tags, this.rank);
}

/// תוצאת התאמה מקומית — לשימוש AiAutoTaggerService
class AiAnalysisResult {
  final String category;
  final List<String> tags;
  /// true = רק Weak matches — לשלוח ל-AI במקום להשתמש בתוצאה
  final bool isAmbiguous;

  const AiAnalysisResult({required this.category, required this.tags, this.isAmbiguous = false});
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
  static const String prefsKeyLastSyncTimestamp = 'dictionary_last_sync_timestamp';
  static const String _prefsKeyLastSyncTimestamp = prefsKeyLastSyncTimestamp;
  static const Duration _timeout = Duration(seconds: 15);

  final Map<String, List<String>> _synonymCache = {};
  final Map<String, String> _termToCategory = {}; // term/expansion -> category (מילון מקומי)
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

  /// סף מינימלי — אם Isar מתחת לזה, טוענים מחדש מ-assets.
  static const int _minDefaultSynonymsCount = 50;

  /// טוען מילון התחלתי מ-assets. Merge, don't Overwrite. נקרא בכל הפעלה.
  Future<void> loadInitialDictionary() async {
    await _loadFromAssets();
    final count = DatabaseService.instance.isar.searchSynonyms.count();
    if (count > 0) {
      appLog('[RECOVERY] Successfully merged default dictionary into Isar.');
    }
  }

  /// משלב מחדש defaults מ-assets (ללא מחיקה). לשימוש לפני Force Sync.
  Future<void> reLoadDefaults() async {
    await _loadFromAssets();
    final count = DatabaseService.instance.isar.searchSynonyms.count();
    appLog('[RECOVERY] Successfully merged default dictionary into Isar. ($count synonyms)');
    await _loadSynonymsFromIsarToCache();
  }

  /// מאתחל: assets → sync מ-dictionary/updates (synonyms + categories).
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await loadInitialDictionary();
      await _loadSynonymsFromIsarToCache();
      final isarCount = DatabaseService.instance.isar.searchSynonyms.count();
      if (isarCount == 0 || isarCount < _minDefaultSynonymsCount) {
        appLog('[RECOVERY] Isar has $isarCount items (< $_minDefaultSynonymsCount) — forcing reload of defaults.');
        await _loadFromAssets();
        appLog('[RECOVERY] Successfully merged default dictionary into Isar.');
        await _loadSynonymsFromIsarToCache();
      }
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
    await _applySmartCategoriesFromAssets(map);
    _loadDatePhrasesAndFileTypes(map);
  }

  /// טוען smartCategories מ-assets (מבנה: category -> [{term, rank}]) — fallback לפני sync.
  Future<void> _applySmartCategoriesFromAssets(Map<String, dynamic> map) async {
    final raw = map['smartCategories'] as Map<String, dynamic>? ?? {};
    for (final entry in raw.entries) {
      final catId = entry.key.toString().trim();
      if (catId.isEmpty) continue;
      final items = entry.value as List<dynamic>? ?? [];
      final synonyms = <String>[];
      final keywordRanks = <String, String>{};
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final term = (item['term'] ?? '').toString().trim();
        if (term.isEmpty) continue;
        synonyms.add(term);
        final rank = (item['rank'] ?? 'medium').toString().toLowerCase();
        keywordRanks[term] = rank;
      }
      if (synonyms.isEmpty) continue;
      _categories[catId] = SmartCategory(
        id: catId,
        labels: {},
        synonyms: synonyms,
        regexPatterns: [],
        keywordRanks: keywordRanks,
      );
    }
    if (_categories.isNotEmpty) {
      await _mergeSmartCategoriesKeywordsIntoSearchSynonyms();
      appLog('[SYNC] Updated Seed and Local Assets with Ranked Dictionary Logic.');
    }
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
      _termToCategory.clear();
      for (final s in all) {
        if (s.term.isEmpty || s.expansions.isEmpty) continue;
        final terms = s.expansions;
        final cat = (s.category ?? '').trim();
        _synonymCache[_keyFor(s.term)] = terms;
        _synonymCache[s.term] = terms;
        if (cat.isNotEmpty) {
          _termToCategory[_keyFor(s.term)] = cat;
          _termToCategory[s.term] = cat;
          for (final exp in terms) {
            if (exp.isNotEmpty) {
              _termToCategory[_keyFor(exp)] = cat;
              _termToCategory[exp] = cat;
            }
          }
        }
      }
    } catch (e) {
      appLog('CategoryManager: _loadSynonymsFromIsarToCache failed - $e');
    }
  }

  /// מחזיר קטגוריה אם המונח תואם term או expansions ב-Isar — לחיפוש מורחב.
  Future<String?> getCategoryForQuery(String query) async {
    await initialize();
    final key = _keyFor(query.trim());
    return _termToCategory[key] ?? _termToCategory[query.trim()];
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
      if (data == null) {
        appLog('[SYNC] Server fetch failed — keeping local/defaults.');
        return;
      }
      await _applyUpdates(data);
      if (version?.lastModified != null) {
        await SyncVersionUtils.saveTimestamp(_prefsKeyLastSyncTimestamp, version!.lastModified!);
      }
      final afterCount = DatabaseService.instance.isar.searchSynonyms.count();
      if (afterCount == 0) {
        appLog('[RECOVERY] Isar empty after sync — re-loading defaults from assets.');
        await _loadFromAssets();
        final count = DatabaseService.instance.isar.searchSynonyms.count();
        appLog('[RECOVERY] Re-loaded $count default synonyms into Isar.');
        await _loadSynonymsFromIsarToCache();
      }
    } catch (e) {
      appLog('CategoryManager: syncWithServer error - $e');
      final count = DatabaseService.instance.isar.searchSynonyms.count();
      if (count == 0) {
        appLog('[RECOVERY] Isar empty after sync error — re-loading defaults.');
        await _loadFromAssets();
        final reloaded = DatabaseService.instance.isar.searchSynonyms.count();
        appLog('[RECOVERY] Re-loaded $reloaded default synonyms into Isar.');
        await _loadSynonymsFromIsarToCache();
      }
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
    await _mergeSmartCategoriesKeywordsIntoSearchSynonyms();
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

  /// ממזג keywords מ-smartCategories ל-SearchSynonym עם rank — לתצוגה ב-Dictionary tab
  Future<void> _mergeSmartCategoriesKeywordsIntoSearchSynonyms() async {
    final toPut = <SearchSynonym>[];
    for (final entry in _categories.entries) {
      final cat = entry.value;
      for (final kw in cat.synonyms) {
        if (kw.isEmpty) continue;
        final rank = cat.keywordRanks[kw] ?? 'medium';
        toPut.add(SearchSynonym.fromMap(kw, cat.synonyms, entry.key, rank));
      }
    }
    if (toPut.isEmpty) return;
    final isar = DatabaseService.instance.isar;
    isar.write((isar) => isar.searchSynonyms.putAll(toPut));
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

  /// מנקה searchSynonyms וטוען מחדש מ-assets (smart_search_config.json). להרצה ידנית.
  Future<int> resetToDefaults() async {
    DatabaseService.instance.isar.write((isar) => isar.searchSynonyms.clear());
    await _loadFromAssets();
    final count = DatabaseService.instance.isar.searchSynonyms.count();
    await _loadSynonymsFromIsarToCache();
    appLog('[RECOVERY] Re-loaded $count default synonyms into Isar.');
    return count;
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

  /// Waterfall: categories (ranked) → synonyms → regex. Strong דורס Weak.
  Future<AiAnalysisResult?> identifyCategory(String rawText) async {
    if (rawText.isEmpty) return null;
    await initialize();
    final lower = rawText.toLowerCase();
    final matches = <_MatchCandidate>[];
    _collectCategoryMatches(lower, matches);
    if (matches.isEmpty) _collectSynonymMatches(lower, matches);
    if (matches.isEmpty) _collectRegexMatches(rawText, matches);
    return _applyKnockout(matches);
  }

  void _collectCategoryMatches(String lower, List<_MatchCandidate> matches) {
    for (final entry in _categories.entries) {
      final cat = entry.value;
      for (final syn in cat.synonyms) {
        if (syn.length < 2) continue;
        if (_termMatches(lower, syn, syn.length < 4)) {
          final rank = RuleRankExt.fromString(cat.keywordRanks[syn]);
          matches.add(_MatchCandidate(entry.key, getEnrichedTags(entry.key), rank));
        }
      }
    }
  }

  void _collectSynonymMatches(String lower, List<_MatchCandidate> matches) {
    for (final entry in _synonymCache.entries) {
      if (entry.key.length < 2) continue;
      _tryAddSynonymMatch(entry.key, entry.value, lower, matches);
    }
  }

  void _tryAddSynonymMatch(String term, List<String> expansions, String lower, List<_MatchCandidate> matches) {
    final cat = _termToCategory[_keyFor(term)] ?? _termToCategory[term] ?? term;
    final tags = expansions.take(5).toList();
    if (_termMatches(lower, term, term.length < 4)) {
      matches.add(_MatchCandidate(cat, tags, RuleRank.medium));
      return;
    }
    if (_anyExpansionMatches(expansions, lower)) matches.add(_MatchCandidate(cat, tags, RuleRank.medium));
  }

  bool _anyExpansionMatches(List<String> expansions, String lower) {
    for (final exp in expansions) {
      if (exp.length >= 2 && _termMatches(lower, exp, exp.length < 4)) return true;
    }
    return false;
  }

  void _collectRegexMatches(String rawText, List<_MatchCandidate> matches) {
    for (final entry in _categories.entries) {
      final catId = entry.key;
      if (_tryRegexMatch(rawText, entry.value.regexPatterns)) {
        matches.add(_MatchCandidate(catId, getEnrichedTags(catId), RuleRank.medium));
        return;
      }
    }
  }

  bool _tryRegexMatch(String text, List<String> patterns) {
    for (final p in patterns) {
      if (p.isEmpty) continue;
      try {
        if (RegExp(p).hasMatch(text)) return true;
      } catch (_) {}
    }
    return false;
  }

  AiAnalysisResult? _applyKnockout(List<_MatchCandidate> matches) {
    if (matches.isEmpty) return null;
    final filtered = _filterByKnockout(matches);
    if (filtered.isEmpty) return null;
    final best = _pickBestByRank(filtered);
    return AiAnalysisResult(
      category: best.category,
      tags: best.tags,
      isAmbiguous: filtered.every((m) => m.rank == RuleRank.weak),
    );
  }

  List<_MatchCandidate> _filterByKnockout(List<_MatchCandidate> matches) {
    final hasStrong = matches.any((m) => m.rank == RuleRank.strong);
    return hasStrong ? matches.where((m) => m.rank != RuleRank.weak).toList() : matches;
  }

  _MatchCandidate _pickBestByRank(List<_MatchCandidate> list) {
    const order = [RuleRank.strong, RuleRank.medium, RuleRank.weak];
    return list.reduce((a, b) => order.indexOf(a.rank) <= order.indexOf(b.rank) ? a : b);
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
            _categories[categoryId] = SmartCategory(id: cat.id, labels: cat.labels, synonyms: cat.synonyms, regexPatterns: [...cat.regexPatterns, rule.trim()], keywordRanks: cat.keywordRanks);
          } else {
            _categories[categoryId] = SmartCategory(id: cat.id, labels: cat.labels, synonyms: [...cat.synonyms, rule.trim()], regexPatterns: cat.regexPatterns, keywordRanks: cat.keywordRanks);
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
