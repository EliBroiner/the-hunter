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
  });

  final DateTime? lastSyncTime;
  final TextEditingController searchController;
  final VoidCallback onForceSync;
  final VoidCallback? onQuickLearning;

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeaderCard(),
          _buildSearchField(),
          Expanded(
            child: ListenableBuilder(
              listenable: searchController,
              builder: (_, __) {
                final query = searchController.text.trim().toLowerCase();
                return StreamBuilder<List<SearchSynonym>>(
                  stream: DatabaseService.instance.watchDictionaryTerms(),
                  builder: (context, snapshot) {
                    final all = snapshot.data ?? [];
                    final items = query.isEmpty
                        ? all
                        : all.where((s) => s.term.toLowerCase().contains(query)).toList();
                    if (kDebugMode) {
                      debugPrint('[ADMIN-UI] Found ${items.length} items in local Isar dictionary.');
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

  Widget _buildHeaderCard() {
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
            return TableRow(
              children: [
                TableCell(
                  verticalAlignment: TableCellVerticalAlignment.middle,
                  child: Padding(
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.bookmark, size: 20, color: color.withValues(alpha: 0.8)),
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
