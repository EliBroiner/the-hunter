/// בדיקת איכות טקסט מחולץ — מונע שליחת ג'יבריש ל-AI
/// תווים "זבל": לא אלפאנומריים, לא עברית, לא רווח/פיסוק בסיסי
const int garbageThresholdPercent = 30;

/// בודק אם תו תקין: עברית (\u0590-\u05FF), לטינית/ספרות, רווחים, פיסוק בסיסי
bool _isValidChar(int codePoint) {
  if (codePoint <= 0x20 && (codePoint == 0x09 || codePoint == 0x0A || codePoint == 0x0D || codePoint == 0x20)) return true;
  if (codePoint >= 0x30 && codePoint <= 0x39) return true; // 0-9
  if (codePoint >= 0x41 && codePoint <= 0x5A) return true; // A-Z
  if (codePoint >= 0x61 && codePoint <= 0x7A) return true; // a-z
  if (codePoint >= 0x0590 && codePoint <= 0x05FF) return true; // עברית + ניקוד
  const punct = [0x2C, 0x2E, 0x3A, 0x3B, 0x21, 0x3F, 0x2D, 0x5F, 0x27, 0x22, 0x28, 0x29];
  if (punct.contains(codePoint)) return true;
  return false;
}

/// מחזיר יחס תווים "זבל" (0.0–1.0) — לשימוש ב־FileValidator עם qualityThreshold
double getGarbageRatio(String text) {
  if (text.isEmpty) return 1.0;
  final runes = text.runes.toList();
  if (runes.isEmpty) return 1.0;
  int garbage = 0;
  for (final r in runes) {
    if (!_isValidChar(r)) garbage++;
  }
  return garbage / runes.length;
}

/// מחזיר true אם היחס תווים זבל <= 30% (מותר לשלוח ל-AI)
bool isExtractedTextAcceptableForAi(String text) {
  if (text.isEmpty) return false;
  return getGarbageRatio(text) <= (garbageThresholdPercent / 100.0);
}
