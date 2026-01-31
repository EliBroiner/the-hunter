import 'dart:convert';
import 'package:flutter/services.dart';
import '../models/date_phrase_config.dart';
import '../models/search_synonym.dart';
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

  /// datePhrases ו-fileTypeKeywords — לחשיפה ל-SmartSearchParser
  List<DatePhraseConfig> get datePhrases => List.unmodifiable(_datePhrases);
  Map<String, List<String>> get fileTypeKeywords =>
      Map.unmodifiable(_fileTypeKeywords);

  /// מאתחל: טוען smart_search_config.json — synonyms ל-Isar + cache, dates + fileTypes בזיכרון
  Future<void> initialize() async {
    if (_initialized) return;

    try {
      final json = await rootBundle.loadString('assets/smart_search_config.json');
      final map = jsonDecode(json) as Map<String, dynamic>;

      // Synonyms — טעינה ל-Isar ול-cache
      final synonymsRaw = map['synonyms'] as Map<String, dynamic>? ?? {};
      final synonyms = <String, List<String>>{};
      for (final e in synonymsRaw.entries) {
        synonyms[e.key.toString()] =
            (e.value as List<dynamic>).map((x) => x.toString()).toList();
      }
      await _loadSynonymsToIsarAndCache(synonyms);

      // DatePhrases — לזיכרון
      final datePhrasesRaw = map['datePhrases'] as List<dynamic>? ?? [];
      _datePhrases = datePhrasesRaw
          .map((e) => DatePhraseConfig.fromJson(e as Map<String, dynamic>))
          .toList();

      // FileTypeKeywords — לזיכרון
      final fileTypeRaw = map['fileTypeKeywords'] as Map<String, dynamic>? ?? {};
      _fileTypeKeywords = <String, List<String>>{};
      for (final e in fileTypeRaw.entries) {
        _fileTypeKeywords[e.key.toString()] =
            (e.value as List<dynamic>).map((x) => x.toString()).toList();
      }

      _initialized = true;
      appLog('KnowledgeBase: loaded from smart_search_config.json');
    } catch (e) {
      appLog('KnowledgeBase: initialize failed - $e, using fallbacks');
      _initFallbacks();
      _initialized = true;
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

  /// טוען synonyms ל-Isar ול-cache — עבור כל (category, terms) שומר חיפוש לפי כל term
  Future<void> _loadSynonymsToIsarAndCache(Map<String, List<String>> synonyms) async {
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
    if (isar.searchSynonyms.count() == 0) {
      isar.write((isar) {
        isar.searchSynonyms.putAll(list);
      });
      appLog('KnowledgeBase: loaded ${list.length} synonym entries into Isar');
    }
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

  /// בודק אם הטקסט מכיל מילת מפתח — לשימוש AiAutoTaggerService
  Future<AiAnalysisResult?> findMatchingCategory(String text) async {
    await initialize();

    if (text.isEmpty) return null;
    final lower = text.toLowerCase();

    for (final entry in _synonymCache.entries) {
      final term = entry.key;
      final expansions = entry.value;
      if (term.length < 2) continue;
      if (lower.contains(term)) {
        appLog('KnowledgeBase: local hit for "$term"');
        return AiAnalysisResult(category: term, tags: expansions.take(5).toList());
      }
      for (final exp in expansions) {
        if (exp.length < 2) continue;
        if (lower.contains(exp.toLowerCase())) {
          appLog('KnowledgeBase: local hit for "$term" (expansion: $exp)');
          return AiAnalysisResult(category: term, tags: expansions.take(5).toList());
        }
      }
    }
    return null;
  }
}
