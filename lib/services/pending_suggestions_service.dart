import 'package:flutter/foundation.dart';
import '../models/ai_analysis_response.dart';

/// שירות מרכזי להצעות למידה ממתינות — path → רשימת הצעות.
/// מאפשר גישה מ־SearchScreen וממסך Quick Learning.
class PendingSuggestionsService extends ChangeNotifier {
  static PendingSuggestionsService? _instance;
  static PendingSuggestionsService get instance {
    _instance ??= PendingSuggestionsService._();
    return _instance!;
  }

  PendingSuggestionsService._();

  final Map<String, List<AiSuggestion>> _byPath = {};

  Map<String, List<AiSuggestion>> get all => Map.unmodifiable(_byPath);

  /// רשימה שטוחה: (path, suggestion) — למיון לפי קטגוריה
  List<({String path, AiSuggestion suggestion})> get allFlat {
    final out = <({String path, AiSuggestion suggestion})>[];
    for (final e in _byPath.entries) {
      for (final s in e.value) {
        out.add((path: e.key, suggestion: s));
      }
    }
    return out;
  }

  int get totalCount => _byPath.values.fold(0, (a, l) => a + l.length);

  void setForPath(String path, List<AiSuggestion> suggestions) {
    if (suggestions.isEmpty) {
      _byPath.remove(path);
    } else {
      _byPath[path] = List.from(suggestions);
    }
    notifyListeners();
  }

  void removePath(String path) {
    _byPath.remove(path);
    notifyListeners();
  }

  /// מסיר הצעה בודדת — מוצא לפי תוכן (category+keywords+regex)
  void removeSuggestion(String path, AiSuggestion suggestion) {
    final list = _byPath[path];
    if (list == null) return;
    list.removeWhere((s) => _suggestionEquals(s, suggestion));
    if (list.isEmpty) _byPath.remove(path);
    notifyListeners();
  }

  /// מסיר כמה הצעות מאותו path
  void removeSuggestions(String path, List<AiSuggestion> suggestions) {
    final list = _byPath[path];
    if (list == null) return;
    for (final s in suggestions) {
      list.removeWhere((x) => _suggestionEquals(x, s));
    }
    if (list.isEmpty) _byPath.remove(path);
    notifyListeners();
  }

  /// מסיר הצעות מכמה paths — למשל אחרי Batch Approve
  void removeEntries(List<({String path, AiSuggestion suggestion})> entries) {
    final byPath = <String, List<AiSuggestion>>{};
    for (final e in entries) {
      byPath.putIfAbsent(e.path, () => []).add(e.suggestion);
    }
    for (final e in byPath.entries) {
      removeSuggestions(e.key, e.value);
    }
  }

  static bool _suggestionEquals(AiSuggestion a, AiSuggestion b) {
    if (a.suggestedCategory != b.suggestedCategory) return false;
    if (a.suggestedKeywords.length != b.suggestedKeywords.length) return false;
    for (var i = 0; i < a.suggestedKeywords.length; i++) {
      if (a.suggestedKeywords[i] != b.suggestedKeywords[i]) return false;
    }
    return (a.suggestedRegex ?? '') == (b.suggestedRegex ?? '');
  }
}
