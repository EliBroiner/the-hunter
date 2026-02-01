import '../models/file_metadata.dart';
import 'log_service.dart';

/// סינון ודה־דופליקציה של תוצאות חיפוש: קבצי מערכת, קבוצות לפי hash/שם דומה, שמירת הגרסה האחרונה
class SearchResultCleanup {
  SearchResultCleanup._();

  /// דמיון שמות — מעל הסף נחשבים לאותו קובץ (גרסאות)
  static const double _similarityThreshold = 0.95;

  /// שמות/נתיבים שמתאימים ל־GUID (hex ארוך), pdf.123, או temp/cache
  static final RegExp _guidLikeName = RegExp(
    r'^[a-fA-F0-9\-]{20,}$',
  );
  static final RegExp _pdfDotNumbers = RegExp(
    r'^pdf\.\d+',
    caseSensitive: false,
  );
  static const List<String> _junkPathSegments = [
    'cache', 'tmp', 'temp', '.thumbnails', 'thumbnails', 'log', '.cache',
  ];

  /// בודק אם הקובץ נחשב "זבל" — GUID, pdf.123, או מתוך תיקיית cache/temp
  static bool isGarbageFile(FileMetadata file) {
    final name = file.name;
    final path = file.path;

    // pdf.123, pdf.1, וכו'
    if (_pdfDotNumbers.hasMatch(name)) return true;

    // שם קובץ (ללא סיומת) — hex ארוך (GUID)
    final lastDot = name.lastIndexOf('.');
    final baseName = lastDot <= 0 ? name : name.substring(0, lastDot);
    if (baseName.length >= 20 && _guidLikeName.hasMatch(baseName)) return true;

    // נתיב מכיל cache/tmp/temp
    final pathLower = path.replaceAll(r'\', '/').toLowerCase();
    for (final segment in _junkPathSegments) {
      if (pathLower.contains('/$segment/') || pathLower.endsWith('/$segment')) {
        return true;
      }
    }
    return false;
  }

  /// דמיון בין שני שמות (0..1) — מבוסס על יחס Levenshtein
  static double _filenameSimilarity(String a, String b) {
    if (a.isEmpty && b.isEmpty) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final al = a.toLowerCase();
    final bl = b.toLowerCase();
    if (al == bl) return 1.0;
    final maxLen = al.length > bl.length ? al.length : bl.length;
    final dist = _levenshtein(al, bl);
    return 1.0 - (dist / maxLen);
  }

  static int _levenshtein(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final m = a.length;
    final n = b.length;
    final d = List.generate(m + 1, (_) => List.filled(n + 1, 0));
    for (var i = 0; i <= m; i++) d[i][0] = i;
    for (var j = 0; j <= n; j++) d[0][j] = j;
    for (var i = 1; i <= m; i++) {
      for (var j = 1; j <= n; j++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        d[i][j] = [
          d[i - 1][j] + 1,
          d[i][j - 1] + 1,
          d[i - 1][j - 1] + cost,
        ].reduce((x, y) => x < y ? x : y);
      }
    }
    return d[m][n];
  }

  /// מסנן זבל ומקבץ לפי contentHash או דמיון שם 95%; מחזיר רק הגרסה האחרונה (lastModified) מכל קבוצה
  static List<FileMetadata> deduplicateAndFilter(List<FileMetadata> results) {
    if (results.isEmpty) return results;

    final filtered = results.where((f) => !isGarbageFile(f)).toList();
    final garbageCount = results.length - filtered.length;
    if (garbageCount > 0) {
      appLog('[Search] Cleanup: Filtered $garbageCount garbage file(s).');
    }

    // קיבוץ לפי contentHash (אם קיים)
    final byHash = <String, List<FileMetadata>>{};
    final noHash = <FileMetadata>[];
    for (final f in filtered) {
      final h = f.contentHash?.trim();
      if (h != null && h.isNotEmpty) {
        byHash.putIfAbsent(h, () => []).add(f);
      } else {
        noHash.add(f);
      }
    }

    final kept = <FileMetadata>[];
    for (final group in byHash.values) {
      group.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      kept.add(group.first);
    }

    // קיבוץ לפי דמיון שם 95% — שומרים נציג אחד (האחרון לפי lastModified) לכל קבוצה
    final used = List.filled(noHash.length, false);
    for (var i = 0; i < noHash.length; i++) {
      if (used[i]) continue;
      final file = noHash[i];
      final group = [file];
      used[i] = true;
      for (var j = i + 1; j < noHash.length; j++) {
        if (used[j]) continue;
        final other = noHash[j];
        if (_filenameSimilarity(file.name, other.name) >= _similarityThreshold) {
          group.add(other);
          used[j] = true;
        }
      }
      group.sort((a, b) => b.lastModified.compareTo(a.lastModified));
      kept.add(group.first);
    }

    final dropped = filtered.length - kept.length;
    if (dropped > 0) {
      appLog('[Search] Cleanup: Deduplicated to ${kept.length} results (dropped $dropped duplicates).');
    }
    return kept;
  }
}
