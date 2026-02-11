/// מודל פרומפט מערכת — תואם ל-Backend SystemPrompt.
/// שדות: id, content, version, isActive, targetFeature (feature), createdAt, activatedAt
class SystemPrompt {
  final int id;
  final String content;
  final String version;
  final bool isActive;
  final String targetFeature;
  final DateTime? createdAt;
  final DateTime? activatedAt;

  const SystemPrompt({
    required this.id,
    required this.content,
    required this.version,
    required this.isActive,
    required this.targetFeature,
    this.createdAt,
    this.activatedAt,
  });

  factory SystemPrompt.fromJson(Map<String, dynamic> json) {
    return SystemPrompt(
      id: json['id'] as int? ?? 0,
      content: json['content'] as String? ?? '',
      version: json['version'] as String? ?? '',
      isActive: json['isActive'] as bool? ?? false,
      targetFeature: json['feature'] as String? ?? json['targetFeature'] as String? ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : null,
      activatedAt: json['activatedAt'] != null
          ? DateTime.tryParse(json['activatedAt'].toString())
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'content': content,
    'version': version,
    'isActive': isActive,
    'feature': targetFeature,
    'createdAt': createdAt?.toIso8601String(),
    'activatedAt': activatedAt?.toIso8601String(),
  };

  SystemPrompt copyWith({
    int? id,
    String? content,
    String? version,
    bool? isActive,
    String? targetFeature,
    DateTime? createdAt,
    DateTime? activatedAt,
  }) =>
      SystemPrompt(
        id: id ?? this.id,
        content: content ?? this.content,
        version: version ?? this.version,
        isActive: isActive ?? this.isActive,
        targetFeature: targetFeature ?? this.targetFeature,
        createdAt: createdAt ?? this.createdAt,
        activatedAt: activatedAt ?? this.activatedAt,
      );

  @override
  String toString() =>
      'SystemPrompt(id: $id, feature: $targetFeature, version: $version, isActive: $isActive)';
}
