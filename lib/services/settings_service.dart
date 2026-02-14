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
  static const String _keyDebugBypassPro = 'debug_bypass_pro';
  static const String _keyAdminKey = 'debug_admin_key';
  static const String _keyAlwaysAnalyzeWithGemini = 'always_analyze_with_gemini';
  static const String _keyRulesLearnedDate = 'rules_learned_date';
  static const String _keyRulesLearnedCount = 'rules_learned_count';

  // Notifiers לשינויים
  final ValueNotifier<bool> isPremiumNotifier = ValueNotifier(false);
  final ValueNotifier<ThemeMode> themeModeNotifier = ValueNotifier(ThemeMode.system);
  final ValueNotifier<Locale> localeNotifier = ValueNotifier(const Locale('he', 'IL'));
  
  /// מאתחל את השירות
  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    isPremiumNotifier.value = _prefs?.getBool(_keyIsPremium) ?? false;
    
    // טעינת מצב התצוגה — ברירת מחדל: מערכת (עוקב אחרי OS)
    final themeModeIndex = _prefs?.getInt(_keyThemeMode) ?? ThemeMode.system.index;
    themeModeNotifier.value = ThemeMode.values[themeModeIndex];

    // טעינת שפה
    final localeCode = _prefs?.getString(_keyLocale) ?? 'he';
    localeNotifier.value = Locale(localeCode, localeCode == 'he' ? 'IL' : 'US');
  }
  
  /// האם המשתמש פרימיום. ב־Debug: אם debug_bypass_pro מופעל — מחזיר true (לבדיקת PRO באתר).
  bool get isPremium {
    if (kReleaseMode) return _prefs?.getBool(_keyIsPremium) ?? false;
    if (_prefs?.getBool(_keyDebugBypassPro) ?? false) return true;
    return _prefs?.getBool(_keyIsPremium) ?? false;
  }
  
  /// דגל עקיפה — רק ב־Debug, מאפשר לבדוק פיצ'רי PRO (Secure Folder, Tags) ללא מנוי.
  bool get debugBypassPro => kDebugMode && (_prefs?.getBool(_keyDebugBypassPro) ?? false);
  
  Future<void> setDebugBypassPro(bool value) async {
    if (kReleaseMode) return;
    await _prefs?.setBool(_keyDebugBypassPro, value);
    isPremiumNotifier.value = isPremium;
  }
  
  /// מגדיר סטטוס פרימיום
  Future<void> setIsPremium(bool value) async {
    await _prefs?.setBool(_keyIsPremium, value);
    isPremiumNotifier.value = value;
  }
  
  /// שפת הזיהוי הקולי (he-IL / en-US)
  String get locale => _prefs?.getString(_keyLocale) ?? 'he';
  
  /// מגדיר שפת אפליקציה
  Future<void> setLocale(String languageCode) async {
    await _prefs?.setString(_keyLocale, languageCode);
    localeNotifier.value = Locale(languageCode, languageCode == 'he' ? 'IL' : 'US');
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

  /// מפתח Admin — רק ב־Debug, ל־PromptAdminService (X-Admin-Key)
  String? get adminKey => kDebugMode ? _prefs?.getString(_keyAdminKey) : null;

  Future<void> setAdminKey(String? value) async {
    if (kReleaseMode) return;
    if (value == null || value.isEmpty) {
      await _prefs?.remove(_keyAdminKey);
    } else {
      await _prefs?.setString(_keyAdminKey, value);
    }
  }

  /// השתמש תמיד ב-AI ללמידה — גם כשהמילון מצא התאמה, שולח ל-Gemini לניתוח מעמיק
  bool get alwaysAnalyzeWithGemini => _prefs?.getBool(_keyAlwaysAnalyzeWithGemini) ?? true;

  Future<void> setAlwaysAnalyzeWithGemini(bool value) async {
    await _prefs?.setBool(_keyAlwaysAnalyzeWithGemini, value);
  }

  /// X חוקים חדשים שנלמדו היום — מתאפס בחצות
  int get rulesLearnedToday {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final stored = _prefs?.getString(_keyRulesLearnedDate);
    if (stored != today) return 0;
    return _prefs?.getInt(_keyRulesLearnedCount) ?? 0;
  }

  /// מוסיף 1 לחוקים שנלמדו היום
  Future<void> incrementRulesLearnedToday() async {
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final stored = _prefs?.getString(_keyRulesLearnedDate);
    var count = stored == today ? (_prefs?.getInt(_keyRulesLearnedCount) ?? 0) : 0;
    count++;
    await _prefs?.setString(_keyRulesLearnedDate, today);
    await _prefs?.setInt(_keyRulesLearnedCount, count);
  }

  /// מוסיף N לחוקים שנלמדו היום (לאחר Batch Approve)
  Future<void> addRulesLearnedToday(int n) async {
    if (n <= 0) return;
    final today = DateTime.now().toIso8601String().substring(0, 10);
    final stored = _prefs?.getString(_keyRulesLearnedDate);
    var count = stored == today ? (_prefs?.getInt(_keyRulesLearnedCount) ?? 0) : 0;
    count += n;
    await _prefs?.setString(_keyRulesLearnedDate, today);
    await _prefs?.setInt(_keyRulesLearnedCount, count);
  }
}
