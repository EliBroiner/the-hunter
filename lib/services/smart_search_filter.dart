import '../models/file_metadata.dart';
import '../models/search_intent.dart';
import 'log_service.dart';

/// מסנן קבצים חכם על בסיס SearchIntent מ-Gemini
class SmartSearchFilter {
  SmartSearchFilter._();

  /// מסנן רשימת קבצים לפי SearchIntent
  static List<FileMetadata> filterFiles(
    List<FileMetadata> files,
    SearchIntent intent,
  ) {
    appLog('SmartFilter: Starting with ${files.length} files');
    appLog('SmartFilter: Intent - Terms: ${intent.terms}, FileTypes: ${intent.fileTypes}, DateRange: ${intent.dateRange}');

    var results = List<FileMetadata>.from(files);

    // שלב 1: סינון לפי סוגי קבצים (אם צוינו)
    if (intent.fileTypes.isNotEmpty) {
      results = _filterByFileTypes(results, intent.fileTypes);
      appLog('SmartFilter: After fileTypes filter: ${results.length} files');
    }

    // שלב 2: סינון לפי טווח תאריכים (אם צוין)
    if (intent.dateRange != null) {
      results = _filterByDateRange(results, intent.dateRange!);
      appLog('SmartFilter: After dateRange filter: ${results.length} files');
    }

    // שלב 3: סינון לפי מילות מפתח (Terms)
    if (intent.terms.isNotEmpty) {
      results = _filterByTerms(results, intent.terms);
      appLog('SmartFilter: After terms filter: ${results.length} files');
    }

    // מיון לפי תאריך שינוי (החדשים קודם)
    results.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    appLog('SmartFilter: Final result: ${results.length} files');
    return results;
  }

  /// סינון לפי סוגי קבצים
  static List<FileMetadata> _filterByFileTypes(
    List<FileMetadata> files,
    List<String> fileTypes,
  ) {
    // נרמול הסיומות (הסרת נקודה אם יש, lowercase)
    final normalizedTypes = fileTypes
        .map((t) => t.toLowerCase().replaceAll('.', ''))
        .toSet();

    return files.where((file) {
      final ext = file.extension.toLowerCase();
      return normalizedTypes.contains(ext);
    }).toList();
  }

  /// סינון לפי טווח תאריכים
  static List<FileMetadata> _filterByDateRange(
    List<FileMetadata> files,
    DateRange dateRange,
  ) {
    final startDate = dateRange.startDate;
    final endDate = dateRange.endDate;

    return files.where((file) {
      final fileDate = file.lastModified;

      // בדיקת תאריך התחלה
      if (startDate != null) {
        final startOfDay = DateTime(startDate.year, startDate.month, startDate.day);
        if (fileDate.isBefore(startOfDay)) {
          return false;
        }
      }

      // בדיקת תאריך סיום
      if (endDate != null) {
        final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        if (fileDate.isAfter(endOfDay)) {
          return false;
        }
      }

      return true;
    }).toList();
  }

  /// סינון לפי מילות מפתח (חיפוש בשם ובטקסט המחולץ)
  static List<FileMetadata> _filterByTerms(
    List<FileMetadata> files,
    List<String> terms,
  ) {
    if (terms.isEmpty) return files;

    // נרמול המילים לחיפוש
    final normalizedTerms = terms.map((t) => t.toLowerCase()).toList();

    return files.where((file) {
      final fileName = file.name.toLowerCase();
      final extractedText = (file.extractedText ?? '').toLowerCase();

      // חיפוש התאמה לפחות לאחת מהמילים
      return normalizedTerms.any((term) =>
          fileName.contains(term) || extractedText.contains(term));
    }).toList();
  }

  /// חיפוש פשוט (fallback) - מבוסס טקסט בלבד
  static List<FileMetadata> simpleSearch(
    List<FileMetadata> files,
    String query,
  ) {
    if (query.trim().isEmpty) {
      return files..sort((a, b) => b.lastModified.compareTo(a.lastModified));
    }

    final lowerQuery = query.toLowerCase();

    final results = files.where((file) =>
        file.name.toLowerCase().contains(lowerQuery) ||
        (file.extractedText?.toLowerCase().contains(lowerQuery) ?? false)
    ).toList();

    results.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return results;
  }
}
