import 'dart:async';

import 'package:flutter/foundation.dart';

import 'category_manager_service.dart';
import 'knowledge_base_service.dart';
import 'log_service.dart';

/// שירות סנכרון תקופתי — בודק גרסת מילון וקטגוריות בעת חזרה ל־Foreground או כל 10 דקות.
class PeriodicSyncService {
  static PeriodicSyncService? _instance;
  static PeriodicSyncService get instance {
    _instance ??= PeriodicSyncService._();
    return _instance!;
  }

  PeriodicSyncService._();

  static const Duration _interval = Duration(minutes: 10);
  static const Duration _throttle = Duration(minutes: 5);
  Timer? _timer;
  DateTime? _lastCheck;

  /// מתחיל את הטיימר התקופתי. קוראים אחרי bootstrap.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _runCheck());
    if (kDebugMode) appLog('[SYNC] PeriodicSyncService started (every 10 min)');
  }

  /// עוצר את הטיימר.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// נקרא כשהאפליקציה חוזרת ל־Foreground (WidgetsBindingObserver.didChangeAppLifecycleState).
  void onAppForeground() {
    _runCheck();
  }

  /// בודק גרסה ומבצע סנכרון רקע רק אם יש עדכונים. ללא overlay.
  Future<void> checkDictionaryVersion() async {
    await _runCheck();
  }

  Future<void> _runCheck() async {
    if (_lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < _throttle) {
      return; // דילוג — פחות מ־5 דקות מאז הסנכרון האחרון
    }
    _lastCheck = DateTime.now();

    try {
      await KnowledgeBaseService.instance.syncDictionaryWithServer();
      await CategoryManagerService.instance.loadCategories();
      if (kDebugMode) appLog('[SYNC] סנכרון רקע הושלם.');
    } catch (e) {
      appLog('[SYNC] sync error: $e');
    }
  }
}
