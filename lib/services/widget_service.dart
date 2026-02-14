import 'dart:convert';

import 'package:home_widget/home_widget.dart';
import 'log_service.dart';

/// פריט במטמון הווידג'ט — קל משקל, ללא Isar
class WidgetCacheItem {
  final String name;
  final String category;
  final String path;
  final int timestamp;

  const WidgetCacheItem({
    required this.name,
    required this.category,
    required this.path,
    required this.timestamp,
  });

  Map<String, dynamic> toJson() =>
      {'n': name, 'c': category, 'p': path, 't': timestamp};

  static WidgetCacheItem? fromJson(Map<String, dynamic>? j) {
    if (j == null) return null;
    final n = j['n'] as String?;
    final p = j['p'] as String?;
    if (n == null || p == null) return null;
    final t = j['t'] is int ? j['t'] as int : 0;
    return WidgetCacheItem(
      name: n,
      category: j['c'] as String? ?? '—',
      path: p,
      timestamp: t,
    );
  }
}

/// שירות ווידג'ט Data-Light — SharedPreferences/AppGroup בלבד, ללא Isar
class WidgetService {
  static WidgetService? _instance;
  WidgetService._();

  static WidgetService get instance {
    _instance ??= WidgetService._();
    return _instance!;
  }

  static const String _androidWidgetName = 'SearchWidgetProvider';
  static const String _appGroupId = 'group.com.thehunter.the_hunter';
  static const String _cacheKey = 'widget_recent_data';
  static const int _maxCachedFiles = 15;

  Future<void> init() async {
    try {
      await HomeWidget.setAppGroupId(_appGroupId);
      await _refreshWidget();
      appLog('WidgetService: Initialized (data-light)');
    } catch (e) {
      appLog('WidgetService: Init error - $e');
    }
  }

  /// מעדכן את המטמון — נקרא מ־FileProcessingService.updateWidgetCache
  Future<void> addToCache(String name, String category, String path) async {
    try {
      final current = await _readCache();
      final item = WidgetCacheItem(
        name: name,
        category: category,
        path: path,
        timestamp: DateTime.now().millisecondsSinceEpoch,
      );
      final updated = [item, ...current.where((e) => e.path != path)]
          .take(_maxCachedFiles)
          .toList();
      await _writeCache(updated);
      await _refreshWidget();
    } catch (e) {
      appLog('WidgetService: addToCache error - $e');
    }
  }

  Future<List<WidgetCacheItem>> _readCache() async {
    final raw = await HomeWidget.getWidgetData<String>(_cacheKey, defaultValue: null);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List<dynamic>?;
      return list?.map((e) => WidgetCacheItem.fromJson(e as Map<String, dynamic>?)).whereType<WidgetCacheItem>().toList() ?? [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _writeCache(List<WidgetCacheItem> items) async {
    final json = jsonEncode(items.map((e) => e.toJson()).toList());
    await HomeWidget.saveWidgetData<String>(_cacheKey, json);
  }

  Future<void> _refreshWidget() async {
    await HomeWidget.updateWidget(
      androidName: _androidWidgetName,
      qualifiedAndroidName: 'com.thehunter.the_hunter.$_androidWidgetName',
    );
  }

  /// בודק אם נתיב קיים במטמון הווידג'ט (SharedPreferences)
  Future<bool> isInCache(String path) async {
    try {
      final items = await _readCache();
      return items.any((e) => e.path == path);
    } catch (_) {
      return false;
    }
  }

  /// רענון ווידג'ט — קורא למטמון הקיים (ללא Isar)
  Future<void> refreshWidget() async => _refreshWidget();

  /// ניקוי מטמון — למשל אחרי Reset All
  Future<void> clearCache() async {
    await HomeWidget.saveWidgetData<String?>(_cacheKey, null);
    await _refreshWidget();
  }

  Future<void> registerInteractivityCallback() async {
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    } catch (e) {
      appLog('WidgetService: Register callback error - $e');
    }
  }
}

@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  appLog('WidgetService: Background callback triggered - $uri');
}
