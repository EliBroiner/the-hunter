import 'dart:convert';
import 'package:http/http.dart' as http;
import 'app_check_http_helper.dart';
import 'auth_service.dart';
import 'log_service.dart';

/// בודק הרשאות משתמש מול הבקאנד — Admin, DebugAccess, User
class UserRolesService {
  static UserRolesService? _instance;
  static UserRolesService get instance {
    _instance ??= UserRolesService._();
    return _instance!;
  }

  UserRolesService._();

  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app';
  static const Duration _cacheDuration = Duration(minutes: 5);

  String? _cachedRole;
  bool? _cachedResult;
  DateTime? _cacheTime;

  /// בודק אם למשתמש יש את התפקיד — עם cache ל־5 דקות
  Future<bool> hasRole(String role) async {
    final user = AuthService.instance.currentUser;
    if (user == null) return false;

    if (_cachedRole == role &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedResult ?? false;
    }

    try {
      final params = <String, String>{
        'userId': user.uid,
        'role': role,
      };
      if (user.email != null && user.email!.isNotEmpty) {
        params['email'] = user.email!;
      }
      final uri = Uri.parse('$_baseUrl/api/users/check-role').replace(queryParameters: params);
      final headers = await AppCheckHttpHelper.getBackendHeaders();

      final response = await http.get(uri, headers: headers).timeout(
        const Duration(seconds: 10),
      );

      if (response.statusCode == 200) {
        final data = _parseCheckRoleResponse(response.body);
        _cachedRole = role;
        _cachedResult = data;
        _cacheTime = DateTime.now();
        return data;
      }
      return false;
    } catch (e) {
      appLog('UserRolesService: hasRole failed - $e');
      return false;
    }
  }

  bool _parseCheckRoleResponse(String body) {
    try {
      final map = jsonDecode(body) as Map<String, dynamic>;
      return map['hasRole'] == true;
    } catch (_) {
      return false;
    }
  }

  /// מנקה cache — למשל אחרי התחברות/התנתקות
  void clearCache() {
    _cachedRole = null;
    _cachedResult = null;
    _cacheTime = null;
  }
}
