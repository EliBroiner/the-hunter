import 'dart:async';
import 'dart:io';
import 'file_scanner_service.dart';

/// שירות מעקב קבצים - עוקב אחר שינויים בתיקיות
class FileWatcherService {
  static FileWatcherService? _instance;
  
  final FileScannerService _scannerService;
  final List<StreamSubscription<FileSystemEvent>> _subscriptions = [];
  final Set<String> _watchedPaths = {};
  
  /// callback כשנמצא קובץ חדש
  Function(String filePath)? onNewFile;
  
  /// callback כשקובץ נמחק
  Function(String filePath)? onFileDeleted;

  FileWatcherService._({FileScannerService? scannerService})
      : _scannerService = scannerService ?? FileScannerService.instance;

  /// מחזיר את ה-singleton של השירות
  static FileWatcherService get instance {
    _instance ??= FileWatcherService._();
    return _instance!;
  }

  /// מחזיר את התיקיות למעקב (Downloads ו-Screenshots)
  List<String> get _watchDirectories {
    final base = _scannerService.basePath;
    if (base.isEmpty) return [];

    if (Platform.isAndroid) {
      return [
        '$base/Download',
        '$base/DCIM/Screenshots',
      ];
    } else {
      final separator = Platform.isWindows ? '\\' : '/';
      return [
        '$base${separator}Downloads',
        '$base${separator}Pictures${separator}Screenshots',
      ];
    }
  }

  /// מתחיל מעקב אחר תיקיות
  Future<void> startWatching() async {
    // עוצר מעקב קודם אם קיים
    await stopWatching();

    for (final path in _watchDirectories) {
      await _watchDirectory(path);
    }
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

  /// מטפל באירועי מערכת קבצים
  Future<void> _handleFileSystemEvent(FileSystemEvent event) async {
    final path = event.path;
    
    // בודק אם זה קובץ (לא תיקייה)
    final isFile = await _isFile(path);
    if (!isFile) return;

    // בודק אם הסיומת נתמכת
    if (!_isSupportedFile(path)) return;

    if (event is FileSystemCreateEvent || event is FileSystemMoveEvent) {
      // קובץ חדש נוצר או הועבר לתיקייה
      // המתנה קצרה כדי לוודא שהקובץ נכתב במלואו
      await Future.delayed(const Duration(milliseconds: 500));
      
      // עיבוד הקובץ החדש
      final result = await _scannerService.processNewFile(path);
      if (result != null) {
        onNewFile?.call(path);
      }
    } else if (event is FileSystemDeleteEvent) {
      // קובץ נמחק
      onFileDeleted?.call(path);
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
