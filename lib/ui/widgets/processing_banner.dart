import 'package:flutter/material.dart';
import '../../services/processing_progress_service.dart';

/// באנר התקדמות עיבוד מסמכים — בתחתית המסך. ניתן לסגירה (X). מונפש בכניסה/יציאה.
class ProcessingBanner extends StatelessWidget {
  const ProcessingBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<bool>(
      valueListenable: ProcessingProgressService.instance.isProcessing,
      builder: (_, isProcessing, child) {
        if (!isProcessing) return const SizedBox.shrink();
        return ValueListenableBuilder<bool>(
          valueListenable: ProcessingProgressService.instance.isDismissed,
          builder: (_, isDismissed, child) {
            if (isDismissed) return const SizedBox.shrink();
            return TweenAnimationBuilder<double>(
              key: const ValueKey('banner-visible'),
              tween: Tween(begin: 1, end: 0),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, value, child) {
                return Transform.translate(
                  offset: Offset(0, value * 24),
                  child: Opacity(
                    opacity: 1 - value,
                    child: _BannerContent(theme: theme),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _BannerContent extends StatelessWidget {
  const _BannerContent({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.primaryContainer,
          border: Border(top: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.3))),
        ),
        child: SafeArea(
          top: false,
          child: Row(
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              ValueListenableBuilder<int>(
                valueListenable: ProcessingProgressService.instance.current,
                builder: (_, current, child) {
                  return ValueListenableBuilder<int>(
                    valueListenable: ProcessingProgressService.instance.total,
                    builder: (_, total, child) {
                      return Expanded(
                        child: Text(
                          'מעבד מסמכים... ($current/$total)',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
              IconButton(
                icon: const Icon(Icons.close, size: 20),
                onPressed: () => ProcessingProgressService.instance.dismiss(),
                tooltip: 'הסתר',
                style: IconButton.styleFrom(
                  minimumSize: const Size(36, 36),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
