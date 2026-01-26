import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// שירות הגדרות - מנהל הגדרות המשתמש וסטטוס פרימיום
class SettingsService {
  static SettingsService? _instance;
  static SharedPreferences? _prefs;
  
  SettingsService._();
  
  static SettingsService get instance {
    _instance ??= SettingsService._();
    return _instance!;
  }
  
  // מפתחות SharedPreferences
  static const String _keyIsPremium = 'is_premium';
  static const String _keyLocale = 'locale';
  static const String _keyDarkMode = 'dark_mode';
  
  // Notifier לשינויים בסטטוס פרימיום
  final ValueNotifier<bool> isPremiumNotifier = ValueNotifier(false);
  
  /// מאתחל את השירות
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    isPremiumNotifier.value = _prefs?.getBool(_keyIsPremium) ?? false;
  }
  
  /// האם המשתמש פרימיום
  bool get isPremium => _prefs?.getBool(_keyIsPremium) ?? false;
  
  /// מגדיר סטטוס פרימיום
  Future<void> setIsPremium(bool value) async {
    await _prefs?.setBool(_keyIsPremium, value);
    isPremiumNotifier.value = value;
  }
  
  /// שפת הזיהוי הקולי (he-IL / en-US)
  String get locale => _prefs?.getString(_keyLocale) ?? 'he-IL';
  
  /// מגדיר שפת זיהוי קולי
  Future<void> setLocale(String value) async {
    await _prefs?.setString(_keyLocale, value);
  }
  
  /// מצב כהה מופעל
  bool get isDarkMode => _prefs?.getBool(_keyDarkMode) ?? true;
  
  /// מגדיר מצב כהה
  Future<void> setDarkMode(bool value) async {
    await _prefs?.setBool(_keyDarkMode, value);
  }
}
