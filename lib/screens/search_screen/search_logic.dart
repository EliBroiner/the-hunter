import '../../models/file_metadata.dart';
import '../../services/database_service.dart';
import '../../utils/file_type_helper.dart';
import 'local_filter.dart';

/// לוגיקה טהורה למסך החיפוש — ללא UI, ניתן לבדיקות יחידה

/// ממיר LocalFilter ל-SearchFilter של מסד הנתונים
SearchFilter dbFilterForLocalFilter(LocalFilter filter) {
  if (filter == LocalFilter.images) return SearchFilter.images;
  if (filter == LocalFilter.pdfs) return SearchFilter.pdfs;
  return SearchFilter.all;
}

/// מסנן תוצאות ענן לפי פילטר מקומי
List<FileMetadata> filterCloudByLocalFilter(
  List<FileMetadata> cloud,
  LocalFilter filter,
) {
  if (filter == LocalFilter.images) {
    return cloud.where((f) => FileTypeHelper.isImage(f)).toList();
  }
  if (filter == LocalFilter.pdfs) {
    return cloud.where((f) => FileTypeHelper.isPDF(f)).toList();
  }
  return cloud;
}

/// מחיל פילטר מקומי על תוצאות (WhatsApp, מועדפים, מיון מועדפים)
List<FileMetadata> applyLocalFilter(
  List<FileMetadata> results,
  LocalFilter filter,
  bool Function(String path) isFavorite,
) {
  if (filter == LocalFilter.whatsapp) {
    return results
        .where((f) => f.path.toLowerCase().contains('whatsapp'))
        .toList();
  }

  if (filter == LocalFilter.favorites) {
    return results.where((f) => isFavorite(f.path)).toList();
  }

  // מיון: מועדפים קודם (אם לא בפילטר מועדפים)
  if (filter != LocalFilter.favorites) {
    final sorted = List<FileMetadata>.from(results);
    sorted.sort((a, b) {
      final aFav = isFavorite(a.path);
      final bFav = isFavorite(b.path);
      if (aFav && !bFav) return -1;
      if (!aFav && bFav) return 1;
      return 0;
    });
    return sorted;
  }

  return results;
}

/// ממזג תוצאות מקומיות עם ענן (ללא כפילויות לפי שם), ממיין לפי תאריך
List<FileMetadata> mergeLocalWithCloud(
  List<FileMetadata> local,
  List<FileMetadata> cloud,
  List<FileMetadata> Function(List<FileMetadata>) applyFilter,
) {
  final localNames = local.map((f) => f.name.toLowerCase()).toSet();
  final uniqueCloud =
      cloud.where((f) => !localNames.contains(f.name.toLowerCase())).toList();
  final combined = [...local, ...uniqueCloud];
  combined.sort((a, b) => b.lastModified.compareTo(a.lastModified));
  return applyFilter(combined);
}

/// מחזיר רשימת סוגי קבצים לפילטר UI (להעברה ל-HybridSearchController)
List<String> getFileTypesForFilter(LocalFilter filter) {
  if (filter == LocalFilter.images) {
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic'];
  }
  if (filter == LocalFilter.pdfs) {
    return ['pdf'];
  }
  return [];
}

/// רשומה לפירוק breakdown
typedef BreakdownRow = ({String label, String value});

/// מפרק מחרוזת פירוט (Fn(31) + Content(133)...) לרשימת (label, value)
List<BreakdownRow> parseBreakdown(String breakdown) {
  if (breakdown.isEmpty) return [];
  final parts = breakdown.split(RegExp(r'\s*\+\s*'));
  final rows = <BreakdownRow>[];
  for (final part in parts) {
    final trimmed = part.trim();
    if (trimmed.isEmpty) continue;

    String label;
    String value;

    final fnMatch = RegExp(r'^Fn\(([\d.]+)\)$').firstMatch(trimmed);
    final locMatch = RegExp(r'^Loc\(([\d.]+)\)$').firstMatch(trimmed);
    final contentMatch = RegExp(r'^Content\(([\d.]+)\)$').firstMatch(trimmed);
    final adjMatch = RegExp(r'^Adj\((\d+)\)$').firstMatch(trimmed);
    final multiMatch = RegExp(r'^MultiWord(.+)$').firstMatch(trimmed);
    final exactMatch = RegExp(r'^Exact\+(\d+)$').firstMatch(trimmed);
    final crypticMatch = RegExp(r'^Cryptic\(([-\d.]+)\)$').firstMatch(trimmed);
    final aiMatch = RegExp(r'^AI\(([\d.]+)\)$').firstMatch(trimmed);
    final driveMatch = RegExp(r'^Drive\+([\d.]+)$').firstMatch(trimmed);

    if (fnMatch != null) {
      label = 'התאמת שם קובץ';
      value = fnMatch.group(1)!;
    } else if (locMatch != null) {
      label = 'התאמת מיקום';
      value = locMatch.group(1)!;
    } else if (contentMatch != null) {
      label = 'התאמת תוכן';
      value = contentMatch.group(1)!;
    } else if (adjMatch != null) {
      label = 'סמיכות מונחים';
      value = adjMatch.group(1)!;
    } else if (multiMatch != null) {
      label = 'ריבוי מילים';
      value = multiMatch.group(1)!;
    } else if (exactMatch != null) {
      label = 'בונוס ביטוי מדויק';
      value = exactMatch.group(1)!;
    } else if (crypticMatch != null) {
      label = 'קנס שם מערכת';
      value = crypticMatch.group(1)!;
    } else if (aiMatch != null) {
      label = 'מטאדאטה AI';
      value = aiMatch.group(1)!;
    } else if (driveMatch != null) {
      label = 'בונוס Drive';
      value = driveMatch.group(1)!;
    } else {
      label = trimmed;
      value = '';
    }
    rows.add((label: label, value: value));
  }
  return rows;
}

/// תווית ספירה לתוצאות חיפוש חכם (לפי טאב)
String smartSearchCountLabel({
  required bool isDriveTab,
  required bool isLocalTab,
  required int driveCount,
  required int localCount,
  required int totalCount,
}) {
  if (isDriveTab) return 'נמצאו $driveCount תוצאות Drive';
  if (isLocalTab) return 'נמצאו $localCount תוצאות מקומי';
  return 'נמצאו $totalCount תוצאות';
}

/// האם להציג צ'יפ "חפש ב-Drive" (חיפוש חכם, טאב הכל, יש מקומי, אין Drive, פרימיום, שאילתה >= 2)
bool shouldShowSearchDriveChip({
  required bool isAllTab,
  required bool haveLocalResults,
  required bool haveDriveResults,
  required bool canSearchDrive,
  required int queryLength,
}) =>
    isAllTab &&
    haveLocalResults &&
    !haveDriveResults &&
    canSearchDrive &&
    queryLength >= 2;
