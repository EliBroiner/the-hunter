import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/file_metadata.dart';
import '../utils/log_sanitization.dart';
import 'backup_service.dart';
import 'database_service.dart';
import 'file_processing_service.dart';
import 'log_service.dart';
import 'permission_service.dart';
import 'settings_service.dart';
import 'sync_manager.dart';
import 'user_activity_service.dart';

/// מפתח לשמירת תיקיות נבחרות
const String _selectedFoldersKey = 'selected_scan_folders';

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
  })  : _databaseService = databaseService ?? DatabaseService.instance,
        _permissionService = permissionService ?? PermissionService.instance;

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

  /// מחזיר רשימת מקורות סריקה לפי פלטפורמה (סינכרוני - ברירת מחדל)
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
  
  /// מפתח לסימון שהמשתמש השלים את בחירת התיקיות (התקנה ראשונה)
  static const String _folderSetupCompletedKey = 'has_completed_folder_setup';

  /// מחזיר רשימת מקורות סריקה מותאמות אישית (אסינכרוני)
  /// אם המשתמש טרם השלים את בחירת התיקיות — מחזיר רשימה ריקה (אין סריקה אוטומטית)
  Future<List<ScanSource>> getCustomScanSources() async {
    final base = basePath;
    if (base.isEmpty) return [];

    try {
      final prefs = await SharedPreferences.getInstance();
      var hasCompleted = prefs.getBool(_folderSetupCompletedKey) ?? false;
      final customPaths = prefs.getStringList(_selectedFoldersKey);

      // מיגרציה: משתמש קיים עם נתיבים שמורים נחשב כהשלמה
      if (!hasCompleted && customPaths != null) {
        await prefs.setBool(_folderSetupCompletedKey, true);
        hasCompleted = true;
      }
      if (!hasCompleted) {
        appLog('FileScannerService: Folder setup not completed — no scan');
        return [];
      }
      if (customPaths != null && customPaths.isNotEmpty) {
        appLog('FileScannerService: Using ${customPaths.length} custom folders');
        return customPaths.map((path) {
          final parts = path.split(Platform.pathSeparator);
          final name = parts.isEmpty ? path : parts.last;
          return ScanSource(name: name, path: path, exists: false);
        }).toList();
      }
    } catch (e) {
      appLog('FileScannerService: Error loading custom folders: $e');
    }

    return [];
  }

  /// בודק אם המשתמש השלים את בחירת התיקיות (התקנה ראשונה)
  static Future<bool> hasCompletedFolderSetup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_folderSetupCompletedKey) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// מסמן שהמשתמש השלים את בחירת התיקיות
  static Future<void> markFolderSetupCompleted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_folderSetupCompletedKey, true);
    } catch (e) {
      appLog('FileScannerService: Error marking folder setup: $e');
    }
  }

  /// מאפס את בחירת התיקיות — המשתמש יראה את פופאפ הבחירה שוב בהפעלה הבאה
  static Future<void> resetFolderSetup() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_folderSetupCompletedKey);
      await prefs.remove(_selectedFoldersKey);
      appLog('FileScannerService: Folder setup reset');
    } catch (e) {
      appLog('FileScannerService: Error resetting folder setup: $e');
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

  /// גודל מינימלי לקובץ (15KB) - מסנן אייקונים קטנים ונכסים
  static const int _minFileSizeBytes = 15 * 1024;
  
  /// נתיבי cache/junk לסינון (כולל .thumb)
  static const List<String> _junkPathPatterns = [
    '/cache/',
    '/.thumbnails/',
    '/.thumb/',
    '/log/',
    '/Cache/',
    '/Thumbnails/',
  ];

  /// סורק תיקייה בודדת באופן רקורסיבי
  Future<List<FileMetadata>> _scanDirectory(String path) async {
    final files = <FileMetadata>[];
    final directory = Directory(path);
    int skipped = 0;
    int skippedHidden = 0;
    int skippedCache = 0;
    int skippedSmall = 0;
    
    if (!await directory.exists()) return files;

    try {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            final fileName = entity.uri.pathSegments.last;
            final filePath = entity.path;
            final extension = _extractExtension(fileName);
            
            // 1. סינון קבצים נסתרים (מתחילים בנקודה) וקבצי ג'אנק (thumbnail_, .thumb)
            if (fileName.startsWith('.') || _isJunkFileName(fileName)) {
              skippedHidden++;
              continue;
            }
            // 2. סינון תיקיות נסתרות (נתיב מכיל תיקייה שמתחילה ב־.)
            if (_pathContainsHiddenFolder(filePath)) {
              skippedHidden++;
              continue;
            }
            // 3. סינון נתיבי cache/junk
            if (_isJunkPath(filePath)) {
              skippedCache++;
              continue;
            }
            
            // 4. סינון לפי סיומת - רק קבצים נתמכים
            if (!_isSupportedExtension(extension)) {
              skipped++;
              continue;
            }
            
            final stat = await entity.stat();
            
            // 5. סינון קבצים קטנים מדי (פחות מ-15KB)
            if (stat.size < _minFileSizeBytes) {
              skippedSmall++;
              continue;
            }
            
            final file = FileMetadata.fromFile(
              path: filePath,
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
    
    final totalSkipped = skipped + skippedHidden + skippedCache + skippedSmall;
    if (totalSkipped > 0) {
      appLog('SCAN: Skipped in $path: $skipped unsupported, $skippedHidden hidden, $skippedCache cache, $skippedSmall small');
    }
    
    return files;
  }
  
  /// קבצים שמתחילים ב־thumbnail_ או .thumb — מתעלמים
  bool _isJunkFileName(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.startsWith('thumbnail_') || lower.startsWith('.thumb');
  }

  /// נתיב שנמצא בתוך תיקייה נסתרת (מתחילה ב־.)
  bool _pathContainsHiddenFolder(String path) {
    final sep = path.contains('\\') ? '\\' : '/';
    for (final segment in path.split(sep)) {
      if (segment.isNotEmpty && segment.startsWith('.')) return true;
    }
    return false;
  }

  /// בודק אם הנתיב הוא נתיב cache/junk
  bool _isJunkPath(String path) {
    final lowerPath = path.toLowerCase();
    for (final pattern in _junkPathPatterns) {
      if (lowerPath.contains(pattern.toLowerCase())) {
        return true;
      }
    }
    return false;
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

    // שימוש בתיקיות מותאמות אישית אם קיימות
    final sources = await getCustomScanSources();
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
    if (allFiles.isNotEmpty) {
      appLog('SCAN: First file: ${allFiles.first.name}');
    }
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

    // שימוש בתיקיות מותאמות אישית אם קיימות
    final sources = await getCustomScanSources();
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

  /// סריקה חכמה עם שחזור מגיבוי - חוסכת OCR על קבצים שכבר עובדו בעבר!
  /// 
  /// זרימה:
  /// 1. סורק את כל הקבצים במכשיר
  /// 2. אם יש גיבוי - ממזג את הנתונים (טקסט מחולץ) מהגיבוי
  /// 3. רק קבצים שלא היו בגיבוי יעברו OCR
  Future<ScanResult> scanWithBackupRestore({
    Function(String status)? onStatus,
    Function(String sourceName, int current, int total)? onProgress,
    required Future<Map<String, dynamic>?> Function() getBackupData,
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
          error: 'הרשאות אחסון נדחו.',
          permissionDenied: true,
        );
      }
    }

    onStatus?.call('סורק קבצים...');
    
    // שימוש בתיקיות מותאמות אישית אם קיימות
    final sources = await getCustomScanSources();
    final scannedSources = <ScanSource>[];
    final allFiles = <FileMetadata>[];
    int currentSource = 0;
    int totalFilesScanned = 0;

    // שלב 1: סריקת כל הקבצים במכשיר
    for (final source in sources) {
      currentSource++;
      onProgress?.call(source.name, currentSource, sources.length);

      final exists = await directoryExists(source.path);
      
      if (!exists) {
        scannedSources.add(source.copyWith(exists: false, filesFound: 0));
        continue;
      }

      final files = await _scanDirectory(source.path);
      totalFilesScanned += files.length;
      allFiles.addAll(files);
      
      scannedSources.add(source.copyWith(exists: true, filesFound: files.length));
    }

    appLog('ScanWithBackup: Found $totalFilesScanned files on device');

    // שלב 2: ניסיון לקבל נתוני גיבוי
    onStatus?.call('בודק גיבוי קיים...');
    int skippedOcrCount = 0;
    
    try {
      final backupData = await getBackupData();
      
      if (backupData != null) {
        final backupFiles = backupData['files'] as List<dynamic>?;
        
        if (backupFiles != null && backupFiles.isNotEmpty) {
          onStatus?.call('ממזג נתונים מגיבוי...');
          
          // יצירת מפה של קבצי הגיבוי לפי נתיב
          final backupMap = <String, Map<String, dynamic>>{};
          for (final fileJson in backupFiles) {
            final path = fileJson['path'] as String?;
            if (path != null) {
              backupMap[path] = fileJson as Map<String, dynamic>;
            }
          }

          appLog('ScanWithBackup: Found ${backupMap.length} files in backup');

          // מיזוג: לכל קובץ במכשיר, בדוק אם יש לו נתונים בגיבוי
          for (final deviceFile in allFiles) {
            final backupFileData = backupMap[deviceFile.path];
            
            if (backupFileData != null) {
              final backupText = backupFileData['extractedText'] as String?;
              final backupIsIndexed = backupFileData['isIndexed'] as bool? ?? false;
              
              if (backupIsIndexed) {
                // הקובץ כבר עבר עיבוד בגיבוי - משתמשים בנתונים!
                deviceFile.extractedText = backupText ?? '';
                deviceFile.isIndexed = true;
                skippedOcrCount++;
              }
            }
          }

          appLog('ScanWithBackup: Merged $skippedOcrCount files from backup (saved OCR!)');
        }
      }
    } catch (e) {
      appLog('ScanWithBackup: Backup merge failed (continuing without) - $e');
    }

    // שלב 3: שמירה למסד
    onStatus?.call('שומר נתונים...');
    _databaseService.replaceAllFiles(allFiles);

    // שלב 4: ניקוי
    final staleFilesRemoved = await _databaseService.cleanupStaleFiles();

    return ScanResult(
      success: true,
      filesScanned: totalFilesScanned,
      newFilesAdded: allFiles.length,
      staleFilesRemoved: staleFilesRemoved,
      scannedSources: scannedSources,
      skippedOcrCount: skippedOcrCount,
    );
  }

  /// מעבד קובץ בודד - סריקה + OCR + תיוג אוטומטי
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

      // תיוג אוטומטי בסיסי (לפי שם)
      metadata.tags = _generateAutoTags(fileName, extension, null);

      // שמירה למסד
      _databaseService.saveFile(metadata);

      if (imageExtensions.contains(extension) || textExtensions.contains(extension) || documentExtensions.contains(extension)) {
        await FileProcessingService.instance.processFileWorkflow(
          metadata,
          isPro: SettingsService.instance.isPremium,
        );
        _mergeContentTags(metadata, fileName, extension);
        _databaseService.updateFile(metadata);
      }

      return metadata;
    } catch (_) {
      return null;
    }
  }

  /// ממזג תגיות אוטומטיות לפי תוכן ל־file.tags
  void _mergeContentTags(FileMetadata file, String fileName, String extension) {
    final contentTags = _generateAutoTags(fileName, extension, file.extractedText);
    if (contentTags.isEmpty) return;
    final currentTags = file.tags ?? [];
    final newTags = contentTags.where((t) => !currentTags.contains(t)).toList();
    if (newTags.isNotEmpty) file.tags = [...currentTags, ...newTags];
  }

  /// מייצר תגיות אוטומטיות לפי שם ותוכן
  List<String> _generateAutoTags(String fileName, String extension, String? content) {
    final tags = <String>{};
    final lowerName = fileName.toLowerCase();
    final lowerContent = content?.toLowerCase() ?? '';
    
    // מילות מפתח פיננסיות
    if (lowerName.contains('invoice') || lowerName.contains('חשבונית') || 
        lowerName.contains('receipt') || lowerName.contains('קבלה') ||
        lowerContent.contains('חשבונית') || lowerContent.contains('קבלה') || lowerContent.contains('סה"כ לתשלום')) {
      tags.add('פיננסי');
    }
    
    // מסמכים אישיים
    if (lowerName.contains('id') || lowerName.contains('passport') || lowerName.contains('תעודת זהות') ||
        lowerContent.contains('תעודת זהות') || lowerContent.contains('דרכון')) {
      tags.add('אישי');
    }
    
    // חוזים
    if (lowerName.contains('contract') || lowerName.contains('agreement') || lowerName.contains('חוזה') || lowerName.contains('הסכם') ||
        lowerContent.contains('חוזה') || lowerContent.contains('הסכם')) {
      tags.add('חוזים');
    }
    
    // מקורות
    if (lowerName.contains('whatsapp')) tags.add('WhatsApp');
    if (lowerName.contains('screenshot') || lowerName.contains('screen_shot') || lowerName.contains('צילום מסך')) tags.add('צילומי מסך');
    if (lowerName.contains('telegram')) tags.add('Telegram');
    if (lowerName.contains('facebook')) tags.add('Facebook');
    if (lowerName.contains('instagram')) tags.add('Instagram');
    if (lowerName.contains('camera') || lowerName.contains('dcim')) tags.add('מצלמה');
    
    // סוגי קבצים
    if (extension == 'pdf') tags.add('PDF');
    if (['doc', 'docx'].contains(extension)) tags.add('Word');
    if (['xls', 'xlsx', 'csv'].contains(extension)) tags.add('Excel');
    
    return tags.toList();
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

  /// בודק ומפעיל גיבוי ביניים
  Future<void> _checkAndTriggerBackup(int count) async {
    // מפעיל כל 100 קבצים שעובדו
    if (count > 0 && count % 100 == 0) {
      final backupService = BackupService.instance;
      // בודק אם גיבוי זמין ומופעל
      if (backupService.isAvailable && await backupService.isAutoBackupEnabled()) {
        appLog('PROCESS: Triggering intermediate backup (processed $count files)...');
        // מפעיל ברקע - לא ממתין כדי לא לחסום את העיבוד
        backupService.smartBackup().then((result) {
          if (result.success) {
            appLog('PROCESS: Intermediate backup success');
          }
        }).catchError((e) {
          appLog('PROCESS: Intermediate backup failed: $e');
        });
      }
    }
  }

  /// מאפס תמונות (כולן או רק בלי טקסט) ואז מריץ OCR מחדש.
  /// [onlyEmptyText] true = רק תמונות בלי extractedText (חוסך סריקות קיימות).
  Future<({int resetCount, ProcessResult result})> reindexImages({
    required bool onlyEmptyText,
    Function(int current, int total)? onProgress,
    bool Function()? shouldPause,
    int batchSize = 3,
    int delayBetweenBatchesMs = 500,
    int delayBetweenFilesMs = 100,
  }) async {
    final n = _databaseService.resetOcrForImages(onlyEmptyText: onlyEmptyText);
    appLog('REINDEX: reset $n images (onlyEmptyText=$onlyEmptyText), running processPendingFiles');
    final result = await processPendingFiles(
      onProgress: onProgress,
      shouldPause: shouldPause,
      batchSize: batchSize,
      delayBetweenBatchesMs: delayBetweenBatchesMs,
      delayBetweenFilesMs: delayBetweenFilesMs,
    );
    return (resetCount: n, result: result);
  }

  /// עיבוד מקבילי — עד [parallelism] קבצים במקביל בתוך אצווה.
  static const int maxBatchSize = 5;
  static const int parallelism = 3;

  /// מעבד קובץ בודד — מחזיר true אם יש טקסט מחולץ.
  Future<bool> _processOneFile(
    FileMetadata file,
    bool Function()? shouldPause,
  ) async {
    appLog('🕵️ Processing file: ${file.path} (ID: ${file.id})');
    try {
      await FileProcessingService.instance.processFileWorkflow(
        file,
        isPro: SettingsService.instance.isPremium,
        isCanceled: shouldPause,
      );
      _mergeContentTags(file, file.name, file.extension);
      _databaseService.updateFile(file);
      appLog('✅ Done processing: ${file.path}');
      return (file.extractedText ?? '').isNotEmpty;
    } catch (e, st) {
      appLog('❌ CRASH on file: ${file.path} - ${sanitizeError(e, st)}');
      file.isIndexed = true;
      file.extractedText = '';
      file.aiStatus = 'error';
      _databaseService.updateFile(file);
      return false;
    }
  }

  /// מעבד קבצים שטרם עברו אינדוקס (OCR לתמונות, חילוץ טקסט למסמכים)
  /// עיבוד מקבילי — עד 3 קבצים ב-Future.wait במקביל, אצוות של 5.
  /// shouldPause - פונקציה שמחזירה true אם צריך להשהות את העיבוד
  /// maxFilesPerSession - מגביל כמה קבצים לעבד במהלך קריאה אחת (למניעת חימום יתר)
  Future<ProcessResult> processPendingFiles({
    Function(int current, int total)? onProgress,
    bool Function()? shouldPause,
    int? maxFilesPerSession,
    int batchSize = maxBatchSize,
    int delayBetweenBatchesMs = 800,  // השהיה בין אצוות
    int delayBetweenFilesMs = 100,   // השהיה קצרה בין קבצים בתוך אצווה
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

      // סנכרון מהיר לפני אצווה — עוקף throttle כי יש קבצים חדשים (אולי Uncategorized)
      await PeriodicSyncService.instance.checkDictionaryVersion(hasUncategorized: true);

      appLog('PROCESS: ${pendingImages.length} images, ${pendingTextFiles.length} text files (batch: $batchSize)');

      int filesProcessed = 0;
      int filesWithText = 0;
      final allPending = [...pendingImages, ...pendingTextFiles];
      var offset = 0;

      while (offset < allPending.length) {
        if (maxFilesPerSession != null && filesProcessed >= maxFilesPerSession) break;
        await Future.delayed(Duration.zero);

        if (UserActivityService.instance.isUserActive.value) {
          appLog('PROCESS: Paused (user active), waiting for idle...');
          await UserActivityService.instance.waitForIdle();
          appLog('PROCESS: Resumed (user idle)');
        }
        if (shouldPause?.call() == true) {
          appLog('PROCESS: Paused by user activity');
          return ProcessResult(
            success: true,
            filesProcessed: filesProcessed,
            filesWithText: filesWithText,
            message: 'עיבוד הושהה - $filesProcessed קבצים עובדו',
          );
        }

        final batch = allPending.skip(offset).take(batchSize).toList();
        if (batch.isEmpty) break;

        final batchStopwatch = Stopwatch()..start();
        appLog('[PERF] Batch of ${batch.length} started in parallel.');

        for (var i = 0; i < batch.length; i += parallelism) {
          if (shouldPause?.call() == true) {
            return ProcessResult(
              success: true,
              filesProcessed: filesProcessed,
              filesWithText: filesWithText,
              message: 'עיבוד הושהה - $filesProcessed קבצים עובדו',
            );
          }
          final chunk = batch.skip(i).take(parallelism).toList();
          final results = await Future.wait(
            chunk.map((file) => _processOneFile(file, shouldPause)),
          );
          for (var j = 0; j < chunk.length; j++) {
            filesProcessed++;
            if (results[j]) filesWithText++;
            onProgress?.call(filesProcessed, totalPending);
            _checkAndTriggerBackup(filesProcessed);
          }
          if (i + parallelism < batch.length) {
            await Future.delayed(Duration(milliseconds: delayBetweenFilesMs));
          }
        }

        batchStopwatch.stop();
        appLog('[PERF] Total processing time for batch: ${batchStopwatch.elapsedMilliseconds}ms.');
        offset += batch.length;
        await Future.delayed(Duration(milliseconds: delayBetweenBatchesMs));
      }

      appLog('PROCESS: Done - $filesProcessed files, $filesWithText with text');

      return ProcessResult(
        success: true,
        filesProcessed: filesProcessed,
        filesWithText: filesWithText,
        message: 'עובדו $filesProcessed קבצים, נמצא טקסט ב-$filesWithText קבצים',
      );
    } catch (e, st) {
      appLog('PROCESS ERROR: ${sanitizeError(e, st)}');
      return ProcessResult(
        success: false,
        filesProcessed: 0,
        filesWithText: 0,
        error: 'שגיאה בעיבוד קבצים: ${sanitizeError(e)}',
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
  final int skippedOcrCount; // כמה קבצים חסכנו OCR בזכות גיבוי
  final List<ScanSource> scannedSources;
  final String? error;
  final bool permissionDenied;

  ScanResult({
    required this.success,
    required this.filesScanned,
    required this.scannedSources,
    this.newFilesAdded = 0,
    this.staleFilesRemoved = 0,
    this.skippedOcrCount = 0,
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
