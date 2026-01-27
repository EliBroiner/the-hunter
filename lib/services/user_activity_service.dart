import 'dart:async';
import 'package:flutter/foundation.dart';

/// שירות למעקב אחר פעילות משתמש
/// מטרתו לזהות מתי המשתמש "פעיל" ומתי הוא "במנוחה" (Idle)
/// כדי לאפשר ביצוע משימות כבדות (כמו OCR) רק בזמן מנוחה
class UserActivityService {
  static UserActivityService? _instance;
  
  UserActivityService._();
  
  static UserActivityService get instance {
    _instance ??= UserActivityService._();
    return _instance!;
  }

  // האם המשתמש פעיל כרגע?
  final ValueNotifier<bool> isUserActive = ValueNotifier<bool>(false);
  
  Timer? _idleTimer;
  
  // זמן המתנה עד שהמשתמש נחשב "במנוחה"
  static const Duration _idleThreshold = Duration(seconds: 2);

  /// נקרא בכל פעם שיש אינטראקציה (מגע) עם המסך
  void onUserInteraction() {
    // אם היינו במנוחה, עכשיו אנחנו פעילים
    if (!isUserActive.value) {
      isUserActive.value = true;
    }
    
    // איפוס הטיימר
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleThreshold, _setIdle);
  }
  
  /// מסמן שהמשתמש במנוחה
  void _setIdle() {
    isUserActive.value = false;
  }
  
  /// ממתין עד שהמשתמש יהיה במנוחה
  Future<void> waitForIdle() async {
    if (!isUserActive.value) return;
    
    // יצירת completer שממתין לשינוי ב-ValueNotifier
    final completer = Completer<void>();
    
    void listener() {
      if (!isUserActive.value) {
        isUserActive.removeListener(listener);
        if (!completer.isCompleted) completer.complete();
      }
    }
    
    isUserActive.addListener(listener);
    return completer.future;
  }
}
