import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
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
  static const String _keyThemeMode = 'theme_mode';
  
  // Notifiers לשינויים
  final ValueNotifier<bool> isPremiumNotifier = ValueNotifier(false);
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.dark);
  
  /// מאתחל את השירות
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    isPremiumNotifier.value = _prefs?.getBool(_keyIsPremium) ?? false;
    
    // טעינת מצב התצוגה
    final themeModeIndex = _prefs?.getInt(_keyThemeMode) ?? 2; // ברירת מחדל: dark
    themeModeNotifier.value = ThemeMode.values[themeModeIndex];
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
  
  /// מצב התצוגה (בהיר/כהה/מערכת)
  ThemeMode get themeMode => themeModeNotifier.value;
  
  /// מגדיר מצב תצוגה
  Future<void> setThemeMode(ThemeMode mode) async {
    await _prefs?.setInt(_keyThemeMode, mode.index);
    themeModeNotifier.value = mode;
  }
  
  /// מצב כהה מופעל (תאימות לאחור)
  bool get isDarkMode => themeMode == ThemeMode.dark;
}
