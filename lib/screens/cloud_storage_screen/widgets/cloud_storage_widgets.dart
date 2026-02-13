import 'package:flutter/material.dart';
import '../../../services/cloud_storage_service.dart';
import '../../../services/localization_service.dart';
import '../../../ui/widgets/popup_menu_row.dart';
import '../../../utils/file_type_helper.dart';
import '../../../utils/format_utils.dart';

/// כרטיס סטטיסטיקות אחסון
class CloudStorageCard extends StatelessWidget {
  const CloudStorageCard({
    super.key,
    required this.theme,
    required this.fileCount,
    required this.usedStorage,
    this.isUploading = false,
    this.uploadProgress = 0,
  });

  final ThemeData theme;
  final int fileCount;
  final int usedStorage;
  final bool isUploading;
  final double uploadProgress;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withValues(alpha: 0.15),
            Colors.cyan.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.blue, Colors.cyan]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('cloud_storage_title'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('cloud_storage_subtitle')
                          .replaceFirst('\${count}', fileCount.toString())
                          .replaceFirst('\${size}', formatBytes(usedStorage)),
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (isUploading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: uploadProgress,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
            Text(
              tr('uploading_progress').replaceFirst('\${percent}', (uploadProgress * 100).toInt().toString()),
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
            ),
          ],
        ],
      ),
    );
  }
}

/// מצב ריק — אין קבצים
class CloudStorageEmptyState extends StatelessWidget {
  const CloudStorageEmptyState({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.cloud_off,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            tr('no_files_cloud'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            tr('upload_files_hint'),
            style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// פריט קובץ ברשימה
class CloudStorageFileItem extends StatelessWidget {
  const CloudStorageFileItem({
    super.key,
    required this.theme,
    required this.file,
    required this.isDownloading,
    required this.downloadProgress,
    required this.onAction,
  });

  final ThemeData theme;
  final CloudFile file;
  final bool isDownloading;
  final double downloadProgress;
  final void Function(String action) onAction;

  @override
  Widget build(BuildContext context) {
    final ext = FileTypeHelper.effectiveExtensionFromName(file.name);
    final color = getFileColor(ext);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: Icon(getFileIcon(ext), color: color, size: 22)),
            ),
            title: Text(
              file.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${formatBytes(file.size)} • ${formatRelativeDate(file.uploadedAt)}',
              style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(value: 'download', child: PopupMenuRow(icon: Icons.download, textKey: 'download')),
                PopupMenuItem(value: 'share', child: PopupMenuRow(icon: Icons.share, textKey: 'share_link')),
                PopupMenuItem(value: 'delete', child: PopupMenuRow(icon: Icons.delete, textKey: 'delete', color: Colors.red)),
              ],
              onSelected: onAction,
            ),
          ),
          if (isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(
                value: downloadProgress,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
        ],
      ),
    );
  }

}
