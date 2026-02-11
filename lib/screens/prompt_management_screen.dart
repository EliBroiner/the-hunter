import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/localization_service.dart';
import '../services/prompt_admin_service.dart';

/// מסך ניהול פרומפטים — רשימה, הוספת טיוטה, הפעלת גרסה.
/// דורש Admin. RTL-friendly, Material 3.
class PromptManagementScreen extends StatefulWidget {
  const PromptManagementScreen({super.key});

  @override
  State<PromptManagementScreen> createState() => _PromptManagementScreenState();
}

class _PromptManagementScreenState extends State<PromptManagementScreen> {
  final _promptService = PromptAdminService.instance;

  List<SystemPrompt> _prompts = [];
  bool _isLoading = true;
  String? _error;
  String _filterFeature = '';

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await _promptService.fetchPrompts(
        feature: _filterFeature.isEmpty ? null : _filterFeature,
      );
      if (mounted) {
        setState(() {
          _prompts = list;
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _onCreatePrompt() async {
    final result = await showDialog<_CreatePromptResult>(
      context: context,
      builder: (context) => const _CreatePromptDialog(),
    );
    if (result == null || !mounted) return;
    final created = await _promptService.savePrompt(
      feature: result.feature,
      content: result.content,
      version: result.version,
    );
    if (!mounted) return;
    if (created != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('prompts_saved')),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadPrompts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('prompts_save_error')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onSetActive(SystemPrompt prompt) async {
    if (prompt.isActive) return;
    final ok = await _promptService.setPromptActive(prompt.id);
    if (!mounted) return;
    if (ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('prompts_activated')),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      await _loadPrompts();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('prompts_activate_error')),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = LocalizationService.instance.isHebrew;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          title: Text(
            tr('prompts_title'),
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.add),
              onPressed: _isLoading ? null : _onCreatePrompt,
              tooltip: tr('prompts_create'),
            ),
          ],
        ),
        body: _buildBody(theme),
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_error != null) {
      return _buildError(theme);
    }
    if (_isLoading) {
      return _buildLoading(theme);
    }
    if (_prompts.isEmpty) {
      return _buildEmpty(theme);
    }
    return _buildList(theme);
  }

  Widget _buildLoading(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: theme.colorScheme.primary,
            strokeWidth: 2,
          ),
          const SizedBox(height: 16),
          Text(
            tr('loading'),
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: theme.colorScheme.error,
            ),
            const SizedBox(height: 16),
            Text(
              tr('prompts_error'),
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadPrompts,
              icon: const Icon(Icons.refresh),
              label: Text(tr('prompts_retry')),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.psychology_outlined,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.4),
          ),
          const SizedBox(height: 16),
          Text(
            tr('prompts_empty'),
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            tr('prompts_empty_desc'),
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _onCreatePrompt,
            icon: const Icon(Icons.add),
            label: Text(tr('prompts_create')),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadPrompts,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _prompts.length,
        itemBuilder: (context, index) {
          final prompt = _prompts[index];
          return _buildPromptCard(theme, prompt);
        },
      ),
    );
  }

  Widget _buildPromptCard(ThemeData theme, SystemPrompt prompt) {
    final isActive = prompt.isActive;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? theme.colorScheme.primary.withValues(alpha: 0.6)
              : theme.colorScheme.outline.withValues(alpha: 0.2),
          width: isActive ? 2 : 1,
        ),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: theme.colorScheme.primary.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ]
            : null,
      ),
      child: InkWell(
        onTap: () => _onSetActive(prompt),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                isActive ? Icons.check_circle : Icons.radio_button_unchecked,
                color: isActive
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                size: 28,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          prompt.targetFeature,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                            color: isActive
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isActive
                                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                                : theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            prompt.version,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isActive
                                  ? theme.colorScheme.primary
                                  : theme.colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              tr('prompts_active'),
                              style: TextStyle(
                                fontSize: 11,
                                color: theme.colorScheme.onPrimary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      prompt.content.length > 120
                          ? '${prompt.content.substring(0, 120)}...'
                          : prompt.content,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isActive)
                Icon(
                  Icons.arrow_forward_ios,
                  size: 16,
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreatePromptResult {
  final String feature;
  final String content;
  final String version;

  _CreatePromptResult({
    required this.feature,
    required this.content,
    required this.version,
  });
}

class _CreatePromptDialog extends StatefulWidget {
  const _CreatePromptDialog();

  @override
  State<_CreatePromptDialog> createState() => _CreatePromptDialogState();
}

class _CreatePromptDialogState extends State<_CreatePromptDialog> {
  final _featureController = TextEditingController(text: 'DocAnalysis');
  final _versionController = TextEditingController(text: '1.0');
  final _contentController = TextEditingController();

  @override
  void dispose() {
    _featureController.dispose();
    _versionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = LocalizationService.instance.isHebrew;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(tr('prompts_create')),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _featureController,
                  decoration: InputDecoration(
                    labelText: tr('prompts_feature_label'),
                    hintText: 'Search, DocAnalysis, Summary, Tags',
                  ),
                  textCapitalization: TextCapitalization.none,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _versionController,
                  decoration: InputDecoration(
                    labelText: tr('prompts_version_label'),
                    hintText: '1.0',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _contentController,
                  decoration: InputDecoration(
                    labelText: tr('prompts_content_label'),
                    hintText: tr('prompts_content_hint'),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 10,
                  minLines: 5,
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('cancel')),
          ),
          FilledButton(
            onPressed: () {
              final feature = _featureController.text.trim();
              final version = _versionController.text.trim();
              final content = _contentController.text.trim();
              if (feature.isEmpty || version.isEmpty || content.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(tr('prompts_fill_required')),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return;
              }
              Navigator.of(context).pop(_CreatePromptResult(
                feature: feature,
                content: content,
                version: version,
              ));
            },
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }
}
