/// נתיב מקוצר — 3 רמות אחרונות (להצגה קומפקטית)
String getShortPath(String path) {
  final parts = path.split('/');
  if (parts.length <= 3) return path;
  return '.../${parts.sublist(parts.length - 3).join('/')}';
}
