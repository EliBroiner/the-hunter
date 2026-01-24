import 'dart:io';
import 'package:isar/isar.dart';
import 'package:path_provider/path_provider.dart';
import '../models/file_metadata.dart';

/// פילטרים לחיפוש
enum SearchFilter {
  all,      // הכל
  images,   // תמונות בלבד
  pdfs,     // PDF בלבד
  recent,   // 7 ימים אחרונים
  ocrOnly,  // רק קבצים עם טקסט מחולץ
}

/// מפענח שאילתת זמן בעברית ומחזיר תאריך התחלה
/// מחזיר null אם אין מונח זמן בשאילתה
DateTime? parseTimeQuery(String query) {
  final lowerQuery = query.toLowerCase();
  final now = DateTime.now();
  
  // שבועיים - חייב להיות לפני שבוע כי הוא מכיל את המילה
  if (lowerQuery.contains('שבועיים') || lowerQuery.contains('2 שבועות')) {
    return now.subtract(const Duration(days: 14));
  }
  
  // שבוע
  if (lowerQuery.contains('שבוע') || lowerQuery.contains('week')) {
    return now.subtract(const Duration(days: 7));
  }
  
  // חודש
  if (lowerQuery.contains('חודש') || lowerQuery.contains('month')) {
    return now.subtract(const Duration(days: 30));
  }
  
  // יום / היום
  if (lowerQuery.contains('היום') || lowerQuery.contains('today')) {
    return DateTime(now.year, now.month, now.day);
  }
  
  // אתמול
  if (lowerQuery.contains('אתמול') || lowerQuery.contains('yesterday')) {
    return now.subtract(const Duration(days: 1));
  }
  
  return null;
}

/// שירות מסד נתונים Isar - מנהל את כל פעולות המסד
class DatabaseService {
  static DatabaseService? _instance;
  static Isar? _isar;

  DatabaseService._();

  /// מחזיר את ה-singleton של השירות
  static DatabaseService get instance {
    _instance ??= DatabaseService._();
    return _instance!;
  }

  /// מאתחל את מסד הנתונים
  Future<void> init() async {
    if (_isar != null) return;

    final dir = await getApplicationDocumentsDirectory();
    _isar = await Isar.open(
      [FileMetadataSchema],
      directory: dir.path,
      name: 'the_hunter_db',
    );
  }

  /// מחזיר את אובייקט Isar
  Isar get isar {
    if (_isar == null) throw Exception('Database not initialized. Call init() first.');
    return _isar!;
  }

  /// שומר קובץ בודד למסד
  Future<void> saveFile(FileMetadata file) async {
    await isar.writeTxn(() async {
      await isar.fileMetadatas.put(file);
    });
  }

  /// שומר מספר קבצים למסד
  Future<void> saveFiles(List<FileMetadata> files) async {
    await isar.writeTxn(() async {
      await isar.fileMetadatas.putAll(files);
    });
  }

  /// מוחק את כל הקבצים ומכניס חדשים (wipe & replace)
  Future<void> replaceAllFiles(List<FileMetadata> files) async {
    await isar.writeTxn(() async {
      await isar.fileMetadatas.clear();
      await isar.fileMetadatas.putAll(files);
    });
  }

  /// מחזיר את כל הקבצים
  Future<List<FileMetadata>> getAllFiles() async {
    return await isar.fileMetadatas.where().findAll();
  }

  /// מחזיר קבצים לפי סיומת
  Future<List<FileMetadata>> getFilesByExtension(String extension) async {
    return await isar.fileMetadatas
        .filter()
        .extensionEqualTo(extension.toLowerCase())
        .findAll();
  }

  /// מחזיר קבצים לפי חיפוש שם
  Future<List<FileMetadata>> searchByName(String query) async {
    return await isar.fileMetadatas
        .filter()
        .nameContains(query, caseSensitive: false)
        .findAll();
  }

  /// חיפוש מתקדם - מחפש בשם הקובץ או בטקסט שחולץ
  /// תומך בחיפוש דו-לשוני (עברית ואנגלית)
  /// [query] - מונח החיפוש
  /// [filter] - פילטר לפי סוג קובץ
  /// [startDate] - תאריך התחלה לסינון (אופציונלי)
  Future<List<FileMetadata>> search({
    required String query,
    SearchFilter filter = SearchFilter.all,
    DateTime? startDate,
  }) async {
    // שליפת כל הקבצים וסינון בזיכרון
    var results = await isar.fileMetadatas.where().findAll();

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

    // סינון לפי תאריך התחלה (Time Filtering)
    if (startDate != null) {
      results = results.where((f) => 
          f.lastModified.isAfter(startDate) || 
          f.lastModified.isAtSameMomentAs(startDate)
      ).toList();
    }

    // סינון לפי שאילתת חיפוש (Bilingual Search - Hebrew & English)
    if (query.isNotEmpty) {
      // ניקוי מונחי זמן מהשאילתה לחיפוש טקסט
      final cleanQuery = _removeTimeTerms(query).toLowerCase();
      
      if (cleanQuery.isNotEmpty) {
        // חיפוש רגיל - contains
        var filtered = results.where((f) =>
            f.name.toLowerCase().contains(cleanQuery) ||
            (f.extractedText?.toLowerCase().contains(cleanQuery) ?? false)
        ).toList();
        
        // Fuzzy Search - אם אין תוצאות, ננסה startsWith
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

    // מיון לפי תאריך שינוי - החדשים קודם (Smart Sorting)
    results.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    return results;
  }

  /// מסיר מונחי זמן מהשאילתה לצורך חיפוש טקסט נקי
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

  /// בודק אם אחת מהמילים בטקסט מתחילה בשאילתה (Fuzzy)
  bool _wordsStartWith(String text, String query) {
    final words = text.toLowerCase().split(RegExp(r'[\s\-_.,;:!?]+'));
    return words.any((word) => word.startsWith(query));
  }

  /// חיפוש ריאקטיבי - מחזיר Stream שמתעדכן בזמן אמת
  /// משתמש ב-Isar watch לעדכון אוטומטי כשהמסד משתנה
  Stream<List<FileMetadata>> watchSearch({
    required String query,
    SearchFilter filter = SearchFilter.all,
    DateTime? startDate,
  }) {
    // מאזין לשינויים במסד ומחזיר תוצאות מסוננות
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

  /// פונקציית סינון פנימית לשימוש חוזר
  List<FileMetadata> _filterResults({
    required List<FileMetadata> files,
    required String query,
    required SearchFilter filter,
    DateTime? startDate,
  }) {
    var results = files;

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

    // סינון לפי שאילתת חיפוש
    if (query.isNotEmpty) {
      final cleanQuery = _removeTimeTerms(query).toLowerCase();
      
      if (cleanQuery.isNotEmpty) {
        var filtered = results.where((f) =>
            f.name.toLowerCase().contains(cleanQuery) ||
            (f.extractedText?.toLowerCase().contains(cleanQuery) ?? false)
        ).toList();
        
        // Fuzzy Search
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

    // מיון לפי תאריך - החדשים קודם
    results.sort((a, b) => b.lastModified.compareTo(a.lastModified));

    return results;
  }

  /// מחזיר קבצי תמונות שטרם עברו אינדוקס
  Future<List<FileMetadata>> getPendingImageFiles() async {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return await isar.fileMetadatas
        .filter()
        .isIndexedEqualTo(false)
        .and()
        .anyOf(imageExtensions, (q, ext) => q.extensionEqualTo(ext))
        .findAll();
  }

  /// מעדכן קובץ במסד
  Future<void> updateFile(FileMetadata file) async {
    await isar.writeTxn(() async {
      await isar.fileMetadatas.put(file);
    });
  }

  /// מחזיר מספר הקבצים במסד
  Future<int> getFilesCount() async {
    return await isar.fileMetadatas.count();
  }

  /// מוחק קובץ לפי ID
  Future<bool> deleteFile(int id) async {
    return await isar.writeTxn(() async {
      return await isar.fileMetadatas.delete(id);
    });
  }

  /// מוחק את כל הקבצים
  Future<void> clearAll() async {
    await isar.writeTxn(() async {
      await isar.fileMetadatas.clear();
    });
  }

  /// בודק אם קובץ קיים במסד לפי נתיב ותאריך שינוי
  Future<bool> fileExists(String path, DateTime lastModified) async {
    final existing = await isar.fileMetadatas
        .filter()
        .pathEqualTo(path)
        .findFirst();
    
    if (existing == null) return false;
    
    // בודק אם תאריך השינוי זהה (עם סבילות של שנייה)
    final diff = existing.lastModified.difference(lastModified).abs();
    return diff.inSeconds < 2;
  }

  /// מחזיר קובץ לפי נתיב
  Future<FileMetadata?> getFileByPath(String path) async {
    return await isar.fileMetadatas
        .filter()
        .pathEqualTo(path)
        .findFirst();
  }

  /// מחזיר את כל הנתיבים במסד
  Future<Set<String>> getAllPaths() async {
    final files = await isar.fileMetadatas.where().findAll();
    return files.map((f) => f.path).toSet();
  }

  /// מוסיף קובץ חדש או מעדכן קיים (upsert)
  Future<void> upsertFile(FileMetadata file) async {
    final existing = await getFileByPath(file.path);
    if (existing != null) {
      file.id = existing.id;
      // שומר טקסט מחולץ אם קיים
      if (existing.extractedText != null && file.extractedText == null) {
        file.extractedText = existing.extractedText;
        file.isIndexed = existing.isIndexed;
      }
    }
    await isar.writeTxn(() async {
      await isar.fileMetadatas.put(file);
    });
  }

  /// מוסיף קבצים חדשים בלבד (מדלג על קיימים)
  Future<int> addNewFilesOnly(List<FileMetadata> files) async {
    int addedCount = 0;
    final existingPaths = await getAllPaths();
    
    final newFiles = files.where((f) => !existingPaths.contains(f.path)).toList();
    
    if (newFiles.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.fileMetadatas.putAll(newFiles);
      });
      addedCount = newFiles.length;
    }
    
    return addedCount;
  }

  /// מוחק רשומות של קבצים שכבר לא קיימים במכשיר
  Future<int> cleanupStaleFiles() async {
    final allFiles = await getAllFiles();
    final staleIds = <int>[];
    
    for (final file in allFiles) {
      final exists = await _fileExistsOnDevice(file.path);
      if (!exists) staleIds.add(file.id);
    }
    
    if (staleIds.isNotEmpty) {
      await isar.writeTxn(() async {
        await isar.fileMetadatas.deleteAll(staleIds);
      });
    }
    
    return staleIds.length;
  }

  /// בודק אם קובץ קיים במכשיר
  Future<bool> _fileExistsOnDevice(String path) async {
    try {
      final file = File(path);
      return await file.exists();
    } catch (_) {
      return false;
    }
  }

  /// סוגר את מסד הנתונים
  Future<void> close() async {
    await _isar?.close();
    _isar = null;
  }
}
