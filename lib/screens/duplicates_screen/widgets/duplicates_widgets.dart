import 'package:flutter/material.dart';
import '../../../models/file_metadata.dart';
import '../../../services/localization_service.dart';
import '../../../utils/format_utils.dart';
import '../../../utils/path_utils.dart';
import '../duplicates_logic.dart';

/// כרטיס סטטוס — כותרת, תת־כותרת, כפתור סריקה
class DuplicatesStatusCard extends StatelessWidget {
  const DuplicatesStatusCard({
    super.key,
    required this.theme,
    required this.title,
    required this.subtitle,
    required this.isScanning,
    required this.onScan,
  });

  final ThemeData theme;
  final String title;
  final String subtitle;
  final bool isScanning;
  final VoidCallback onScan;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.15),
            theme.colorScheme.secondary.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.find_replace, color: theme.colorScheme.primary, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: isScanning ? null : onScan,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: isScanning
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.search),
              label: Text(isScanning ? tr('scanning') : tr('scan_duplicates')),
            ),
          ),
        ],
      ),
    );
  }
}

/// תצוגת סריקה — מעגל התקדמות + הודעה
class DuplicatesScanningView extends StatelessWidget {
  const DuplicatesScanningView({
    super.key,
    required this.theme,
    required this.progress,
    required this.message,
  });

  final ThemeData theme;
  final double progress;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: progress,
                    strokeWidth: 8,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                Text(
                  '${(progress * 100).toInt()}%',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(message, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
        ],
      ),
    );
  }
}

/// מצב ריק — אין כפולים
class DuplicatesEmptyState extends StatelessWidget {
  const DuplicatesEmptyState({super.key, required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: Colors.green.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text(
            tr('no_duplicates_found'),
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Text(
            tr('files_clean_desc'),
            style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// קבוצת כפולים — כותרת + רשימת קבצים
class DuplicatesGroupCard extends StatelessWidget {
  const DuplicatesGroupCard({
    super.key,
    required this.theme,
    required this.group,
    required this.selectedPaths,
    required this.onToggle,
    required this.onShowInFolder,
  });

  final ThemeData theme;
  final DuplicateGroup group;
  final Set<String> selectedPaths;
  final void Function(String path) onToggle;
  final void Function(FileMetadata file) onShowInFolder;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme),
          ...group.files.asMap().entries.map((e) => _buildFileRow(e.key, e.value, theme)),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(Icons.content_copy, color: theme.colorScheme.primary, size: 20),
          const SizedBox(width: 10),
          Text(
            tr('identical_files').replaceFirst('\${count}', group.files.length.toString()),
            style: TextStyle(fontWeight: FontWeight.w600, color: theme.colorScheme.primary),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              tr('wasted').replaceFirst('\${size}', formatBytes(group.wastedSpace)),
              style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileRow(int idx, FileMetadata file, ThemeData theme) {
    final isFirst = idx == 0;
    final isSelected = selectedPaths.contains(file.path);
    return InkWell(
      onTap: isFirst ? null : () => onToggle(file.path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.red.withValues(alpha: 0.1) : null,
          border: Border(bottom: BorderSide(color: theme.colorScheme.outline.withValues(alpha: 0.1))),
        ),
        child: Row(
          children: [
            isFirst
                ? Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.check, color: Colors.green, size: 16),
                  )
                : Checkbox(
                    value: isSelected,
                    onChanged: (_) => onToggle(file.path),
                    activeColor: Colors.red,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (isFirst)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          margin: const EdgeInsets.only(left: 6),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tr('original'),
                            style: const TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold),
                          ),
                        ),
                      Expanded(
                        child: Text(
                          file.name,
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 13,
                            color: theme.colorScheme.onSurface,
                            decoration: isSelected ? TextDecoration.lineThrough : null,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    getShortPath(file.path),
                    style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  formatBytes(group.size),
                  style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurface.withValues(alpha: 0.6)),
                ),
                if (!isFirst)
                  IconButton(
                    icon: const Icon(Icons.open_in_new, size: 18),
                    onPressed: () => onShowInFolder(file),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    tooltip: tr('show_in_folder'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
