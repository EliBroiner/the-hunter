import 'dart:io';

import '../models/file_metadata.dart';
import '../services/database_service.dart';
import '../services/file_processing_service.dart';
import '../services/settings_service.dart';
import '../services/widget_service.dart';
import 'workflow_log_sink.dart';

/// כלי דיבאג — מריץ צינור עיבוד מלא ומדפיס כל שלב ל-Debug Console
class WorkflowTester {
  WorkflowTester._();
  static final WorkflowTester instance = WorkflowTester._();

  final _sink = WorkflowLogSink.instance;
  final _db = DatabaseService.instance;
  final _processor = FileProcessingService.instance;

  /// מריץ צינור עיבוד מלא על קובץ — מדפיס כל שלב ל־WorkflowLogSink
  Future<void> testFileWorkflow(String filePath) async {
    _sink.clear();
    final name = filePath.split(RegExp(r'[/\\]')).last;
    _sink.log('--- WORKFLOW TEST START ---');
    _sink.log('[File]: $name');
    _sink.log('');

    final file = File(filePath);
    if (!await file.exists()) {
      _sink.log('[Error]: File not found: $filePath');
      _sink.log('--- WORKFLOW TEST END ---');
      return;
    }

    var meta = _db.getFileByPath(filePath);
    if (meta == null) {
      final stat = await file.stat();
      meta = FileMetadata.fromFile(
        path: filePath,
        name: name,
        size: stat.size,
        lastModified: stat.modified,
      );
      _db.saveFile(meta);
      _sink.log('[DB]: File added for test (not in index)');
      _sink.log('');
    }

    final isPro = SettingsService.instance.isPremium;
    if (!isPro) {
      _sink.log('[Warning]: Not Premium — Gemini may be skipped');
      _sink.log('');
    }

    void onLog(String msg) => _sink.log(msg);

    try {
      FileProcessingService.workflowTestLog = onLog;
      final result = await _processor.forceReprocessFile(
        meta,
        isPro: isPro,
        reportProgress: (msg) => _sink.log('[$msg]'),
      );
      FileProcessingService.workflowTestLog = null;

      _sink.log('');
      _sink.log('[Outcome]: ${result.message}');
      if (result.suggestions.isNotEmpty) {
        _sink.log('[Suggestions]: ${result.suggestions.length} learning rules');
      }
      final inCache = await WidgetService.instance.isInCache(filePath);
      _sink.log('[Widget Cache]: ${inCache ? "Yes" : "No"}');
    } catch (e, st) {
      FileProcessingService.workflowTestLog = null;
      _sink.log('');
      _sink.log('[Error]: $e');
      _sink.log(st.toString().split('\n').take(5).join('\n'));
    }

    _sink.log('');
    _sink.log('--- WORKFLOW TEST END ---');
  }
}
