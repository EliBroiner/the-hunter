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
  /// מחזיר הפרומפט שנוצר, או null בשגיאה.
  Future<SystemPrompt?> savePrompt({
    required String feature,
    required String content,
    required String version,
  }) async {
    if (feature.isEmpty || content.isEmpty || version.isEmpty) return null;
    try {
      final uri = Uri.parse('$_baseUrl$_promptsPath');
      final headers = await _getHeaders(existing: {'Content-Type': 'application/json'});
      final body = jsonEncode({
        'feature': feature,
        'content': content,
        'version': version,
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
