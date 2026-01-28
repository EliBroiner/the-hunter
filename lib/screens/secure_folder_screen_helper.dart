import 'package:flutter/material.dart';
import '../services/localization_service.dart';

class _PopupMenuItemText extends StatelessWidget {
  final String textKey;
  final Color? color;

  const _PopupMenuItemText({
    required this.textKey,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Text(
      tr(textKey),
      style: TextStyle(color: color),
    );
  }
}
