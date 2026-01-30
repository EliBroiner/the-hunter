import 'dart:convert';

/// תוצאת פירוק חיפוש — מילות מפתח, טווח תאריכים וסוגי קבצים
class SearchIntent {
  final List<String> terms;
  final DateTime? dateFrom;
  final DateTime? dateTo;
  final List<String> fileTypes;

  const SearchIntent({
    this.terms = const [],
    this.dateFrom,
    this.dateTo,
    this.fileTypes = const [],
  });

  bool get hasContent =>
      terms.isNotEmpty || fileTypes.isNotEmpty || dateFrom != null || dateTo != null;

  @override
  String toString() =>
      'SearchIntent(terms: $terms, dateFrom: $dateFrom, dateTo: $dateTo, fileTypes: $fileTypes)';
}

/// קונפיגורציה לחיפוש חכם — נטענת מ-JSON (או ברירת מחדל בקוד)
class SmartSearchConfig {
  final Map<String, List<String>> synonyms;
  final List<DatePhraseConfig> datePhrases;
  final Map<String, List<String>> fileTypeKeywords;

  const SmartSearchConfig({
    required this.synonyms,
    required this.datePhrases,
    required this.fileTypeKeywords,
  });

  /// בונה קונפיגורציה מ-JSON (Map או מחרוזת)
  factory SmartSearchConfig.fromJson(dynamic source) {
    final Map<String, dynamic> map = source is String
        ? (jsonDecode(source) as Map<String, dynamic>)
        : (source as Map<String, dynamic>);

    final synonymsRaw = map['synonyms'] as Map<String, dynamic>? ?? {};
    final synonyms = <String, List<String>>{};
    for (final e in synonymsRaw.entries) {
      synonyms[e.key.toString()] = (e.value as List<dynamic>).map((x) => x.toString()).toList();
    }

    final datePhrasesRaw = map['datePhrases'] as List<dynamic>? ?? [];
    final datePhrases = datePhrasesRaw
        .map((e) => DatePhraseConfig.fromJson(e as Map<String, dynamic>))
        .toList();

    final fileTypeRaw = map['fileTypeKeywords'] as Map<String, dynamic>? ?? {};
    final fileTypeKeywords = <String, List<String>>{};
    for (final e in fileTypeRaw.entries) {
      fileTypeKeywords[e.key.toString()] =
          (e.value as List<dynamic>).map((x) => x.toString()).toList();
    }

    return SmartSearchConfig(
      synonyms: synonyms,
      datePhrases: datePhrases,
      fileTypeKeywords: fileTypeKeywords,
    );
  }
}

/// הגדרת ביטוי תאריך — pattern + type (today/yesterday) או days (מספר ימים אחורה)
class DatePhraseConfig {
  final String pattern;
  final String? type;
  final int? days;

  DatePhraseConfig({required this.pattern, this.type, this.days});

  factory DatePhraseConfig.fromJson(Map<String, dynamic> json) {
    return DatePhraseConfig(
      pattern: json['pattern'] as String? ?? '',
      type: json['type'] as String?,
      days: json['days'] as int?,
    );
  }

  /// מחזיר (dateFrom, dateTo) לפי now
  (DateTime, DateTime) getRange(DateTime now) {
    if (type == 'today') {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      return (start, end);
    }
    if (type == 'yesterday') {
      final start = now.subtract(const Duration(days: 1));
      final startOfDay = DateTime(start.year, start.month, start.day);
      final end = startOfDay.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      return (startOfDay, end);
    }
    if (days != null && days! > 0) {
      final end = now;
      final start = now.subtract(Duration(days: days!));
      return (start, end);
    }
    final start = DateTime(now.year, now.month, now.day);
    return (start, start.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
  }
}

/// מפרק שאילתת חיפוש טבעית ל־SearchIntent (מילים נרדפות, תאריכים, נורמליזציה)
class SmartSearchParser {
  SmartSearchParser._();

  /// קונפיגורציה חיצונית — אם הוגדרה (מ-JSON), משתמשים בה; אחרת ברירת מחדל בקוד
  static SmartSearchConfig? config;

  /// ברירת מחדל — משמש כשלא נטען JSON
  static Map<String, List<String>> get _defaultSynonyms => _builtInSynonyms;
  static List<DatePhraseConfig> get _defaultDatePhrases => _builtInDatePhrases;
  static Map<String, List<String>> get _defaultFileTypeKeywords => _builtInFileTypeKeywords;

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

  /// רק ביטויים יחסיים מפורשים — בלי week/month/שבוע/חודש בודדים (מונע "Project week 4")
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

  /// שנים מפורשות 2020–2039 — מוצא ומחזיר טווח שנה מלאה; מוסר מהשאילתה
  static final RegExp _yearRegex = RegExp(r'\b20[1-3][0-9]\b');

  static const Map<String, List<String>> _builtInFileTypeKeywords = {
    'תמונות': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
    'תמונה': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
    'images': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
    'image': ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'],
    'pdf': ['pdf'],
    'מסמכים': ['pdf', 'doc', 'docx', 'txt'],
    'מסמך': ['pdf', 'doc', 'docx', 'txt'],
    'documents': ['pdf', 'doc', 'docx', 'txt'],
    'document': ['pdf', 'doc', 'docx', 'txt'],
  };

  static Map<String, List<String>> get _synonyms => config?.synonyms ?? _defaultSynonyms;
  static List<DatePhraseConfig> get _datePhrases => config?.datePhrases ?? _defaultDatePhrases;
  static Map<String, List<String>> get _fileTypeKeywords =>
      config?.fileTypeKeywords ?? _defaultFileTypeKeywords;

  /// מחזיר (dateFrom, dateTo, remainingQuery) — שנה מפורשת דורסת ביטויים יחסיים
  static (DateTime?, DateTime?, String) _parseDates(String query) {
    String remaining = query.trim();
    DateTime? dateFrom;
    DateTime? dateTo;
    final now = DateTime.now();

    // קודם: זיהוי שנה מפורשת (2020–2039) — דורס ביטויים יחסיים
    final yearMatch = _yearRegex.firstMatch(remaining);
    if (yearMatch != null) {
      final year = int.tryParse(yearMatch.group(0)!);
      if (year != null) {
        dateFrom = DateTime(year, 1, 1);
        dateTo = DateTime(year, 12, 31, 23, 59, 59);
        remaining = remaining.replaceAll(_yearRegex, ' ').trim();
        remaining = _collapseSpaces(remaining);
        return (dateFrom, dateTo, remaining);
      }
    }

    // אחרת: ביטויים יחסיים (today, yesterday, last week, last month וכו') — רק מפורשים
    for (final phrase in _datePhrases) {
      final regex = RegExp(phrase.pattern, caseSensitive: false, unicode: true);
      final match = regex.firstMatch(remaining);
      if (match != null) {
        final range = phrase.getRange(now);
        if (dateFrom == null || range.$1.isBefore(dateFrom)) dateFrom = range.$1;
        if (dateTo == null || range.$2.isAfter(dateTo)) dateTo = range.$2;
        remaining = remaining.replaceAll(regex, ' ').trim();
      }
    }
    remaining = _collapseSpaces(remaining);
    return (dateFrom, dateTo, remaining);
  }

  /// מפרק שאילתה גולמית ל־SearchIntent
  static SearchIntent parse(String query) {
    if (query.trim().isEmpty) {
      return const SearchIntent();
    }

    final (dateFrom, dateTo, remaining) = _parseDates(query);

    // שלב ג': נורמליזציה — הסרת פיסוק, פיצול למילים, מילים נרדפות + סוגי קבצים
    final terms = <String>{};
    final fileTypesSet = <String>{};
    final normalized = _normalizeText(remaining);
    final words = normalized.split(RegExp(r'\s+')).where((s) => s.isNotEmpty);

    for (final word in words) {
      terms.add(word);
      final key = word.toLowerCase();
      final syns = _synonyms[key];
      if (syns != null) {
        for (final s in syns) {
          if (s.isNotEmpty) terms.add(s.toLowerCase());
        }
      }
      final extList = _fileTypeKeywords[key];
      if (extList != null) {
        fileTypesSet.addAll(extList.map((e) => e.toLowerCase()));
      }
    }

    return SearchIntent(
      terms: terms.toList(),
      dateFrom: dateFrom,
      dateTo: dateTo,
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
