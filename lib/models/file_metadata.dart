import 'package:isar/isar.dart';

part 'file_metadata.g.dart';

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
}
