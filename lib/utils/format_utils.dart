/// פורמט תאריך יחסי — היום, אתמול, לפני X ימים
String formatRelativeDate(DateTime date) {
  final now = DateTime.now();
  final diff = now.difference(date);
  if (diff.inDays == 0) return 'היום';
  if (diff.inDays == 1) return 'אתמול';
  if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
  return '${date.day}/${date.month}/${date.year}';
}

/// פורמט גודל קובץ (B, KB, MB, GB)
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
}
