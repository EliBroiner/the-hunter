import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'app_check_http_helper.dart';

/// כלי עזר משותפים לסנכרון גרסה — CategoryManagerService.
class SyncVersionUtils {
  SyncVersionUtils._();

  static bool isServerNewer(String server, String local) =>
      server.compareTo(local) > 0;

  static Future<({String version, String? lastModified})?> fetchVersion(
    String fullUrl,
  ) async {
    final uri = Uri.parse(fullUrl);
    final headers = await AppCheckHttpHelper.getBackendHeaders();
    final r = await http.get(uri, headers: headers).timeout(
      const Duration(seconds: 5),
    );
    if (r.statusCode != 200) return null;
    final data = jsonDecode(r.body);
    if (data is! Map<String, dynamic>) return null;
    return (
      version: data['version']?.toString() ?? '',
      lastModified: data['lastModified']?.toString(),
    );
  }

  static Future<void> saveTimestamp(String prefsKey, String ts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(prefsKey, ts);
  }

  static Future<String?> getTimestamp(String prefsKey) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(prefsKey);
  }

  /// מאפס את ה-timestamp — מאפשר סנכרון מלא מחדש.
  static Future<void> resetTimestamp(String prefsKey) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(prefsKey);
  }
}
