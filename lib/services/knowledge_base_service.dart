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
  static const Duration _syncTimeout = Duration(seconds: 10);

  /// datePhrases ו-fileTypeKeywords — לחשיפה ל-SmartSearchParser
  List<DatePhraseConfig> get datePhrases => List.unmodifiable(_datePhrases);
  Map<String, List<String>> get fileTypeKeywords =>
      Map.unmodifiable(_fileTypeKeywords);

  /// מאתחל: Dynamic Sync — קודם טוען מ-Isar (persistence offline), אחר כך assets, ואז סינכרון עם השרת
  /// סדר הפעולות: 1) טעינת synonyms שמורים מ-Isar  2) smart_search_config.json  3) syncDictionaryWithServer
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      // שלב 1: טעינה מ-Isar — מונחים שסונכרנו מהשרת בעבר, זמינים גם offline בהפעלה הבאה
      await _loadSynonymsFromIsarToCache();

      // שלב 2: טעינת smart_search_config.json — synonyms, datePhrases, fileTypeKeywords
      final json =
          await rootBundle.loadString('assets/smart_search_config.json');
      final map = jsonDecode(json) as Map<String, dynamic>;

      final synonymsRaw = map['synonyms'] as Map<String, dynamic>? ?? {};
      final synonyms = <String, List<String>>{};
      for (final e in synonymsRaw.entries) {
        synonyms[e.key.toString().trim()] =
            (e.value as List<dynamic>).map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList();
      }
      await _mergeSynonymsToIsarAndCache(_normalizeSynonyms(synonyms));

      // DatePhrases ו-FileTypeKeywords — לזיכרון
      final datePhrasesRaw = map['datePhrases'] as List<dynamic>? ?? [];
      _datePhrases = datePhrasesRaw
          .map((e) => DatePhraseConfig.fromJson(e as Map<String, dynamic>))
          .toList();

      final fileTypeRaw = map['fileTypeKeywords'] as Map<String, dynamic>? ?? {};
      _fileTypeKeywords = <String, List<String>>{};
      for (final e in fileTypeRaw.entries) {
        _fileTypeKeywords[e.key.toString()] =
            (e.value as List<dynamic>).map((x) => x.toString()).toList();
      }

      // שלב 3: סינכרון דינמי — מונחים חדשים מהשרת מתווספים ל-cache ול-Isar
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

  /// סינכרון מילון עם השרת — קורא GET api/dictionary/updates וממזג מונחים חדשים ל-cache ול-Isar
  /// התשובה עשויה להיות Map או List — בדיקה דפנסיבית למניעת type `List<dynamic>` is not a subtype of `Map<String, dynamic>?`
  Future<void> syncDictionaryWithServer() async {
    try {
      final uri = Uri.parse('$_baseUrl$_dictionaryUpdatesPath');
      final headers = await AppCheckHttpHelper.getBackendHeaders();
      final response = await http.get(uri, headers: headers).timeout(_syncTimeout);

      if (response.statusCode != 200) {
        appLog('KnowledgeBase: syncDictionary failed ${response.statusCode}');
        return;
      }

      final data = jsonDecode(response.body);

      // זרימה: תשובה List = רשימת synonyms; תשובה Map = synonyms + rankingConfig
      if (data is List) {
        // השרת החזיר רשימה — מטפלים כ-synonyms (למשל [{term, category}, ...])
        final synonyms = _parseSynonymsFromList(data);
        final recordCount = synonyms.values.fold<int>(0, (s, terms) => s + terms.length);
        if (kDebugMode) appLog('SYNC: Received $recordCount records from API (List format)');
        if (synonyms.isNotEmpty) {
          await _mergeSynonymsToIsarAndCache(synonyms);
          appLog('KnowledgeBase: syncDictionary merged ${synonyms.length} categories from List response');
        }
        return;
      }

      if (data is! Map<String, dynamic>) {
        appLog('KnowledgeBase: syncDictionary — Unexpected format: ${data.runtimeType}');
        return;
      }

      final map = data;

      // מיזוג synonyms — חילוץ בטוח עם as Map<String, dynamic>? למניעת cast error
      final synonymsRaw = map['synonyms'];
      final synonyms = <String, List<String>>{};
      if (synonymsRaw is Map<String, dynamic>) {
        for (final e in synonymsRaw.entries) {
          final vals = e.value;
          synonyms[e.key.toString().trim()] = vals is List
              ? vals.map((x) => x.toString().trim()).where((s) => s.isNotEmpty).toList()
              : [vals.toString().trim()];
        }
        final normalized = _normalizeSynonyms(synonyms);
        synonyms..clear()..addAll(normalized);
      } else if (synonymsRaw is List) {
        synonyms.addAll(_parseSynonymsFromList(synonymsRaw));
      }
      if (synonyms.isNotEmpty) {
        final recordCount = synonyms.values.fold<int>(0, (s, terms) => s + terms.length);
        if (kDebugMode) appLog('SYNC: Received $recordCount records from API (Map format)');
        await _mergeSynonymsToIsarAndCache(synonyms);
        appLog('KnowledgeBase: syncDictionary merged ${synonyms.length} categories from server');
      }

      // עדכון rankingConfig — בדיקת טיפוס לפני cast (מניעת List/Map cast error)
      final rankingRaw = map['rankingConfig'];
      final rankingData = rankingRaw is Map<String, dynamic> ? rankingRaw : null;
      if (rankingData != null) {
        RankingConfig.instance.applyFromServer(rankingData);
        appLog('KnowledgeBase: syncDictionary applied rankingConfig from server');
      }
    } catch (e) {
      appLog('KnowledgeBase: syncDictionaryWithServer error - $e');
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
