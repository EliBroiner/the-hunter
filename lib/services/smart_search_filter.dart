import '../models/file_metadata.dart';
import '../models/search_intent.dart';
import 'log_service.dart';

/// פילטר חכם - מסנן קבצים לפי SearchIntent מה-AI
class SmartSearchFilter {
  SmartSearchFilter._();

  /// מסנן רשימת קבצים לפי intent
  static List<FileMetadata> filterFiles(List<FileMetadata> files, SearchIntent intent) {
    var results = files.toList();

    // סינון לפי סוגי קבצים
    if (intent.fileTypes.isNotEmpty) {
      results = _filterByFileTypes(results, intent.fileTypes);
      appLog('SmartFilter: After fileTypes filter: ${results.length} files');
    }

    // סינון לפי טווח תאריכים
    if (intent.dateRange != null) {
      results = _filterByDateRange(results, intent.dateRange!);
      appLog('SmartFilter: After dateRange filter: ${results.length} files');
    }

    // סינון לפי מילות חיפוש
    if (intent.terms.isNotEmpty) {
      results = _filterByTerms(results, intent.terms);
      appLog('SmartFilter: After terms filter: ${results.length} files');
    }

    // מיון: התאמה בשם קודם, אח"כ לפי תאריך
    results = _sortByRelevance(results, intent.terms);

    return results;
  }

  /// סינון לפי סוגי קבצים
  static List<FileMetadata> _filterByFileTypes(List<FileMetadata> files, List<String> fileTypes) {
    final normalizedTypes = fileTypes.map((t) => t.toLowerCase()).toSet();
    
    return files.where((file) {
      final ext = file.extension.toLowerCase();
      return normalizedTypes.contains(ext);
    }).toList();
  }

  /// סינון לפי טווח תאריכים
  static List<FileMetadata> _filterByDateRange(List<FileMetadata> files, DateRange dateRange) {
    final startDate = dateRange.startDate;
    final endDate = dateRange.endDate;

    return files.where((file) {
      final fileDate = file.lastModified;
      
      if (startDate != null && fileDate.isBefore(startDate)) {
        return false;
      }
      
      if (endDate != null) {
        // כולל את היום האחרון
        final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
        if (fileDate.isAfter(endOfDay)) {
          return false;
        }
      }
      
      return true;
    }).toList();
  }

  /// סינון לפי מילות חיפוש
  static List<FileMetadata> _filterByTerms(List<FileMetadata> files, List<String> terms) {
    if (terms.isEmpty) return files;

    final lowerTerms = terms.map((t) => t.toLowerCase()).toList();

    return files.where((file) {
      final fileName = file.name.toLowerCase();
      final extractedText = file.extractedText?.toLowerCase() ?? '';

      // בודק אם לפחות מילה אחת נמצאת בשם או בטקסט
      return lowerTerms.any((term) =>
          fileName.contains(term) || extractedText.contains(term));
    }).toList();
  }

  /// מיון לפי רלוונטיות
  static List<FileMetadata> _sortByRelevance(List<FileMetadata> files, List<String> terms) {
    if (terms.isEmpty) {
      // אם אין terms - מיון לפי תאריך
      files.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      return files;
    }

    final lowerTerms = terms.map((t) => t.toLowerCase()).toList();

    // חישוב ציון רלוונטיות
    int getScore(FileMetadata file) {
      int score = 0;
      final fileName = file.name.toLowerCase();
      final extractedText = file.extractedText?.toLowerCase() ?? '';

      for (final term in lowerTerms) {
        // התאמה בשם = ציון גבוה
        if (fileName.contains(term)) score += 10;
        // התאמה בטקסט = ציון נמוך יותר
        if (extractedText.contains(term)) score += 1;
      }

      return score;
    }

    files.sort((a, b) {
      final scoreA = getScore(a);
      final scoreB = getScore(b);
      
      if (scoreA != scoreB) {
        return scoreB.compareTo(scoreA); // גבוה יותר = קודם
      }
      
      // אם אותו ציון - לפי תאריך
      return b.lastModified.compareTo(a.lastModified);
    });

    return files;
  }
}
