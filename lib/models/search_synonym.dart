import 'package:isar/isar.dart';

part 'search_synonym.g.dart';

/// מילת מפתח + הרחבות (מילים נרדפות) + קטגוריה — Isar
@Collection()
class SearchSynonym {
  @Id()
  int id = 0;

  /// מילת המפתח (ייחודית)
  @Index(unique: true)
  late String term;

  /// הרחבות — מילים נרדפות
  List<String> expansions = [];

  /// קטגוריה לסיווג
  late String category;

  SearchSynonym();

  factory SearchSynonym.fromMap(String key, List<String> expansions, [String? category]) {
    final s = SearchSynonym()
      ..term = key
      ..expansions = expansions
      ..category = category ?? key;
    return s;
  }
}
