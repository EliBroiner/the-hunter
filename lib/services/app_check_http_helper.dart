import 'package:firebase_app_check/firebase_app_check.dart';
import 'log_service.dart';

/// עוטף קריאות HTTP לבקאנד — מוסיף כותרת X-Firebase-AppCheck
/// זרימת טוקן: getToken() מביא attestation מהמכשיר → Firebase מחזיר JWT → הבקאנד מאמת
class AppCheckHttpHelper {
  static const String _headerName = 'X-Firebase-AppCheck';

  /// מחזיר headers עם טוקן App Check לשימוש בבקשות לבקאנד
  /// [existing] — headers קיימים (Content-Type וכו') — ימוזגו עם הכותרת
  /// אם getToken() נכשל (למשל debug/emulator) — מחזיר רק את existing בלי להכשיל
  static Future<Map<String, String>> getBackendHeaders({
    Map<String, String>? existing,
  }) async {
    final headers = Map<String, String>.from(existing ?? {});
    try {
      final token = await FirebaseAppCheck.instance.getToken();
      if (token != null && token.isNotEmpty) {
        headers[_headerName] = token;
      }
    } catch (e) {
      appLog('AppCheck: getToken failed - $e (request will proceed without token)');
    }
    return headers;
  }
}
