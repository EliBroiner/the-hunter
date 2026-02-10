/// היגיינת לוגים — מונע לוגים ענקיים (חיתוך ב-Cloud Run ~256KB, קריאות).
/// כלל: לוג סיכום (Smart Summary) ולא dump מלא.
library;

const int _kMaxLogLineChars = 2000;   // מתחת למגבלת Cloud Run
const int _kMaxErrorChars = 500;
const int _kMaxStackTraceChars = 800;
const int _kMaxBodyPreviewChars = 150;
const int _kMaxTextPreviewChars = 100;
const int _kMaxListPreviewItems = 5;
const int _kMaxListLogItems = 10;

/// מקצר מחרוזת ללוג — preview + אורך.
/// לא לדלוף תוכן OCR/Base64 מלא.
String truncateForLog(String? text, {int maxPreviewChars = _kMaxTextPreviewChars}) {
  if (text == null || text.isEmpty) return 'empty (0 chars)';
  final len = text.length;
  if (len <= maxPreviewChars) return text;
  final preview = text.substring(0, maxPreviewChars).replaceAll(RegExp(r'\s+'), ' ').trim();
  return 'preview: "$preview…", total_length: $len';
}

/// סיכום לוג ל-OCR — בלי להדפיס את כל הטקסט.
String ocrSummary(String? extractedText) {
  if (extractedText == null || extractedText.isEmpty) {
    return 'found_text: false, length: 0';
  }
  final preview = extractedText.length <= _kMaxTextPreviewChars
      ? extractedText.replaceAll(RegExp(r'\s+'), ' ').trim()
      : '${extractedText.substring(0, _kMaxTextPreviewChars).replaceAll(RegExp(r'\s+'), ' ').trim()}…';
  return 'found_text: true, length: ${extractedText.length}, preview: "$preview"';
}

/// גודל קובץ ללוג — לא תוכן. (תמונות/Base64 לא נכנסים ללוג.)
String fileMetaForLog({int? sizeBytes, String? extension}) {
  final parts = <String>[];
  if (sizeBytes != null) parts.add('size_kb: ${(sizeBytes / 1024).round()}');
  if (extension != null && extension.isNotEmpty) parts.add('ext: $extension');
  return parts.isEmpty ? '—' : parts.join(', ');
}

/// רשימה ללוג — אם ארוכה: count + 5 ראשונים.
String listForLog(List<dynamic>? list, {int maxItems = _kMaxListPreviewItems, int threshold = _kMaxListLogItems}) {
  if (list == null || list.isEmpty) return '[]';
  if (list.length <= threshold) return list.map((e) => e.toString()).join(', ');
  final take = list.take(maxItems).map((e) => e.toString()).toList();
  return 'count: ${list.length}, first_${take.length}: $take';
}

/// גוף תשובה (JSON וכו') — לא לדפיס מלא. size + preview קצר.
String bodyForLog(String? body) {
  if (body == null || body.isEmpty) return 'empty';
  final len = body.length;
  if (len <= _kMaxBodyPreviewChars) return body;
  return 'size: $len, preview: "${body.substring(0, _kMaxBodyPreviewChars)}…"';
}

/// שגיאה ללוג — חיתוך הודעה ו-StackTrace.
String sanitizeError(Object? e, [StackTrace? st]) {
  final errStr = e?.toString() ?? 'null';
  final err = errStr.length > _kMaxErrorChars
      ? '${errStr.substring(0, _kMaxErrorChars)}…'
      : errStr;
  if (st == null) return err;
  final stStr = st.toString();
  final stack = stStr.length > _kMaxStackTraceChars
      ? '${stStr.substring(0, _kMaxStackTraceChars)}…'
      : stStr;
  return '$err\nStackTrace: $stack';
}

/// מקצר כל הודעת לוג כך שלא תעבור את המגבלה לשורה.
String sanitizeMessage(String message) {
  if (message.length <= _kMaxLogLineChars) return message;
  return '${message.substring(0, _kMaxLogLineChars)}… [truncated, total ${message.length} chars]';
}
