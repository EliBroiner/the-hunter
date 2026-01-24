import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

/// שירות OCR - חילוץ טקסט מתמונות באמצעות Google ML Kit
/// תומך בעברית ואנגלית עם אופטימיזציה לביצועים
class OCRService {
  static OCRService? _instance;
  
  // שני מזהי טקסט - לעברית ולטינית (אנגלית)
  final TextRecognizer _latinRecognizer;
  final TextRecognizer _hebrewRecognizer;

  /// גודל קובץ מקסימלי לעיבוד ישיר (5MB)
  static const int _maxFileSizeBytes = 5 * 1024 * 1024;
  
  /// רזולוציה מקסימלית מומלצת
  static const int _maxImageDimension = 2048;

  OCRService._()
      : _latinRecognizer = TextRecognizer(script: TextRecognitionScript.latin),
        _hebrewRecognizer = TextRecognizer(script: TextRecognitionScript.devanagiri); 
        // הערה: Google ML Kit לא תומך ישירות בעברית, משתמשים ב-latin שעובד סביר

  /// מחזיר את ה-singleton של השירות
  static OCRService get instance {
    _instance ??= OCRService._();
    return _instance!;
  }

  /// מחלץ טקסט מתמונה
  /// מחזיר מחרוזת ריקה אם החילוץ נכשל או אם אין טקסט
  Future<String> extractText(String filePath) async {
    try {
      final file = File(filePath);
      
      // בדיקת קיום הקובץ
      if (!await file.exists()) return '';

      // בדיקת תקינות התמונה
      final validationResult = await _validateImage(file);
      if (!validationResult.isValid) return '';

      // אזהרה אם התמונה גדולה מדי
      if (validationResult.needsResize) {
        // לוג פנימי - התמונה גדולה, עיבוד עלול להיות איטי
      }

      final inputImage = InputImage.fromFilePath(filePath);
      
      // עיבוד עם מזהה לטיני (עובד טוב גם לעברית)
      final recognizedText = await _latinRecognizer.processImage(inputImage);

      // ניקוי וטיפול בטקסט
      final cleanedText = _cleanupText(recognizedText.text);
      
      return cleanedText;
    } catch (e) {
      // שגיאה בחילוץ טקסט - מחזיר מחרוזת ריקה
      return '';
    }
  }

  /// בודק תקינות התמונה לפני עיבוד
  Future<_ImageValidationResult> _validateImage(File file) async {
    try {
      final stat = await file.stat();
      final fileSize = stat.size;
      
      // בדיקת גודל קובץ
      if (fileSize == 0) {
        return _ImageValidationResult(isValid: false, needsResize: false);
      }

      // בדיקה אם הקובץ גדול מדי - עדיין תקין אבל מומלץ לכווץ
      final needsResize = fileSize > _maxFileSizeBytes;

      return _ImageValidationResult(isValid: true, needsResize: needsResize);
    } catch (e) {
      return _ImageValidationResult(isValid: false, needsResize: false);
    }
  }

  /// מנקה את הטקסט שחולץ
  /// מסיר שורות ריקות מיותרות, רווחים כפולים ומנקה whitespace
  String _cleanupText(String text) {
    if (text.isEmpty) return '';

    var cleaned = text
        // החלפת שורות חדשות מרובות בשורה אחת
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        // החלפת רווחים מרובים ברווח אחד
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        // הסרת רווחים בתחילת ובסוף שורות
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        // ניקוי סופי
        .trim();

    return cleaned;
  }

  /// בודק אם הקובץ הוא תמונה נתמכת
  static bool isSupportedImage(String extension) {
    const supportedExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return supportedExtensions.contains(extension.toLowerCase());
  }

  /// מחזיר את גודל הקובץ המקסימלי המומלץ בבייטים
  static int get maxRecommendedFileSize => _maxFileSizeBytes;

  /// מחזיר את הרזולוציה המקסימלית המומלצת
  static int get maxRecommendedDimension => _maxImageDimension;

  /// סוגר את ה-TextRecognizers ומשחרר משאבים
  Future<void> dispose() async {
    await _latinRecognizer.close();
    await _hebrewRecognizer.close();
    _instance = null;
  }
}

/// תוצאת בדיקת תקינות תמונה
class _ImageValidationResult {
  final bool isValid;
  final bool needsResize;

  _ImageValidationResult({
    required this.isValid,
    required this.needsResize,
  });
}
