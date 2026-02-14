import 'package:flutter/material.dart';
import '../../services/log_service.dart';
import '../../services/processing_progress_service.dart';

/// Spinner קטן ב-header — מוצג כשהבאנר מוסתר ועדיין עיבוד פעיל. לחיצה משחזרת את הבאנר.
class ProcessingSpinner extends StatelessWidget {
  const ProcessingSpinner({super.key});

  void _onTap() {
    ProcessingProgressService.instance.restore();
    appLog('[UI] Processing banner restored by user from header spinner.');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ProcessingProgressService.instance.isProcessing,
      builder: (_, isProcessing, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: ProcessingProgressService.instance.isDismissed,
          builder: (_, isDismissed, child) {
            if (!isProcessing || !isDismissed) return const SizedBox.shrink();
            return Tooltip(
              message: 'הצג התקדמות עיבוד',
              child: GestureDetector(
                onTap: _onTap,
                behavior: HitTestBehavior.opaque,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}
