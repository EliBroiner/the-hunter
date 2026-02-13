import 'package:flutter/material.dart';
import '../../../models/ai_analysis_response.dart';
import '../../../models/file_metadata.dart';
import '../../../services/localization_service.dart';
import '../../../ui/sheets/file_details_sheet.dart';

/// תוכן מודל פרטי קובץ — מוצג ב-showModalBottomSheet
class SearchFileDetailsModal extends StatelessWidget {
  const SearchFileDetailsModal({
    super.key,
    required this.file,
    required this.theme,
    required this.pendingSuggestions,
    required this.detailsCard,
    required this.onReanalyze,
    required this.onClose,
  });

  final FileMetadata file;
  final ThemeData theme;
  final List<AiSuggestion>? pendingSuggestions; // לא בשימוש כרגע — נשמר להרחבה
  final Widget detailsCard;
  final Future<void> Function(void Function(String)? report, bool Function()? isCanceled) onReanalyze;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
        decoration: BoxDecoration(
          color: theme.canvasColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(theme),
              const SizedBox(height: 20),
              _buildTitleRow(theme),
              const SizedBox(height: 20),
              detailsCard,
              const SizedBox(height: 16),
              FileDetailsSheet(
                file: file,
                onReanalyze: (report, isCanceled) => onReanalyze(report, isCanceled),
              ),
              const SizedBox(height: 20),
              _buildCloseButton(theme),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle(ThemeData theme) {
    return Container(
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: theme.colorScheme.outline.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  Widget _buildTitleRow(ThemeData theme) {
    final textColor = theme.textTheme.bodyLarge?.color ??
        (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.info_outline, color: theme.colorScheme.primary, size: 24),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            tr('file_details_title'),
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: textColor),
          ),
        ),
      ],
    );
  }

  Widget _buildCloseButton(ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onClose,
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.colorScheme.primary,
          foregroundColor: theme.colorScheme.onPrimary,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(tr('close')),
      ),
    );
  }

}
