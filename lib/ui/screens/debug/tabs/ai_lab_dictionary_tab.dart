import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../../../../models/search_synonym.dart';
import '../../../../services/database_service.dart';
import '../ai_lab_constants.dart';

/// טאב Dictionary — synonyms מקומיים מ-Isar (searchSynonyms) + Force Sync.
/// StreamBuilder: מתעדכן אוטומטית אחרי sync.
class AiLabDictionaryTab extends StatelessWidget {
  const AiLabDictionaryTab({
    super.key,
    required this.lastSyncTime,
    required this.searchController,
    required this.onForceSync,
    this.onQuickLearning,
    this.onNukeAndResync,
    this.onResetToDefaults,
  });

  final DateTime? lastSyncTime;
  final TextEditingController searchController;
  final VoidCallback onForceSync;
  final VoidCallback? onQuickLearning;
  /// Nuke & Re-Sync — מנקה Isar, מאפס timestamp, מריץ Force Sync.
  final Future<void> Function()? onNukeAndResync;
  /// Reset to Defaults — מנקה searchSynonyms וטוען מ-assets.
  final Future<void> Function()? onResetToDefaults;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderCard(context),
          _buildSearchField(),
          Expanded(
            child: ListenableBuilder(
              listenable: searchController,
              builder: (_, _) {
                final query = searchController.text.trim().toLowerCase();
                return StreamBuilder<List<SearchSynonym>>(
                  stream: DatabaseService.instance.watchDictionaryTerms(),
                  builder: (context, snapshot) {
                    final all = snapshot.data ?? [];
                    final items = query.isEmpty
                        ? all
                        : all.where((s) => s.term.toLowerCase().contains(query)).toList();
                    if (kDebugMode) {
                      final count = DatabaseService.instance.isar.searchSynonyms.count();
                      debugPrint('DEBUG: Isar has $count synonyms. StreamBuilder showing ${items.length} items.');
                    }
                    return _buildTable(items);
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        color: const Color(0xFF161B22),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Last Sync: ${lastSyncTime?.toIso8601String() ?? '—'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: onForceSync,
                    icon: const Icon(Icons.cloud_download, size: 20),
                    label: const Text('Force Sync from Cloud'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  if (onQuickLearning != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: onQuickLearning,
                      icon: const Icon(Icons.lightbulb_outline, size: 20),
                      label: const Text('Quick Learning'),
                    ),
                  ],
                  if (onResetToDefaults != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Reset to Defaults?'),
                            content: const Text(
                              'מוחק את searchSynonyms וטוען מחדש את 174 ברירות המחדל מ-assets/smart_search_config.json.',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                child: const Text('Reset to Defaults'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) await onResetToDefaults!();
                      },
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('Reset to Defaults', style: TextStyle(fontSize: 12)),
                    ),
                  ],
                  if (kDebugMode && onNukeAndResync != null) ...[
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: () async {
                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Nuke & Re-Sync?'),
                            content: const Text(
                              'מוחק את כל הנתונים המקומיים (Isar), מאפס lastSyncTimestamp, ומריץ Force Sync. לא נוגע ב-user preferences.',
                            ),
                            actions: [
                              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                              FilledButton(
                                onPressed: () => Navigator.pop(ctx, true),
                                style: FilledButton.styleFrom(backgroundColor: Colors.red),
                                child: const Text('Nuke & Re-Sync'),
                              ),
                            ],
                          ),
                        );
                        if (confirm == true && context.mounted) await onNukeAndResync!();
                      },
                      icon: const Icon(Icons.delete_forever, size: 18, color: Colors.redAccent),
                      label: const Text('Nuke & Re-Sync', style: TextStyle(color: Colors.redAccent, fontSize: 12)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Colors.redAccent),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: TextField(
        controller: searchController,
        decoration: InputDecoration(
          hintText: 'חיפוש במילון מקומי (term contains…)',
          prefixIcon: const Icon(Icons.search, color: Colors.white54),
          border: const OutlineInputBorder(),
          filled: true,
          fillColor: const Color(0xFF0D1117),
        ),
        style: const TextStyle(color: Colors.white70),
      ),
    );
  }

  Widget _buildTable(List<SearchSynonym> items) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          'אין פריטים — הרץ Force Sync או בדוק חיבור.',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Table(
        columnWidths: const {
          0: FixedColumnWidth(48),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(1),
        },
        border: TableBorder.symmetric(
          inside: BorderSide(color: Colors.white12),
        ),
        children: [
          TableRow(
            decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08)),
            children: [
              _headerCell(Icons.tag),
              _headerCell('מונח / כלל'),
              _headerCell('קטגוריה'),
            ],
          ),
          ...items.map((s) {
            final rule = s.expansions.isEmpty ? s.term : '${s.term} → [${s.expansions.join(', ')}]';
            final color = categoryColor(s.category.hashCode);
            final rankIcon = _rankIcon(s.rank);
            return TableRow(
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.bookmark, size: 20, color: color.withValues(alpha: 0.8)),
                        if (rankIcon != null) ...[
                          const SizedBox(width: 4),
                          rankIcon,
                        ],
                      ],
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      rule,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                    ),
                  ),
                ),
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Text(
                      s.category,
                      style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  /// אייקון דירוג: 💪 Strong, ⚠️ Weak (Medium ללא אייקון)
  Widget? _rankIcon(String? rank) {
    if (rank == null || rank.isEmpty) return null;
    switch (rank.toLowerCase()) {
      case 'strong':
        return Tooltip(
          message: 'Strong',
          child: Text('💪', style: TextStyle(fontSize: 14, color: Colors.green.shade300)),
        );
      case 'weak':
        return Tooltip(
          message: 'Weak',
          child: Text('⚠️', style: TextStyle(fontSize: 14, color: Colors.orange.shade300)),
        );
      default:
        return null;
    }
  }

  Widget _headerCell(dynamic content) {
    return TableCell(
      verticalAlignment: TableCellVerticalAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: content is IconData
            ? Icon(content, size: 18, color: Colors.white54)
            : Text(
                content as String,
                style: const TextStyle(
                  color: Colors.white70,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
      ),
    );
  }
}
