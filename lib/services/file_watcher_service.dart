import 'dart:async';
import 'dart:io';
import 'file_scanner_service.dart';
import 'log_service.dart';

/// שירות מעקב קבצים - עוקב אחר שינויים בתיקיות (תיקיות מותאמות אישית)
class FileWatcherService {
  static FileWatcherService? _instance;

  final FileScannerService _scannerService;
  final List<StreamSubscription<FileSystemEvent>> _subscriptions = [];
  final Set<String> _watchedPaths = {};
  Timer? _debounceTimer;
  final Set<String> _pendingPaths = {};

  /// Debounce — ממתין 2 שניות אחרי אירוע אחרון כדי להימנע מקריאת קבצים לא מושלמים
  static const Duration _debounceDelay = Duration(seconds: 2);

  /// callback כשנמצא קובץ חדש (או אחרי debounce — סריקה)
  Function(String filePath)? onNewFile;

  /// callback כשקובץ נמחק
  Function(String filePath)? onFileDeleted;

  FileWatcherService._({FileScannerService? scannerService})
      : _scannerService = scannerService ?? FileScannerService.instance;

  static FileWatcherService get instance {
    _instance ??= FileWatcherService._();
    return _instance!;
  }

  /// תיקיות למעקב — מתוך getCustomScanSources (תיקיות שנבחרו על ידי המשתמש)
  Future<List<String>> _getWatchDirectories() async {
    final sources = await _scannerService.getCustomScanSources();
    return sources.map((s) => s.path).where((p) => p.isNotEmpty).toList();
  }

  /// מתחיל מעקב אחר תיקיות
  Future<void> startWatching() async {
    await stopWatching();

    final paths = await _getWatchDirectories();
    if (paths.isEmpty) {
      appLog('FileWatcher: No custom folders — skipping watch');
      return;
    }

    for (final path in paths) {
      await _watchDirectory(path);
    }
    appLog('FileWatcher: Watching ${paths.length} folders');
  }

  /// מוסיף מעקב לתיקייה בודדת
  Future<void> _watchDirectory(String path) async {
    if (_watchedPaths.contains(path)) return;

    final directory = Directory(path);
    if (!await directory.exists()) return;

    try {
      final stream = directory.watch(
        events: FileSystemEvent.create | FileSystemEvent.delete | FileSystemEvent.move,
        recursive: true,
      );

      final subscription = stream.listen(
        _handleFileSystemEvent,
        onError: (error) {
          // שגיאה במעקב - ממשיכים
        },
      );

      _subscriptions.add(subscription);
      _watchedPaths.add(path);
    } catch (_) {
      // לא ניתן לעקוב אחר התיקייה
    }
  }

  /// מטפל באירועי מערכת קבצים — debounce 2 שניות
  void _handleFileSystemEvent(FileSystemEvent event) {
    final path = event.path;

    if (event is FileSystemCreateEvent || event is FileSystemMoveEvent) {
      if (!_isSupportedFile(path)) return;
      _debounceAndProcess(path);
    } else if (event is FileSystemDeleteEvent) {
      onFileDeleted?.call(path);
    }
  }

  /// Debounce — אוסף נתיבים, ממתין 2 שניות אחרי אירוע אחרון, אז מעבד את כולם
  void _debounceAndProcess(String path) {
    _pendingPaths.add(path);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, () async {
      _debounceTimer = null;
      final paths = _pendingPaths.toList();
      _pendingPaths.clear();
      for (final p in paths) {
        await _processAfterDebounce(p);
      }
    });
  }

  Future<void> _processAfterDebounce(String path) async {
    final isFile = await _isFile(path);
    if (!isFile) return;

    final result = await _scannerService.processNewFile(path);
    if (result != null) {
      onNewFile?.call(path);
    }
  }

  /// בודק אם הנתיב הוא קובץ
  Future<bool> _isFile(String path) async {
    try {
      final type = await FileSystemEntity.type(path);
      return type == FileSystemEntityType.file;
    } catch (_) {
      return false;
    }
  }

  /// בודק אם הקובץ נתמך
  bool _isSupportedFile(String path) {
    final extension = _extractExtension(path);
    return FileScannerService.supportedExtensions.contains(extension.toLowerCase());
  }

  /// מחלץ סיומת מנתיב
  String _extractExtension(String path) {
    final fileName = path.split(Platform.pathSeparator).last;
    final lastDot = fileName.lastIndexOf('.');
    if (lastDot == -1 || lastDot == fileName.length - 1) return '';
    return fileName.substring(lastDot + 1).toLowerCase();
  }

  /// עוצר את כל המעקבים
  Future<void> stopWatching() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _pendingPaths.clear();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    _subscriptions.clear();
    _watchedPaths.clear();
  }

  /// האם המעקב פעיל
  bool get isWatching => _subscriptions.isNotEmpty;

  /// מחזיר את רשימת התיקיות הנצפות
  Set<String> get watchedPaths => Set.unmodifiable(_watchedPaths);

  /// סוגר את השירות
  Future<void> dispose() async {
    await stopWatching();
    _instance = null;
  }
}
