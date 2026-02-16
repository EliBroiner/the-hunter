import 'package:flutter/material.dart';

import '../models/file_metadata.dart';

/// אייקון לפי סיומת קובץ — שימוש חוזר במסכים
IconData getFileIcon(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'heic':
      return Icons.image;
    case 'pdf':
      return Icons.picture_as_pdf;
    case 'doc':
    case 'docx':
      return Icons.description;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Icons.table_chart;
    case 'txt':
      return Icons.text_snippet;
    case 'mp4':
    case 'mov':
    case 'avi':
      return Icons.video_file;
    case 'mp3':
    case 'wav':
    case 'aac':
      return Icons.audio_file;
    default:
      return Icons.insert_drive_file;
  }
}

/// צבע לפי סיומת קובץ — שימוש חוזר במסכים
Color getFileColor(String extension) {
  switch (extension.toLowerCase()) {
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'bmp':
    case 'heic':
    case 'heif':
      return Colors.purple;
    case 'mp4':
    case 'mov':
    case 'avi':
    case 'mkv':
    case 'webm':
    case '3gp':
      return Colors.pink;
    case 'pdf':
      return Colors.red;
    case 'doc':
    case 'docx':
      return Colors.blue;
    case 'xls':
    case 'xlsx':
    case 'csv':
      return Colors.green;
    case 'txt':
    case 'rtf':
      return Colors.orange;
    case 'mp3':
    case 'wav':
    case 'm4a':
    case 'ogg':
    case 'aac':
      return Colors.teal;
    default:
      return Colors.grey;
  }
}

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
