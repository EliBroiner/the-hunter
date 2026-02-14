import 'dart:async';

import 'package:flutter/foundation.dart';

import 'category_manager_service.dart';
import 'knowledge_base_service.dart';
import 'log_service.dart';

/// שירות סנכרון תקופתי — בודק גרסת מילון וקטגוריות בעת חזרה ל־Foreground או כל 60 דקות.
class PeriodicSyncService {
  static PeriodicSyncService? _instance;
  static PeriodicSyncService get instance {
    _instance ??= PeriodicSyncService._();
    return _instance!;
  }

  PeriodicSyncService._();

  static const Duration _interval = Duration(minutes: 60);
  static const Duration syncThrottleDuration = Duration(minutes: 30);
  Timer? _timer;
  DateTime? _lastCheck;

  /// מתחיל את הטיימר התקופתי. קוראים אחרי bootstrap.
  void start() {
    _timer?.cancel();
    _timer = Timer.periodic(_interval, (_) => _runCheck(forceSync: false));
    if (kDebugMode) appLog('[SYNC] PeriodicSyncService started (every 60 min)');
  }

  /// עוצר את הטיימר.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// נקרא כשהאפליקציה חוזרת ל־Foreground.
  void onAppForeground() {
    _runCheck(forceSync: false);
  }

  /// בודק גרסה ומבצע סנכרון. [forceSync] או [hasUncategorized] — עוקף throttle.
  Future<void> checkDictionaryVersion({
    bool forceSync = false,
    bool hasUncategorized = false,
  }) async {
    await _runCheck(forceSync: forceSync, hasUncategorized: hasUncategorized);
  }

  Future<void> _runCheck({bool forceSync = false, bool hasUncategorized = false}) async {
    final bypassThrottle = forceSync || hasUncategorized;
    if (!bypassThrottle &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < syncThrottleDuration) {
      appLog('[SYNC] Skipping auto-sync: last sync was less than 30 mins ago.');
      return;
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
