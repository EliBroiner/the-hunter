import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/log_service.dart';

/// אורך טקסט מינימלי (תווים) — מתחת לזה נחשב "לא קריא"
const int minTextLength = 30;
/// סף יחס ג'יבריש (0.0–1.0) — מעליו הטקסט נחשב לא תקין לניתוח
const double qualityThreshold = 0.3;
/// מינימום התאמות מילון כדי לסמן dictionaryMatched
const int minDictionaryMatches = 1;

/// ברירות מחדל למשקלי הדירוג
const double kDefaultFilenameWeight = 200;
const double kDefaultContentWeight = 120;
const double kDefaultPathWeight = 80;
const double kDefaultFullMatchMultiplier = 1.2;
const double kDefaultExactPhraseBonus = 150;

const String _keyFilename = 'ranking_filename_weight';
const String _keyContent = 'ranking_content_weight';
const String _keyPath = 'ranking_path_weight';
const String _keyFullMatch = 'ranking_full_match_multiplier';
const String _keyExactPhrase = 'ranking_exact_phrase_bonus';

/// קונפיגורציית משקלי הדירוג — סינגלטון, נשמר ב-SharedPreferences
class RankingConfig extends ChangeNotifier {
  static RankingConfig? _instance;
  static RankingConfig get instance {
    _instance ??= RankingConfig._();
    return _instance!;
  }

  RankingConfig._() {
    _load();
  }

  /// מומלץ לקרוא באתחול האפליקציה כדי לטעון ערכים מ־SharedPreferences לפני חיפוש
  static Future<void> ensureLoaded() async {
    await instance._load();
  }

  double _filenameWeight = kDefaultFilenameWeight;
  double _contentWeight = kDefaultContentWeight;
  double _pathWeight = kDefaultPathWeight;
  double _fullMatchMultiplier = kDefaultFullMatchMultiplier;
  double _exactPhraseBonus = kDefaultExactPhraseBonus;
  bool _loaded = false;

  double get filenameWeight => _filenameWeight;
  double get contentWeight => _contentWeight;
  double get pathWeight => _pathWeight;
  double get fullMatchMultiplier => _fullMatchMultiplier;
  double get exactPhraseBonus => _exactPhraseBonus;

  set filenameWeight(double v) {
    if (_filenameWeight == v) return;
    _filenameWeight = v;
    _save();
    notifyListeners();
  }

  set contentWeight(double v) {
    if (_contentWeight == v) return;
    _contentWeight = v;
    _save();
    notifyListeners();
  }

  set pathWeight(double v) {
    if (_pathWeight == v) return;
    _pathWeight = v;
    _save();
    notifyListeners();
  }

  set fullMatchMultiplier(double v) {
    if (_fullMatchMultiplier == v) return;
    _fullMatchMultiplier = v;
    _save();
    notifyListeners();
  }

  set exactPhraseBonus(double v) {
    if (_exactPhraseBonus == v) return;
    _exactPhraseBonus = v;
    _save();
    notifyListeners();
  }

  Future<void> _load() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _filenameWeight = prefs.getDouble(_keyFilename) ?? kDefaultFilenameWeight;
      _contentWeight = prefs.getDouble(_keyContent) ?? kDefaultContentWeight;
      _pathWeight = prefs.getDouble(_keyPath) ?? kDefaultPathWeight;
      _fullMatchMultiplier = prefs.getDouble(_keyFullMatch) ?? kDefaultFullMatchMultiplier;
      _exactPhraseBonus = prefs.getDouble(_keyExactPhrase) ?? kDefaultExactPhraseBonus;
      _loaded = true;
    } catch (_) {}
  }

  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(_keyFilename, _filenameWeight);
      await prefs.setDouble(_keyContent, _contentWeight);
      await prefs.setDouble(_keyPath, _pathWeight);
      await prefs.setDouble(_keyFullMatch, _fullMatchMultiplier);
      await prefs.setDouble(_keyExactPhrase, _exactPhraseBonus);
    } catch (_) {}
  }

  /// מחזיר לברירות המחדל (200, 120, 80, 1.2, 150)
  Future<void> resetToDefaults() async {
    _filenameWeight = kDefaultFilenameWeight;
    _contentWeight = kDefaultContentWeight;
    _pathWeight = kDefaultPathWeight;
    _fullMatchMultiplier = kDefaultFullMatchMultiplier;
    _exactPhraseBonus = kDefaultExactPhraseBonus;
    await _save();
    notifyListeners();
  }

  /// עדכון דינמי מהשרת — ממזג ערכי rankingConfig מתוך JSON response
  /// ולידציה: משקלים 0–1000, מכפיל 0.1–5. בונוס ±500. ערך לא תקין → ברירת מחדל + לוג
  void applyFromServer(Map<String, dynamic>? rankingConfig) {
    if (rankingConfig == null || rankingConfig.isEmpty) return;
    var changed = false;

    final fn = _parseAndValidateWeight(
      rankingConfig['filenameWeight'],
      _filenameWeight,
      kDefaultFilenameWeight,
      'filenameWeight',
    );
    if (fn != _filenameWeight) {
      _filenameWeight = fn;
      changed = true;
    }

    final ct = _parseAndValidateWeight(
      rankingConfig['contentWeight'],
      _contentWeight,
      kDefaultContentWeight,
      'contentWeight',
    );
    if (ct != _contentWeight) {
      _contentWeight = ct;
      changed = true;
    }

    final pt = _parseAndValidateWeight(
      rankingConfig['pathWeight'],
      _pathWeight,
      kDefaultPathWeight,
      'pathWeight',
    );
    if (pt != _pathWeight) {
      _pathWeight = pt;
      changed = true;
    }

    final fm = _parseAndValidateMultiplier(
      rankingConfig['fullMatchMultiplier'],
      _fullMatchMultiplier,
      kDefaultFullMatchMultiplier,
      'fullMatchMultiplier',
    );
    if (fm != _fullMatchMultiplier) {
      _fullMatchMultiplier = fm;
      changed = true;
    }

    final ex = _parseAndValidateBonus(
      rankingConfig['exactPhraseBonus'],
      _exactPhraseBonus,
      kDefaultExactPhraseBonus,
      'exactPhraseBonus',
    );
    if (ex != _exactPhraseBonus) {
      _exactPhraseBonus = ex;
      changed = true;
    }

    if (changed) {
      _save();
      notifyListeners();
    }
  }

  /// משקל דירוג: 0–1000. מחוץ לטווח → ברירת מחדל + לוג אזהרה
  double _parseAndValidateWeight(dynamic v, double current, double fallback, String key) {
    final parsed = _parseDouble(v);
    if (parsed == null) return current;
    if (parsed < 0 || parsed > 1000) {
      appLog('RankingConfig: ערך לא תקין ל-$key ($parsed), משתמש בברירת מחדל $fallback');
      return fallback;
    }
    return parsed;
  }

  /// מכפיל: 0.1–5
  double _parseAndValidateMultiplier(dynamic v, double current, double fallback, String key) {
    final parsed = _parseDouble(v);
    if (parsed == null) return current;
    if (parsed < 0.1 || parsed > 5) {
      appLog('RankingConfig: ערך לא תקין ל-$key ($parsed), משתמש בברירת מחדל $fallback');
      return fallback;
    }
    return parsed;
  }

  /// בונוס: -500 עד 500
  double _parseAndValidateBonus(dynamic v, double current, double fallback, String key) {
    final parsed = _parseDouble(v);
    if (parsed == null) return current;
    if (parsed < -500 || parsed > 500) {
      appLog('RankingConfig: ערך לא תקין ל-$key ($parsed), משתמש בברירת מחדל $fallback');
      return fallback;
    }
    return parsed;
  }

  static double? _parseDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
    return null;
  }
}
