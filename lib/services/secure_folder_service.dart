import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';
import 'database_service.dart';

/// קובץ מאובטח
class SecureFile {
  final String originalPath;
  final String secureId;
  final String name;
  final String extension;
  final int size;
  final DateTime addedAt;

  SecureFile({
    required this.originalPath,
    required this.secureId,
    required this.name,
    required this.extension,
    required this.size,
    required this.addedAt,
  });

  Map<String, dynamic> toJson() => {
    'originalPath': originalPath,
    'secureId': secureId,
    'name': name,
    'extension': extension,
    'size': size,
    'addedAt': addedAt.toIso8601String(),
  };

  factory SecureFile.fromJson(Map<String, dynamic> json) => SecureFile(
    originalPath: json['originalPath'] ?? '',
    secureId: json['secureId'] ?? '',
    name: json['name'] ?? '',
    extension: json['extension'] ?? '',
    size: json['size'] ?? 0,
    addedAt: DateTime.tryParse(json['addedAt'] ?? '') ?? DateTime.now(),
  );

  /// נתיב מלא לקובץ המאובטח
  String get securePath => '$_secureFolderPath/$secureId.$extension';
  
  static String _secureFolderPath = '';
  
  /// הגדרת נתיב התיקייה המאובטחת
  static void setSecureFolderPath(String path) {
    _secureFolderPath = path;
  }
}

/// שירות ניהול תיקייה מאובטחת
class SecureFolderService {
  static SecureFolderService? _instance;
  static const String _metadataKey = 'secure_folder_metadata';
  static const String _pinKey = 'secure_folder_pin';
  
  SecureFolderService._();
  
  static SecureFolderService get instance {
    _instance ??= SecureFolderService._();
    return _instance!;
  }

  List<SecureFile> _files = [];
  String? _pin;
  String? _secureFolderPath;
  bool _isUnlocked = false;

  /// רשימת הקבצים המאובטחים
  List<SecureFile> get files => _isUnlocked ? List.unmodifiable(_files) : [];
  
  /// האם התיקייה פתוחה
  bool get isUnlocked => _isUnlocked;
  
  /// האם יש קוד PIN מוגדר
  bool get hasPin => _pin != null && _pin!.isNotEmpty;
  
  /// מספר קבצים מאובטחים
  int get fileCount => _files.length;

  /// אתחול השירות
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // טעינת PIN
      _pin = prefs.getString(_pinKey);
      
      // יצירת תיקייה מאובטחת
      final appDir = await getApplicationDocumentsDirectory();
      _secureFolderPath = '${appDir.path}/.secure';
      SecureFile.setSecureFolderPath(_secureFolderPath!);
      
      final secureDir = Directory(_secureFolderPath!);
      if (!await secureDir.exists()) {
        await secureDir.create(recursive: true);
      }
      
      // טעינת מטאדאטה
      final metadataJson = prefs.getString(_metadataKey);
      if (metadataJson != null) {
        final List<dynamic> filesList = jsonDecode(metadataJson);
        _files = filesList.map((json) => SecureFile.fromJson(json)).toList();
      }
      
      appLog('SecureFolderService: Initialized with ${_files.length} files, PIN set: $hasPin');
    } catch (e) {
      appLog('SecureFolderService: Init error - $e');
    }
  }

  /// הגדרת PIN חדש
  Future<bool> setPin(String pin) async {
    if (pin.length < 4) return false;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_pinKey, pin);
      _pin = pin;
      _isUnlocked = true;
      appLog('SecureFolderService: PIN set');
      return true;
    } catch (e) {
      appLog('SecureFolderService: Failed to set PIN - $e');
      return false;
    }
  }

  /// שינוי PIN
  Future<bool> changePin(String oldPin, String newPin) async {
    if (!verifyPin(oldPin)) return false;
    return setPin(newPin);
  }

  /// אימות PIN
  bool verifyPin(String pin) {
    return _pin == pin;
  }

  /// פתיחת התיקייה
  bool unlock(String pin) {
    if (verifyPin(pin)) {
      _isUnlocked = true;
      appLog('SecureFolderService: Unlocked');
      return true;
    }
    return false;
  }

  /// נעילת התיקייה
  void lock() {
    _isUnlocked = false;
    appLog('SecureFolderService: Locked');
  }

  /// הוספת קובץ לתיקייה המאובטחת
  Future<bool> addFile(String sourcePath, {bool moveFile = true}) async {
    if (!_isUnlocked) return false;
    
    try {
      final sourceFile = File(sourcePath);
      if (!await sourceFile.exists()) {
        appLog('SecureFolderService: Source file not found - $sourcePath');
        return false;
      }
      
      // יצירת מזהה ייחודי
      final secureId = DateTime.now().millisecondsSinceEpoch.toString();
      final fileName = sourcePath.split('/').last;
      final extension = fileName.contains('.') 
          ? fileName.split('.').last.toLowerCase() 
          : '';
      final name = fileName.contains('.')
          ? fileName.substring(0, fileName.lastIndexOf('.'))
          : fileName;
      
      final destPath = '$_secureFolderPath/$secureId.$extension';
      
      // העתקה או העברה
      if (moveFile) {
        await sourceFile.copy(destPath);
        await sourceFile.delete();
        
        // הסרה מבסיס הנתונים
        await DatabaseService.instance.deleteFile(sourcePath);
      } else {
        await sourceFile.copy(destPath);
      }
      
      // הוספה לרשימה
      final secureFile = SecureFile(
        originalPath: sourcePath,
        secureId: secureId,
        name: name,
        extension: extension,
        size: await File(destPath).length(),
        addedAt: DateTime.now(),
      );
      
      _files.add(secureFile);
      await _saveMetadata();
      
      appLog('SecureFolderService: Added file - $name.$extension');
      return true;
    } catch (e) {
      appLog('SecureFolderService: Failed to add file - $e');
      return false;
    }
  }

  /// שחזור קובץ מהתיקייה המאובטחת
  Future<bool> restoreFile(String secureId) async {
    if (!_isUnlocked) return false;
    
    try {
      final fileIndex = _files.indexWhere((f) => f.secureId == secureId);
      if (fileIndex == -1) return false;
      
      final secureFile = _files[fileIndex];
      final secureFilePath = secureFile.securePath;
      
      final file = File(secureFilePath);
      if (!await file.exists()) {
        appLog('SecureFolderService: Secure file not found - $secureFilePath');
        return false;
      }
      
      // העתקה חזרה למיקום המקורי
      final destDir = Directory(secureFile.originalPath.substring(
          0, secureFile.originalPath.lastIndexOf('/')));
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      
      await file.copy(secureFile.originalPath);
      await file.delete();
      
      // הסרה מהרשימה
      _files.removeAt(fileIndex);
      await _saveMetadata();
      
      appLog('SecureFolderService: Restored file - ${secureFile.name}');
      return true;
    } catch (e) {
      appLog('SecureFolderService: Failed to restore file - $e');
      return false;
    }
  }

  /// מחיקת קובץ מהתיקייה המאובטחת
  Future<bool> deleteFile(String secureId) async {
    if (!_isUnlocked) return false;
    
    try {
      final fileIndex = _files.indexWhere((f) => f.secureId == secureId);
      if (fileIndex == -1) return false;
      
      final secureFile = _files[fileIndex];
      final file = File(secureFile.securePath);
      
      if (await file.exists()) {
        await file.delete();
      }
      
      _files.removeAt(fileIndex);
      await _saveMetadata();
      
      appLog('SecureFolderService: Deleted file - ${secureFile.name}');
      return true;
    } catch (e) {
      appLog('SecureFolderService: Failed to delete file - $e');
      return false;
    }
  }

  /// קבלת נתיב קובץ מאובטח
  String? getSecureFilePath(String secureId) {
    if (!_isUnlocked) return null;
    
    final file = _files.firstWhere(
      (f) => f.secureId == secureId,
      orElse: () => SecureFile(
        originalPath: '',
        secureId: '',
        name: '',
        extension: '',
        size: 0,
        addedAt: DateTime.now(),
      ),
    );
    
    if (file.secureId.isEmpty) return null;
    return file.securePath;
  }

  /// שמירת מטאדאטה
  Future<void> _saveMetadata() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _files.map((f) => f.toJson()).toList();
      await prefs.setString(_metadataKey, jsonEncode(jsonList));
    } catch (e) {
      appLog('SecureFolderService: Failed to save metadata - $e');
    }
  }

  /// ניקוי התיקייה המאובטחת (מחיקת הכל)
  Future<void> clearAll() async {
    if (!_isUnlocked) return;
    
    try {
      final secureDir = Directory(_secureFolderPath!);
      if (await secureDir.exists()) {
        await for (final entity in secureDir.list()) {
          if (entity is File) {
            await entity.delete();
          }
        }
      }
      
      _files.clear();
      await _saveMetadata();
      
      appLog('SecureFolderService: Cleared all files');
    } catch (e) {
      appLog('SecureFolderService: Failed to clear - $e');
    }
  }
}
