import 'dart:io';
import '../models/file_metadata.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'ocr_service.dart';
import 'permission_service.dart';
import 'text_extraction_service.dart';

/// מקור סריקה - מייצג תיקייה לסריקה
class ScanSource {
  final String name;
  final String path;
  final bool exists;
  final int filesFound;

  ScanSource({
    required this.name,
    required this.path,
    required this.exists,
    this.filesFound = 0,
  });

  ScanSource copyWith({int? filesFound, bool? exists}) => ScanSource(
    name: name,
    path: path,
    exists: exists ?? this.exists,
    filesFound: filesFound ?? this.filesFound,
  );
}

/// שירות סריקת קבצים - סורק תיקיות נפוצות ושומר למסד הנתונים
class FileScannerService {
  static FileScannerService? _instance;
  
  final DatabaseService _databaseService;
  final PermissionService _permissionService;
  final OCRService _ocrService;
  final TextExtractionService _textExtractionService;

  /// סיומות תמונות נתמכות (לסריקת OCR)
  static const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'heic', 'heif'];
  
  /// סיומות טקסט נתמכות (לחילוץ טקסט ישיר)
  static const textExtensions = ['txt', 'text', 'log', 'md', 'json', 'xml', 'csv', 'pdf'];
  
  /// סיומות וידאו
  static const videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];
  
  /// סיומות מסמכים
  static const documentExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'txt', 'rtf'];
  
  /// סיומות אודיו
  static const audioExtensions = ['mp3', 'wav', 'm4a', 'ogg', 'aac'];
  
  /// כל הסיומות הנתמכות לסריקה
  static const supportedExtensions = [
    ...imageExtensions, 
    ...videoExtensions, 
    ...documentExtensions,
    ...audioExtensions,
  ];

  FileScannerService._({
    DatabaseService? databaseService,
    PermissionService? permissionService,
    OCRService? ocrService,
    TextExtractionService? textExtractionService,
  })  : _databaseService = databaseService ?? DatabaseService.instance,
        _permissionService = permissionService ?? PermissionService.instance,
        _ocrService = ocrService ?? OCRService.instance,
        _textExtractionService = textExtractionService ?? TextExtractionService.instance;

  /// מחזיר את ה-singleton של השירות
  static FileScannerService get instance {
    _instance ??= FileScannerService._();
    return _instance!;
  }

  /// בודק אם תיקייה קיימת
  Future<bool> directoryExists(String path) async {
    if (path.isEmpty) return false;
    try {
      final directory = Directory(path);
      return await directory.exists();
    } catch (_) {
      return false;
    }
  }

  /// מחזיר את נתיב הבסיס לפי פלטפורמה
  String get basePath {
    if (Platform.isAndroid) return '/storage/emulated/0';
    if (Platform.isLinux) return Platform.environment['HOME'] ?? '';
    if (Platform.isMacOS) return Platform.environment['HOME'] ?? '';
    if (Platform.isWindows) return Platform.environment['USERPROFILE'] ?? '';
    return '';
  }

  /// מחזיר רשימת מקורות סריקה לפי פלטפורמה
  List<ScanSource> getScanSources() {
    final base = basePath;
    if (base.isEmpty) return [];

    if (Platform.isAndroid) {
      return [
        ScanSource(name: 'Downloads', path: '$base/Download', exists: false),
        ScanSource(name: 'Documents', path: '$base/Documents', exists: false),
        ScanSource(name: 'DCIM', path: '$base/DCIM', exists: false),
        ScanSource(name: 'Screenshots', path: '$base/DCIM/Screenshots', exists: false),
        ScanSource(name: 'Pictures', path: '$base/Pictures', exists: false),
        ScanSource(name: 'WhatsApp Media', path: '$base/Android/media/com.whatsapp/WhatsApp/Media', exists: false),
        ScanSource(name: 'WhatsApp Images', path: '$base/WhatsApp/Media/WhatsApp Images', exists: false),
        ScanSource(name: 'Telegram', path: '$base/Telegram', exists: false),
      ];
    } else {
      // Linux / macOS / Windows
      final separator = Platform.isWindows ? '\\' : '/';
      return [
        ScanSource(name: 'Downloads', path: '$base${separator}Downloads', exists: false),
        ScanSource(name: 'Documents', path: '$base${separator}Documents', exists: false),
        ScanSource(name: 'Pictures', path: '$base${separator}Pictures', exists: false),
        ScanSource(name: 'Desktop', path: '$base${separator}Desktop', exists: false),
      ];
    }
  }

  /// בודק אילו מקורות קיימים
  Future<List<ScanSource>> checkAvailableSources() async {
    final sources = getScanSources();
    final results = <ScanSource>[];
    
    for (final source in sources) {
      final exists = await directoryExists(source.path);
      results.add(source.copyWith(exists: exists));
    }
    
    return results;
  }

  /// בודק אם הסיומת נתמכת לסריקה
  bool _isSupportedExtension(String extension) {
    return supportedExtensions.contains(extension.toLowerCase());
  }

  /// סורק תיקייה בודדת באופן רקורסיבי
  Future<List<FileMetadata>> _scanDirectory(String path) async {
    final files = <FileMetadata>[];
    final directory = Directory(path);
    int skipped = 0;
    
    if (!await directory.exists()) return files;

    try {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final fileName = entity.uri.pathSegments.last;
            final extension = _extractExtension(fileName);
            
            // סינון לפי סיומת - רק קבצים נתמכים
            if (!_isSupportedExtension(extension)) {
              skipped++;
              continue;
            }
            
            final stat = await entity.stat();
            final file = FileMetadata.fromFile(
              path: entity.path,
              name: fileName,
              size: stat.size,
              lastModified: stat.modified,
            );
            files.add(file);
          } catch (_) {
            // דילוג על קבצים שלא ניתן לקרוא
          }
        }
      }
    } catch (_) {
      // שגיאה בסריקת תיקייה - ממשיכים הלאה
    }
    
    if (skipped > 0) appLog('SCAN: Skipped $skipped unsupported files in $path');
    
    return files;
  }

  /// מחלץ סיומת מהשם
  String _extractExtension(String fileName) {
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  /// סורק את כל המקורות הזמינים (סריקה מלאה - wipe & replace)
  Future<ScanResult> scanAllSources({
    Function(String sourceName, int current, int total)? onProgress,
  }) async {
    // בדיקת הרשאות
    final hasPermission = await _permissionService.hasStoragePermission();
    if (!hasPermission) {
      final result = await _permissionService.requestStoragePermission();
      if (result != PermissionResult.granted) {
        return ScanResult(
          success: false,
          filesScanned: 0,
          newFilesAdded: 0,
          scannedSources: [],
          error: result == PermissionResult.permanentlyDenied
              ? 'הרשאות אחסון נדחו לצמיתות. אנא פתח את הגדרות האפליקציה.'
              : 'הרשאות אחסון נדחו.',
          permissionDenied: true,
        );
      }
    }

    final sources = getScanSources();
    final scannedSources = <ScanSource>[];
    final allFiles = <FileMetadata>[];
    int currentSource = 0;

    for (final source in sources) {
      currentSource++;
      onProgress?.call(source.name, currentSource, sources.length);

      final exists = await directoryExists(source.path);
      
      if (!exists) {
        scannedSources.add(source.copyWith(exists: false, filesFound: 0));
        continue;
      }

      final files = await _scanDirectory(source.path);
      allFiles.addAll(files);
      scannedSources.add(source.copyWith(exists: true, filesFound: files.length));
    }

    // שמירה למסד הנתונים (wipe & replace)
    appLog('SCAN: Total files: ${allFiles.length}');
    if (allFiles.isNotEmpty)
      appLog('SCAN: First file: ${allFiles.first.name}');
    _databaseService.replaceAllFiles(allFiles);
    
    final savedCount = _databaseService.getFilesCount();
    appLog('SCAN: DB count after save: $savedCount');

    return ScanResult(
      success: true,
      filesScanned: allFiles.length,
      newFilesAdded: allFiles.length,
      scannedSources: scannedSources,
    );
  }

  /// סריקה חכמה - רק קבצים חדשים (incremental)
  Future<ScanResult> scanNewFilesOnly({
    Function(String sourceName, int current, int total)? onProgress,
    bool runCleanup = true,
  }) async {
    // בדיקת הרשאות
    final hasPermission = await _permissionService.hasStoragePermission();
    if (!hasPermission) {
      final result = await _permissionService.requestStoragePermission();
      if (result != PermissionResult.granted) {
        return ScanResult(
          success: false,
          filesScanned: 0,
          newFilesAdded: 0,
          scannedSources: [],
          error: result == PermissionResult.permanentlyDenied
              ? 'הרשאות אחסון נדחו לצמיתות. אנא פתח את הגדרות האפליקציה.'
              : 'הרשאות אחסון נדחו.',
          permissionDenied: true,
        );
      }
    }

    final sources = getScanSources();
    final scannedSources = <ScanSource>[];
    final allNewFiles = <FileMetadata>[];
    int currentSource = 0;
    int totalFilesScanned = 0;

    // שליפת כל הנתיבים הקיימים במסד
    final existingPaths = _databaseService.getAllPaths();

    for (final source in sources) {
      currentSource++;
      onProgress?.call(source.name, currentSource, sources.length);

      final exists = await directoryExists(source.path);
      
      if (!exists) {
        scannedSources.add(source.copyWith(exists: false, filesFound: 0));
        continue;
      }

      // סריקת התיקייה
      final files = await _scanDirectory(source.path);
      totalFilesScanned += files.length;
      
      // סינון רק קבצים חדשים
      final newFiles = files.where((f) => !existingPaths.contains(f.path)).toList();
      allNewFiles.addAll(newFiles);
      
      scannedSources.add(source.copyWith(exists: true, filesFound: files.length));
    }

    // הוספת קבצים חדשים למסד
    if (allNewFiles.isNotEmpty) {
      _databaseService.saveFiles(allNewFiles);
    }

    // ניקוי קבצים מיושנים
    int staleFilesRemoved = 0;
    if (runCleanup) {
      staleFilesRemoved = await _databaseService.cleanupStaleFiles();
    }

    return ScanResult(
      success: true,
      filesScanned: totalFilesScanned,
      newFilesAdded: allNewFiles.length,
      staleFilesRemoved: staleFilesRemoved,
      scannedSources: scannedSources,
    );
  }

  /// מעבד קובץ בודד - סריקה + OCR
  Future<FileMetadata?> processNewFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final fileName = file.uri.pathSegments.last;
      final extension = _extractExtension(fileName);
      
      // בדיקה אם הסיומת נתמכת
      if (!_isSupportedExtension(extension)) return null;

      // בדיקה אם הקובץ כבר קיים במסד
      final existing = _databaseService.getFileByPath(filePath);
      if (existing != null) return existing;

      final stat = await file.stat();
      final metadata = FileMetadata.fromFile(
        path: filePath,
        name: fileName,
        size: stat.size,
        lastModified: stat.modified,
      );

      // שמירה למסד
      _databaseService.saveFile(metadata);

      // הרצת OCR אם זו תמונה
      if (imageExtensions.contains(extension)) {
        final extractedText = await _ocrService.extractText(filePath);
        metadata.extractedText = extractedText;
        metadata.isIndexed = true;
        _databaseService.updateFile(metadata);
      }

      return metadata;
    } catch (_) {
      return null;
    }
  }

  /// סורק את תיקיית Downloads בלבד (תאימות לאחור)
  Future<ScanResult> scanDownloadsFolder() async {
    final hasPermission = await _permissionService.hasStoragePermission();
    if (!hasPermission) {
      final result = await _permissionService.requestStoragePermission();
      if (result != PermissionResult.granted) {
        return ScanResult(
          success: false,
          filesScanned: 0,
          scannedSources: [],
          error: result == PermissionResult.permanentlyDenied
              ? 'הרשאות אחסון נדחו לצמיתות. אנא פתח את הגדרות האפליקציה.'
              : 'הרשאות אחסון נדחו.',
          permissionDenied: true,
        );
      }
    }

    final sources = getScanSources();
    final downloadSource = sources.firstWhere(
      (s) => s.name == 'Downloads',
      orElse: () => ScanSource(name: 'Downloads', path: '', exists: false),
    );

    if (downloadSource.path.isEmpty || !await directoryExists(downloadSource.path)) {
      return ScanResult(
        success: false,
        filesScanned: 0,
        scannedSources: [downloadSource.copyWith(exists: false)],
        error: 'תיקיית Downloads לא נמצאה',
      );
    }

    final files = await _scanDirectory(downloadSource.path);
    _databaseService.replaceAllFiles(files);

    return ScanResult(
      success: true,
      filesScanned: files.length,
      scannedSources: [downloadSource.copyWith(exists: true, filesFound: files.length)],
    );
  }

  /// מעבד קבצים שטרם עברו אינדוקס (OCR לתמונות, חילוץ טקסט למסמכים)
  Future<ProcessResult> processPendingFiles({
    Function(int current, int total)? onProgress,
  }) async {
    try {
      // קבלת כל הקבצים שטרם עובדו
      final pendingImages = _databaseService.getPendingImageFiles();
      final pendingTextFiles = _databaseService.getPendingTextFiles();
      final totalPending = pendingImages.length + pendingTextFiles.length;
      
      if (totalPending == 0) {
        return ProcessResult(
          success: true,
          filesProcessed: 0,
          filesWithText: 0,
          message: 'אין קבצים לעיבוד',
        );
      }

      appLog('PROCESS: ${pendingImages.length} images, ${pendingTextFiles.length} text files');

      int filesProcessed = 0;
      int filesWithText = 0;

      // עיבוד תמונות עם OCR
      for (final file in pendingImages) {
        onProgress?.call(filesProcessed + 1, totalPending);

        final extractedText = await _ocrService.extractText(file.path);

        file.extractedText = extractedText;
        file.isIndexed = true;
        _databaseService.updateFile(file);

        filesProcessed++;
        if (extractedText.isNotEmpty) filesWithText++;
      }

      // עיבוד קבצי טקסט ו-PDF
      for (final file in pendingTextFiles) {
        onProgress?.call(filesProcessed + 1, totalPending);

        final extractedText = await _textExtractionService.extractText(file.path);

        file.extractedText = extractedText;
        file.isIndexed = true;
        _databaseService.updateFile(file);

        filesProcessed++;
        if (extractedText.isNotEmpty) filesWithText++;
      }

      appLog('PROCESS: Done - $filesProcessed files, $filesWithText with text');

      return ProcessResult(
        success: true,
        filesProcessed: filesProcessed,
        filesWithText: filesWithText,
        message: 'עובדו $filesProcessed קבצים, נמצא טקסט ב-$filesWithText קבצים',
      );
    } catch (e) {
      appLog('PROCESS ERROR: $e');
      return ProcessResult(
        success: false,
        filesProcessed: 0,
        filesWithText: 0,
        error: 'שגיאה בעיבוד קבצים: $e',
      );
    }
  }
}

/// תוצאת עיבוד OCR
class ProcessResult {
  final bool success;
  final int filesProcessed;
  final int filesWithText;
  final String? message;
  final String? error;

  ProcessResult({
    required this.success,
    required this.filesProcessed,
    required this.filesWithText,
    this.message,
    this.error,
  });

  @override
  String toString() {
    if (success) return message ?? 'עיבוד הושלם בהצלחה';
    return error ?? 'עיבוד נכשל';
  }
}

/// תוצאת סריקה
class ScanResult {
  final bool success;
  final int filesScanned;
  final int newFilesAdded;
  final int staleFilesRemoved;
  final List<ScanSource> scannedSources;
  final String? error;
  final bool permissionDenied;

  ScanResult({
    required this.success,
    required this.filesScanned,
    required this.scannedSources,
    this.newFilesAdded = 0,
    this.staleFilesRemoved = 0,
    this.error,
    this.permissionDenied = false,
  });

  /// מחזיר רק את המקורות שנמצאו
  List<ScanSource> get availableSources => 
      scannedSources.where((s) => s.exists).toList();

  /// מחזיר את מספר המקורות הזמינים
  int get availableSourcesCount => availableSources.length;

  @override
  String toString() {
    if (success) {
      if (newFilesAdded > 0 || staleFilesRemoved > 0) {
        return 'נוספו $newFilesAdded קבצים חדשים, הוסרו $staleFilesRemoved מיושנים';
      }
      return 'סריקה הצליחה: $filesScanned קבצים נסרקו מ-$availableSourcesCount מקורות';
    }
    return 'סריקה נכשלה: $error';
  }
}
