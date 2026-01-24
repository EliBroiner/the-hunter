import 'dart:io';
import 'package:permission_handler/permission_handler.dart';

/// שירות הרשאות - מנהל בקשות הרשאות לאחסון
class PermissionService {
  static PermissionService? _instance;

  PermissionService._();

  /// מחזיר את ה-singleton של השירות
  static PermissionService get instance {
    _instance ??= PermissionService._();
    return _instance!;
  }

  /// בודק אם יש הרשאת אחסון
  Future<bool> hasStoragePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return true;

    // Android 13+ משתמש בהרשאות מדיה ספציפיות
    if (Platform.isAndroid) {
      // נבדוק קודם MANAGE_EXTERNAL_STORAGE עבור גישה מלאה
      final manageStatus = await Permission.manageExternalStorage.status;
      if (manageStatus.isGranted) return true;

      // אחרת נבדוק הרשאת אחסון רגילה
      final storageStatus = await Permission.storage.status;
      return storageStatus.isGranted;
    }

    // iOS
    final status = await Permission.storage.status;
    return status.isGranted;
  }

  /// מבקש הרשאת אחסון מהמשתמש
  Future<PermissionResult> requestStoragePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return PermissionResult.granted;
    }

    // ב-Android ננסה קודם MANAGE_EXTERNAL_STORAGE לגישה מלאה לתיקיית Downloads
    if (Platform.isAndroid) {
      // נבדוק אם כבר יש הרשאה
      var status = await Permission.manageExternalStorage.status;
      
      if (status.isGranted) return PermissionResult.granted;

      // נבקש הרשאה
      status = await Permission.manageExternalStorage.request();
      
      if (status.isGranted) return PermissionResult.granted;
      if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
      
      // אם נדחה, ננסה הרשאת אחסון רגילה כגיבוי
      status = await Permission.storage.request();
      
      if (status.isGranted) return PermissionResult.granted;
      if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
      return PermissionResult.denied;
    }

    // iOS
    final status = await Permission.storage.request();
    
    if (status.isGranted) return PermissionResult.granted;
    if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
    return PermissionResult.denied;
  }

  /// פותח את הגדרות האפליקציה
  Future<bool> openSettings() async {
    return await openAppSettings();
  }

  /// בודק אם יש הרשאת מיקרופון
  Future<bool> hasMicrophonePermission() async {
    final status = await Permission.microphone.status;
    return status.isGranted;
  }

  /// מבקש הרשאת מיקרופון מהמשתמש (מחזיר PermissionResult מפורט)
  Future<PermissionResult> requestMicrophonePermission() async {
    var status = await Permission.microphone.status;
    
    if (status.isGranted) return PermissionResult.granted;

    status = await Permission.microphone.request();
    
    if (status.isGranted) return PermissionResult.granted;
    if (status.isPermanentlyDenied) return PermissionResult.permanentlyDenied;
    return PermissionResult.denied;
  }

  /// מבקש הרשאת מיקרופון ומחזיר true אם ניתנה, false אחרת
  Future<bool> requestMicPermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return true;

    status = await Permission.microphone.request();
    return status.isGranted;
  }
}

/// תוצאת בקשת הרשאה
enum PermissionResult {
  granted,           // הרשאה ניתנה
  denied,            // הרשאה נדחתה (אפשר לבקש שוב)
  permanentlyDenied, // הרשאה נדחתה לצמיתות (צריך להיכנס להגדרות)
}
