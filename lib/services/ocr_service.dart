import 'dart:io';
import 'package:tesseract_ocr/tesseract_ocr.dart';
import 'package:tesseract_ocr/ocr_engine_config.dart';
import 'log_service.dart';

/// שירות OCR - חילוץ טקסט מתמונות באמצעות Tesseract (eng+heb)
/// תומך בעברית ובאנגלית; ML Kit אינו תומך בסקריפט עברי.
class OCRService {
  static OCRService? _instance;

  /// גודל קובץ מקסימלי לעיבוד ישיר (5MB)
  static const int _maxFileSizeBytes = 5 * 1024 * 1024;

  /// רזולוציה מקסימלית מומלצת
  static const int _maxImageDimension = 2048;

  OCRService._();

  static OCRService get instance {
    _instance ??= OCRService._();
    return _instance!;
  }

  /// מחלץ טקסט מתמונה (Tesseract eng+heb)
  /// מחזיר מחרוזת ריקה אם החילוץ נכשל או אם אין טקסט
  Future<String> extractText(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';

      final validationResult = await _validateImage(file);
      if (!validationResult.isValid) return '';

      final config = OCRConfig(
        language: 'eng+heb',
        engine: OCREngine.tesseract,
      );
      final raw = await TesseractOcr.extractText(filePath, config: config);
      return _cleanupText(raw);
    } catch (e) {
      appLog('OCRService: extractText error "$filePath" — $e');
      return '';
    }
  }

  Future<_ImageValidationResult> _validateImage(File file) async {
    try {
      final stat = await file.stat();
      if (stat.size == 0) {
        return _ImageValidationResult(isValid: false, needsResize: false);
      }
      final needsResize = stat.size > _maxFileSizeBytes;
      return _ImageValidationResult(isValid: true, needsResize: needsResize);
    } catch (_) {
      return _ImageValidationResult(isValid: false, needsResize: false);
    }
  }

  static const int _maxTextLength = 3000;

  String _cleanupText(String text) {
    if (text.isEmpty) return '';

    var cleaned = text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .join('\n')
        .trim();

    if (cleaned.length > _maxTextLength) {
      cleaned = cleaned.substring(0, _maxTextLength);
    }
    return cleaned;
  }

  static bool isSupportedImage(String extension) {
    const supported = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp'];
    return supported.contains(extension.toLowerCase());
  }

  static int get maxRecommendedFileSize => _maxFileSizeBytes;
  static int get maxRecommendedDimension => _maxImageDimension;
}

class _ImageValidationResult {
  final bool isValid;
  final bool needsResize;

  _ImageValidationResult({required this.isValid, required this.needsResize});
}
