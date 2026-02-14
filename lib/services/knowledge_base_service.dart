import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../models/date_phrase_config.dart';
import '../models/search_synonym.dart';
import '../configs/ranking_config.dart';
import 'app_check_http_helper.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'sync_version_utils.dart';

/// תוצאת התאמה מקומית מ-Knowledge Base (לשימוש AiAutoTaggerService)
class AiAnalysisResult {
  final String category;
  final List<String> tags;

  const AiAnalysisResult({required this.category, required this.tags});
}

/// שירות קונפיגורציה — מקור אמת יחיד: smart_search_config.json
/// טוען synonyms, datePhrases, fileTypeKeywords — חושף ל-SmartSearchParser
class KnowledgeBaseService {
  static KnowledgeBaseService? _instance;
  static KnowledgeBaseService get instance {
    _instance ??= KnowledgeBaseService._();
    return _instance!;
  }

  KnowledgeBaseService._();

  /// Cache: term -> expansions (חיפוש לפי כל מונח מחזיר את הקטגוריה)
  final Map<String, List<String>> _synonymCache = {};
  List<DatePhraseConfig> _datePhrases = [];
  Map<String, List<String>> _fileTypeKeywords = {};
  bool _initialized = false;

  static const String _baseUrl =
      'https://the-hunter-105628026575.me-west1.run.app';
  static const String _dictionaryUpdatesPath = '/api/dictionary/updates';
  static const String _dictionaryVersionPath = '/api/dictionary/version';
  static const String _prefsKeyLastSyncTimestamp = 'dictionary_last_sync_timestamp';
  static const Duration _syncTimeout = Duration(seconds: 10);

  /// חותמת זמן של הסנכרון האחרון (ISO8601) — מ־SharedPreferences.
  Future<String?> get lastSyncTimestamp =>
      SyncVersionUtils.getTimestamp(_prefsKeyLastSyncTimestamp);

  /// datePhrases ו-fileTypeKeywords — לחשיפה ל-SmartSearchParser
  List<DatePhraseConfig> get datePhrases => List.unmodifiable(_datePhrases);
  Map<String, List<String>> get fileTypeKeywords =>
      Map.unmodifiable(_fileTypeKeywords);

  /// מאתחל: Dynamic Sync — Isar → assets → sync.
  Future<void> initialize() async {
    if (_initialized) return;
    try {
      await _loadSynonymsFromIsarToCache();
      await _loadFromAssets();
      await syncDictionaryWithServer();
      _initialized = true;
      appLog(
          'KnowledgeBase: loaded (Isar + assets + server), cache size: ${_synonymCache.length}');
    } catch (e) {
      appLog('KnowledgeBase: initialize failed - $e, using fallbacks');
      _initFallbacks();
      _initialized = true;
    }
  }

  Future<void> _loadFromAssets() async {
    final json =
        await rootBundle.loadString('assets/smart_search_config.json');
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
    _loadDatePhrases(map);
    _loadFileTypeKeywords(map);
  }

  void _loadDatePhrases(Map<String, dynamic> map) {
    final raw = map['datePhrases'] as List<dynamic>? ?? [];
    _datePhrases = raw
        .map((e) => DatePhraseConfig.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  void _loadFileTypeKeywords(Map<String, dynamic> map) {
    final raw = map['fileTypeKeywords'] as Map<String, dynamic>? ?? {};
    _fileTypeKeywords = <String, List<String>>{};
    for (final e in raw.entries) {
      _fileTypeKeywords[e.key.toString()] =
          (e.value as List<dynamic>).map((x) => x.toString()).toList();
    }
  }

  /// בודק גרסה קלה — אם השרת חדש יותר, מבצע סנכרון חכם. מחזיר true אם בוצע סנכרון.
  Future<bool> checkVersionAndSyncIfNeeded({bool silent = false}) async {
    try {
      final version = await _fetchDictionaryVersion();
      if (version == null) {
        await _syncFull();
        return true;
      }
      final local = await lastSyncTimestamp ?? '';
      if (version.lastModified != null && version.lastModified == local) {
        return false;
      }
      await syncDictionaryWithServer();
      return true;
    } catch (e) {
      appLog('KnowledgeBase: checkVersionAndSyncIfNeeded error - $e');
      return false;
    }
  }

  Future<({String version, String? lastModified})?> _fetchDictionaryVersion() =>
      SyncVersionUtils.fetchVersion('$_baseUrl$_dictionaryVersionPath');

  Future<void> _saveLastSyncTimestamp(String ts) =>
      SyncVersionUtils.saveTimestamp(_prefsKeyLastSyncTimestamp, ts);

  /// סנכרון חכם: בודק גרסה, מושך רק שינויים מאז lastSyncTimestamp.
  Future<void> syncDictionaryWithServer() async {
    try {
      final version = await _fetchDictionaryVersion();
      final localTs = await lastSyncTimestamp;
      final serverLastModified = version?.lastModified;

      if (_shouldDoIncremental(serverLastModified, localTs)) {
        await _doSmartSync(localTs!, serverLastModified!);
        return;
      }
      if (_hasLocalAndNoUpdates(serverLastModified, localTs)) {
        appLog('[SYNC] No new updates found on server. Using local cache.');
        return;
      }
      await _syncFull();
    } catch (e) {
      appLog('KnowledgeBase: syncDictionaryWithServer error - $e');
      await _syncFull();
    }
  }

  bool _shouldDoIncremental(String? server, String? local) =>
      server != null &&
      local != null &&
      local.isNotEmpty &&
      SyncVersionUtils.isServerNewer(server, local);

  bool _hasLocalAndNoUpdates(String? server, String? local) =>
      server != null && local != null && local.isNotEmpty && server == local;

  Future<void> _doSmartSync(String localTs, String serverLastModified) async {
    appLog('[SYNC] מבצע סנכרון חכם. מושך רק שינויים מאז: $localTs');
    final ok = await _syncIncremental(localTs);
    if (ok && serverLastModified.isNotEmpty) {
      await _saveLastSyncTimestamp(serverLastModified);
    } else if (!ok) {
      appLog('[SYNC] סנכרון אינקרמנטלי נכשל — מבצע סנכרון מלא.');
      await _syncFull();
    }
  }

  Future<bool> _syncIncremental(String since) async {
    try {
      final data = await _fetchUpdates(since: since);
      if (data == null) return false;
      await _applyUpdatesFromResponse(data);
      final version = await _fetchDictionaryVersion();
      if (version?.lastModified != null) {
        await _saveLastSyncTimestamp(version!.lastModified!);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _syncFull() async {
    final data = await _fetchUpdates();
    if (data == null) return;
    await _applyUpdatesFromResponse(data);
    final version = await _fetchDictionaryVersion();
    if (version?.lastModified != null) {
      await _saveLastSyncTimestamp(version!.lastModified!);
    }
  }

  Future<dynamic> _fetchUpdates({String? since}) async {
    final uri = since != null
        ? Uri.parse('$_baseUrl$_dictionaryUpdatesPath')
            .replace(queryParameters: {'since': since})
        : Uri.parse('$_baseUrl$_dictionaryUpdatesPath');
    final headers = await AppCheckHttpHelper.getBackendHeaders();
    final r = await http.get(uri, headers: headers).timeout(_syncTimeout);
    if (r.statusCode != 200) {
      appLog('KnowledgeBase: syncDictionary failed ${r.statusCode}');
      return null;
    }
    return jsonDecode(r.body);
  }

  Future<void> _applyUpdatesFromResponse(dynamic data) async {
    try {
      if (data is List) {
        await _applyListFormat(data);
        return;
      }
      if (data is! Map<String, dynamic>) {
        appLog('KnowledgeBase: syncDictionary — Unexpected format: ${data.runtimeType}');
        return;
      }
      await _applyMapFormat(data);
    } catch (e) {
      appLog('KnowledgeBase: _applyUpdatesFromResponse error - $e');
      rethrow;
    }
  }

  Future<void> _applyListFormat(List data) async {
    final synonyms = _parseSynonymsFromList(data);
    if (synonyms.isEmpty) return;
    if (kDebugMode) {
      final n = synonyms.values.fold<int>(0, (s, t) => s + t.length);
      appLog('SYNC: Received $n records from API (List format)');
    }
    await _mergeSynonymsToIsarAndCache(synonyms);
    appLog('KnowledgeBase: syncDictionary merged ${synonyms.length} categories from List response');
  }

  Future<void> _applyMapFormat(Map<String, dynamic> map) async {
    final synonyms = _extractSynonymsFromMap(map);
    if (synonyms.isNotEmpty) {
      if (kDebugMode) {
        final n = synonyms.values.fold<int>(0, (s, t) => s + t.length);
        appLog('SYNC: Received $n records from API (Map format)');
      }
      await _mergeSynonymsToIsarAndCache(synonyms);
      appLog('KnowledgeBase: syncDictionary merged ${synonyms.length} categories from server');
    }
    _applyRankingConfig(map['rankingConfig']);
  }

  Map<String, List<String>> _extractSynonymsFromMap(Map<String, dynamic> map) {
    final synonymsRaw = map['synonyms'];
    final synonyms = <String, List<String>>{};
    if (synonymsRaw is Map<String, dynamic>) {
      for (final e in synonymsRaw.entries) {
        final vals = e.value;
        synonyms[e.key.toString().trim()] = vals is List
            ? vals.map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList()
            : [vals.toString().trim()];
      }
      return _normalizeSynonyms(synonyms);
    }
    if (synonymsRaw is List) {
      return _parseSynonymsFromList(synonymsRaw);
    }
    return synonyms;
  }

  void _applyRankingConfig(dynamic rankingRaw) {
    final data = rankingRaw is Map<String, dynamic> ? rankingRaw : null;
    if (data != null) {
      RankingConfig.instance.applyFromServer(data);
      appLog('KnowledgeBase: syncDictionary applied rankingConfig from server');
    }
  }

  /// מזהה זוגות למזג — "Invoice" → "Invoice / חשבונית"
  Map<String, String> _findBilingualMergePairs(Map<String, List<String>> synonyms) {
    final toMerge = <String, String>{};
    for (final k in synonyms.keys) {
      if (!k.contains(' / ')) continue;
      final short = k.split(' / ').first.trim();
      if (short.isEmpty || short == k) continue;
      if (synonyms.containsKey(short)) toMerge[short] = k;
    }
    return toMerge;
  }

  /// ממזג קטגוריות דואליות — "Invoice" ו-"Invoice / חשבונית" → אחת
  Map<String, List<String>> _mergeBilingualCategories(Map<String, List<String>> synonyms) {
    final toMerge = _findBilingualMergePairs(synonyms);
    for (final e in toMerge.entries) {
      final terms = synonyms.remove(e.key) ?? [];
      synonyms.putIfAbsent(e.value, () => []).addAll(terms);
    }
    return synonyms;
  }

  /// מסיר כפילויות ברשימה (מנרמל לפי lowercase)
  static List<String> _deduplicateList(List<String> list) {
    final seen = <String>{};
    return list.where((t) {
      if (t.isEmpty) return false;
      final lower = t.toLowerCase();
      if (seen.contains(lower)) return false;
      seen.add(lower);
      return true;
    }).toList();
  }

  /// ממזג קטגוריות דואליות ומסיר כפילויות — שימוש חוזר
  Map<String, List<String>> _normalizeSynonyms(Map<String, List<String>> synonyms) {
    return _deduplicateSynonymTerms(_mergeBilingualCategories(synonyms));
  }

  /// מסיר כפילויות במונחים לכל קטגוריה
  Map<String, List<String>> _deduplicateSynonymTerms(Map<String, List<String>> synonyms) {
    final out = <String, List<String>>{};
    for (final e in synonyms.entries) {
      final terms = _deduplicateList(e.value);
      if (terms.isNotEmpty) out[e.key] = terms;
    }
    return out;
  }

  /// ממיר פריט בודד ל-(category, term) או null
  static (String, String)? _parseSynonymItem(dynamic item) {
    if (item is! Map<String, dynamic>) return null;
    final cat = item['category']?.toString().trim() ?? '';
    final term = item['term']?.toString().trim() ?? '';
    return (cat.isEmpty || term.isEmpty) ? null : (cat, term);
  }

  /// ממיר רשימה ל-map synonyms — ממזג קטגוריות דואליות, מסיר כפילויות
  Map<String, List<String>> _parseSynonymsFromList(List list) {
    final synonyms = <String, List<String>>{};
    for (final item in list) {
      final parsed = _parseSynonymItem(item);
      if (parsed == null) continue;
      synonyms.putIfAbsent(parsed.$1, () => []).add(parsed.$2);
    }
    return _normalizeSynonyms(synonyms);
  }

  /// טוען synonyms מ-Isar ל-cache — מאפשר שימוש במונחים שסונכרנו בעבר גם offline
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
      if (all.isNotEmpty) {
        appLog('KnowledgeBase: loaded ${all.length} synonyms from Isar (offline persistence)');
      }
    } catch (e) {
      appLog('KnowledgeBase: _loadSynonymsFromIsarToCache failed - $e');
    }
  }

  void _initFallbacks() {
    _datePhrases = [
      DatePhraseConfig(pattern: r'\b(today|היום)\b', type: 'today'),
      DatePhraseConfig(pattern: r'\b(yesterday|אתמול)\b', type: 'yesterday'),
      DatePhraseConfig(
          pattern: r'\b(last\s+week|previous\s+week|שבוע\s+שעבר)\b', days: 7),
      DatePhraseConfig(
          pattern: r'\b(last\s+month|previous\s+month|חודש\s+שעבר)\b', days: 30),
      DatePhraseConfig(pattern: r'\b(last\s+year|שנה\s+שעברה)\b', days: 365),
    ];
    _fileTypeKeywords = {
      'תמונות': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'images': ['jpg', 'jpeg', 'png', 'gif', 'webp'],
      'pdf': ['pdf'],
      'מסמך': ['pdf', 'doc', 'docx', 'txt'],
    };
  }

  /// ממזג synonyms ל-Isar ול-cache — עבור כל (category, terms) שומר חיפוש לפי כל term.
  /// Isar unique index on term — putAll מבצע upsert (מחליף קיימים, מוסיף חדשים)
  Future<void> _mergeSynonymsToIsarAndCache(
      Map<String, List<String>> synonyms) async {
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
    isar.write((isar) {
      isar.searchSynonyms.putAll(list);
    });
    appLog('KnowledgeBase: merged ${list.length} synonym entries into Isar');
  }

  String _keyFor(String term) =>
      term.contains(RegExp(r'[a-zA-Z]')) ? term.toLowerCase() : term;

  /// הרחבת מילה — מחזיר רשימת נרדפות (חיפוש לפי כל מונח מחזיר את הקטגוריה)
  Future<List<String>> expandTerm(String term) async {
    await initialize();

    final key = _keyFor(term);
    if (_synonymCache.containsKey(key)) return _synonymCache[key]!;
    if (_synonymCache.containsKey(term)) return _synonymCache[term]!;
    return [];
  }

  /// מילון — כל המונחים המוכרים (לשימוש SmartSearchParser)
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

  /// מפת synonyms לסינכרוני — לשימוש SmartSearchParser
  Map<String, List<String>> get synonymMap => Map.unmodifiable(_synonymCache);

  /// התאמת מילה שלמה — מונעת False Positive (למשל "ID" בתוך "DAVID").
  /// למונחים קצרים (< 4 תווים) חובה; למונחים ארוכים אפשר contains.
  static bool _termMatchesWholeWord(String text, String term, {bool caseSensitive = false}) {
    if (term.isEmpty || text.isEmpty) return false;
    final escaped = RegExp.escape(term);
    // גבול מילה: לא אות/ספרה לפני ואחרי (תומך Unicode — עברית)
    final re = RegExp('(^|[^\\w])$escaped([^\\w]|\$)', unicode: true, caseSensitive: caseSensitive);
    return re.hasMatch(text);
  }

  static bool _termMatches(String text, String term, bool useWholeWord) {
    final lower = text.toLowerCase();
    final t = term.toLowerCase();
    if (useWholeWord) return _termMatchesWholeWord(lower, t);
    return lower.contains(t);
  }

  /// בודק אם הטקסט מכיל מילת מפתח — לשימוש AiAutoTaggerService.
  /// מונחים קצרים (< 4 תווים): התאמת מילה שלמה בלבד (מניעת "ID" ב-"DAVID").
  Future<AiAnalysisResult?> findMatchingCategory(String text) async {
    await initialize();

    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    for (final entry in _synonymCache.entries) {
      final term = entry.key;
      final expansions = entry.value;
      if (term.length < 2) continue;
      final shortTerm = term.length < 4;
      if (_termMatches(lower, term, shortTerm)) {
        appLog('KnowledgeBase: local hit for "$term"');
        return AiAnalysisResult(category: term, tags: expansions.take(5).toList());
      }
      for (final exp in expansions) {
        if (exp.length < 2) continue;
        final shortExp = exp.length < 4;
        if (_termMatches(lower, exp, shortExp)) {
          appLog('KnowledgeBase: local hit for "$term" (expansion: $exp)');
          return AiAnalysisResult(category: term, tags: expansions.take(5).toList());
        }
      }
    }
    return null;
  }
}
