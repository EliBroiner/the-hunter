import 'package:flutter/material.dart';

/// בסיס כתובת הבקאנד — AI Lab (חשוף ל־UI לצורכי Deep Network Tracing)
const String kAiLabBackendBase = 'https://the-hunter-105628026575.me-west1.run.app';

/// כתובת הבסיס הנוכחית — לתצוגה ובדיקת חיבור אמיתי
String get currentBaseUrl => kAiLabBackendBase;

/// צבע לפי hash — לתצוגת קטגוריות ו־stages
Color categoryColor(int hash) {
  const colors = [
    Colors.blueAccent,
    Colors.amberAccent,
    Colors.greenAccent,
    Colors.purpleAccent,
    Colors.cyanAccent,
    Colors.orangeAccent,
  ];
  return colors[hash.abs() % colors.length];
}

/// צבעי outline ל־stages (Pipeline + OCR Lab)
const List<Color> kStageColors = [
  Colors.blueAccent,
  Colors.amberAccent,
  Colors.greenAccent,
  Colors.purpleAccent,
];
