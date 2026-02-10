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

/// תוצאת ניתוח מסמך מהשרת — קטגוריה, תגיות והצעות למידה.
class DocumentAnalysisResult {
  final String category;
  final List<String> tags;
  final List<AiSuggestion> suggestions;

  const DocumentAnalysisResult({
    required this.category,
    required this.tags,
    this.suggestions = const [],
  });
}
