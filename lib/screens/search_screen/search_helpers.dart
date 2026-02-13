export '../../utils/file_type_helper.dart' show getFileIcon, getFileColor;

/// פונקציות עזר טהורות למסך החיפוש — ללא תלות ב-BuildContext
/// (מאפשר שימוש חוזר ובדיקות יחידה)

/// מחלץ שם התיקייה מהנתיב
String getFolderName(String path) {
  final parts = path.split('/');
  if (parts.length < 2) return 'Unknown';

  final knownFolders = {
    'Download': 'Downloads',
    'Downloads': 'Downloads',
    'DCIM': 'DCIM',
    'Screenshots': 'Screenshots',
    'Pictures': 'Pictures',
    'WhatsApp': 'WhatsApp',
    'Telegram': 'Telegram',
    'Documents': 'Documents',
    'Desktop': 'Desktop',
  };

  for (final entry in knownFolders.entries) {
    if (path.contains(entry.key)) return entry.value;
  }

  return parts.length > 1 ? parts[parts.length - 2] : 'Unknown';
}

/// בודק אם טקסט מכיל עברית
bool isHebrew(String text) {
  return RegExp(r'[\u0590-\u05FF]').hasMatch(text);
}

/// מנקה מונחי זמן מהשאילתה להדגשה
String getCleanQuery(String query) {
  var clean = query;
  const timeTerms = [
    'שבועיים', '2 שבועות', 'שבוע', 'חודש', 'היום', 'אתמול',
    'week', 'month', 'today', 'yesterday',
  ];
  for (final term in timeTerms) {
    clean = clean.replaceAll(RegExp(term, caseSensitive: false), '');
  }
  return clean.trim();
}

/// מפרמט זמן יחסי
String formatRecentTime(DateTime time) {
  final now = DateTime.now();
  final diff = now.difference(time);

  if (diff.inMinutes < 1) return 'עכשיו';
  if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דקות';
  if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
  if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
  return '${time.day}/${time.month}/${time.year}';
}

/// חולץ קטע טקסט סביב מונח החיפוש
String getTextSnippet(String text, String query) {
  final lowerText = text.toLowerCase();
  final lowerQuery = query.toLowerCase();
  final index = lowerText.indexOf(lowerQuery);

  if (index == -1) return text.substring(0, text.length.clamp(0, 60));

  const charsBeforeAfter = 30;
  int start = (index - charsBeforeAfter).clamp(0, text.length);
  int end = (index + query.length + charsBeforeAfter).clamp(0, text.length);

  String snippet = text.substring(start, end);

  if (start > 0) snippet = '...$snippet';
  if (end < text.length) snippet = '$snippet...';

  return snippet.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
}

const int _debugFormulaMaxLen = 40;

/// פורמט דיבוג: ציון בתחילה, פורמולה מקוצרת
String formatDebugScore(double score, String? breakdown) {
  final formula = breakdown ?? '';
  final truncated = formula.length > _debugFormulaMaxLen
      ? '${formula.substring(0, _debugFormulaMaxLen)}...'
      : formula;
  return '${score.round()} : [$truncated]';
}

/// פורמט תאריך
String formatDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);

  if (diff.inDays == 0) return 'היום';
  if (diff.inDays == 1) return 'אתמול';
  if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';

  return '${date.day}/${date.month}/${date.year}';
}
