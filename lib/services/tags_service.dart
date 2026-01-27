import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

/// מיפוי שמות אייקונים לאייקונים קבועים (נדרש ל-tree shaking)
const Map<String, IconData> _iconMap = {
  'label': Icons.label,
  'work': Icons.work,
  'person': Icons.person,
  'priority_high': Icons.priority_high,
  'attach_money': Icons.attach_money,
  'family_restroom': Icons.family_restroom,
  'folder': Icons.folder,
  'star': Icons.star,
  'favorite': Icons.favorite,
  'home': Icons.home,
  'school': Icons.school,
  'shopping_cart': Icons.shopping_cart,
  'flight': Icons.flight,
  'restaurant': Icons.restaurant,
  'sports': Icons.sports,
  'music_note': Icons.music_note,
  'photo': Icons.photo,
  'movie': Icons.movie,
  'book': Icons.book,
  'medical_services': Icons.medical_services,
};

/// תגית מותאמת אישית
class CustomTag {
  final String id;
  final String name;
  final Color color;
  final String iconName;

  CustomTag({
    required this.id,
    required this.name,
    required this.color,
    this.iconName = 'label',
  });

  /// מחזיר את האייקון לפי השם
  IconData get icon => _iconMap[iconName] ?? Icons.label;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'color': color.value,
    'iconName': iconName,
  };

  factory CustomTag.fromJson(Map<String, dynamic> json) => CustomTag(
    id: json['id'] ?? '',
    name: json['name'] ?? '',
    color: Color(json['color'] ?? 0xFF6366F1),
    iconName: json['iconName'] ?? 'label',
  );
  
  /// רשימת שמות אייקונים זמינים
  static List<String> get availableIconNames => _iconMap.keys.toList();
  
  /// מחזיר אייקון לפי שם
  static IconData getIconByName(String name) => _iconMap[name] ?? Icons.label;
}

/// שירות ניהול תגיות
class TagsService {
  static TagsService? _instance;
  static const String _tagsKey = 'custom_tags';
  static const String _fileTagsKey = 'file_tags';
  
  TagsService._();
  
  static TagsService get instance {
    _instance ??= TagsService._();
    return _instance!;
  }

  List<CustomTag> _tags = [];
  Map<String, Set<String>> _fileTags = {}; // path -> tag ids
  
  /// רשימת התגיות
  List<CustomTag> get tags => List.unmodifiable(_tags);
  
  /// תגיות ברירת מחדל
  static List<CustomTag> get defaultTags => [
    CustomTag(id: 'work', name: 'עבודה', color: Colors.blue, iconName: 'work'),
    CustomTag(id: 'personal', name: 'אישי', color: Colors.green, iconName: 'person'),
    CustomTag(id: 'important', name: 'חשוב', color: Colors.red, iconName: 'priority_high'),
    CustomTag(id: 'finance', name: 'כספים', color: Colors.amber, iconName: 'attach_money'),
    CustomTag(id: 'family', name: 'משפחה', color: Colors.pink, iconName: 'family_restroom'),
  ];

  /// צבעים זמינים לבחירה
  static List<Color> get availableColors => [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
  ];

  /// טוען תגיות מהאחסון
  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // טעינת תגיות
      final tagsJson = prefs.getString(_tagsKey);
      if (tagsJson != null) {
        final List<dynamic> tagsList = jsonDecode(tagsJson);
        _tags = tagsList.map((json) => CustomTag.fromJson(json)).toList();
      } else {
        // יצירת תגיות ברירת מחדל
        _tags = defaultTags;
        await _saveTags();
      }
      
      // טעינת קשרי קובץ-תגית
      final fileTagsJson = prefs.getString(_fileTagsKey);
      if (fileTagsJson != null) {
        final Map<String, dynamic> fileTagsMap = jsonDecode(fileTagsJson);
        _fileTags = fileTagsMap.map((key, value) => 
          MapEntry(key, Set<String>.from(value as List)));
      }
      
      appLog('TagsService: Loaded ${_tags.length} tags, ${_fileTags.length} file mappings');
    } catch (e) {
      appLog('TagsService: Error loading - $e');
      _tags = defaultTags;
      _fileTags = {};
    }
  }

  /// מוסיף תגית חדשה
  Future<void> addTag(CustomTag tag) async {
    _tags.add(tag);
    await _saveTags();
  }

  /// מסיר תגית
  Future<void> removeTag(String tagId) async {
    _tags.removeWhere((t) => t.id == tagId);
    // הסרת התגית מכל הקבצים
    for (final entry in _fileTags.entries) {
      entry.value.remove(tagId);
    }
    await _saveTags();
    await _saveFileTags();
  }

  /// מעדכן תגית
  Future<void> updateTag(CustomTag tag) async {
    final index = _tags.indexWhere((t) => t.id == tag.id);
    if (index != -1) {
      _tags[index] = tag;
      await _saveTags();
    }
  }

  /// מחזיר תגיות של קובץ
  List<CustomTag> getFileTags(String path) {
    final tagIds = _fileTags[path] ?? {};
    return _tags.where((t) => tagIds.contains(t.id)).toList();
  }

  /// בודק אם לקובץ יש תגית מסוימת
  bool hasTag(String path, String tagId) {
    return _fileTags[path]?.contains(tagId) ?? false;
  }

  /// מוסיף תגית לקובץ
  Future<void> addTagToFile(String path, String tagId) async {
    _fileTags.putIfAbsent(path, () => {});
    _fileTags[path]!.add(tagId);
    await _saveFileTags();
  }

  /// מסיר תגית מקובץ
  Future<void> removeTagFromFile(String path, String tagId) async {
    _fileTags[path]?.remove(tagId);
    if (_fileTags[path]?.isEmpty ?? false) {
      _fileTags.remove(path);
    }
    await _saveFileTags();
  }

  /// מחליף תגית לקובץ (toggle)
  Future<void> toggleFileTag(String path, String tagId) async {
    if (hasTag(path, tagId)) {
      await removeTagFromFile(path, tagId);
    } else {
      await addTagToFile(path, tagId);
    }
  }

  /// מחזיר קבצים עם תגית מסוימת
  Set<String> getFilesWithTag(String tagId) {
    return _fileTags.entries
        .where((e) => e.value.contains(tagId))
        .map((e) => e.key)
        .toSet();
  }

  /// מחזיר מספר קבצים עם תגית
  int getFileCountForTag(String tagId) {
    return getFilesWithTag(tagId).length;
  }

  /// שומר תגיות
  Future<void> _saveTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonList = _tags.map((t) => t.toJson()).toList();
      await prefs.setString(_tagsKey, jsonEncode(jsonList));
    } catch (e) {
      appLog('TagsService: Error saving tags - $e');
    }
  }

  /// שומר קשרי קובץ-תגית
  Future<void> _saveFileTags() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = _fileTags.map((key, value) => 
        MapEntry(key, value.toList()));
      await prefs.setString(_fileTagsKey, jsonEncode(map));
    } catch (e) {
      appLog('TagsService: Error saving file tags - $e');
    }
  }

  /// מנקה הכל
  Future<void> clear() async {
    _tags = defaultTags;
    _fileTags.clear();
    await _saveTags();
    await _saveFileTags();
  }
}
