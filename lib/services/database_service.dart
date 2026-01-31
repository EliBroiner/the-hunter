import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/file_metadata.dart';
import '../models/search_intent.dart' as api;
import '../utils/smart_search_parser.dart';
import 'log_service.dart';
import 'relevance_engine.dart';

/// פילטרים לחיפוש
enum SearchFilter {
  all,      // הכל
  images,   // תמונות בלבד
  pdfs,     // PDF בלבד
  recent,   // 7 ימים אחרונים
  ocrOnly,  // רק קבצים עם טקסט מחולץ
}

/// מפענח שאילתת זמן בעברית ומחזיר תאריך התחלה
DateTime? parseTimeQuery(String query) {
  final lowerQuery = query.toLowerCase();
  final now = DateTime.now();
  
  if (lowerQuery.contains('שבועיים') || lowerQuery.contains('2 שבועות')) {
    return now.subtract(const Duration(days: 14));
  }
  if (lowerQuery.contains('שבוע') || lowerQuery.contains('week')) {
    return now.subtract(const Duration(days: 7));
  }
  if (lowerQuery.contains('חודש') || lowerQuery.contains('month')) {
    return now.subtract(const Duration(days: 30));
  }
  if (lowerQuery.contains('היום') || lowerQuery.contains('today')) {
    return DateTime(now.year, now.month, now.day);
  }
  if (lowerQuery.contains('אתמול') || lowerQuery.contains('yesterday')) {
    return now.subtract(const Duration(days: 1));
  }
  
  return null;
}

/// שירות מסד נתונים Isar v4 - מנהל את כל פעולות המסד
class DatabaseService {
  static DatabaseService? _instance;
  static Isar? _isar;

  DatabaseService._();

  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  /// מאתחל את מסד הנתונים - Isar v4 syntax
  Future<void> init() async {
    if (_isar != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _isar = Isar.open(
      schemas: [FileMetadataSchema],
      directory: dir.path,
      name: 'the_hunter_db',
    );
  }

  Isar get isar {
    if (_isar == null) throw Exception('Database not initialized. Call init() first.');
    return _isar!;
  }

  /// שומר קובץ בודד למסד - Isar v4: סינכרוני
  void saveFile(FileMetadata file) {
    file.generateId(); // יצירת ID ייחודי לפני שמירה
    isar.write((isar) {
      isar.fileMetadatas.put(file);
    });
  }

  /// שומר מספר קבצים למסד (ממזג אם קיים)
  void saveFiles(List<FileMetadata> files) {
    for (final file in files) {
      file.generateId(); // יצירת ID ייחודי לכל קובץ
    }
    
    // שימוש ב-putAll במקום replace כדי לא למחוק נתונים קיימים
    isar.write((isar) {
      isar.fileMetadatas.putAll(files);
    });
  }

  /// מוחק את כל הקבצים ומכניס חדשים (wipe & replace)
  Future<void> replaceAllFilesAsync(List<FileMetadata> files) async {
    appLog('DB: replaceAllFilesAsync - ${files.length} files');
    
    // יצירת IDs ייחודיים לכל הקבצים
    for (final file in files) {
      file.generateId();
    }
    
    try {
      isar.write((isar) {
        isar.fileMetadatas.clear();
      });
      appLog('DB: Cleared all files');
      
      const batchSize = 500;
      int totalSaved = 0;
      
      for (var i = 0; i < files.length; i += batchSize) {
        final end = (i + batchSize < files.length) ? i + batchSize : files.length;
        final batch = files.sublist(i, end);
        
        isar.write((isar) {
          isar.fileMetadatas.putAll(batch);
        });
        
        totalSaved += batch.length;
        if (totalSaved % 2000 == 0 || totalSaved == files.length) {
          appLog('DB: Saved $totalSaved / ${files.length}');
        }
      }
      
      final finalCount = isar.fileMetadatas.count();
      appLog('DB: Final count: $finalCount');
    } catch (e) {
      appLog('DB ERROR: $e');
    }
  }
  
  /// מוחק את כל הקבצים ומכניס חדשים (wipe & replace) - סינכרוני
  void replaceAllFiles(List<FileMetadata> files) {
    appLog('DB: replaceAllFiles - ${files.length} files');
    
    // יצירת IDs ייחודיים לכל הקבצים
    for (final file in files) {
      file.generateId();
    }
    
    try {
      isar.write((isar) {
        isar.fileMetadatas.clear();
      });
      
      const batchSize = 500;
      int saved = 0;
      for (var i = 0; i < files.length; i += batchSize) {
        final end = (i + batchSize < files.length) ? i + batchSize : files.length;
        final batch = files.sublist(i, end);
        isar.write((isar) {
          isar.fileMetadatas.putAll(batch);
        });
        saved += batch.length;
        if (saved % 2000 == 0 || saved == files.length) {
          appLog('DB: Saved $saved / ${files.length}');
        }
      }
      
      appLog('DB: Final count: ${isar.fileMetadatas.count()}');
    } catch (e) {
      appLog('DB ERROR: $e');
    }
  }

  /// מחזיר את כל הקבצים
  List<FileMetadata> getAllFiles() {
    final files = isar.fileMetadatas.where().findAll();
    appLog('DB: getAllFiles -> ${files.length}');
    return files;
  }

  /// מחזיר קבצים לפי סיומת
  List<FileMetadata> getFilesByExtension(String extension) {
    return isar.fileMetadatas
        .where()
        .findAll()
        .where((f) => f.extension.toLowerCase() == extension.toLowerCase())
        .toList();
  }

  /// מחזיר קבצים לפי חיפוש שם
  List<FileMetadata> searchByName(String query) {
    return isar.fileMetadatas
        .where()
        .findAll()
        .where((f) => f.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
  }

  /// מילון מילים נרדפות עברית-אנגלית
  static const Map<String, List<String>> _synonyms = {
    // ביטוח
    'ביטוח': ['insurance', 'policy', 'פוליסה'],
    'insurance': ['ביטוח', 'פוליסה', 'policy'],
    'פוליסה': ['policy', 'ביטוח', 'insurance'],
    
    // כסף/תשלום
    'חשבונית': ['invoice', 'receipt', 'קבלה', 'bill'],
    'invoice': ['חשבונית', 'קבלה', 'receipt', 'bill'],
    'קבלה': ['receipt', 'חשבונית', 'invoice'],
    'receipt': ['קבלה', 'חשבונית', 'invoice'],
    'תשלום': ['payment', 'pay', 'חיוב'],
    'payment': ['תשלום', 'pay', 'חיוב'],
    
    // בנק
    'בנק': ['bank', 'banking'],
    'bank': ['בנק', 'banking'],
    
    // רכב
    'רכב': ['car', 'vehicle', 'auto'],
    'car': ['רכב', 'vehicle', 'auto'],
    'רישיון': ['license', 'licence'],
    'license': ['רישיון', 'licence'],
    
    // בריאות
    'רפואי': ['medical', 'health', 'רפואה'],
    'medical': ['רפואי', 'health', 'רפואה'],
    'בריאות': ['health', 'medical'],
    'health': ['בריאות', 'רפואי', 'medical'],
    
    // מסמכים
    'חוזה': ['contract', 'agreement', 'הסכם'],
    'contract': ['חוזה', 'agreement', 'הסכם'],
    'הסכם': ['agreement', 'contract', 'חוזה'],
    'agreement': ['הסכם', 'contract', 'חוזה'],
    'מסמך': ['document', 'doc', 'file'],
    'document': ['מסמך', 'doc', 'file'],
    
    // עבודה
    'משכורת': ['salary', 'payslip', 'תלוש'],
    'salary': ['משכורת', 'payslip', 'תלוש'],
    'תלוש': ['payslip', 'משכורת', 'salary'],
    
    // דירה
    'דירה': ['apartment', 'flat', 'שכירות'],
    'apartment': ['דירה', 'flat', 'שכירות'],
    'שכירות': ['rent', 'rental', 'דירה'],
    'rent': ['שכירות', 'rental', 'דירה'],
  };

  /// מרחיב שאילתת חיפוש עם מילים נרדפות
  List<String> _expandQuery(String query) {
    final terms = <String>{query.toLowerCase()};
    
    // מוסיף מילים נרדפות
    final synonymList = _synonyms[query.toLowerCase()];
    if (synonymList != null) terms.addAll(synonymList);
    
    // גם לכל מילה בנפרד אם יש רווחים
    for (final word in query.toLowerCase().split(' ')) {
      if (word.isNotEmpty) {
        terms.add(word);
        final wordSynonyms = _synonyms[word];
        if (wordSynonyms != null) terms.addAll(wordSynonyms);
      }
    }
    
    return terms.toList();
  }

  /// חיפוש מתקדם - מחפש בשם הקובץ או בטקסט שחולץ
  List<FileMetadata> search({
    required String query,
    SearchFilter filter = SearchFilter.all,
    DateTime? startDate,
  }) {
    var results = isar.fileMetadatas.where().findAll();

    // סינון לפי סוג
    switch (filter) {
      case SearchFilter.all:
        break;
      case SearchFilter.images:
        const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
        results = results.where((f) => imageExts.contains(f.extension.toLowerCase())).toList();
        break;
      case SearchFilter.pdfs:
        results = results.where((f) => f.extension.toLowerCase() == 'pdf').toList();
        break;
      case SearchFilter.recent:
        final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
        results = results.where((f) => f.lastModified.isAfter(sevenDaysAgo)).toList();
        break;
      case SearchFilter.ocrOnly:
        results = results.where((f) => f.extractedText != null && f.extractedText!.isNotEmpty).toList();
        break;
    }

    // סינון לפי תאריך התחלה
    if (startDate != null) {
      results = results.where((f) => 
          f.lastModified.isAfter(startDate) || 
          f.lastModified.isAtSameMomentAs(startDate)
      ).toList();
    }

    // סינון לפי שאילתת חיפוש עם מילים נרדפות
    if (query.isNotEmpty) {
      final cleanQuery = _removeTimeTerms(query);
      
      if (cleanQuery.isNotEmpty) {
        // הרחבת השאילתה עם מילים נרדפות
        final searchTerms = _expandQuery(cleanQuery);
        appLog('SEARCH: "$cleanQuery" -> ${searchTerms.join(", ")}');
        
        var filtered = results.where((f) {
          final name = f.name.toLowerCase();
          final text = f.extractedText?.toLowerCase() ?? '';
          
          // מחפש כל אחת מהמילים (OR)
          return searchTerms.any((term) =>
              name.contains(term) || text.contains(term)
          );
        }).toList();
        
        // Fuzzy Search אם לא נמצא כלום
        if (filtered.isEmpty) {
          filtered = results.where((f) {
            final name = f.name.toLowerCase();
            final text = f.extractedText?.toLowerCase() ?? '';
            
            return searchTerms.any((term) =>
                _wordsStartWith(name, term) || _wordsStartWith(text, term)
            );
          }).toList();
        }
        
        results = filtered;
      }
    }

    // מיון לפי תאריך - החדשים קודם
    results.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    return results;
  }

  String _removeTimeTerms(String query) {
    var clean = query;
    const timeTerms = [
      'שבועיים', '2 שבועות', 'שבוע', 'חודש', 'היום', 'אתמול',
      'week', 'month', 'today', 'yesterday',
    ];
    for (final term in timeTerms) {
      clean = clean.replaceAll(RegExp(term, caseSensitive: false), '');
    }
    return clean.trim();
  }

  bool _wordsStartWith(String text, String query) {
    final words = text.toLowerCase().split(RegExp(r'[\s\-_.,;:!?]+'));
    return words.any((word) => word.startsWith(query));
  }

  /// חיפוש ריאקטיבי - מחזיר Stream שמתעדכן בזמן אמת
  Stream<List<FileMetadata>> watchSearch({
    required String query,
    SearchFilter filter = SearchFilter.all,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    return isar.fileMetadatas
        .where()
        .watch(fireImmediately: true)
        .map((files) => _filterResults(
              files: files,
              query: query,
              filter: filter,
              startDate: startDate,
              endDate: endDate,
            ));
  }

  List<FileMetadata> _filterResults({
    required List<FileMetadata> files,
    required String query,
    required SearchFilter filter,
    DateTime? startDate,
    DateTime? endDate,
  }) {
    var results = files;

    switch (filter) {
      case SearchFilter.all:
        break;
      case SearchFilter.images:
        const imageExts = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
        results = results.where((f) => imageExts.contains(f.extension.toLowerCase())).toList();
        break;
      case SearchFilter.pdfs:
        results = results.where((f) => f.extension.toLowerCase() == 'pdf').toList();
        break;
      case SearchFilter.recent:
        final sevenDaysAgo = DateTime.now().subtract(const Duration(days: 7));
        results = results.where((f) => f.lastModified.isAfter(sevenDaysAgo)).toList();
        break;
      case SearchFilter.ocrOnly:
        results = results.where((f) => f.extractedText != null && f.extractedText!.isNotEmpty).toList();
        break;
    }

    // סינון לפי טווח תאריכים
    if (startDate != null) {
      results = results.where((f) => 
          f.lastModified.isAfter(startDate) || 
          f.lastModified.isAtSameMomentAs(startDate)
      ).toList();
    }
    
    if (endDate != null) {
      // מוסיף יום אחד לסוף הטווח כדי לכלול את היום הזה
      final endOfDay = DateTime(endDate.year, endDate.month, endDate.day, 23, 59, 59);
      results = results.where((f) => 
          f.lastModified.isBefore(endOfDay) || 
          f.lastModified.isAtSameMomentAs(endOfDay)
      ).toList();
    }

    if (query.isNotEmpty) {
      final cleanQuery = _removeTimeTerms(query).toLowerCase();
      
      if (cleanQuery.isNotEmpty) {
        var filtered = results.where((f) =>
            f.name.toLowerCase().contains(cleanQuery) ||
            (f.extractedText?.toLowerCase().contains(cleanQuery) ?? false)
        ).toList();
        
        if (filtered.isEmpty) {
          filtered = results.where((f) =>
              f.name.toLowerCase().startsWith(cleanQuery) ||
              _wordsStartWith(f.name, cleanQuery) ||
              _wordsStartWith(f.extractedText ?? '', cleanQuery)
          ).toList();
        }
        
        results = filtered;
        
        // מיון לפי רלוונטיות: שם קובץ תואם קודם, תוכן אח"כ
        results = _sortByRelevance(results, cleanQuery);
        return results;
      }
    }

    // אם אין שאילתה - מיון לפי תאריך בלבד
    results.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return results;
  }
  
  /// מיון לפי רלוונטיות: שם קובץ תואם קודם, תוכן אח"כ
  List<FileMetadata> _sortByRelevance(List<FileMetadata> files, String query) {
    // חלוקה לשתי קבוצות: התאמה בשם / התאמה בתוכן בלבד
    final nameMatches = <FileMetadata>[];
    final contentOnlyMatches = <FileMetadata>[];
    
    for (final file in files) {
      if (file.name.toLowerCase().contains(query)) {
        nameMatches.add(file);
      } else {
        contentOnlyMatches.add(file);
      }
    }
    
    // מיון פנימי לפי תאריך (חדש קודם)
    nameMatches.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    contentOnlyMatches.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    
    // איחוד: שם קודם, תוכן אח"כ
    return [...nameMatches, ...contentOnlyMatches];
  }

  /// ציון רלוונטיות לקובץ לפי מונחים — שם +10, extractedText +1, עד 30 יום +2
  int _calculateRelevance(FileMetadata file, List<String> terms) {
    int score = 0;
    final nameLower = file.name.toLowerCase();
    final textLower = file.extractedText?.toLowerCase() ?? '';
    for (final term in terms) {
      if (nameLower.contains(term)) score += 10;
      if (textLower.contains(term)) score += 1;
    }
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    if (file.lastModified.isAfter(thirtyDaysAgo)) score += 2;
    return score;
  }

  /// חיפוש חכם מקומי לפי SearchIntent — קבוצה א' (מונחים OR + short-word exact), קבוצה ב' (שנה מפורשת), מיון ב-RelevanceEngine
  Future<List<FileMetadata>> localSmartSearch(SearchIntent intent) async {
    List<FileMetadata> candidates;

    if (intent.dateFrom != null) {
      final from = intent.dateFrom!;
      final to = intent.dateTo ?? from.add(const Duration(days: 365));
      candidates = isar.fileMetadatas
          .where()
          .lastModifiedBetween(from, to)
          .findAll();
    } else {
      candidates = isar.fileMetadatas.where().findAll();
    }

    if (intent.fileTypes.isNotEmpty) {
      final extSet = intent.fileTypes.map((e) => e.toLowerCase()).toSet();
      candidates = candidates.where((f) => extSet.contains(f.extension.toLowerCase())).toList();
    }

    // קבוצה א': מונחים — OR; מונח קצר (אורך < 3) = התאמה מדויקת (whole-word), אחרת .contains()
    if (intent.terms.isNotEmpty) {
      candidates = candidates.where((f) {
        final name = f.name.toLowerCase();
        final text = f.extractedText?.toLowerCase() ?? '';
        return intent.terms.any((term) {
          final t = term.toLowerCase().trim();
          if (t.isEmpty) return false;
          final exactOnly = t.length < 3;
          if (exactOnly) {
            return _wholeWordMatch(name, t) || _wholeWordMatch(text, t);
          }
          return name.contains(t) || text.contains(t);
        });
      }).toList();
    }

    // קבוצה ב': שנה מפורשת — AND (name או extractedText מכילים שנה או lastModified באותה שנה)
    if (intent.explicitYear != null && intent.explicitYear!.isNotEmpty) {
      final yearStr = intent.explicitYear!.trim();
      final yearNum = int.tryParse(yearStr);
      candidates = candidates.where((f) {
        final name = f.name.contains(yearStr);
        final text = (f.extractedText ?? '').contains(yearStr);
        final yearMatch = yearNum != null && f.lastModified.year == yearNum;
        return name || text || yearMatch;
      }).toList();
    }

    final results = RelevanceEngine.rankAndSort(candidates, intent);
    appLog('DB: localSmartSearch -> ${results.length} results');
    return results;
  }

  /// התאמת מונח כ־whole-word (גבולות מילה) — למניעת "מס" בתוך "מסמך"
  static bool _wholeWordMatch(String content, String term) {
    if (term.isEmpty) return false;
    int i = 0;
    while (true) {
      final idx = content.indexOf(term, i);
      if (idx == -1) return false;
      final beforeOk = idx == 0 || !_isWordChar(content.codeUnitAt(idx - 1));
      final afterOk = idx + term.length >= content.length || !_isWordChar(content.codeUnitAt(idx + term.length));
      if (beforeOk && afterOk) return true;
      i = idx + 1;
    }
  }

  static bool _isWordChar(int code) {
    return (code >= 0x30 && code <= 0x39) || (code >= 0x41 && code <= 0x5A) ||
        (code >= 0x61 && code <= 0x7A) || (code >= 0x05D0 && code <= 0x05EA);
  }

  /// חיפוש לפי SearchIntent מה-AI — תאריכים, fileTypes, terms (OR)
  Future<List<FileMetadata>> searchByIntent(api.SearchIntent intent) async {
    List<FileMetadata> candidates;

    final startDate = intent.dateRange?.startDate;
    final endDate = intent.dateRange?.endDate;

    if (startDate != null) {
      final to = endDate ?? startDate.add(const Duration(days: 365));
      candidates = isar.fileMetadatas
          .where()
          .lastModifiedBetween(startDate, to)
          .findAll();
    } else {
      candidates = isar.fileMetadatas.where().findAll();
    }

    if (intent.fileTypes.isNotEmpty) {
      final extSet = intent.fileTypes.map((e) => e.toLowerCase()).toSet();
      candidates = candidates.where((f) => extSet.contains(f.extension.toLowerCase())).toList();
    }

    final termsLower = intent.terms.map((t) => t.toLowerCase()).toList();
    if (termsLower.isNotEmpty) {
      candidates = candidates.where((f) {
        final name = f.name.toLowerCase();
        final text = f.extractedText?.toLowerCase() ?? '';
        return termsLower.any((term) => name.contains(term) || text.contains(term));
      }).toList();
    }

    candidates.sort((a, b) {
      final scoreA = _calculateRelevance(a, termsLower);
      final scoreB = _calculateRelevance(b, termsLower);
      if (scoreA != scoreB) return scoreB.compareTo(scoreA);
      return b.lastModified.compareTo(a.lastModified);
    });

    appLog('DB: searchByIntent -> ${candidates.length} results');
    return candidates;
  }

  /// מחזיר קבצי תמונות שטרם עברו אינדוקס
  List<FileMetadata> getPendingImageFiles() {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return isar.fileMetadatas
        .where()
        .findAll()
        .where((f) => !f.isIndexed && imageExtensions.contains(f.extension.toLowerCase()))
        .toList();
  }

  /// מחזיר קבצי טקסט ו-PDF שטרם עברו אינדוקס
  List<FileMetadata> getPendingTextFiles() {
    const textExtensions = ['txt', 'text', 'log', 'md', 'json', 'xml', 'csv', 'pdf'];
    return isar.fileMetadatas
        .where()
        .findAll()
        .where((f) => !f.isIndexed && textExtensions.contains(f.extension.toLowerCase()))
        .toList();
  }

  /// מחזיר את כל הקבצים שטרם עברו אינדוקס (תמונות + טקסט)
  List<FileMetadata> getAllPendingFiles() {
    return isar.fileMetadatas
        .where()
        .findAll()
        .where((f) => !f.isIndexed)
        .toList();
  }

  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];

  /// מאפס תמונות לפני סריקת OCR מחדש.
  /// [onlyEmptyText] true = רק תמונות בלי טקסט מחולץ (חוסך סריקות קיימות).
  int resetOcrForImages({bool onlyEmptyText = false}) {
    final all = isar.fileMetadatas.where().findAll();
    final images = all.where((f) =>
        _imageExtensions.contains(f.extension.toLowerCase())).toList();
    final toReset = onlyEmptyText
        ? images.where((f) {
            final t = f.extractedText;
            return t == null || t.trim().isEmpty;
          }).toList()
        : images;

    for (final f in toReset) {
      f.isIndexed = false;
      f.extractedText = null;
      updateFile(f);
    }
    appLog('DB: resetOcrForImages onlyEmpty=$onlyEmptyText -> ${toReset.length} images');
    return toReset.length;
  }

  /// מעדכן קובץ במסד
  void updateFile(FileMetadata file) {
    file.generateId(); // וודא שיש ID ייחודי
    isar.write((isar) {
      isar.fileMetadatas.put(file);
    });
  }

  /// מחזיר מספר הקבצים במסד
  int getFilesCount() {
    return isar.fileMetadatas.count();
  }

  /// מוחק קובץ לפי ID
  bool deleteFile(int id) {
    bool deleted = false;
    isar.write((isar) {
      deleted = isar.fileMetadatas.delete(id);
    });
    return deleted;
  }

  /// מוחק קובץ לפי נתיב
  Future<bool> deleteFileByPath(String path) async {
    bool deleted = false;
    isar.write((isar) {
      final file = isar.fileMetadatas.where().pathEqualTo(path).findFirst();
      if (file != null) {
        deleted = isar.fileMetadatas.delete(file.id);
      }
    });
    return deleted;
  }

  /// מוחק את כל הקבצים
  void clearAll() {
    isar.write((isar) {
      isar.fileMetadatas.clear();
    });
  }

  /// בודק אם קובץ קיים במסד לפי נתיב ותאריך שינוי
  bool fileExists(String path, DateTime lastModified) {
    final existing = isar.fileMetadatas
        .where()
        .findAll()
        .where((f) => f.path == path)
        .firstOrNull;
    
    if (existing == null) return false;
    
    final diff = existing.lastModified.difference(lastModified).abs();
    return diff.inSeconds < 2;
  }

  /// מחזיר קובץ לפי נתיב
  FileMetadata? getFileByPath(String path) {
    return isar.fileMetadatas
        .where()
        .findAll()
        .where((f) => f.path == path)
        .firstOrNull;
  }

  /// מחזיר את כל הנתיבים במסד
  Set<String> getAllPaths() {
    final files = isar.fileMetadatas.where().findAll();
    return files.map((f) => f.path).toSet();
  }

  /// מוסיף קובץ חדש או מעדכן קיים (upsert)
  void upsertFile(FileMetadata file) {
    final existing = getFileByPath(file.path);
    if (existing != null) {
      file.id = existing.id;
      if (existing.extractedText != null && file.extractedText == null) {
        file.extractedText = existing.extractedText;
        file.isIndexed = existing.isIndexed;
      }
    }
    isar.write((isar) {
      isar.fileMetadatas.put(file);
    });
  }

  /// מוסיף קבצים חדשים בלבד (מדלג על קיימים)
  int addNewFilesOnly(List<FileMetadata> files) {
    final existingPaths = getAllPaths();
    final newFiles = files.where((f) => !existingPaths.contains(f.path)).toList();
    
    if (newFiles.isNotEmpty) {
      isar.write((isar) {
        isar.fileMetadatas.putAll(newFiles);
      });
    }
    
    return newFiles.length;
  }

  /// מוחק רשומות של קבצים שכבר לא קיימים במכשיר
  Future<int> cleanupStaleFiles() async {
    final allFiles = getAllFiles();
    final staleIds = <int>[];
    
    for (final file in allFiles) {
      final exists = await _fileExistsOnDevice(file.path);
      if (!exists) staleIds.add(file.id);
    }
    
    if (staleIds.isNotEmpty) {
      isar.write((isar) {
        isar.fileMetadatas.deleteAll(staleIds);
      });
    }
    
    return staleIds.length;
  }

  Future<bool> _fileExistsOnDevice(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// סוגר את מסד הנתונים
  void close() {
    _isar?.close();
    _isar = null;
  }
}
