import 'package:shared_preferences/shared_preferences.dart';
import 'log_service.dart';

/// שירות מועדפים - שומר קבצים מועדפים ב-SharedPreferences
/// זמין רק למשתמשי פרימיום
class FavoritesService {
  static FavoritesService? _instance;
  static const String _favoritesKey = 'favorite_files';
  
  Set<String> _favorites = {};
  bool _isInitialized = false;
  
  FavoritesService._();
  
  static FavoritesService get instance {
    _instance ??= FavoritesService._();
    return _instance!;
  }

  /// אתחול - טוען מועדפים מהאחסון
  Future<void> init() async {
    if (_isInitialized) return;
    
    try {
      final prefs = await SharedPreferences.getInstance();
      final favorites = prefs.getStringList(_favoritesKey) ?? [];
      _favorites = favorites.toSet();
      _isInitialized = true;
      appLog('Favorites: Loaded ${_favorites.length} favorites');
    } catch (e) {
      appLog('Favorites ERROR: $e');
      _favorites = {};
    }
  }

  /// בודק אם קובץ מועדף
  bool isFavorite(String path) {
    return _favorites.contains(path);
  }

  /// מוסיף קובץ למועדפים
  Future<bool> addFavorite(String path) async {
    try {
      _favorites.add(path);
      await _save();
      appLog('Favorites: Added $path');
      return true;
    } catch (e) {
      appLog('Favorites ERROR: Failed to add - $e');
      return false;
    }
  }

  /// מסיר קובץ מהמועדפים
  Future<bool> removeFavorite(String path) async {
    try {
      _favorites.remove(path);
      await _save();
      appLog('Favorites: Removed $path');
      return true;
    } catch (e) {
      appLog('Favorites ERROR: Failed to remove - $e');
      return false;
    }
  }

  /// מחליף מצב מועדף
  Future<bool> toggleFavorite(String path) async {
    if (isFavorite(path)) {
      return removeFavorite(path);
    } else {
      return addFavorite(path);
    }
  }

  /// מחזיר את כל המועדפים
  Set<String> get favorites => Set.from(_favorites);

  /// מספר המועדפים
  int get count => _favorites.length;

  /// שומר לאחסון
  Future<void> _save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favoritesKey, _favorites.toList());
    } catch (e) {
      appLog('Favorites ERROR: Failed to save - $e');
    }
  }

  /// מנקה את כל המועדפים
  Future<void> clear() async {
    _favorites.clear();
    await _save();
  }
}
