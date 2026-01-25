import 'package:flutter/foundation.dart';

/// שירות לוגים פשוט לאבחון
class LogService {
  static final LogService _instance = LogService._();
  static LogService get instance => _instance;
  
  LogService._();
  
  final List<String> _logs = [];
  final ValueNotifier<List<String>> logsNotifier = ValueNotifier([]);
  
  /// מוסיף לוג
  void log(String message) {
    final timestamp = DateTime.now().toString().substring(11, 19);
    final logEntry = '[$timestamp] $message';
    _logs.add(logEntry);
    
    // שומר רק 100 לוגים אחרונים
    if (_logs.length > 100) _logs.removeAt(0);
    
    logsNotifier.value = List.from(_logs);
    
    // גם מדפיס לקונסול
    print(logEntry);
  }
  
  /// מנקה את הלוגים
  void clear() {
    _logs.clear();
    logsNotifier.value = [];
  }
  
  /// מחזיר את כל הלוגים כטקסט
  String getAllLogs() {
    return _logs.join('\n');
  }
  
  /// מחזיר את מספר הלוגים
  int get count => _logs.length;
}

/// קיצור לשימוש קל
void appLog(String message) => LogService.instance.log(message);
