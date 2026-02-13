import 'package:flutter/material.dart';
import '../../../models/file_metadata.dart';
import '../search_helpers.dart';
import 'search_result_widgets.dart';

/// תוכן תפריט פעולות קובץ — מוצג ב-showModalBottomSheet
class SearchFileActionsSheet extends StatelessWidget {
  const SearchFileActionsSheet({
    super.key,
    required this.file,
    required this.theme,
    required this.actionTiles,
  });

  final FileMetadata file;
  final ThemeData theme;
  final List<Widget> actionTiles;

  @override
  Widget build(BuildContext context) {
    final textColor = theme.textTheme.bodyLarge?.color ??
        (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
    final secondaryColor = theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurfaceVariant;

    return SafeArea(
      top: false,
      bottom: true,
      child: Container(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
        decoration: BoxDecoration(
          color: theme.canvasColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHandle(theme),
              const SizedBox(height: 16),
              _buildHeader(file, theme, textColor, secondaryColor),
              const SizedBox(height: 20),
              ...actionTiles,
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

  Widget _buildHeader(FileMetadata file, ThemeData theme, Color textColor, Color secondaryColor) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: getFileColor(file.extension).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: SearchFileIcon(
              extension: file.extension,
              isWhatsApp: file.path.toLowerCase().contains('whatsapp'),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.name,
                style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textColor),
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                file.readableSize,
                style: TextStyle(color: secondaryColor, fontSize: 12),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
