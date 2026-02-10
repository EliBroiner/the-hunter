/// קטגוריה חכמה — מפתח, תרגומים, מילים נרדפות וחוקי Regex.
/// תואם למסמכי Firestore ב־smart_categories (נטען דרך API).
class SmartCategory {
  final String id;
  final Map<String, String> labels;
  final List<String> synonyms;
  final List<String> regexPatterns;

  const SmartCategory({
    required this.id,
    required this.labels,
    required this.synonyms,
    required this.regexPatterns,
  });

  /// בנייה מתשובת API (שדות באנגלית: key, display_names, keywords, regex_patterns).
  factory SmartCategory.fromJson(Map<String, dynamic> json) {
    final key = json['key'] as String? ?? '';
    final displayNames = json['displayNames'] as Map<String, dynamic>? ?? json['display_names'] as Map<String, dynamic>? ?? {};
    final labels = <String, String>{};
    for (final e in displayNames.entries) {
      labels[e.key.toString()] = (e.value ?? '').toString();
    }
    final keywords = _stringList(json['keywords']);
    final regex = _stringList(json['regexPatterns'] ?? json['regex_patterns']);
    return SmartCategory(
      id: key,
      labels: labels,
      synonyms: keywords,
      regexPatterns: regex,
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
