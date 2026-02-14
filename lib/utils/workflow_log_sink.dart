import 'package:flutter/foundation.dart';

/// בורר לוגים לצינור בדיקה — מאפשר הצגה ב-Debug Console
class WorkflowLogSink extends ChangeNotifier {
  static WorkflowLogSink? _instance;
  static WorkflowLogSink get instance {
    _instance ??= WorkflowLogSink._();
    return _instance!;
  }

  WorkflowLogSink._();

  final List<String> _lines = [];
  static const int _maxLines = 500;

  List<String> get lines => List.unmodifiable(_lines);

  void log(String line) {
    _lines.add(line);
    if (_lines.length > _maxLines) _lines.removeAt(0);
    notifyListeners();
  }

  void clear() {
    _lines.clear();
    notifyListeners();
  }

  String get fullText => _lines.join('\n');
}
