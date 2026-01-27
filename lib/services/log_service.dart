import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
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
    
    // שומר רק 500 לוגים אחרונים (הגדלתי מ-100 כדי לתפוס יותר היסטוריה)
    if (_logs.length > 500) _logs.removeAt(0);
    
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
  
  /// מייצא את הלוגים לקובץ ומשתף אותו
  Future<void> exportLogs() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/app_logs.txt');
      
      final logContent = getAllLogs();
      await file.writeAsString(logContent);
      
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'The Hunter App Logs',
        text: 'מצורף קובץ לוגים לאבחון תקלה.',
      );
    } catch (e) {
      log('Error exporting logs: $e');
    }
  }
  
  /// מחזיר את מספר הלוגים
  int get count => _logs.length;
}

/// קיצור לשימוש קל
void appLog(String message) => LogService.instance.log(message);
