import 'package:flutter/material.dart';

import '../models/models.dart';
import '../services/localization_service.dart';
import '../services/prompt_admin_service.dart';
import 'prompt_management_screen/widgets/prompt_management_widgets.dart';

/// מסך ניהול פרומפטים — רשימה, הוספת טיוטה, הפעלת גרסה.
/// דורש Admin. RTL-friendly, Material 3.
class PromptManagementScreen extends StatefulWidget {
  const PromptManagementScreen({super.key});

  @override
  State<PromptManagementScreen> createState() => _PromptManagementScreenState();
}

class _PromptManagementScreenState extends State<PromptManagementScreen> {
  final _promptService = PromptAdminService.instance;

  static const _featureOptions = [
    ('analysis', 'Document Analysis'),
    ('trainer', 'Document Trainer'),
    ('search', 'Smart Search'),
    ('ocr_extraction', 'OCR Extraction'),
  ];

  List<SystemPrompt> _prompts = [];
  SystemPromptResult? _latestFallback;
  bool _isLoading = true;
  String? _error;
  String _selectedFeature = 'analysis';

  @override
  void initState() {
    super.initState();
    _loadPrompts();
  }

  Future<void> _loadPrompts() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _latestFallback = null;
    });
    try {
      final list = await _promptService.fetchPromptsByFeature(_selectedFeature);
      SystemPromptResult? latest;
      if (list.isEmpty) {
        latest = await _promptService.fetchLatestPrompt(_selectedFeature);
      }
      if (mounted) {
        setState(() {
          _prompts = list;
          _latestFallback = latest;
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
      builder: (context) => _CreatePromptDialog(initialFeature: _selectedFeature),
    );
    if (result == null || !mounted) return;
    final created = await _promptService.savePrompt(
      feature: result.feature,
      content: result.content,
      version: result.version,
      setActive: result.setActive,
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

  Future<void> _showPromptHistory() async {
    await showDialog<void>(
      context: context,
      builder: (context) => _PromptHistoryDialog(
        promptService: _promptService,
        onEdit: _onEditPrompt,
        onSetActive: _onSetActive,
        onClosed: _loadPrompts,
      ),
    );
    if (mounted) await _loadPrompts();
  }

  Future<void> _onEditPrompt(SystemPrompt prompt) async {
    final result = await showDialog<_CreatePromptResult>(
      context: context,
      builder: (context) => _EditPromptDialog(prompt: prompt),
    );
    if (result == null || !mounted) return;
    final created = await _promptService.savePrompt(
      feature: result.feature,
      content: result.content,
      version: result.version,
      setActive: result.setActive,
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
    final ok = ['analysis', 'trainer', 'search', 'ocr_extraction'].contains(_selectedFeature)
        ? await _promptService.setPromptActiveByFeatureVersion(prompt.targetFeature, prompt.version)
        : await _promptService.setPromptActive(prompt.id);
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
              icon: const Icon(Icons.history),
              onPressed: _isLoading ? null : _showPromptHistory,
              tooltip: tr('prompts_history'),
            ),
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
      return PromptManagementError(
        theme: theme,
        detailMessage: _error!,
        onRetry: _loadPrompts,
      );
    }
    if (_isLoading) {
      return PromptManagementLoading(theme: theme);
    }
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedFeature,
            decoration: InputDecoration(
              labelText: tr('prompts_select_feature'),
              border: const OutlineInputBorder(),
            ),
            items: _featureOptions
                .map((e) => DropdownMenuItem(value: e.$1, child: Text(e.$2)))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                setState(() => _selectedFeature = v);
                _loadPrompts();
              }
            },
          ),
        ),
        Expanded(
          child: _prompts.isEmpty && _latestFallback == null
              ? PromptManagementEmpty(theme: theme, onCreate: _onCreatePrompt)
              : _buildList(theme),
        ),
      ],
    );
  }

  Widget _buildList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadPrompts,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_prompts.isEmpty && _latestFallback != null) _buildFallbackCard(theme),
          ..._prompts.map((p) => PromptManagementCard(
                theme: theme,
                prompt: p,
                onTap: () => _onSetActive(p),
                onEdit: () => _onEditPrompt(p),
              )),
        ],
      ),
    );
  }

  Widget _buildFallbackCard(ThemeData theme) {
    final fb = _latestFallback!;
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.amber.shade700, size: 24),
              const SizedBox(width: 8),
              Text(
                '${tr('prompts_active')}: ${fb.version}',
                style: theme.textTheme.titleSmall?.copyWith(color: Colors.amber.shade800),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            fb.text.length > 200 ? '${fb.text.substring(0, 200)}...' : fb.text,
            style: theme.textTheme.bodySmall,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => _onSaveFallbackAs10(),
            icon: const Icon(Icons.save, size: 18),
            label: Text(tr('prompts_save_as').replaceAll('{{version}}', '1.0')),
          ),
        ],
      ),
    );
  }

  Future<void> _onSaveFallbackAs10() async {
    final fb = _latestFallback;
    if (fb == null) return;
    final created = await _promptService.savePrompt(
      feature: _selectedFeature,
      content: fb.text,
      version: '1.0',
      setActive: true,
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

}

class _CreatePromptResult {
  final String feature;
  final String content;
  final String version;
  final bool setActive;

  _CreatePromptResult({
    required this.feature,
    required this.content,
    required this.version,
    this.setActive = false,
  });
}

class _EditPromptDialog extends StatefulWidget {
  const _EditPromptDialog({required this.prompt});

  final SystemPrompt prompt;

  @override
  State<_EditPromptDialog> createState() => _EditPromptDialogState();
}

class _EditPromptDialogState extends State<_EditPromptDialog> {
  late final TextEditingController _featureController;
  late final TextEditingController _versionController;
  late final TextEditingController _contentController;
  late final String _originalVersion;
  bool _setActive = false;

  static String _nextVersion(String current) {
    final parts = current.split('.');
    if (parts.isEmpty) return '1.1';
    final last = int.tryParse(parts.last) ?? 0;
    parts[parts.length - 1] = '${last + 1}';
    return parts.join('.');
  }

  @override
  void initState() {
    super.initState();
    _originalVersion = widget.prompt.version;
    _featureController = TextEditingController(text: widget.prompt.targetFeature);
    _versionController = TextEditingController(text: _nextVersion(widget.prompt.version));
    _contentController = TextEditingController(text: widget.prompt.content);
  }

  @override
  void dispose() {
    _featureController.dispose();
    _versionController.dispose();
    _contentController.dispose();
    super.dispose();
  }

  String get _effectiveVersion {
    final v = _versionController.text.trim();
    return v == _originalVersion ? '$v.1' : v;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = LocalizationService.instance.isHebrew;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(tr('prompts_edit')),
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
                SwitchListTile(
                  title: Text(tr('prompts_set_active')),
                  value: _setActive,
                  onChanged: (v) => setState(() => _setActive = v),
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
              var version = _versionController.text.trim();
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
              if (version == _originalVersion) version = '$version.1';
              Navigator.of(context).pop(_CreatePromptResult(
                feature: feature,
                content: content,
                version: version,
                setActive: _setActive,
              ));
            },
            child: Text(tr('prompts_save_as').replaceAll('{{version}}', _effectiveVersion)),
          ),
        ],
      ),
    );
  }
}

class _CreatePromptDialog extends StatefulWidget {
  const _CreatePromptDialog({this.initialFeature = 'analysis'});

  final String initialFeature;

  @override
  State<_CreatePromptDialog> createState() => _CreatePromptDialogState();
}

class _CreatePromptDialogState extends State<_CreatePromptDialog> {
  late final TextEditingController _featureController;

  @override
  void initState() {
    super.initState();
    _featureController = TextEditingController(text: widget.initialFeature);
  }
  final _versionController = TextEditingController(text: '1.0');
  final _contentController = TextEditingController();
  bool _setActive = false;

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
                SwitchListTile(
                  title: Text(tr('prompts_set_active')),
                  value: _setActive,
                  onChanged: (v) => setState(() => _setActive = v),
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
                setActive: _setActive,
              ));
            },
            child: Text(tr('save')),
          ),
        ],
      ),
    );
  }
}

/// דיאלוג היסטוריית פרומפטים — בחירת feature, רשימת גרסאות, נקודה ירוקה לפעיל.
class _PromptHistoryDialog extends StatefulWidget {
  const _PromptHistoryDialog({
    required this.promptService,
    required this.onEdit,
    required this.onSetActive,
    required this.onClosed,
  });

  final PromptAdminService promptService;
  final void Function(SystemPrompt) onEdit;
  final void Function(SystemPrompt) onSetActive;
  final VoidCallback onClosed;

  @override
  State<_PromptHistoryDialog> createState() => _PromptHistoryDialogState();
}

class _PromptHistoryDialogState extends State<_PromptHistoryDialog> {
  static const _features = [
    ('analysis', 'Document Analysis'),
    ('trainer', 'Document Trainer'),
    ('search', 'Smart Search'),
    ('ocr_extraction', 'OCR Extraction'),
  ];
  String _selectedFeature = _features.first.$1;
  List<SystemPrompt> _prompts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await widget.promptService.fetchPromptsByFeature(_selectedFeature);
      if (mounted) {
        setState(() {
          _prompts = list;
          _loading = false;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isRtl = LocalizationService.instance.isHebrew;

    return Directionality(
      textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
      child: AlertDialog(
        backgroundColor: theme.colorScheme.surface,
        title: Text(tr('prompts_history')),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedFeature,
                decoration: InputDecoration(
                  labelText: tr('prompts_feature_label'),
                ),
                items: _features.map((f) => DropdownMenuItem(value: f.$1, child: Text(f.$2))).toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() => _selectedFeature = v);
                    _load();
                  }
                },
              ),
              const SizedBox(height: 16),
              if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_error != null)
                Text(_error!, style: TextStyle(color: theme.colorScheme.error, fontSize: 12))
              else if (_prompts.isEmpty)
                Text(tr('prompts_empty'), style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.6)))
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _prompts.length,
                    itemBuilder: (_, i) {
                      final p = _prompts[i];
                      return ListTile(
                        leading: Icon(
                          Icons.circle,
                          size: 12,
                          color: p.isActive ? Colors.green : theme.colorScheme.outline.withValues(alpha: 0.4),
                        ),
                        title: Text(p.version),
                        subtitle: p.isActive ? Text(tr('prompts_active'), style: TextStyle(color: Colors.green, fontSize: 12)) : null,
                        onTap: () {
                          Navigator.of(context).pop();
                          widget.onEdit(p);
                        },
                        trailing: !p.isActive
                            ? IconButton(
                                icon: const Icon(Icons.check_circle_outline, size: 20),
                                tooltip: tr('prompts_set_active'),
                                onPressed: () {
                                  widget.onSetActive(p);
                                  Navigator.of(context).pop();
                                },
                              )
                            : null,
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onClosed();
            },
            child: Text(tr('close')),
          ),
        ],
      ),
    );
  }
}
