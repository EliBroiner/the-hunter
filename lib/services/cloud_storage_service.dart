import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'log_service.dart';
import 'settings_service.dart';

/// מצב העלאה
enum UploadStatus { pending, uploading, completed, failed }

/// קובץ שמור בענן
class CloudFile {
  final String name;
  final String path;
  final String cloudPath;
  final int size;
  final DateTime uploadedAt;
  final UploadStatus status;

  CloudFile({
    required this.name,
    required this.path,
    required this.cloudPath,
    required this.size,
    required this.uploadedAt,
    this.status = UploadStatus.completed,
  });
}

/// שירות אחסון בענן
class CloudStorageService {
  static CloudStorageService? _instance;
  
  CloudStorageService._();
  
  static CloudStorageService get instance {
    _instance ??= CloudStorageService._();
    return _instance!;
  }

  /// בדיקה אם יש משתמש מחובר
  bool get hasUser => FirebaseAuth.instance.currentUser != null;
  
  /// בדיקה אם פרימיום
  bool get isPremium => SettingsService.instance.isPremium;

  /// מזהה המשתמש
  String? get userId => FirebaseAuth.instance.currentUser?.uid;

  /// נתיב בסיס לאחסון קבצים
  String get _basePath => 'cloud_files/${userId ?? 'anonymous'}';

  /// העלאת קובץ לענן
  Future<CloudFile?> uploadFile(
    String localPath, {
    String? customName,
    void Function(double progress)? onProgress,
  }) async {
    if (!hasUser || !isPremium) return null;
    
    try {
      final file = File(localPath);
      if (!await file.exists()) {
        appLog('CloudStorage: File not found - $localPath');
        return null;
      }
      
      final fileName = customName ?? localPath.split('/').last;
      final cloudPath = '$_basePath/$fileName';
      final ref = FirebaseStorage.instance.ref(cloudPath);
      
      // העלאה עם מעקב התקדמות
      final uploadTask = ref.putFile(file);
      
      uploadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });
      
      await uploadTask;
      
      final size = await file.length();
      
      appLog('CloudStorage: Uploaded - $fileName');
      
      return CloudFile(
        name: fileName,
        path: localPath,
        cloudPath: cloudPath,
        size: size,
        uploadedAt: DateTime.now(),
        status: UploadStatus.completed,
      );
    } catch (e) {
      appLog('CloudStorage: Upload failed - $e');
      return null;
    }
  }

  /// הורדת קובץ מהענן
  Future<String?> downloadFile(
    String cloudPath,
    String localPath, {
    void Function(double progress)? onProgress,
  }) async {
    if (!hasUser || !isPremium) return null;
    
    try {
      final ref = FirebaseStorage.instance.ref(cloudPath);
      final file = File(localPath);
      
      // יצירת תיקייה אם לא קיימת
      final dir = file.parent;
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      
      final downloadTask = ref.writeToFile(file);
      
      downloadTask.snapshotEvents.listen((snapshot) {
        final progress = snapshot.bytesTransferred / snapshot.totalBytes;
        onProgress?.call(progress);
      });
      
      await downloadTask;
      
      appLog('CloudStorage: Downloaded - ${cloudPath.split('/').last}');
      return localPath;
    } catch (e) {
      appLog('CloudStorage: Download failed - $e');
      return null;
    }
  }

  /// רשימת קבצים בענן
  Future<List<CloudFile>> listFiles() async {
    if (!hasUser || !isPremium) return [];
    
    try {
      final ref = FirebaseStorage.instance.ref(_basePath);
      final result = await ref.listAll();
      
      final files = <CloudFile>[];
      
      for (final item in result.items) {
        final metadata = await item.getMetadata();
        files.add(CloudFile(
          name: item.name,
          path: '',
          cloudPath: item.fullPath,
          size: metadata.size ?? 0,
          uploadedAt: metadata.updated ?? DateTime.now(),
        ));
      }
      
      // מיון לפי תאריך (החדש ראשון)
      files.sort((a, b) => b.uploadedAt.compareTo(a.uploadedAt));
      
      appLog('CloudStorage: Listed ${files.length} files');
      return files;
    } catch (e) {
      appLog('CloudStorage: List failed - $e');
      return [];
    }
  }

  /// מחיקת קובץ מהענן
  Future<bool> deleteFile(String cloudPath) async {
    if (!hasUser || !isPremium) return false;
    
    try {
      final ref = FirebaseStorage.instance.ref(cloudPath);
      await ref.delete();
      
      appLog('CloudStorage: Deleted - ${cloudPath.split('/').last}');
      return true;
    } catch (e) {
      appLog('CloudStorage: Delete failed - $e');
      return false;
    }
  }

  /// קבלת URL להורדה ישירה
  Future<String?> getDownloadUrl(String cloudPath) async {
    if (!hasUser || !isPremium) return null;
    
    try {
      final ref = FirebaseStorage.instance.ref(cloudPath);
      return await ref.getDownloadURL();
    } catch (e) {
      appLog('CloudStorage: Get URL failed - $e');
      return null;
    }
  }

  /// חישוב שטח מאוחסן
  Future<int> getUsedStorage() async {
    if (!hasUser || !isPremium) return 0;
    
    try {
      final files = await listFiles();
      return files.fold(0, (sum, file) => sum + file.size);
    } catch (e) {
      appLog('CloudStorage: Get storage failed - $e');
      return 0;
    }
  }

  /// פורמט גודל קריא
  String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
