import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
}
