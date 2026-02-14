import 'package:flutter/material.dart';

/// מחזיר צבע לפי קטגוריה — תמיכה דו־לשונית
Color getColorForCategory(String? category) {
  if (category == null || category.isEmpty) return Colors.grey;
  final c = category.toLowerCase();
  if (_matchesAny(c, ['financial', 'כספי', 'invoice', 'חשבונית', 'receipt', 'קבלה', 'bank', 'בנק'])) {
    return Colors.green;
  }
  if (_matchesAny(c, ['travel', 'נסיעות', 'flight', 'טיסה', 'trip', 'טיול'])) return Colors.blue;
  if (_matchesAny(c, ['medical', 'רפואי', 'health', 'בריאות'])) return Colors.red;
  if (_matchesAny(c, ['id', 'תעודה', 'passport', 'דרכון', 'legal', 'משפטי', 'contract', 'חוזה'])) {
    return Colors.amber;
  }
  return Colors.grey;
}

bool _matchesAny(String c, List<String> terms) =>
    terms.any((t) => c.contains(t));

/// מחזיר אייקון לפי קטגוריה — תמיכה דו־לשונית (עברית/אנגלית)
IconData getIconForCategory(String? category) {
  if (category == null || category.isEmpty) return Icons.insert_drive_file;
  final c = category.toLowerCase();
  if (_matches(c, 'invoice', 'חשבונית', 'receipt', 'קבלה')) return Icons.receipt;
  if (_matches(c, 'document', 'מסמך', 'doc')) return Icons.description;
  if (_matches(c, 'image', 'תמונה', 'photo', 'תצלום')) return Icons.image;
  if (_matches(c, 'pdf')) return Icons.picture_as_pdf;
  if (_matches(c, 'contract', 'חוזה', 'agreement')) return Icons.gavel;
  if (_matches(c, 'id', 'תעודה', 'identity')) return Icons.badge;
  if (_matches(c, 'medical', 'רפואי', 'בריאות')) return Icons.medical_services;
  if (_matches(c, 'bank', 'בנק', 'financial', 'כספי')) return Icons.account_balance;
  return Icons.insert_drive_file;
}

bool _matches(String c, String a, [String? b, String? d, String? e]) {
  return c.contains(a) ||
      (b != null && c.contains(b)) ||
      (d != null && c.contains(d)) ||
      (e != null && c.contains(e));
}
