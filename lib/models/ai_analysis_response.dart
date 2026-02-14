/// הצעת למידה מ-Gemini — מילים או Regex לזיהוי מקומי.
class AiSuggestion {
  final String suggestedCategory;
  final List<String> suggestedKeywords;
  final String? suggestedRegex;
  final double confidence;

  const AiSuggestion({
    required this.suggestedCategory,
    required this.suggestedKeywords,
    this.suggestedRegex,
    this.confidence = 0,
  });

  /// true אם יש מילות מפתח או regex — חוקים טכניים לזיהוי מקומי
  bool get hasTechnicalRules =>
      suggestedKeywords.isNotEmpty || (suggestedRegex != null && suggestedRegex!.trim().isNotEmpty);

  static AiSuggestion? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final cat = json['suggested_category'] ?? json['suggestedCategory'] ?? '';
    final kw = json['suggested_keywords'] ?? json['suggestedKeywords'];
    final list = kw is List ? kw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList() : <String>[];
    final regex = json['suggested_regex'] ?? json['suggestedRegex'];
    final conf = (json['confidence'] is num) ? (json['confidence'] as num).toDouble() : 0.0;
    return AiSuggestion(
      suggestedCategory: cat.toString(),
      suggestedKeywords: list,
      suggestedRegex: regex?.toString(),
      confidence: conf,
    );
  }
}

/// מטא־דאטה מחולצת — שמות, מזהים, מיקומים
class DocumentMetadata {
  final List<String> names;
  final List<String> ids;
  final List<String> locations;

  const DocumentMetadata({
    this.names = const [],
    this.ids = const [],
    this.locations = const [],
  });

  static DocumentMetadata? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final names = _parseList(json['names']);
    final ids = _parseList(json['ids']);
    final locations = _parseList(json['locations']);
    if (names.isEmpty && ids.isEmpty && locations.isEmpty) return null;
    return DocumentMetadata(names: names, ids: ids, locations: locations);
  }

  static List<String> _parseList(dynamic v) {
    if (v is! List) return [];
    return v.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
  }
}

/// תוצאת ניתוח מסמך מהשרת — קטגוריה, תגיות והצעות למידה.
class DocumentAnalysisResult {
  final String category;
  final List<String> tags;
  final List<AiSuggestion> suggestions;
  final bool requiresHighResOcr;
  final DocumentMetadata? metadata;

  const DocumentAnalysisResult({
    required this.category,
    required this.tags,
    this.suggestions = const [],
    this.requiresHighResOcr = false,
    this.metadata,
  });
}
