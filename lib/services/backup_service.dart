import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/file_metadata.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'settings_service.dart';

/// תוצאת גיבוי/שחזור
class BackupResult {
  final bool success;
  final String? message;
  final String? error;
  final int? filesCount;
  final int? skippedOcrCount; // כמה קבצים חסכנו OCR
  final DateTime? backupDate;

  BackupResult({
    required this.success,
    this.message,
    this.error,
    this.filesCount,
    this.skippedOcrCount,
    this.backupDate,
  });

  factory BackupResult.success({
    String? message, 
    int? filesCount, 
    int? skippedOcrCount,
    DateTime? backupDate,
  }) => BackupResult(
    success: true, 
    message: message, 
    filesCount: filesCount,
    skippedOcrCount: skippedOcrCount,
    backupDate: backupDate,
  );
  
  factory BackupResult.failure(String error) => 
    BackupResult(success: false, error: error);
}

/// מידע על גיבוי קיים
class BackupInfo {
  final DateTime date;
  final int filesCount;
  final int sizeBytes;
  final int filesWithText; // כמה קבצים עם טקסט מחולץ

  BackupInfo({
    required this.date,
    required this.filesCount,
    required this.sizeBytes,
    this.filesWithText = 0,
  });

  String get formattedDate {
    return '${date.day}/${date.month}/${date.year} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
  }

  String get formattedSize {
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// שירות גיבוי לענן - זמין רק למשתמשי פרימיום
class BackupService {
  static BackupService? _instance;
  
  BackupService._();
  
  static BackupService get instance {
    _instance ??= BackupService._();
    return _instance!;
  }

  final _storage = FirebaseStorage.instance;
  final _auth = FirebaseAuth.instance;
  final _databaseService = DatabaseService.instance;
  final _settingsService = SettingsService.instance;
  
  // הגדרות גיבוי אוטומטי
  static const String _lastBackupKey = 'last_backup_timestamp';
  static const String _autoBackupEnabledKey = 'auto_backup_enabled';
  static const Duration autoBackupInterval = Duration(hours: 24); // גיבוי כל 24 שעות

  /// בודק אם הגיבוי זמין (משתמש מחובר + פרימיום)
  bool get isAvailable {
    return _auth.currentUser != null && _settingsService.isPremium;
  }
  
  /// בודק אם יש משתמש מחובר (בלי תלות בפרימיום - לבדיקת גיבוי קיים)
  bool get hasUser => _auth.currentUser != null;

  /// מחזיר את הנתיב לגיבוי בענן
  String get _backupPath {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('User not logged in');
    return 'backups/$userId/database_backup.json';
  }
  
  /// בודק אם צריך גיבוי אוטומטי
  Future<bool> shouldAutoBackup() async {
    if (!isAvailable) return false;
    
    final prefs = await SharedPreferences.getInstance();
    final autoEnabled = prefs.getBool(_autoBackupEnabledKey) ?? true;
    if (!autoEnabled) return false;
    
    final lastBackup = prefs.getInt(_lastBackupKey);
    if (lastBackup == null) return true; // מעולם לא גובה
    
    final lastBackupTime = DateTime.fromMillisecondsSinceEpoch(lastBackup);
    final now = DateTime.now();
    
    return now.difference(lastBackupTime) > autoBackupInterval;
  }
  
  /// שומר את זמן הגיבוי האחרון
  Future<void> _saveLastBackupTime() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastBackupKey, DateTime.now().millisecondsSinceEpoch);
  }
  
  /// מפעיל/מכבה גיבוי אוטומטי
  Future<void> setAutoBackupEnabled(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoBackupEnabledKey, enabled);
  }
  
  /// בודק אם גיבוי אוטומטי מופעל
  Future<bool> isAutoBackupEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_autoBackupEnabledKey) ?? true;
  }

  /// מגבה את מסד הנתונים לענן
  Future<BackupResult> backupToCloud({
    Function(double progress)? onProgress,
  }) async {
    if (!isAvailable) {
      return BackupResult.failure('גיבוי זמין רק למשתמשי פרימיום');
    }

    try {
      appLog('Backup: Starting cloud backup...');
      onProgress?.call(0.1);

      // קבלת כל הקבצים מהמסד
      final files = _databaseService.getAllFiles();
      if (files.isEmpty) {
        return BackupResult.failure('אין קבצים לגיבוי');
      }

      appLog('Backup: Exporting ${files.length} files...');
      onProgress?.call(0.3);

      // המרה ל-JSON
      final backupData = {
        'version': 1,
        'date': DateTime.now().toIso8601String(),
        'filesCount': files.length,
        'files': files.map((f) => _fileToJson(f)).toList(),
      };

      final jsonString = jsonEncode(backupData);
      final bytes = utf8.encode(jsonString);

      appLog('Backup: Uploading ${bytes.length} bytes to cloud...');
      onProgress?.call(0.5);

      // ספירת קבצים עם טקסט מחולץ
      final filesWithText = files.where((f) => 
        f.extractedText != null && f.extractedText!.isNotEmpty
      ).length;

      // העלאה ל-Firebase Storage
      final ref = _storage.ref(_backupPath);
      final uploadTask = ref.putData(
        bytes as dynamic,
        SettableMetadata(
          contentType: 'application/json',
          customMetadata: {
            'filesCount': files.length.toString(),
            'filesWithText': filesWithText.toString(),
            'backupDate': DateTime.now().toIso8601String(),
          },
        ),
      );

      // מעקב אחר ההעלאה
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        onProgress?.call(0.5 + (progress * 0.4));
      });

      await uploadTask;
      
      // שמירת זמן הגיבוי האחרון
      await _saveLastBackupTime();

      appLog('Backup: Upload complete!');
      onProgress?.call(1.0);

      return BackupResult.success(
        message: 'הגיבוי הושלם בהצלחה',
        filesCount: files.length,
        backupDate: DateTime.now(),
      );
    } catch (e) {
      appLog('Backup ERROR: $e');
      return BackupResult.failure('שגיאה בגיבוי: $e');
    }
  }
  
  /// גיבוי אוטומטי (רץ ברקע אם צריך)
  Future<void> runAutoBackupIfNeeded() async {
    try {
      if (await shouldAutoBackup()) {
        appLog('AutoBackup: Starting automatic backup...');
        final result = await backupToCloud();
        if (result.success) {
          appLog('AutoBackup: Completed - ${result.filesCount} files');
        } else {
          appLog('AutoBackup: Failed - ${result.error}');
        }
      }
    } catch (e) {
      appLog('AutoBackup ERROR: $e');
    }
  }

  /// משחזר מסד נתונים מהענן (שחזור מלא - מחליף הכל)
  Future<BackupResult> restoreFromCloud({
    Function(double progress)? onProgress,
  }) async {
    if (!isAvailable) {
      return BackupResult.failure('שחזור זמין רק למשתמשי פרימיום');
    }

    try {
      appLog('Restore: Starting cloud restore...');
      onProgress?.call(0.1);

      // בדיקה אם יש גיבוי
      final ref = _storage.ref(_backupPath);
      
      try {
        await ref.getMetadata();
      } catch (e) {
        return BackupResult.failure('לא נמצא גיבוי בענן');
      }

      appLog('Restore: Downloading backup...');
      onProgress?.call(0.3);

      // הורדת הקובץ
      final data = await ref.getData();
      if (data == null) {
        return BackupResult.failure('שגיאה בהורדת הגיבוי');
      }

      appLog('Restore: Parsing backup data...');
      onProgress?.call(0.5);

      // פענוח JSON
      final jsonString = utf8.decode(data);
      final backupData = jsonDecode(jsonString) as Map<String, dynamic>;

      final version = backupData['version'] as int? ?? 1;
      final filesJson = backupData['files'] as List<dynamic>;

      appLog('Restore: Restoring ${filesJson.length} files (version $version)...');
      onProgress?.call(0.7);

      // המרה לאובייקטים
      final files = filesJson.map((json) => _jsonToFile(json)).toList();

      // שמירה למסד (מחליף את הקיים)
      await _databaseService.replaceAllFilesAsync(files);

      appLog('Restore: Complete!');
      onProgress?.call(1.0);

      final backupDate = DateTime.tryParse(backupData['date'] ?? '');

      return BackupResult.success(
        message: 'השחזור הושלם בהצלחה',
        filesCount: files.length,
        backupDate: backupDate,
      );
    } catch (e) {
      appLog('Restore ERROR: $e');
      return BackupResult.failure('שגיאה בשחזור: $e');
    }
  }
  
  /// שחזור חכם - ממזג נתוני גיבוי עם קבצים קיימים במכשיר
  /// המטרה: אם קובץ קיים גם בגיבוי וגם במכשיר, להשתמש בטקסט המחולץ מהגיבוי
  /// כך חוסכים את ה-OCR על הקבצים האלה!
  Future<BackupResult> smartRestore({
    required List<FileMetadata> deviceFiles,
    Function(double progress)? onProgress,
    Function(String status)? onStatus,
  }) async {
    if (!hasUser) {
      return BackupResult.failure('משתמש לא מחובר');
    }

    try {
      appLog('SmartRestore: Starting...');
      onStatus?.call('בודק גיבוי קיים...');
      onProgress?.call(0.1);

      // הורדת הגיבוי
      final ref = _storage.ref(_backupPath);
      
      List<dynamic> backupFilesJson;
      try {
        final data = await ref.getData();
        if (data == null) {
          return BackupResult.failure('לא נמצא גיבוי');
        }
        
        final jsonString = utf8.decode(data);
        final backupData = jsonDecode(jsonString) as Map<String, dynamic>;
        backupFilesJson = backupData['files'] as List<dynamic>;
        
        appLog('SmartRestore: Found ${backupFilesJson.length} files in backup');
      } catch (e) {
        // אין גיבוי - זה בסדר, פשוט נמשיך בלי
        appLog('SmartRestore: No backup found - $e');
        return BackupResult.failure('לא נמצא גיבוי');
      }

      onStatus?.call('ממזג נתוני גיבוי...');
      onProgress?.call(0.3);

      // יצירת מפה של קבצי הגיבוי לפי נתיב
      final backupMap = <String, Map<String, dynamic>>{};
      for (final fileJson in backupFilesJson) {
        final path = fileJson['path'] as String?;
        if (path != null) {
          backupMap[path] = fileJson as Map<String, dynamic>;
        }
      }

      appLog('SmartRestore: Merging with ${deviceFiles.length} device files...');
      onProgress?.call(0.5);

      int skippedOcrCount = 0;
      int mergedCount = 0;

      // מיזוג: לכל קובץ במכשיר, בדוק אם יש לו נתונים בגיבוי
      for (final deviceFile in deviceFiles) {
        final backupData = backupMap[deviceFile.path];
        
        if (backupData != null) {
          // קובץ קיים בגיבוי!
          final backupText = backupData['extractedText'] as String?;
          final backupIsIndexed = backupData['isIndexed'] as bool? ?? false;
          
          if (backupIsIndexed && backupText != null && backupText.isNotEmpty) {
            // יש טקסט מחולץ בגיבוי - משתמשים בו במקום לעשות OCR מחדש!
            deviceFile.extractedText = backupText;
            deviceFile.isIndexed = true;
            skippedOcrCount++;
            mergedCount++;
          } else if (backupIsIndexed) {
            // הקובץ עבר אינדוקס בגיבוי (גם אם בלי טקסט)
            deviceFile.isIndexed = true;
            skippedOcrCount++;
            mergedCount++;
          }
        }
        // אם הקובץ לא בגיבוי - יישאר isIndexed=false וה-OCR ירוץ עליו
      }

      onStatus?.call('שומר נתונים...');
      onProgress?.call(0.8);

      // שמירת הקבצים הממוזגים למסד
      _databaseService.saveFiles(deviceFiles);

      appLog('SmartRestore: Complete! Merged $mergedCount files, skipped OCR for $skippedOcrCount');
      onProgress?.call(1.0);

      return BackupResult.success(
        message: 'מוזגו $mergedCount קבצים מהגיבוי',
        filesCount: deviceFiles.length,
        skippedOcrCount: skippedOcrCount,
      );
    } catch (e) {
      appLog('SmartRestore ERROR: $e');
      return BackupResult.failure('שגיאה במיזוג: $e');
    }
  }
  
  /// בודק אם יש גיבוי קיים (לבדיקה בהתקנה ראשונה)
  Future<bool> hasExistingBackup() async {
    if (!hasUser) return false;
    
    try {
      final ref = _storage.ref(_backupPath);
      await ref.getMetadata();
      return true;
    } catch (e) {
      return false;
    }
  }

  /// בודק אם יש גיבוי קיים בענן
  Future<BackupInfo?> getBackupInfo() async {
    if (_auth.currentUser == null) return null;

    try {
      final ref = _storage.ref(_backupPath);
      final metadata = await ref.getMetadata();

      final filesCount = int.tryParse(metadata.customMetadata?['filesCount'] ?? '0') ?? 0;
      final filesWithText = int.tryParse(metadata.customMetadata?['filesWithText'] ?? '0') ?? 0;
      final backupDateStr = metadata.customMetadata?['backupDate'];
      final backupDate = backupDateStr != null 
          ? DateTime.tryParse(backupDateStr) ?? metadata.timeCreated 
          : metadata.timeCreated;

      return BackupInfo(
        date: backupDate ?? DateTime.now(),
        filesCount: filesCount,
        sizeBytes: metadata.size ?? 0,
        filesWithText: filesWithText,
      );
    } catch (e) {
      // אין גיבוי
      return null;
    }
  }

  /// מוחק גיבוי קיים
  Future<bool> deleteBackup() async {
    if (_auth.currentUser == null) return false;

    try {
      final ref = _storage.ref(_backupPath);
      await ref.delete();
      appLog('Backup: Deleted successfully');
      return true;
    } catch (e) {
      appLog('Backup: Delete failed - $e');
      return false;
    }
  }

  /// ממיר FileMetadata ל-JSON
  Map<String, dynamic> _fileToJson(FileMetadata file) {
    return {
      'name': file.name,
      'path': file.path,
      'extension': file.extension,
      'size': file.size,
      'lastModified': file.lastModified.toIso8601String(),
      'extractedText': file.extractedText,
      'isIndexed': file.isIndexed,
    };
  }

  /// ממיר JSON ל-FileMetadata
  FileMetadata _jsonToFile(Map<String, dynamic> json) {
    return FileMetadata(
      name: json['name'] ?? '',
      path: json['path'] ?? '',
      extension: json['extension'] ?? '',
      size: json['size'] ?? 0,
      lastModified: DateTime.tryParse(json['lastModified'] ?? '') ?? DateTime.now(),
    )
      ..extractedText = json['extractedText']
      ..isIndexed = json['isIndexed'] ?? false;
  }
}
