import 'package:flutter/material.dart';
import '../../../../models/search_synonym.dart';
import '../ai_lab_constants.dart';

/// טאב Dictionary — synonyms מקומיים + Force Sync
class AiLabDictionaryTab extends StatelessWidget {
  const AiLabDictionaryTab({
    super.key,
    required this.lastSyncTime,
    required this.synonymsCount,
    required this.synonymsByCategory,
    required this.searchController,
    required this.onForceSync,
    this.onQuickLearning,
  });

  final DateTime? lastSyncTime;
  final int synonymsCount;
  final Map<String, List<SearchSynonym>> synonymsByCategory;
  final TextEditingController searchController;
  final VoidCallback onForceSync;
  final VoidCallback? onQuickLearning;

  @override
  Widget build(BuildContext context) {
    final categoryKeys = synonymsByCategory.keys.toList()..sort((a, b) => a.compareTo(b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
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
                  const SizedBox(height: 4),
                  Text(
                    'Total Synonyms: $synonymsCount · ${synonymsByCategory.length} categories',
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
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: searchController,
            decoration: InputDecoration(
              hintText: 'Search local dictionary (term contains…)',
              prefixIcon: const Icon(Icons.search, color: Colors.white54),
              border: const OutlineInputBorder(),
              filled: true,
              fillColor: const Color(0xFF0D1117),
            ),
            style: const TextStyle(color: Colors.white70),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: categoryKeys.length,
            itemBuilder: (_, index) {
              final category = categoryKeys[index];
              final synonyms = synonymsByCategory[category]!;
              final color = categoryColor(category.hashCode);
              return Card(
                color: const Color(0xFF161B22),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: color.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: synonyms.map((s) {
                          final label = s.expansions.isEmpty
                              ? s.term
                              : '${s.term} (${s.expansions.take(2).join(', ')}${s.expansions.length > 2 ? '…' : ''})';
                          return Chip(
                            label: Text(
                              label,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            backgroundColor: color.withValues(alpha: 0.15),
                            side: BorderSide(color: color.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
