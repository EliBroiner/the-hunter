import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import '../../../utils/workflow_log_sink.dart';
import '../../../utils/workflow_tester.dart';

/// מסך בדיקת צינור — בחירת קובץ והרצת testFileWorkflow, Timeline + Export
class WorkflowTestScreen extends StatefulWidget {
  const WorkflowTestScreen({super.key});

  @override
  State<WorkflowTestScreen> createState() => _WorkflowTestScreenState();
}

class _WorkflowTestScreenState extends State<WorkflowTestScreen> {
  final _sink = WorkflowLogSink.instance;
  final _tester = WorkflowTester.instance;
  bool _isRunning = false;

  @override
  void initState() {
    super.initState();
    _sink.addListener(_onLogChanged);
  }

  @override
  void dispose() {
    _sink.removeListener(_onLogChanged);
    super.dispose();
  }

  void _onLogChanged() => setState(() {});

  Future<void> _pickAndRun() async {
    if (_isRunning) return;
    final result = await FilePicker.platform.pickFiles(
      type: FileType.any,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;

    setState(() => _isRunning = true);
    try {
      await _tester.testFileWorkflow(path);
    } finally {
      if (mounted) setState(() => _isRunning = false);
    }
  }

  Future<void> _exportLog() async {
    if (_sink.lines.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: _sink.fullText, subject: 'Workflow Test Results'),
    );
  }

  /// מחזיר צבע לפי זמן (ms): Green < 2s, Yellow 2-5s, Red > 5s
  Color? _timerColor(String line) {
    final match = RegExp(r'(\d+(?:\.\d+)?)\s*(ms|s)').firstMatch(line);
    if (match == null) return null;
    var ms = double.tryParse(match.group(1) ?? '0') ?? 0;
    if ((match.group(2) ?? '') == 's') ms *= 1000;
    if (ms < 2000) return const Color(0xFF4CAF50);
    if (ms <= 5000) return const Color(0xFFFFC107);
    return const Color(0xFFE53935);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pipeline Test'),
        actions: [
          IconButton(
            icon: const Icon(Icons.upload_file),
            onPressed: _sink.lines.isEmpty ? null : _exportLog,
            tooltip: 'Export Log',
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _sink.lines.isEmpty ? null : () => _sink.clear(),
            tooltip: 'Clear',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton.icon(
              onPressed: _isRunning ? null : _pickAndRun,
              icon: _isRunning
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.play_arrow),
              label: Text(_isRunning ? 'Running...' : 'Pick File & Test Pipeline'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              width: double.infinity,
              color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFF5F5F5),
              child: _sink.lines.isEmpty
                  ? Center(
                      child: Text(
                        'No logs yet. Tap "Pick File & Test Pipeline" to run.',
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.hintColor),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(16),
                      itemCount: _sink.lines.length,
                      itemBuilder: (_, i) {
                        final line = _sink.lines[i];
                        final isTimer = line.contains('[Timer]');
                        final timerColor = isTimer ? _timerColor(line) : null;
                        final isHeader = line.startsWith('---');
                        Color? fg = isDark ? Colors.white70 : Colors.black87;
                        if (timerColor != null) fg = timerColor;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: SelectableText(
                            line,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              fontWeight: isHeader || isTimer ? FontWeight.w600 : FontWeight.normal,
                              color: fg,
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
