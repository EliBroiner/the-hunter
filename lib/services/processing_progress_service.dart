import 'package:flutter/foundation.dart';

/// שירות מעקב אחר התקדמות עיבוד מסמכים — להצגת ProcessingBanner ו-spinner שקט.
class ProcessingProgressService {
  static ProcessingProgressService? _instance;
  static ProcessingProgressService get instance {
    _instance ??= ProcessingProgressService._();
    return _instance!;
  }

  ProcessingProgressService._();

  final ValueNotifier<bool> isProcessing = ValueNotifier(false);
  final ValueNotifier<int> current = ValueNotifier(0);
  final ValueNotifier<int> total = ValueNotifier(0);
  final ValueNotifier<bool> isDismissed = ValueNotifier(false);

  void start(int totalCount) {
    isProcessing.value = true;
    current.value = 0;
    total.value = totalCount;
    // לא מאפסים isDismissed — אם המשתמש סגר (X), הבאנר נשאר מוסתר
  }

  void update(int cur, int tot) {
    current.value = cur;
    total.value = tot;
  }

  void finish() {
    isProcessing.value = false;
  }

  void dismiss() {
    isDismissed.value = true;
  }

  void restore() {
    isDismissed.value = false;
  }

  bool get showBanner => isProcessing.value && !isDismissed.value;
  bool get showSilentSpinner => isProcessing.value && isDismissed.value;
}
