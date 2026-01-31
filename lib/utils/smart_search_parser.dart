import '../models/date_phrase_config.dart';
import '../services/knowledge_base_service.dart';

/// תוצאת פירוק חיפוש — מילות מקור, מונחים מורחבים, שנה מפורשת, תאריכים וסוגי קבצים
class SearchIntent {
  /// המילים בדיוק כפי שהמשתמש הקליד (ללא שנה שהוסרה)
  final List<String> rawTerms;
  /// רשימה מורחבת: שורשים + מילים נרדפות (ללא שנה)
  final List<String> terms;
  /// שנה בת 4 ספרות אם נמצאה — הוסרה מ־terms
  final String? explicitYear;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  /// true רק כאשר תאריכים מ־ביטויים יחסיים (today, last week) — לא משנה בשאילתה
  final bool useDateRangeFilter;
  final List<String> fileTypes;

  const SearchIntent({
    this.rawTerms = const [],
    this.terms = const [],
    this.explicitYear,
    this.dateFrom,
    this.dateTo,
    this.useDateRangeFilter = false,
    this.fileTypes = const [],
  });

  bool get hasContent =>
      terms.isNotEmpty ||
      rawTerms.isNotEmpty ||
      fileTypes.isNotEmpty ||
      dateFrom != null ||
      dateTo != null ||
      explicitYear != null;

  @override
  String toString() =>
      'SearchIntent(rawTerms: $rawTerms, terms: $terms, explicitYear: $explicitYear, '
      'dateFrom: $dateFrom, dateTo: $dateTo, fileTypes: $fileTypes)';
}

/// מפרק שאילתת חיפוש טבעית ל־SearchIntent (מילים נרדפות, תאריכים, נורמליזציה)
class SmartSearchParser {
  SmartSearchParser._();

  /// שירות קונפיגורציה — מקור אמת יחיד: smart_search_config.json (מוזרק באתחול)
  static KnowledgeBaseService? knowledgeBaseService;

  static List<DatePhraseConfig> get _datePhrases =>
      knowledgeBaseService?.datePhrases ?? _builtInDatePhrases;
  static Map<String, List<String>> get _fileTypeKeywords =>
      knowledgeBaseService?.fileTypeKeywords ?? _builtInFileTypeKeywords;
  static Map<String, List<String>> get _synonyms =>
      knowledgeBaseService?.synonymMap ?? _builtInSynonyms;
  static Set<String> get _dictionary =>
      knowledgeBaseService?.dictionary ?? _builtInDictionary;

  static const Map<String, List<String>> _builtInSynonyms = {
    'invoice': ['invoice', 'bill', 'receipt', 'חשבונית', 'קבלה'],
    'חשבונית': ['invoice', 'bill', 'receipt', 'חשבונית', 'קבלה'],
    'bill': ['invoice', 'bill', 'receipt', 'חשבונית', 'קבלה'],
    'receipt': ['invoice', 'receipt', 'קבלה', 'חשבונית'],
    'קבלה': ['receipt', 'invoice', 'קבלה', 'חשבונית', 'bill'],
    'check': ['check', 'cheque', 'צ\'ק', 'צק', 'טפס'],
    'cheque': ['check', 'cheque', 'צ\'ק', 'צק'],
    'צ\'ק': ['check', 'cheque', 'צ\'ק', 'צק'],
    'צק': ['check', 'cheque', 'צ\'ק', 'צק'],
    'id': ['id', 'identity', 'תעודת זהות', 'ת.ז', 'תז', 'תעודה'],
    'identity': ['id', 'identity', 'תעודת זהות', 'ת.ז', 'תז'],
    'תעודת': ['id', 'תעודת זהות', 'ת.ז', 'תז', 'תעודה'],
    'ת.ז': ['id', 'תעודת זהות', 'ת.ז', 'תז'],
    'תז': ['id', 'תעודת זהות', 'ת.ז', 'תז'],
    'תעודה': ['id', 'תעודה', 'תעודת זהות', 'ת.ז'],
    'salary': ['salary', 'payslip', 'תלוש', 'משכורת', 'pay'],
    'משכורת': ['salary', 'payslip', 'תלוש', 'משכורת'],
    'payslip': ['salary', 'payslip', 'תלוש', 'משכורת'],
    'תלוש': ['payslip', 'משכורת', 'salary', 'תלוש'],
    'pay': ['salary', 'pay', 'משכורת', 'תשלום'],
    'תשלום': ['payment', 'pay', 'תשלום', 'חיוב'],
    'payment': ['payment', 'תשלום', 'pay'],
    'document': ['document', 'doc', 'מסמך', 'file'],
    'מסמך': ['document', 'מסמך', 'doc', 'file'],
    'contract': ['contract', 'חוזה', 'הסכם', 'agreement'],
    'חוזה': ['contract', 'חוזה', 'הסכם', 'agreement'],
    'הסכם': ['agreement', 'contract', 'חוזה', 'הסכם'],
    'agreement': ['agreement', 'contract', 'חוזה', 'הסכם'],
    'insurance': ['insurance', 'ביטוח', 'פוליסה', 'policy'],
    'ביטוח': ['insurance', 'ביטוח', 'פוליסה', 'policy'],
    'policy': ['policy', 'ביטוח', 'פוליסה', 'insurance'],
    'פוליסה': ['policy', 'ביטוח', 'פוליסה', 'insurance'],
  };

  static Set<String> get _builtInDictionary {
    final set = <String>{};
    for (final k in _builtInSynonyms.keys) {
      set.add(k);
      set.add(k.toLowerCase());
    }
    for (final k in _builtInFileTypeKeywords.keys) {
      set.add(k);
      set.add(k.toLowerCase());
    }
    return set;
  }

  /// ברירת מחדל — רק כש-KnowledgeBaseService לא זמין
  static final List<DatePhraseConfig> _builtInDatePhrases = [
    DatePhraseConfig(pattern: r'\b(today|היום)\b', type: 'today'),
    DatePhraseConfig(pattern: r'\b(yesterday|אתמול)\b', type: 'yesterday'),
    DatePhraseConfig(
        pattern: r'\b(last\s+week|previous\s+week|שבוע\s+שעבר|השבוע\s+שעבר|לפני\s+שבוע)\b',
        days: 7),
    DatePhraseConfig(
        pattern: r'\b(last\s+month|previous\s+month|חודש\s+שעבר|בחודש\s+שעבר|לפני\s+חודש)\b',
        days: 30),
    DatePhraseConfig(pattern: r'\b(last\s+year|שנה\s+שעברה|בשנה\s+שעברה)\b', days: 365),
    DatePhraseConfig(pattern: r'\b(2\s*weeks|שבועיים|שתי?\s*שבועות?)\b', days: 14),
  ];

  /// שנים מפורשות 4 ספרות (למשל 1990–2039) — מוצא, שומר כ־explicitYear, מוסר מהשאילתה
  static final RegExp _yearRegex = RegExp(r'\b(19[5-9]\d|20[0-3]\d)\b');

  static const Map<String, List<String>> _builtInFileTypeKeywords = {
    'תמונות': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
    'images': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
    'pdf': ['pdf'],
    'מסמך': ['pdf', 'doc', 'docx', 'txt'],
  };

  /// שלב א': תאריכים ושנים — מחזיר (dateFrom, dateTo, explicitYear, useDateRangeFilter, remaining)
  /// שנה מפורשת: useDateRangeFilter=false (לא מסננים לפי תאריך ב-Isar)
  /// ביטויים יחסיים: useDateRangeFilter=true
  static (DateTime?, DateTime?, String?, bool, String) _parseDatesAndYear(String query) {
    String remaining = query.trim();
    DateTime? dateFrom;
    DateTime? dateTo;
    String? explicitYear;
    bool useDateRangeFilter = false;
    final now = DateTime.now();

    // קודם: זיהוי שנה מפורשת (4 ספרות) — לא משמש לסינון תאריכים ב-Isar
    final yearMatch = _yearRegex.firstMatch(remaining);
    if (yearMatch != null) {
      final yearStr = yearMatch.group(0)!;
      final year = int.tryParse(yearStr);
      if (year != null) {
        explicitYear = yearStr;
        dateFrom = DateTime(year, 1, 1);
        dateTo = DateTime(year, 12, 31, 23, 59, 59);
        remaining = remaining.replaceAll(_yearRegex, ' ').trim();
        remaining = _collapseSpaces(remaining);
        return (dateFrom, dateTo, explicitYear, false, remaining); // לא useDateRangeFilter
      }
    }

    // אחרת: ביטויים יחסיים (today, yesterday, last week וכו') — משמש לסינון
    for (final phrase in _datePhrases) {
      final regex = RegExp(phrase.pattern, caseSensitive: false, unicode: true);
      final match = regex.firstMatch(remaining);
      if (match != null) {
        useDateRangeFilter = true;
        final range = phrase.getRange(now);
        if (dateFrom == null || range.$1.isBefore(dateFrom)) dateFrom = range.$1;
        if (dateTo == null || range.$2.isAfter(dateTo)) dateTo = range.$2;
        remaining = remaining.replaceAll(regex, ' ').trim();
      }
    }
    remaining = _collapseSpaces(remaining);
    return (dateFrom, dateTo, explicitYear, useDateRangeFilter, remaining);
  }

  /// שלב ב': הסרת תחיליות עבריות — ה, ו, מ, ב, כ, ל, כש (מנסה כש לפני כ)
  static String _stripHebrewPrefixes(String word) {
    if (word.isEmpty) return word;
    String rest = word.trim();
    const prefixes = ['כש', 'ה', 'ו', 'מ', 'ב', 'כ', 'ל'];
    bool changed = true;
    while (changed && rest.isNotEmpty) {
      changed = false;
      for (final p in prefixes) {
        if (rest.startsWith(p) && rest.length > p.length) {
          rest = rest.substring(p.length);
          changed = true;
          break;
        }
      }
    }
    return rest;
  }

  /// מיפוי מיקומים (עברית↔אנגלית) — שלב ג': מילים נרדפות + לוקיישנים
  static const Map<String, List<String>> _builtInLocations = {
    'תאילנד': ['Thailand', 'תאילנד'],
    'Thailand': ['Thailand', 'תאילנד'],
    'אירופה': ['Europe', 'אירופה'],
    'Europe': ['Europe', 'אירופה'],
  };

  static Map<String, List<String>> get _allSynonyms {
    final out = Map<String, List<String>>.from(_synonyms);
    for (final e in _builtInLocations.entries) {
      out.putIfAbsent(e.key, () => e.value);
    }
    return out;
  }

  /// מחזיר מפתח להשוואה (לטינית: lowercase; עברית:-is)
  static String _keyFor(String word) =>
      word.contains(RegExp(r'[a-zA-Z]')) ? word.toLowerCase() : word;

  /// מפרק שאילתה גולמית ל־SearchIntent (אסינכרוני) — משתמש ב-KnowledgeBaseService.expandTerm
  static Future<SearchIntent> parseAsync(String query) async {
    if (query.trim().isEmpty) return const SearchIntent();

    final (dateFrom, dateTo, explicitYear, useDateRangeFilter, remaining) = _parseDatesAndYear(query);
    final normalized = _normalizeText(remaining);
    final rawTerms = normalized
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    final termsSet = <String>{};
    final fileTypesSet = <String>{};
    final dict = _dictionary;
    final synonymsMap = _allSynonyms;
    final kb = knowledgeBaseService;

    for (final word in rawTerms) {
      final key = _keyFor(word);

      // סוגי קבצים — תמיד לפי מילת מפתח
      final extList = _fileTypeKeywords[key];
      if (extList != null) {
        fileTypesSet.addAll(extList.map((e) => e.toLowerCase()));
      }

      // מילים נרדפות — Isar אם זמין, אחרת config
      if (dict.contains(key)) {
        termsSet.add(word);
        if (kb != null) {
          final expansions = await kb.expandTerm(word);
          for (final s in expansions) {
            if (s.isNotEmpty) {
              termsSet.add(s.contains(RegExp(r'[a-zA-Z]')) ? s.toLowerCase() : s);
            }
          }
        } else {
          final syns = synonymsMap[key] ?? synonymsMap[word];
          if (syns != null) {
            for (final s in syns) {
              if (s.isNotEmpty) {
                termsSet.add(s.contains(RegExp(r'[a-zA-Z]')) ? s.toLowerCase() : s);
              }
            }
          }
        }
        continue;
      }

      final root = _stripHebrewPrefixes(word);
      if (root.isEmpty) {
        termsSet.add(word);
        continue;
      }
      final rootKey = _keyFor(root);
      if (dict.contains(rootKey)) {
        termsSet.add(root);
        if (kb != null) {
          final expansions = await kb.expandTerm(root);
          for (final s in expansions) {
            if (s.isNotEmpty) {
              termsSet.add(s.contains(RegExp(r'[a-zA-Z]')) ? s.toLowerCase() : s);
            }
          }
        } else {
          final syns = synonymsMap[rootKey] ?? synonymsMap[root];
          if (syns != null) {
            for (final s in syns) {
              if (s.isNotEmpty) {
                termsSet.add(s.contains(RegExp(r'[a-zA-Z]')) ? s.toLowerCase() : s);
              }
            }
          }
        }
      } else {
        termsSet.add(word);
      }
    }

    return SearchIntent(
      rawTerms: rawTerms,
      terms: termsSet.toList(),
      explicitYear: explicitYear,
      dateFrom: dateFrom,
      dateTo: dateTo,
      useDateRangeFilter: useDateRangeFilter,
      fileTypes: fileTypesSet.toList(),
    );
  }

  /// מפרק שאילתה גולמית ל־SearchIntent (שלבים א'–ג') — סינכרוני
  static SearchIntent parse(String query) {
    if (query.trim().isEmpty) {
      return const SearchIntent();
    }

    // שלב א': תאריכים ושנים — explicitYear מוצא ומוסר מהשאילתה
    final (dateFrom, dateTo, explicitYear, useDateRangeFilter, remaining) = _parseDatesAndYear(query);
    final normalized = _normalizeText(remaining);
    final rawTerms = normalized
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    final termsSet = <String>{};
    final fileTypesSet = <String>{};
    final dict = _dictionary;
    final synonymsMap = _allSynonyms;

    for (final word in rawTerms) {
      final key = _keyFor(word);

      // סוגי קבצים — תמיד לפי מילת מפתח
      final extList = _fileTypeKeywords[key];
      if (extList != null) {
        fileTypesSet.addAll(extList.map((e) => e.toLowerCase()));
      }

      // שלב ב' + ג': במילון → הוסף מילה + נרדפות; אחרת נסה שורש עברי
      if (dict.contains(key)) {
        termsSet.add(word);
        final syns = synonymsMap[key] ?? synonymsMap[word];
        if (syns != null) {
          for (final s in syns) {
            if (s.isNotEmpty) termsSet.add(s.contains(RegExp(r'[a-zA-Z]')) ? s.toLowerCase() : s);
          }
        }
        continue;
      }

      final root = _stripHebrewPrefixes(word);
      if (root.isEmpty) {
        termsSet.add(word);
        continue;
      }
      final rootKey = _keyFor(root);
      if (dict.contains(rootKey)) {
        termsSet.add(root);
        final syns = synonymsMap[rootKey] ?? synonymsMap[root];
        if (syns != null) {
          for (final s in syns) {
            if (s.isNotEmpty) termsSet.add(s.contains(RegExp(r'[a-zA-Z]')) ? s.toLowerCase() : s);
          }
        }
      } else {
        termsSet.add(word);
      }
    }

    return SearchIntent(
      rawTerms: rawTerms,
      terms: termsSet.toList(),
      explicitYear: explicitYear,
      dateFrom: dateFrom,
      dateTo: dateTo,
      useDateRangeFilter: useDateRangeFilter,
      fileTypes: fileTypesSet.toList(),
    );
  }

  static String _normalizeText(String text) {
    final withoutPunctuation =
        text.replaceAll(RegExp(r'[^\w\s\u0590-\u05FF\-]+', unicode: true), ' ');
    return _collapseSpaces(withoutPunctuation.trim());
  }

  static String _collapseSpaces(String s) {
    return s.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
