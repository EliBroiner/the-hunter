import '../models/file_metadata.dart';

/// סיומת וסוג קובץ — בדיקה נייטרלית (case-insensitive, תמיכה בסיומת כפולה)
class FileTypeHelper {
  FileTypeHelper._();

  /// סיומת אפקטיבית מהשם — החלק אחרי הנקודה האחרונה (למשל file.pdf.pdf → pdf)
  static String effectiveExtensionFromName(String fileName) {
    if (fileName.isEmpty) return '';
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  /// האם הקובץ נחשב PDF — לפי שם וסיומת, case-insensitive
  static bool isPDF(FileMetadata file) {
    final extFromName = effectiveExtensionFromName(file.name);
    final extFromField = (file.extension).toLowerCase();
    return extFromName == 'pdf' || extFromField == 'pdf';
  }

  /// סיומות תמונה לטאב Images
  static const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'];

  /// האם הקובץ נחשב תמונה
  static bool isImage(FileMetadata file) {
    final ext = effectiveExtensionFromName(file.name);
    if (ext.isNotEmpty) return imageExtensions.contains(ext);
    return imageExtensions.contains(file.extension.toLowerCase());
  }
}
