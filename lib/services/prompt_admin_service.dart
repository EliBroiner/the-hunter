import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/models.dart';
import 'app_check_http_helper.dart';
import 'log_service.dart';

/// שירות ניהול פרומפטים — קריאות ל־Admin API (/admin/prompts).
/// דורש Admin Key: קרא ל־PromptAdminService.setAdminKey לפני שימוש.
/// משתמש ב־AppCheckHttpHelper.getBackendHeaders() + X-Admin-Key.
class PromptAdminService {
  static PromptAdminService? _instance;
  static PromptAdminService get instance {
    _instance ??= PromptAdminService._();
    return _instance!;
  }

  PromptAdminService._();

  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app';
  static const String _promptsPath = '/admin/prompts';
  static const Duration _timeout = Duration(seconds: 15);

  /// מפתח Admin — יש להגדיר לפני קריאות (למשל מקומת Admin). משמש ל־X-Admin-Key.
  static String? _adminKey;
  static void setAdminKey(String? key) => _adminKey = key;

  /// מחזיר headers עם App Check + X-Admin-Key (אם הוגדר)
  Future<Map<String, String>> _getHeaders({Map<String, String>? existing}) async {
    final headers = await AppCheckHttpHelper.getBackendHeaders(existing: existing);
    final key = _adminKey;
    if (key != null && key.isNotEmpty) {
      headers['X-Admin-Key'] = key;
    }
    return headers;
  }

  /// מביא את הפרומפט הפעיל או fallback מוטבע — להצגה ב-UI כשהרשימה ריקה.
  Future<SystemPromptResult?> fetchLatestPrompt(String feature) async {
    if (feature.isEmpty) return null;
    try {
      final uri = Uri.parse('$_baseUrl$_promptsPath/latest?feature=${Uri.encodeComponent(feature)}');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(_timeout);
      if (response.statusCode != 200) return null;
      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      if (map == null || map['success'] != true) return null;
      final data = map['data'];
      if (data is! Map<String, dynamic>) return null;
      return SystemPromptResult.fromJson(data);
    } catch (e) {
      appLog('PromptAdmin: fetchLatestPrompt error - $e');
      return null;
    }
  }

  /// מביא פרומפטים לפי feature — ממוין לפי גרסה יורד (1.2, 1.1, 1.0).
  Future<List<SystemPrompt>> fetchPromptsByFeature(String feature) async {
    if (feature.isEmpty) return [];
    try {
      final uri = Uri.parse('$_baseUrl$_promptsPath/by-feature?feature=${Uri.encodeComponent(feature)}');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode != 200) {
        appLog('PromptAdmin: fetchPromptsByFeature failed ${response.statusCode}');
        throw Exception('${response.statusCode}: ${response.body.length > 100 ? response.body.substring(0, 100) : response.body}');
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      if (map == null) return [];
      if (map['success'] != true) return [];
      final data = map['data'];
      if (data is! List) return [];

      return data
          .map((e) => SystemPrompt.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLog('PromptAdmin: fetchPromptsByFeature error - $e');
      rethrow;
    }
  }

  /// מביא רשימת פרומפטים מ־API. אופציונלי: סינון לפי feature.
  /// מחזיר רשימה ריקה אם יש שגיאה או 401.
  Future<List<SystemPrompt>> fetchPrompts({String? feature}) async {
    try {
      final query = feature != null && feature.isNotEmpty
          ? '?feature=${Uri.encodeComponent(feature)}'
          : '';
      final uri = Uri.parse('$_baseUrl$_promptsPath$query');
      final headers = await _getHeaders();
      final response = await http.get(uri, headers: headers).timeout(_timeout);

      if (response.statusCode != 200) {
        appLog('PromptAdmin: fetchPrompts failed ${response.statusCode}');
        throw Exception('${response.statusCode}: ${response.body.length > 100 ? response.body.substring(0, 100) : response.body}');
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      if (map == null) return [];
      if (map['success'] != true) return [];
      final data = map['data'];
      if (data is! List) return [];

      return data
          .map((e) => SystemPrompt.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      appLog('PromptAdmin: fetchPrompts error - $e');
      rethrow;
    }
  }

  /// שומר טיוטת פרומפט חדש.
  /// [setActive] — אם true, מיד מפעיל את הפרומפט לאחר השמירה.
  /// מחזיר הפרומפט שנוצר, או null בשגיאה.
  Future<SystemPrompt?> savePrompt({
    required String feature,
    required String content,
    required String version,
    bool setActive = false,
  }) async {
    if (feature.isEmpty || content.isEmpty || version.isEmpty) return null;
    try {
      final uri = Uri.parse('$_baseUrl$_promptsPath');
      final headers = await _getHeaders(existing: {'Content-Type': 'application/json'});
      final body = jsonEncode({
        'feature': feature,
        'content': content,
        'version': version,
        'setActive': setActive,
      });
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        appLog('PromptAdmin: savePrompt failed ${response.statusCode}');
        return null;
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      if (map == null || map['success'] != true) return null;
      final data = map['data'];
      if (data is! Map<String, dynamic>) return null;

      return SystemPrompt.fromJson(data);
    } catch (e) {
      appLog('PromptAdmin: savePrompt error - $e');
      return null;
    }
  }

  /// מפעיל פרומפט לפי feature+version.
  Future<bool> setPromptActiveByFeatureVersion(String feature, String version) async {
    try {
      final uri = Uri.parse('$_baseUrl$_promptsPath/set-active?feature=${Uri.encodeComponent(feature)}&version=${Uri.encodeComponent(version)}');
      final headers = await _getHeaders();
      final response = await http.patch(uri, headers: headers).timeout(_timeout);

      if (response.statusCode != 200) {
        appLog('PromptAdmin: setPromptActiveByFeatureVersion failed ${response.statusCode}');
        return false;
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      return map != null && map['success'] == true;
    } catch (e) {
      appLog('PromptAdmin: setPromptActiveByFeatureVersion error - $e');
      return false;
    }
  }

  /// מפעיל פרומפט — משנה IsActive ל־true ומבטל את השאר באותו feature.
  /// מחזיר true בהצלחה.
  Future<bool> setPromptActive(int promptId) async {
    try {
      final uri = Uri.parse('$_baseUrl$_promptsPath/$promptId/active');
      final headers = await _getHeaders();
      final response = await http
          .patch(uri, headers: headers)
          .timeout(_timeout);

      if (response.statusCode != 200) {
        appLog('PromptAdmin: setPromptActive failed ${response.statusCode}');
        return false;
      }

      final map = jsonDecode(response.body) as Map<String, dynamic>?;
      return map != null && map['success'] == true;
    } catch (e) {
      appLog('PromptAdmin: setPromptActive error - $e');
      return false;
    }
  }
}
