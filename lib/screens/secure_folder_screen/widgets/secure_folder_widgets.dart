import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';
import '../../../services/secure_folder_service.dart';
import '../../../ui/widgets/popup_menu_row.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/file_type_helper.dart';

/// מצב ריק — אין קבצים בתיקייה
class SecureFolderEmptyState extends StatelessWidget {
  const SecureFolderEmptyState({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            tr('folder_empty'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('add_files_hint'),
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// פריט קובץ ברשימה
class SecureFolderFileItem extends StatelessWidget {
  const SecureFolderFileItem({
    super.key,
    required this.theme,
    required this.file,
    required this.onTap,
    required this.onAction,
  });

  final ThemeData theme;
  final SecureFile file;
  final VoidCallback onTap;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final color = getFileColor(file.extension);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(getFileIcon(file.extension), color: color, size: 22),
          ),
        ),
        title: Text(
          '${file.name}.${file.extension}',
          style: const TextStyle(fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          formatBytes(file.size),
          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            PopupMenuItem(value: 'open', child: PopupMenuRow(icon: Icons.open_in_new, textKey: 'open')),
            PopupMenuItem(value: 'share', child: PopupMenuRow(icon: Icons.share, textKey: 'share')),
            PopupMenuItem(value: 'restore', child: PopupMenuRow(icon: Icons.restore, textKey: 'restore_original', color: Colors.blue)),
            PopupMenuItem(value: 'delete', child: PopupMenuRow(icon: Icons.delete, textKey: 'delete', color: Colors.red)),
          ],
          onSelected: onAction,
        ),
        onTap: onTap,
      ),
    );
  }
}
