import '../../models/file_metadata.dart';

/// גודל מינימלי לסריקה (קבצים קטנים מדי לא נחשבים כפולים)
const int kMinFileSizeForDuplicate = 50 * 1024;

/// קיבוץ קבצים לפי גודל — מחזיר רק קבצים מעל הסף
Map<int, List<FileMetadata>> groupFilesBySize(List<FileMetadata> files) {
  final sizeGroups = <int, List<FileMetadata>>{};
  for (final file in files) {
    if (file.size < kMinFileSizeForDuplicate) continue;
    sizeGroups.putIfAbsent(file.size, () => []);
    sizeGroups[file.size]!.add(file);
  }
  return sizeGroups;
}

/// מחפש קבוצות כפולים — קיבוץ משנה לפי שם
List<DuplicateGroup> findDuplicateGroups(Map<int, List<FileMetadata>> sizeGroups) {
  final confirmed = <DuplicateGroup>[];
  for (final entry in sizeGroups.entries) {
    if (entry.value.length <= 1) continue;
    final nameGroups = <String, List<FileMetadata>>{};
    for (final file in entry.value) {
      final key = file.name.toLowerCase();
      nameGroups.putIfAbsent(key, () => []);
      nameGroups[key]!.add(file);
    }
    for (final ng in nameGroups.entries) {
      if (ng.value.length > 1) {
        confirmed.add(DuplicateGroup(key: '${entry.key}_${ng.key}', size: entry.key, files: ng.value));
      }
    }
  }
  confirmed.sort((a, b) => b.wastedSpace.compareTo(a.wastedSpace));
  return confirmed;
}

/// קבוצת קבצים כפולים
class DuplicateGroup {
  final String key;
  final int size;
  final List<FileMetadata> files;

  DuplicateGroup({
    required this.key,
    required this.size,
    required this.files,
  });

  /// גודל שניתן לחסוך אם מוחקים את הכפולים
  int get wastedSpace => size * (files.length - 1);
}

/// סכום נפח מבוזבז מכל הקבוצות
int computeTotalWastedSpace(List<DuplicateGroup> groups) {
  return groups.fold(0, (sum, g) => sum + g.wastedSpace);
}
