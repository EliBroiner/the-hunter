import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'ai_auto_tagger_service.dart';
import 'backup_service.dart';
import 'database_service.dart';
import 'file_scanner_service.dart';
import 'file_watcher_service.dart';
import 'log_service.dart';
import 'processing_progress_service.dart';
import 'user_activity_service.dart';
import 'widget_service.dart';

/// מנהל סריקה אוטומטית ומעקב קבצים.
/// תומך ב-lifecycle — עיבוד רק כשהאפליקציה ברקע.
class AutoScanManager with WidgetsBindingObserver {
  static final AutoScanManager _instance = AutoScanManager._();
  static AutoScanManager get instance => _instance;

  AutoScanManager._();

  bool _isInitialized = false;
  bool _isScanning = false;
  bool _isProcessing = false;
  bool _isPaused = false;
  bool _hasLifecycleObserver = false;
  bool _appInBackground = false;
  Timer? _resumeDebounceTimer;
  static const Duration _resumeDebounce = Duration(milliseconds: 3000);
  static const int maxFilesPerSession = 20;

  final ValueNotifier<bool> isScanningNotifier = ValueNotifier(false);

  Function(ScanResult result)? onScanComplete;
  Function(ProcessResult result)? onProcessComplete;
  Function(String path)? onNewFileFound;
  Function(String status)? onStatusUpdate;
  Function(BackupInfo backupInfo)? onBackupFound;

  bool get isScanning => _isScanning;
  bool get isProcessing => _isProcessing;
  bool get isPaused => _isPaused;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    if (!_hasLifecycleObserver) {
      WidgetsBinding.instance.addObserver(this);
      _hasLifecycleObserver = true;
    }

    UserActivityService.instance.isUserActive.addListener(_onUserActivityChanged);
    _runBackgroundScanAndProcess();
    _startFileWatcher();
  }

  void _onUserActivityChanged() {
    final isActive = UserActivityService.instance.isUserActive.value;
    if (isActive) {
      _resumeDebounceTimer?.cancel();
      if (!_appInBackground && !_isPaused) {
        _isPaused = true;
        appLog('AutoScan: Paused (user active)');
      }
    } else {
      if (_isPaused) {
        _resumeDebounceTimer?.cancel();
        _resumeDebounceTimer = Timer(_resumeDebounce, () {
          _resumeDebounceTimer = null;
          if (_isPaused) {
            _isPaused = false;
            appLog('AutoScan: Resumed (user idle, debounced)');
            _resumeProcessingIfNeeded();
          }
        });
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appInBackground = false;
        _onAppResumed();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _appInBackground = true;
        _resumeDebounceTimer?.cancel();
        _resumeDebounceTimer = null;
        if (_isPaused) {
          _isPaused = false;
          appLog('AutoScan: Resumed (app backgrounded)');
          _resumeProcessingIfNeeded();
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }

  bool _shouldPause() => _isPaused && !AiAutoTaggerService.instance.isUploading;

  /// כשהאפליקציה חוזרת לרקע — סריקה מיידית לקבצים חדשים
  void _onAppResumed() {
    if (_isScanning || _isProcessing) return;
    appLog('AutoScan: App resumed — triggering scanForNewFiles');
    unawaited(_scanForNewFilesOnResume());
  }

  Future<void> _scanForNewFilesOnResume() async {
    try {
      final result = await FileScannerService.instance.scanNewFilesOnly(runCleanup: true);
      if (result.newFilesAdded > 0) {
        appLog('AutoScan: Resume scan found ${result.newFilesAdded} new files');
        onScanComplete?.call(result);
        final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
        if (pendingCount > 0 && !_shouldPause()) {
          _isProcessing = true;
          ProcessingProgressService.instance.start(pendingCount);
          final processResult = await FileScannerService.instance.processPendingFiles(
            shouldPause: _shouldPause,
            maxFilesPerSession: maxFilesPerSession,
            onProgress: (c, t) => ProcessingProgressService.instance.update(c, t),
          );
          ProcessingProgressService.instance.finish();
          onProcessComplete?.call(processResult);
        }
        await WidgetService.instance.refreshWidget();
      }
    } catch (e) {
      appLog('AutoScan: scanForNewFiles on resume failed - $e');
    }
  }

  Future<void> _resumeProcessingIfNeeded() async {
    if (_isProcessing || _shouldPause()) return;

    final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
    if (pendingCount > 0) {
      appLog('AutoScan: Resuming processing of $pendingCount pending files');
      _isProcessing = true;
      ProcessingProgressService.instance.start(pendingCount);

      final processResult = await FileScannerService.instance.processPendingFiles(
        shouldPause: _shouldPause,
        maxFilesPerSession: maxFilesPerSession,
        onProgress: (c, t) => ProcessingProgressService.instance.update(c, t),
      );
      ProcessingProgressService.instance.finish();
      onProcessComplete?.call(processResult);

      _isProcessing = false;
    }
  }

  Future<void> _runBackgroundScanAndProcess() async {
    if (_isScanning) return;
    _isScanning = true;
    isScanningNotifier.value = true;

    try {
      final isFirstRun = DatabaseService.instance.getFilesCount() == 0;
      final backupService = BackupService.instance;

      if (isFirstRun && backupService.hasUser) {
        onStatusUpdate?.call('בודק גיבוי קיים...');

        final backupInfo = await backupService.getBackupInfo();
        if (backupInfo != null && backupInfo.filesCount > 0) {
          appLog('AutoScan: Found backup with ${backupInfo.filesCount} files!');

          onStatusUpdate?.call('משחזר מגיבוי...');

          final result = await FileScannerService.instance.scanWithBackupRestore(
            onStatus: (status) => onStatusUpdate?.call(status),
            getBackupData: () => _getBackupData(),
          );

          onScanComplete?.call(result);

          if (result.skippedOcrCount > 0) {
            appLog('AutoScan: Saved OCR on ${result.skippedOcrCount} files from backup!');
          }

          final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
          if (pendingCount > 0) {
            _isScanning = false;
            _isProcessing = true;
            onStatusUpdate?.call('מחלץ טקסט מ-$pendingCount קבצים חדשים...');
            ProcessingProgressService.instance.start(pendingCount);

            final processResult = await FileScannerService.instance.processPendingFiles(
              shouldPause: _shouldPause,
              maxFilesPerSession: maxFilesPerSession,
              onProgress: (c, t) => ProcessingProgressService.instance.update(c, t),
            );
            ProcessingProgressService.instance.finish();
            onProcessComplete?.call(processResult);
          }

          onStatusUpdate?.call('');
          _runAutoBackupIfNeeded();
          return;
        }
      }

      onStatusUpdate?.call('סורק תיקיות...');

      final result = await FileScannerService.instance.scanNewFilesOnly(
        runCleanup: true,
      );

      onScanComplete?.call(result);

      final pendingCount = DatabaseService.instance.getAllPendingFiles().length;

      if (pendingCount > 0) {
        _isScanning = false;
        _isProcessing = true;
        onStatusUpdate?.call('מחלץ טקסט מ-$pendingCount קבצים...');
        ProcessingProgressService.instance.start(pendingCount);

        final processResult = await FileScannerService.instance.processPendingFiles(
          shouldPause: _shouldPause,
          maxFilesPerSession: maxFilesPerSession,
          onProgress: (c, t) => ProcessingProgressService.instance.update(c, t),
        );
        ProcessingProgressService.instance.finish();
        onProcessComplete?.call(processResult);
        onStatusUpdate?.call('');

        _runAutoBackupIfNeeded();
      } else {
        onStatusUpdate?.call('');
        _runAutoBackupIfNeeded();
      }

      await WidgetService.instance.refreshWidget();
    } finally {
      _isScanning = false;
      _isProcessing = false;
      isScanningNotifier.value = false;
    }
  }

  Future<Map<String, dynamic>?> _getBackupData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;

      final ref = FirebaseStorage.instance.ref('backups/${user.uid}/database_backup.json');
      final data = await ref.getData();

      if (data == null) return null;

      final jsonString = utf8.decode(data);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      appLog('AutoScan: Failed to get backup data - $e');
      return null;
    }
  }

  Future<void> _runAutoBackupIfNeeded() async {
    try {
      await BackupService.instance.runAutoBackupIfNeeded();
    } catch (e) {
      appLog('AutoScan: Auto backup failed - $e');
    }
  }

  Future<void> runFullScan() async {
    if (_isScanning || _isProcessing) return;
    _isScanning = true;
    isScanningNotifier.value = true;

    try {
      onStatusUpdate?.call('סריקה מלאה...');

      final result = await FileScannerService.instance.scanAllSources();
      onScanComplete?.call(result);

      if (result.success) {
        _isScanning = false;
        _isProcessing = true;
        onStatusUpdate?.call('מחלץ טקסט...');
        final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
        if (pendingCount > 0) ProcessingProgressService.instance.start(pendingCount);

        final processResult = await FileScannerService.instance.processPendingFiles(
          shouldPause: _shouldPause,
          maxFilesPerSession: maxFilesPerSession,
          onProgress: (c, t) => ProcessingProgressService.instance.update(c, t),
        );
        ProcessingProgressService.instance.finish();
        onProcessComplete?.call(processResult);
        onStatusUpdate?.call('');
      } else {
        onStatusUpdate?.call('');
      }
    } finally {
      _isScanning = false;
      _isProcessing = false;
      isScanningNotifier.value = false;
    }
  }

  void _startFileWatcher() {
    final watcher = FileWatcherService.instance;

    watcher.onNewFile = (path) async {
      onNewFileFound?.call(path);

      if (!_isProcessing && !_isPaused) {
        _isProcessing = true;
        final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
        if (pendingCount > 0) ProcessingProgressService.instance.start(pendingCount);
        await FileScannerService.instance.processPendingFiles(
          shouldPause: _shouldPause,
          maxFilesPerSession: maxFilesPerSession,
          onProgress: (c, t) => ProcessingProgressService.instance.update(c, t),
        );
        ProcessingProgressService.instance.finish();
        _isProcessing = false;
        await WidgetService.instance.refreshWidget();
      }
    };

    watcher.startWatching();
  }

  Future<void> dispose() async {
    _resumeDebounceTimer?.cancel();
    await FileWatcherService.instance.stopWatching();
    UserActivityService.instance.isUserActive.removeListener(_onUserActivityChanged);
  }
}
