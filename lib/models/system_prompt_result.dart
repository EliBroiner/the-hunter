/// תוצאת getLatestPrompt — טקסט, גרסה, האם fallback מוטבע.
class SystemPromptResult {
  final String text;
  final String version;
  final bool isFallback;

  const SystemPromptResult({
    required this.text,
    required this.version,
    this.isFallback = false,
  });

  factory SystemPromptResult.fromJson(Map<String, dynamic> json) {
    return SystemPromptResult(
      text: json['text'] as String? ?? '',
      version: json['version'] as String? ?? '',
      isFallback: json['isFallback'] as bool? ?? false,
    );
  }
}
