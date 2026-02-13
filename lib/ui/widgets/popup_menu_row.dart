import 'package:flutter/material.dart';
import '../../services/localization_service.dart';

/// שורת אייקון + טקסט לתפריט קופץ — שימוש חוזר
class PopupMenuRow extends StatelessWidget {
  final IconData icon;
  final String textKey;
  final Color? color;

  const PopupMenuRow({
    super.key,
    required this.icon,
    required this.textKey,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 12),
        Text(tr(textKey), style: TextStyle(color: color)),
      ],
    );
  }
}
