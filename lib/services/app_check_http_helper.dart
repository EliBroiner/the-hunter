import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';
import 'log_service.dart';

/// עוטף קריאות HTTP לבקאנד — מוסיף כותרת X-Firebase-AppCheck
/// Cooldown 5 דקות אחרי כישלון — מניעת "Too many attempts"
class AppCheckHttpHelper {
  static const String _headerName = 'X-Firebase-AppCheck';
  static const Duration _cooldownAfterFailure = Duration(minutes: 5);
  static DateTime? _lastTokenFailure;

  /// מחזיר headers עם טוקן App Check. אם getToken נכשל — cooldown 5 דקות לפני ניסיון חוזר
  static Future<Map<String, String>> getBackendHeaders({
    Map<String, String>? existing,
  }) async {
    final headers = Map<String, String>.from(existing ?? {});

    if (_lastTokenFailure != null &&
        DateTime.now().difference(_lastTokenFailure!) < _cooldownAfterFailure) {
      return headers;
    }

    try {
      final token = await FirebaseAppCheck.instance.getToken();
      if (token != null && token.isNotEmpty) {
        headers[_headerName] = token;
        if (kDebugMode) {
          debugPrint('AppCheck: X-Firebase-AppCheck header attached (JWT len=${token.length})');
        }
      } else {
        if (kDebugMode) {
          debugPrint('AppCheck: NO TOKEN — X-Firebase-AppCheck not sent, 401 likely');
        }
      }
    } catch (e) {
      _lastTokenFailure = DateTime.now();
      appLog('AppCheck: getToken failed - $e (cooldown $_cooldownAfterFailure before retry)');
      if (kDebugMode) debugPrint('AppCheck getToken error: $e');
    }
    return headers;
  }
}
