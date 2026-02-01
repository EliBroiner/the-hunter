import 'package:flutter/foundation.dart';

/// לוגר לפיתוח — שומר 100 לוגים אחרונים; IDE console מקבל גם debugPrint
class DevLogger {
  static final DevLogger _instance = DevLogger._();
  static DevLogger get instance => _instance;

  DevLogger._();

  static const int _maxLogs = 100;
  final List<String> _logs = [];
  final ValueNotifier<List<String>> logsNotifier = ValueNotifier([]);

  void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final entry = '[$timestamp] $message';
    _logs.add(entry);
    if (_logs.length > _maxLogs) _logs.removeAt(0);
    logsNotifier.value = List.from(_logs);
    debugPrint(message);
  }

  List<String> get logs => List.unmodifiable(_logs);

  void clear() {
    _logs.clear();
    logsNotifier.value = [];
  }
}
