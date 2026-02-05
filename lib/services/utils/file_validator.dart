import '../../configs/ranking_config.dart';
import '../../utils/extracted_text_quality.dart';

/// סטטוס ניתוח קובץ — לאחר ולידציה ו/או מילון ו/או AI
enum AnalysisStatus {
  /// טקסט קצר מדי או יחס ג'יבריש גבוה — לא ממשיכים למילון/AI
  unreadable,
  /// התאמה במילון המקומי — נשמרו תגיות, לא נדרש AI
  dictionaryMatched,
  /// עבר ולידציה, ממתין לשליחה ל-AI (או לא PRO)
  pendingAi,
  /// נותח ב-AI (שרת)
  completed,
}

/// ולידציית איכות טקסט לפני מילון/AI — אורך מינימלי ויחס ג'יבריש
class FileValidator {
  FileValidator._();

  static final FileValidator instance = FileValidator._();

  /// בודק אם הטקסט עובר את סף האיכות: אורך >= minTextLength ויחס ג'יבריש <= qualityThreshold.
  /// מחזיר unreadable אם לא עובר; אחרת pendingAi (מוכן לשלב מילון ואז AI).
  AnalysisStatus validateQuality(String text) {
    if (text.trim().length < minTextLength) return AnalysisStatus.unreadable;
    if (getGarbageRatio(text) > qualityThreshold) return AnalysisStatus.unreadable;
    return AnalysisStatus.pendingAi;
  }
}
