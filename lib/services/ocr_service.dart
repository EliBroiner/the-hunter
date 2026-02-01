import 'dart:io';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'log_service.dart';

/// שירות OCR - חילוץ טקסט מתמונות באמצעות ML Kit (לטינית; עברית נתמכת דרך recognizer ברירת מחדל)
class OCRService {
  static OCRService? _instance;

  /// ML Kit – Latin recognizer מטפל גם בעברית ב־V2
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  OCRService._();

  static OCRService get instance {
    _instance ??= OCRService._();
    return _instance!;
  }

  /// מחלץ טקסט מתמונה
  Future<String> extractText(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return '';

      final inputImage = InputImage.fromFilePath(imagePath);
      final RecognizedText recognizedText =
          await _textRecognizer.processImage(inputImage);

      if (recognizedText.text.isEmpty) return '';

      return _cleanupText(recognizedText.text);
    } catch (e) {
      appLog('OCRService: extractText error "$imagePath" — $e');
      return '';
    }
  }

  static const int _maxTextLength = 3000;

  String _cleanupText(String text) {
    if (text.isEmpty) return '';

    final cleaned = text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();

    if (cleaned.length > _maxTextLength) {
      return cleaned.substring(0, _maxTextLength);
    }
    return cleaned;
  }

  static bool isSupportedImage(String extension) {
    const supported = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return supported.contains(extension.toLowerCase());
  }

  void dispose() {
    _textRecognizer.close();
  }
}
