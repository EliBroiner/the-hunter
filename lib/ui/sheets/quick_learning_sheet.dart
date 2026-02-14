import 'package:flutter/material.dart';
import '../../../models/ai_analysis_response.dart';
import '../../../services/category_manager_service.dart';
import '../../../services/pending_suggestions_service.dart';
import '../../../services/settings_service.dart';
import '../../../utils/path_utils.dart';
import '../../../ui/utils/snackbar_helper.dart';

/// גיליון Quick Learning — הצעות מקובצות לפי קטגוריה, Quick Merge, Batch Approve
class QuickLearningSheet extends StatefulWidget {
  const QuickLearningSheet({super.key});

  @override
  State<QuickLearningSheet> createState() => _QuickLearningSheetState();
}

class _QuickLearningSheetState extends State<QuickLearningSheet> {
  final _pendingService = PendingSuggestionsService.instance;
  final _catManager = CategoryManagerService.instance;
  final _settings = SettingsService.instance;
  final Set<({String path, AiSuggestion suggestion})> _selected = {};
  bool _isMerging = false;

  @override
  void initState() {
    super.initState();
    _pendingService.addListener(_onPendingChanged);
  }

  @override
  void dispose() {
    _pendingService.removeListener(_onPendingChanged);
    super.dispose();
  }

  void _onPendingChanged() => setState(() {});

  /// מקבץ לפי קטגוריה
  Map<String, List<({String path, AiSuggestion suggestion})>> _groupByCategory() {
    final groups = <String, List<({String path, AiSuggestion suggestion})>>{};
    for (final e in _pendingService.allFlat) {
      final cat = e.suggestion.suggestedCategory.trim().isEmpty ? 'Uncategorized' : e.suggestion.suggestedCategory;
      groups.putIfAbsent(cat, () => []).add(e);
    }
    return groups;
  }

  Future<void> _quickMerge(String path, AiSuggestion s) async {
    if (_isMerging) return;
    setState(() => _isMerging = true);
    final catId = s.suggestedCategory.trim();
    if (catId.isEmpty) {
      _showSnack('קטגוריה ריקה');
      setState(() => _isMerging = false);
      return;
    }
    final added = await _catManager.approveSuggestions(catId, [s]);
    if (!mounted) return;
    if (added > 0) {
      _pendingService.removeSuggestion(path, s);
      await _settings.addRulesLearnedToday(added);
      if (mounted) showSuccessSnackBar(context, 'Dictionary updated. Local recognition improved for $catId.');
    } else {
      _showSnack('לא נוספו חוקים חדשים');
    }
    setState(() => _isMerging = false);
  }

  Future<void> _batchApprove() async {
    if (_selected.isEmpty || _isMerging) return;
    setState(() => _isMerging = true);
    final byCategory = <String, List<AiSuggestion>>{};
    for (final e in _selected) {
      final cat = e.suggestion.suggestedCategory.trim().isEmpty ? 'Uncategorized' : e.suggestion.suggestedCategory;
      byCategory.putIfAbsent(cat, () => []).add(e.suggestion);
    }
    var totalAdded = 0;
    for (final e in byCategory.entries) {
      final added = await _catManager.approveSuggestions(e.key, e.value);
      totalAdded += added;
    }
    if (!mounted) return;
    if (totalAdded > 0) {
      _pendingService.removeEntries(_selected.toList());
      await _settings.addRulesLearnedToday(totalAdded);
      final cats = byCategory.keys.join(', ');
      if (mounted) showSuccessSnackBar(context, 'Dictionary updated. Local recognition improved for $cats.');
    } else {
      _showSnack('לא נוספו חוקים חדשים');
    }
    setState(() {
      _selected.clear();
      _isMerging = false;
    });
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyLarge?.color ?? Colors.white;
    final groups = _groupByCategory();
    final rulesToday = _settings.rulesLearnedToday;

    if (groups.isEmpty) {
      return _buildEmpty(theme);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          _buildHeader(theme, textColor, rulesToday),
          if (_selected.isNotEmpty) _buildBatchBar(theme),
          Expanded(
            child: ListView.builder(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              itemCount: groups.length,
              itemBuilder: (_, i) {
                final cat = groups.keys.elementAt(i);
                final items = groups[cat]!;
                return _buildCategorySection(context, theme, textColor, cat, items);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lightbulb_outline, size: 48, color: theme.colorScheme.outline),
          const SizedBox(height: 16),
          Text('אין הצעות ממתינות', style: theme.textTheme.titleMedium),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, Color textColor, int rulesToday) {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.lightbulb_outline, color: Color(0xFF9C27B0)),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Quick Learning', style: theme.textTheme.titleLarge?.copyWith(color: textColor)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text('$rulesToday new rules today', style: const TextStyle(fontSize: 12, color: Color(0xFF4CAF50))),
          ),
        ],
      ),
    );
  }

  Widget _buildBatchBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
      child: Row(
        children: [
          Text('${_selected.length} selected', style: theme.textTheme.bodyMedium),
          const Spacer(),
          TextButton(onPressed: () => setState(() => _selected.clear()), child: const Text('Clear')),
          const SizedBox(width: 8),
          FilledButton(
            onPressed: _isMerging ? null : _batchApprove,
            child: Text(_isMerging ? '...' : 'Batch Approve'),
          ),
        ],
      ),
    );
  }

  Widget _buildCategorySection(
    BuildContext context,
    ThemeData theme,
    Color textColor,
    String category,
    List<({String path, AiSuggestion suggestion})> items,
  ) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(category, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
            const SizedBox(height: 12),
            ...items.map((e) => _buildSuggestionRow(context, theme, textColor, e.path, e.suggestion)),
          ],
        ),
      ),
    );
  }

  Widget _buildSuggestionRow(
    BuildContext context,
    ThemeData theme,
    Color textColor,
    String path,
    AiSuggestion s,
  ) {
    final entry = (path: path, suggestion: s);
    final isSelected = _selected.contains(entry);
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadExistingFlags(s.suggestedCategory, s),
      builder: (_, snap) {
        final existingKw = (snap.data?['keywords'] as Map<String, bool>?) ?? {};
        final regexExists = snap.data?['regex'] as bool? ?? false;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Checkbox(
                      value: isSelected,
                      onChanged: (v) {
                        setState(() {
                          if (v == true) {
                            _selected.add(entry);
                          } else {
                            _selected.remove(entry);
                          }
                        });
                      },
                    ),
                  const SizedBox(width: 4),
                  Expanded(child: Text(getShortPath(path), style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.7)))),
                  SizedBox(
                    width: 100,
                    child: FilledButton(
                      onPressed: _isMerging ? null : () => _quickMerge(path, s),
                      style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4)),
                      child: const Text('Quick Merge', style: TextStyle(fontSize: 11)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              _buildKeywordsChips(s, existingKw, textColor),
              if (s.suggestedRegex != null && s.suggestedRegex!.trim().isNotEmpty)
                _buildRegexChip(s.suggestedRegex!, regexExists, textColor),
            ],
          ),
        );
      },
    );
  }

  Future<Map<String, dynamic>> _loadExistingFlags(String catId, AiSuggestion s) async {
    await _catManager.loadCategories();
    final existingKw = <String, bool>{};
    for (final kw in s.suggestedKeywords) {
      final exists = await _catManager.hasKeywordInCategory(catId, kw);
      existingKw[kw] = exists;
    }
    var regexExists = false;
    final r = s.suggestedRegex?.trim();
    if (r != null && r.isNotEmpty) {
      regexExists = await _catManager.hasRegexInCategory(catId, r);
    }
    return {'keywords': existingKw, 'regex': regexExists};
  }

  Widget _buildKeywordsChips(AiSuggestion s, Map<String, bool> existingKw, Color textColor) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: s.suggestedKeywords.where((k) => k.trim().isNotEmpty).map((kw) {
        final exists = existingKw[kw] ?? false;
        return Chip(
          label: Text(kw, style: TextStyle(fontSize: 11, color: exists ? Colors.green : textColor)),
          backgroundColor: exists ? Colors.green.withValues(alpha: 0.2) : null,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          visualDensity: VisualDensity.compact,
        );
      }).toList(),
    );
  }

  Widget _buildRegexChip(String regex, bool exists, Color textColor) {
    final isValid = CategoryManagerService.isRegexValid(regex);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: exists ? Colors.green : (isValid ? Colors.white24 : Colors.orange)),
              ),
              child: SelectableText(regex, style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: textColor)),
            ),
          ),
          if (exists)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.check_circle, color: Colors.green, size: 20),
            )
          else if (!isValid)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Icon(Icons.warning_amber, color: Colors.orange, size: 20),
            ),
        ],
      ),
    );
  }
}
