import 'package:isar/isar.dart';

part 'file_metadata.g.dart';

/// מטא־דאטה מחולצת מ-AI — שמות, מזהים, מיקומים (לא ב-tags)
class AiMetadata {
  final List<String> names;
  final List<String> ids;
  final List<String> locations;

  const AiMetadata({
    this.names = const [],
    this.ids = const [],
    this.locations = const [],
  });

  bool get isEmpty => names.isEmpty && ids.isEmpty && locations.isEmpty;

  static AiMetadata? fromJson(Map<String, dynamic>? json) {
    if (json == null) return null;
    final names = parseStringList(json['names']);
    final ids = parseStringList(json['ids']);
    final locations = parseStringList(json['locations']);
    if (names.isEmpty && ids.isEmpty && locations.isEmpty) return null;
    return AiMetadata(names: names, ids: ids, locations: locations);
  }

  static List<String> parseStringList(dynamic v) {
    if (v is! List) return [];
    return v.map((e) => e?.toString().trim() ?? '').where((s) => s.isNotEmpty).toList();
  }

  Map<String, dynamic> toJson() => {
        'names': names,
        'ids': ids,
        'locations': locations,
      };
}

/// מודל מטאדאטה של קובץ - מאחסן מידע על קבצים שנסרקו
@Collection()
class FileMetadata {
  @Id()
  int id = 0; // יוגדר לפי hash של הנתיב לפני שמירה
  
  /// יוצר ID ייחודי מהנתיב - מבטיח שכל קובץ יקבל ID שונה
  void generateId() {
    if (id == 0 && path.isNotEmpty) {
      id = path.hashCode.abs(); // hashCode יכול להיות שלילי, אז abs()
    }
  }

  /// נתיב מלא לקובץ
  @Index()
  late String path;

  /// שם הקובץ
  @Index()
  late String name;

  /// סיומת הקובץ (ללא נקודה)
  @Index()
  late String extension;

  /// גודל הקובץ בבייטים
  late int size;

  /// תאריך שינוי אחרון
  @Index()
  late DateTime lastModified;

  /// תאריך הוספה למסד הנתונים
  late DateTime addedAt;

  /// טקסט שחולץ מהקובץ (לחיפוש מהיר)
  @Index()
  String? extractedText;

  /// תגיות לסיווג הקובץ
  List<String>? tags;

  /// קטגוריה מ-AI (מסמך, חשבונית, חוזה וכו')
  String? category;

  /// דגל: true אם נדרש OCR ברזולוציה גבוהה (טקסט מקוטע/מבנה שבור)
  bool requiresHighResOcr = false;

  /// מטא־דאטה מחולצת מ-AI — שמות, מזהים, מיקומים (לא ב-tags)
  List<String>? aiMetadataNames;
  List<String>? aiMetadataIds;
  List<String>? aiMetadataLocations;

  /// גישה נוחה ל־aiMetadata כמבנה (לא נשמר ב-Isar)
  @Ignore()
  AiMetadata? get aiMetadata {
    if (aiMetadataNames == null && aiMetadataIds == null && aiMetadataLocations == null) return null;
    return AiMetadata(
      names: aiMetadataNames ?? [],
      ids: aiMetadataIds ?? [],
      locations: aiMetadataLocations ?? [],
    );
  }

  set aiMetadata(AiMetadata? value) {
    aiMetadataNames = value == null || value.names.isEmpty ? null : value.names;
    aiMetadataIds = value == null || value.ids.isEmpty ? null : value.ids;
    aiMetadataLocations = value == null || value.locations.isEmpty ? null : value.locations;
  }

  /// האם הקובץ עבר ניתוח AI
  bool isAiAnalyzed = false;

  /// סטטוס ניתוח AI: null/ok, quotaLimit, error
  String? aiStatus;

  /// האם הקובץ עבר אינדוקס (חילוץ טקסט)
  bool isIndexed = false;

  /// האם הקובץ נמצא בענן (Google Drive)
  bool isCloud = false;

  /// מזהה הקובץ בענן (אם קיים)
  String? cloudId;

  /// קישור לצפייה בקובץ בענן
  String? cloudWebViewLink;

  /// קישור לתמונה ממוזערת בענן
  String? cloudThumbnailLink;

  /// ציון רלוונטיות (לא נשמר ב-Isar) — לבדיקת מיון
  @Ignore()
  double? debugScore;

  /// פירוט הציון (למשל "Name(100) + Loc(80)") — לא נשמר ב-Isar
  @Ignore()
  String? debugScoreBreakdown;

  /// גיבוב תוכן (אופציונלי) — לדה־דופליקציה כשמוגדר
  @Ignore()
  String? contentHash;

  FileMetadata();

  /// יוצר אובייקט FileMetadata מאובייקט File
  factory FileMetadata.fromFile({
    required String path,
    required String name,
    required int size,
    required DateTime lastModified,
  }) {
    final file = FileMetadata()
      ..path = path
      ..name = name
      ..extension = _extractExtension(name)
      ..size = size
      ..lastModified = lastModified
      ..addedAt = DateTime.now();
    return file;
  }

  /// מחלץ רשימה מ-metadata או aiMetadata ב-JSON (גיבוי, API)
  static List<String> parseMetadataList(Map<String, dynamic> json, String key) {
    final meta = json['metadata'] ?? json['aiMetadata'];
    if (meta is! Map) return [];
    return AiMetadata.parseStringList(meta[key]);
  }

  /// מחלץ סיומת מהשם
  static String _extractExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  /// מחזיר גודל קריא (KB, MB, GB)
  String get readableSize {
    if (size < 1024) return '$size B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)} KB';
    if (size < 1024 * 1024 * 1024) return '${(size / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(size / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  @override
  String toString() => 'FileMetadata(name: $name, size: $readableSize, ext: $extension)';

  /// יוצר FileMetadata מ-JSON (גיבוי, API)
  factory FileMetadata.fromJson(Map<String, dynamic> json) {
    final f = FileMetadata()
      ..path = json['path'] as String? ?? ''
      ..name = json['name'] as String? ?? ''
      ..extension = (json['extension'] as String? ?? _extractExtension(json['name'] as String? ?? ''))
      ..size = json['size'] as int? ?? 0
      ..lastModified = DateTime.tryParse(json['lastModified'] as String? ?? '') ?? DateTime.now()
      ..addedAt = DateTime.tryParse(json['addedAt'] as String? ?? '') ?? DateTime.now()
      ..extractedText = json['extractedText'] as String?
      ..tags = (json['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList()
      ..category = json['category'] as String?
      ..requiresHighResOcr = (json['requires_high_res_ocr'] ?? json['requiresHighResOcr']) == true
      ..aiMetadataNames = parseMetadataList(json, 'names')
      ..aiMetadataIds = parseMetadataList(json, 'ids')
      ..aiMetadataLocations = parseMetadataList(json, 'locations')
      ..isAiAnalyzed = json['isAiAnalyzed'] as bool? ?? false
      ..aiStatus = json['aiStatus'] as String?
      ..isIndexed = json['isIndexed'] as bool? ?? false
      ..isCloud = json['isCloud'] as bool? ?? false
      ..cloudId = json['cloudId'] as String?
      ..cloudWebViewLink = json['cloudWebViewLink'] as String?
      ..cloudThumbnailLink = json['cloudThumbnailLink'] as String?;
    if (json['id'] != null) f.id = json['id'] as int;
    return f;
  }

  /// ממיר ל-JSON (גיבוי, API)
  Map<String, dynamic> toJson() => {
        'id': id,
        'path': path,
        'name': name,
        'extension': extension,
        'size': size,
        'lastModified': lastModified.toIso8601String(),
        'addedAt': addedAt.toIso8601String(),
        'extractedText': extractedText,
        'tags': tags,
        'category': category,
        'requiresHighResOcr': requiresHighResOcr,
        if (aiMetadata != null && !aiMetadata!.isEmpty) 'metadata': aiMetadata!.toJson(),
        'isAiAnalyzed': isAiAnalyzed,
        'aiStatus': aiStatus,
        'isIndexed': isIndexed,
        'isCloud': isCloud,
        'cloudId': cloudId,
        'cloudWebViewLink': cloudWebViewLink,
        'cloudThumbnailLink': cloudThumbnailLink,
      };
}
