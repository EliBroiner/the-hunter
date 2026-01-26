import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:path_provider/path_provider.dart';
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
  final DateTime? backupDate;

  BackupResult({
    required this.success,
    this.message,
    this.error,
    this.filesCount,
    this.backupDate,
  });

  factory BackupResult.success({String? message, int? filesCount, DateTime? backupDate}) => 
    BackupResult(success: true, message: message, filesCount: filesCount, backupDate: backupDate);
  
  factory BackupResult.failure(String error) => 
    BackupResult(success: false, error: error);
}

/// מידע על גיבוי קיים
class BackupInfo {
  final DateTime date;
  final int filesCount;
  final int sizeBytes;

  BackupInfo({
    required this.date,
    required this.filesCount,
    required this.sizeBytes,
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

  /// בודק אם הגיבוי זמין (משתמש מחובר + פרימיום)
  bool get isAvailable {
    return _auth.currentUser != null && _settingsService.isPremium;
  }

  /// מחזיר את הנתיב לגיבוי בענן
  String get _backupPath {
    final userId = _auth.currentUser?.uid;
    if (userId == null) throw Exception('User not logged in');
    return 'backups/$userId/database_backup.json';
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

      // העלאה ל-Firebase Storage
      final ref = _storage.ref(_backupPath);
      final uploadTask = ref.putData(
        bytes as dynamic,
        SettableMetadata(
          contentType: 'application/json',
          customMetadata: {
            'filesCount': files.length.toString(),
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

  /// משחזר מסד נתונים מהענן
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

  /// בודק אם יש גיבוי קיים בענן
  Future<BackupInfo?> getBackupInfo() async {
    if (_auth.currentUser == null) return null;

    try {
      final ref = _storage.ref(_backupPath);
      final metadata = await ref.getMetadata();

      final filesCount = int.tryParse(metadata.customMetadata?['filesCount'] ?? '0') ?? 0;
      final backupDateStr = metadata.customMetadata?['backupDate'];
      final backupDate = backupDateStr != null 
          ? DateTime.tryParse(backupDateStr) ?? metadata.timeCreated 
          : metadata.timeCreated;

      return BackupInfo(
        date: backupDate ?? DateTime.now(),
        filesCount: filesCount,
        sizeBytes: metadata.size ?? 0,
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
