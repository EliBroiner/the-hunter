import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/file_metadata.dart';
import 'log_service.dart';

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
  
  if (lowerQuery.contains('שבועיים') || lowerQuery.contains('2 שבועות'))
    return now.subtract(const Duration(days: 14));
  if (lowerQuery.contains('שבוע') || lowerQuery.contains('week'))
    return now.subtract(const Duration(days: 7));
  if (lowerQuery.contains('חודש') || lowerQuery.contains('month'))
    return now.subtract(const Duration(days: 30));
  if (lowerQuery.contains('היום') || lowerQuery.contains('today'))
    return DateTime(now.year, now.month, now.day);
  if (lowerQuery.contains('אתמול') || lowerQuery.contains('yesterday'))
    return now.subtract(const Duration(days: 1));
  
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

  /// שומר מספר קבצים למסד
  void saveFiles(List<FileMetadata> files) {
    for (final file in files) {
      file.generateId(); // יצירת ID ייחודי לכל קובץ
    }
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
        if (totalSaved % 2000 == 0 || totalSaved == files.length)
          appLog('DB: Saved $totalSaved / ${files.length}');
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
        if (saved % 2000 == 0 || saved == files.length)
          appLog('DB: Saved $saved / ${files.length}');
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
  }) {
    return isar.fileMetadatas
        .where()
        .watch(fireImmediately: true)
        .map((files) => _filterResults(
              files: files,
              query: query,
              filter: filter,
              startDate: startDate,
            ));
  }

  List<FileMetadata> _filterResults({
    required List<FileMetadata> files,
    required String query,
    required SearchFilter filter,
    DateTime? startDate,
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

    if (startDate != null) {
      results = results.where((f) => 
          f.lastModified.isAfter(startDate) || 
          f.lastModified.isAtSameMomentAs(startDate)
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
      }
    }

    results.sort((a, b) => b.lastModified.compareTo(a.lastModified));
    return results;
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
