/// קטגוריה חכמה — מפתח, תרגומים, מילים נרדפות וחוקי Regex.
/// תואם למסמכי Firestore ב־smart_categories (נטען דרך API).
class SmartCategory {
  final String id;
  final Map<String, String> labels;
  final List<String> synonyms;
  final List<String> regexPatterns;
  /// דירוג לכל keyword — ברירת מחדל medium.
  final Map<String, String> keywordRanks;

  const SmartCategory({
    required this.id,
    required this.labels,
    required this.synonyms,
    required this.regexPatterns,
    this.keywordRanks = const {},
  });

  /// המרה ל־Map — לשימוש CategoryManagerService._mergeCategoriesIntoCache
  Map<String, dynamic> toJson() => {
        'key': id,
        'displayNames': labels,
        'keywords': synonyms,
        'regexPatterns': regexPatterns,
        'keywordRanks': keywordRanks,
      };

  /// בנייה מתשובת API (שדות באנגלית: key, display_names, keywords, regex_patterns, keyword_ranks).
  factory SmartCategory.fromJson(Map<String, dynamic> json) {
    final key = json['key'] as String? ?? '';
    final displayNames = json['displayNames'] as Map<String, dynamic>? ?? json['display_names'] as Map<String, dynamic>? ?? {};
    final labels = <String, String>{};
    for (final e in displayNames.entries) {
      labels[e.key.toString()] = (e.value ?? '').toString();
    }
    final keywords = _stringList(json['keywords']);
    final regex = _stringList(json['regexPatterns'] ?? json['regex_patterns']);
    final ranksRaw = json['keywordRanks'] as Map<String, dynamic>? ?? json['keyword_ranks'] as Map<String, dynamic>? ?? {};
    final keywordRanks = <String, String>{};
    for (final e in ranksRaw.entries) {
      keywordRanks[e.key.toString()] = (e.value ?? 'medium').toString().toLowerCase();
    }
    return SmartCategory(
      id: key,
      labels: labels,
      synonyms: keywords,
      regexPatterns: regex,
      keywordRanks: keywordRanks,
    );
  }

  static List<String> _stringList(dynamic value) {
    if (value == null) return [];
    if (value is List) {
      return value.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
    }
    return [];
  }
}
