import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

/// מידע על קובץ אחרון
class RecentFile {
  final String path;
  final String name;
  final String extension;
  final DateTime accessedAt;

  RecentFile({
    required this.path,
    required this.name,
    required this.extension,
    required this.accessedAt,
  });

  Map<String, dynamic> toJson() => {
    'path': path,
    'name': name,
    'extension': extension,
    'accessedAt': accessedAt.toIso8601String(),
  };

  factory RecentFile.fromJson(Map<String, dynamic> json) => RecentFile(
    path: json['path'] ?? '',
    name: json['name'] ?? '',
    extension: json['extension'] ?? '',
    accessedAt: DateTime.tryParse(json['accessedAt'] ?? '') ?? DateTime.now(),
  );
}

/// שירות ניהול קבצים אחרונים
class RecentFilesService {
  static RecentFilesService? _instance;
  static const String _storageKey = 'recent_files';
  static const int _maxRecentFiles = 20;
  
  RecentFilesService._();
  
  static RecentFilesService get instance {
    _instance ??= RecentFilesService._();
    return _instance!;
  }

  List<RecentFile> _recentFiles = [];
  
  /// רשימת הקבצים האחרונים
  List<RecentFile> get recentFiles => List.unmodifiable(_recentFiles);
  
  /// מספר קבצים אחרונים
  int get count => _recentFiles.length;

  /// טוען קבצים אחרונים מהאחסון
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_storageKey);
      
      if (jsonString != null) {
        final List<dynamic> jsonList = jsonDecode(jsonString);
        _recentFiles = jsonList
            .map((json) => RecentFile.fromJson(json))
            .toList();
        appLog('RecentFiles: Loaded ${_recentFiles.length} recent files');
      }
    } catch (e) {
      appLog('RecentFiles: Error loading - $e');
      _recentFiles = [];
    }
  }

  /// מוסיף קובץ לרשימת האחרונים
  Future<void> addRecentFile({
    required String path,
    required String name,
    required String extension,
  }) async {
    // הסרת קובץ קיים עם אותו נתיב
    _recentFiles.removeWhere((f) => f.path == path);
    
    // הוספה בתחילת הרשימה
    _recentFiles.insert(0, RecentFile(
      path: path,
      name: name,
      extension: extension,
      accessedAt: DateTime.now(),
    ));
    
    // שמירה על מקסימום קבצים
    if (_recentFiles.length > _maxRecentFiles) {
      _recentFiles = _recentFiles.sublist(0, _maxRecentFiles);
    }
    
    await _save();
  }

  /// מסיר קובץ מהרשימה
  Future<void> removeRecentFile(String path) async {
    _recentFiles.removeWhere((f) => f.path == path);
    await _save();
  }

  /// מנקה את כל ההיסטוריה
  Future<void> clear() async {
    _recentFiles.clear();
    await _save();
    appLog('RecentFiles: Cleared all recent files');
  }

  /// שומר לאחסון
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _recentFiles.map((f) => f.toJson()).toList();
      await prefs.setString(_storageKey, jsonEncode(jsonList));
    } catch (e) {
      appLog('RecentFiles: Error saving - $e');
    }
  }
}
