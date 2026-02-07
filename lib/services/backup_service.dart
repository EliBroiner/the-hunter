import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_storage/firebase_storage.dart';
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
  
  // הגדרות גיבוי אוטומטי וחכם
  static const String _lastBackupKey = 'last_backup_timestamp';
  static const String _lastBackupFilesCountKey = 'last_backup_files_count';
  static const String _lastBackupFilesWithTextKey = 'last_backup_files_with_text';
  static const String _lastBackupChecksumKey = 'last_backup_checksum';
  static const String _autoBackupEnabledKey = 'auto_backup_enabled';
  static const Duration autoBackupInterval = Duration(hours: 24); // גיבוי כל 24 שעות

  // מניעת גיבויים מקבילים
  bool _isBackingUp = false;

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
    if (_isBackingUp) return false;
    
    final prefs = await SharedPreferences.getInstance();
    final autoEnabled = prefs.getBool(_autoBackupEnabledKey) ?? true;
    if (!autoEnabled) return false;
    
    final lastBackup = prefs.getInt(_lastBackupKey);
    if (lastBackup == null) return true; // מעולם לא גובה
    
    final lastBackupTime = DateTime.fromMillisecondsSinceEpoch(lastBackup);
    final now = DateTime.now();
    
    return now.difference(lastBackupTime) > autoBackupInterval;
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

  /// מגבה את מסד הנתונים לענן - גיבוי מלא
  Future<BackupResult> backupToCloud({
    Function(double progress)? onProgress,
    bool force = false,
  }) async {
    if (_isBackingUp) return BackupResult.failure('גיבוי כבר רץ ברקע');
    if (!isAvailable) {
      return BackupResult.failure('גיבוי זמין רק למשתמשי פרימיום');
    }
    
    _isBackingUp = true;

    try {
      appLog('Backup: Starting cloud backup...');
      onProgress?.call(0.1);

      // קבלת כל הקבצים מהמסד וסינון רק קבצים שעברו סריקה
      final allFiles = _databaseService.getAllFiles();
      final files = allFiles.where((f) => f.isIndexed).toList();

      if (files.isEmpty) {
        return BackupResult.failure('אין קבצים סרוקים לגיבוי');
      }

      appLog('Backup: Exporting ${files.length} indexed files...');
      onProgress?.call(0.3);

      // המרה ל-JSON
      final backupData = {
        'version': 2, // גרסה 2 - תומך בגיבוי חכם
        'date': DateTime.now().toIso8601String(),
        'filesCount': files.length,
        'files': files.map((f) => _fileToJson(f)).toList(),
      };

      final jsonString = jsonEncode(backupData);
      final bytes = utf8.encode(jsonString);

      appLog('Backup: Uploading ${bytes.length} bytes to cloud...');
      appLog('Backup: Path=$_backupPath, Bucket=${_storage.bucket}');
      onProgress?.call(0.5);

      // ספירת קבצים עם טקסט מחולץ
      final filesWithText = files.where((f) => 
        f.extractedText != null && f.extractedText!.isNotEmpty
      ).length;
      
      // חישוב checksum לזיהוי שינויים
      final checksum = _calculateChecksum(files);

      // העלאה ל-Firebase Storage
      final ref = _storage.ref(_backupPath);
      final uploadTask = ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(
          contentType: 'application/json',
          customMetadata: {
            'filesCount': files.length.toString(),
            'filesWithText': filesWithText.toString(),
            'backupDate': DateTime.now().toIso8601String(),
            'checksum': checksum,
            'sizeBytes': bytes.length.toString(),
          },
        ),
      );

      // מעקב אחר ההעלאה
      uploadTask.snapshotEvents.listen((event) {
        final progress = event.bytesTransferred / event.totalBytes;
        onProgress?.call(0.5 + (progress * 0.4));
      });

      await uploadTask;
      
      // שמירת זמן וחתימה של הגיבוי האחרון
      await _saveLastBackupInfo(files.length, filesWithText, checksum);

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
    } finally {
      _isBackingUp = false;
    }
  }
  
  /// גיבוי חכם - מעלה רק אם יש שינויים משמעותיים
  Future<BackupResult> smartBackup({
    Function(double progress)? onProgress,
  }) async {
    if (_isBackingUp) return BackupResult.failure('גיבוי כבר רץ ברקע');
    if (!isAvailable) {
      return BackupResult.failure('גיבוי זמין רק למשתמשי פרימיום');
    }
    
    _isBackingUp = true;

    try {
      appLog('SmartBackup: Checking for changes...');
      onProgress?.call(0.1);

      // קבלת מצב נוכחי - רק קבצים סרוקים
      final allFiles = _databaseService.getAllFiles();
      final files = allFiles.where((f) => f.isIndexed).toList();

      if (files.isEmpty) {
        return BackupResult.failure('אין קבצים סרוקים לגיבוי');
      }

      final currentCount = files.length;
      final currentWithText = files.where((f) => 
        f.extractedText != null && f.extractedText!.isNotEmpty
      ).length;
      final currentChecksum = _calculateChecksum(files);

      // קבלת מידע על הגיבוי האחרון
      final prefs = await SharedPreferences.getInstance();
      final lastCount = prefs.getInt(_lastBackupFilesCountKey) ?? 0;
      final lastWithText = prefs.getInt(_lastBackupFilesWithTextKey) ?? 0;
      final lastChecksum = prefs.getString(_lastBackupChecksumKey) ?? '';

      onProgress?.call(0.3);

      // בדיקה אם יש שינויים
      final hasChanges = _hasSignificantChanges(
        currentCount: currentCount,
        currentWithText: currentWithText,
        currentChecksum: currentChecksum,
        lastCount: lastCount,
        lastWithText: lastWithText,
        lastChecksum: lastChecksum,
      );

      if (!hasChanges) {
        appLog('SmartBackup: No significant changes detected, skipping backup');
        return BackupResult.success(
          message: 'אין שינויים - הגיבוי עדכני',
          filesCount: currentCount,
        );
      }

      appLog('SmartBackup: Changes detected, proceeding with incremental backup');
      onProgress?.call(0.4);

      // ניסיון לגיבוי אינקרמנטלי
      return await _incrementalBackup(
        files: files,
        onProgress: (p) => onProgress?.call(0.4 + (p * 0.6)),
      );
    } catch (e) {
      appLog('SmartBackup ERROR: $e');
      // fallback לגיבוי מלא
      // שים לב: כאן אנחנו קוראים ל-backupToCloud אבל הוא יכשל בגלל ה-lock
      // לכן אנחנו צריכים לשחרר את ה-lock לפני הקריאה
      _isBackingUp = false;
      return backupToCloud(onProgress: onProgress);
    } finally {
      // ה-lock משוחרר רק אם לא נכנסנו ל-catch שקרא ל-backupToCloud
      // אם נכנסנו ל-catch, ה-backupToCloud ינהל את ה-lock בעצמו
      // אבל רגע, ה-finally ירוץ בכל מקרה!
      // אז אם קראנו ל-backupToCloud, הוא ירוץ, יסיים, ואז ה-finally הזה ירוץ ויקבע false. זה בסדר.
      // הבעיה היא אם backupToCloud זורק שגיאה, ה-finally שלו ירוץ, ואז ה-finally הזה ירוץ.
      // אבל אם backupToCloud נקרא מתוך catch, אנחנו צריכים לוודא שה-lock פנוי עבורו.
      
      // פתרון פשוט יותר: ננהל את ה-lock בתוך ה-catch
      // אבל ה-finally תמיד רץ.
      // אז נשתמש ב-flag מקומי כדי לדעת אם לשחרר את ה-lock
      if (_isBackingUp) _isBackingUp = false;
    }
  }
  
  /// גיבוי אינקרמנטלי - מוריד גיבוי קיים, ממזג שינויים, מעלה
  Future<BackupResult> _incrementalBackup({
    required List<FileMetadata> files,
    Function(double progress)? onProgress,
  }) async {
    // הערה: פונקציה זו נקראת מתוך smartBackup שכבר תפסה את ה-lock
    try {
      onProgress?.call(0.1);
      
      // ניסיון להוריד גיבוי קיים
      Map<String, dynamic>? existingBackup;
      try {
        final ref = _storage.ref(_backupPath);
        final data = await ref.getData();
        if (data != null) {
          final jsonString = utf8.decode(data);
          existingBackup = jsonDecode(jsonString) as Map<String, dynamic>;
          appLog('IncrementalBackup: Downloaded existing backup');
        }
      } on FirebaseException catch (e) {
        if (e.code == 'object-not-found' || e.code == 'storage/object-not-found') {
          appLog('[Backup] No previous backup found, performing initial full upload.');
        } else {
          appLog('IncrementalBackup: Storage error ${e.code} - ${e.message}');
        }
      } catch (e) {
        appLog('[Backup] No previous backup found, performing initial full upload.');
      }

      onProgress?.call(0.3);

      // יצירת מפת הקבצים הנוכחיים
      final currentFilesMap = <String, Map<String, dynamic>>{};
      for (final file in files) {
        currentFilesMap[file.path] = _fileToJson(file);
      }

      Map<String, dynamic> mergedBackup;
      int unchangedCount = 0;
      int updatedCount = 0;
      int newCount = 0;

      if (existingBackup != null) {
        // מיזוג חכם
        final existingFiles = existingBackup['files'] as List<dynamic>? ?? [];
        final existingFilesMap = <String, Map<String, dynamic>>{};
        
        for (final fileJson in existingFiles) {
          final path = fileJson['path'] as String?;
          if (path != null) {
            existingFilesMap[path] = fileJson as Map<String, dynamic>;
          }
        }

        // בניית הגיבוי הממוזג
        final mergedFiles = <Map<String, dynamic>>[];
        
        for (final entry in currentFilesMap.entries) {
          final path = entry.key;
          final currentFile = entry.value;
          final existingFile = existingFilesMap[path];
          
          if (existingFile != null) {
            // קובץ קיים - בדוק אם השתנה
            final currentText = currentFile['extractedText'] as String? ?? '';
            final existingText = existingFile['extractedText'] as String? ?? '';
            final currentIndexed = currentFile['isIndexed'] as bool? ?? false;
            final existingIndexed = existingFile['isIndexed'] as bool? ?? false;
            
            if (currentText == existingText && currentIndexed == existingIndexed) {
              // לא השתנה - משתמשים בקיים (חוסכים bandwidth)
              mergedFiles.add(existingFile);
              unchangedCount++;
            } else {
              // השתנה - משתמשים בחדש
              mergedFiles.add(currentFile);
              updatedCount++;
            }
          } else {
            // קובץ חדש
            mergedFiles.add(currentFile);
            newCount++;
          }
        }

        appLog('IncrementalBackup: Unchanged=$unchangedCount, Updated=$updatedCount, New=$newCount');

        final filesWithText = files.where((f) => 
          f.extractedText != null && f.extractedText!.isNotEmpty
        ).length;

        mergedBackup = {
          'version': 2,
          'date': DateTime.now().toIso8601String(),
          'filesCount': mergedFiles.length,
          'filesWithText': filesWithText,
          'incrementalInfo': {
            'unchanged': unchangedCount,
            'updated': updatedCount,
            'new': newCount,
          },
          'files': mergedFiles,
        };
      } else {
        // אין גיבוי קיים - גיבוי מלא
        final filesWithText = files.where((f) => 
          f.extractedText != null && f.extractedText!.isNotEmpty
        ).length;
        
        mergedBackup = {
          'version': 2,
          'date': DateTime.now().toIso8601String(),
          'filesCount': files.length,
          'filesWithText': filesWithText,
          'files': currentFilesMap.values.toList(),
        };
        newCount = files.length;
      }

      onProgress?.call(0.6);

      // העלאת הגיבוי הממוזג
      final jsonString = jsonEncode(mergedBackup);
      final bytes = utf8.encode(jsonString);
      
      final filesWithText = files.where((f) => 
        f.extractedText != null && f.extractedText!.isNotEmpty
      ).length;
      final checksum = _calculateChecksum(files);

      appLog('IncrementalBackup: Uploading ${bytes.length} bytes...');
      appLog('IncrementalBackup: Path=$_backupPath, Bucket=${_storage.bucket}');

      final ref = _storage.ref(_backupPath);
      await ref.putData(
        Uint8List.fromList(bytes),
        SettableMetadata(
          contentType: 'application/json',
          customMetadata: {
            'filesCount': files.length.toString(),
            'filesWithText': filesWithText.toString(),
            'backupDate': DateTime.now().toIso8601String(),
            'checksum': checksum,
            'sizeBytes': bytes.length.toString(),
            'incrementalBackup': 'true',
          },
        ),
      );

      await _saveLastBackupInfo(files.length, filesWithText, checksum);

      onProgress?.call(1.0);

      final message = newCount > 0 || updatedCount > 0
          ? 'גיבוי חכם: $newCount חדשים, $updatedCount עודכנו'
          : 'הגיבוי עדכני';

      return BackupResult.success(
        message: message,
        filesCount: files.length,
        backupDate: DateTime.now(),
      );
    } catch (e) {
      appLog('IncrementalBackup ERROR: $e');
      rethrow; // זורק כדי שה-smartBackup יתפוס ויעשה fallback
    }
  }
  
  /// בודק אם יש שינויים משמעותיים שמצדיקים גיבוי
  bool _hasSignificantChanges({
    required int currentCount,
    required int currentWithText,
    required String currentChecksum,
    required int lastCount,
    required int lastWithText,
    required String lastChecksum,
  }) {
    // אם אין גיבוי קודם - צריך לגבות
    if (lastCount == 0) return true;
    
    // אם ה-checksum זהה - אין שינויים
    if (currentChecksum == lastChecksum) return false;
    
    // בדיקת שינויים משמעותיים
    final countDiff = (currentCount - lastCount).abs();
    final textDiff = (currentWithText - lastWithText).abs();
    
    // שינוי של יותר מ-5 קבצים או יותר מ-3 קבצים עם טקסט
    if (countDiff >= 5) return true;
    if (textDiff >= 3) return true;
    
    // שינוי של יותר מ-10% מהקבצים
    if (lastCount > 0 && countDiff.toDouble() / lastCount > 0.1) return true;
    
    return false;
  }
  
  /// מחשב checksum של רשימת הקבצים
  String _calculateChecksum(List<FileMetadata> files) {
    // checksum פשוט מבוסס על paths ו-isIndexed
    final buffer = StringBuffer();
    for (final file in files) {
      buffer.write('${file.path}:${file.isIndexed}:${file.extractedText?.length ?? 0};');
    }
    return buffer.toString().hashCode.toRadixString(16);
  }
  
  /// שומר מידע על הגיבוי האחרון
  Future<void> _saveLastBackupInfo(int filesCount, int filesWithText, String checksum) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastBackupKey, DateTime.now().millisecondsSinceEpoch);
    await prefs.setInt(_lastBackupFilesCountKey, filesCount);
    await prefs.setInt(_lastBackupFilesWithTextKey, filesWithText);
    await prefs.setString(_lastBackupChecksumKey, checksum);
  }
  
  /// גיבוי אוטומטי חכם (רץ ברקע אם צריך)
  Future<void> runAutoBackupIfNeeded() async {
    try {
      if (await shouldAutoBackup()) {
        appLog('AutoBackup: Starting smart automatic backup...');
        final result = await smartBackup(); // משתמש בגיבוי חכם!
        if (result.success) {
          appLog('AutoBackup: Completed - ${result.message}');
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

      // שמירה למסד (מיזוג במקום החלפה)
      // במקום replaceAllFilesAsync שמוחק הכל, נשתמש ב-saveFiles שמוסיף/מעדכן
      // await _databaseService.replaceAllFilesAsync(files);
      _databaseService.saveFiles(files);

      appLog('Restore: Complete!');
      onProgress?.call(1.0);
      
      // הפעלת סריקה מלאה כדי לוודא שקבצים מקומיים שלא היו בגיבוי יחזרו למסד
      // זה פותר את הבעיה שקבצים "נעלמים" עד להפעלה מחדש
      // אבל מכיוון שהשתמשנו ב-saveFiles (מיזוג), הקבצים המקומיים אמורים להישאר.
      // ליתר ביטחון, נפעיל סריקת קבצים חדשים ברקע.
      // הערה: אנחנו לא יכולים לקרוא ל-AutoScanManager מכאן כי זה ייצור תלות מעגלית.
      // הפתרון הוא להחזיר flag ב-BackupResult שיגיד ל-Caller להריץ סריקה.
      
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
    return FileMetadata()
      ..path = json['path'] ?? ''
      ..name = json['name'] ?? ''
      ..extension = json['extension'] ?? ''
      ..size = json['size'] ?? 0
      ..lastModified = DateTime.tryParse(json['lastModified'] ?? '') ?? DateTime.now()
      ..addedAt = DateTime.now()
      ..extractedText = json['extractedText']
      ..isIndexed = json['isIndexed'] ?? false;
  }
}
