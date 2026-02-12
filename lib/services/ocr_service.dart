import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:image/image.dart' as img;

import '../utils/extracted_text_quality.dart';
import 'log_service.dart';

/// קבלת הודעת preprocess — (path, applyBinaryThreshold)
typedef PreprocessInput = (String, bool);

/// נקודת כניסה ל־Isolate — עיבוד תמונה סינכרוני (גווני אפור, threshold). חוסך מעבד מה-main thread.
String _preprocessImageInIsolate(PreprocessInput input) {
  final (imagePath, applyBinaryThreshold) = input;
  try {
    final bytes = File(imagePath).readAsBytesSync();
    img.Image? image = img.decodeImage(bytes);
    if (image == null) return imagePath;

    image = img.grayscale(image);
    image = img.contrast(image, contrast: 130);

    if (applyBinaryThreshold) {
      const threshold = 128;
      for (var y = 0; y < image.height; y++) {
        for (var x = 0; x < image.width; x++) {
          final p = image.getPixel(x, y);
          final l = (p.r.toInt() + p.g.toInt() + p.b.toInt()) ~/ 3;
          final v = l > threshold ? 255.0 : 0.0;
          image.setPixel(x, y, image.getColor(v, v, v));
        }
      }
    }

    final outBytes = img.encodePng(image);
    final suffix = applyBinaryThreshold ? 'full' : 'light';
    final tempFile = File(
      '${Directory.systemTemp.path}/ocr_${suffix}_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    tempFile.writeAsBytesSync(outBytes);
    return tempFile.path;
  } catch (_) {
    return imagePath;
  }
}

/// נקודת כניסה ל־Isolate — דחיסת תמונה B&W לעלייה. סינכרוני.
({List<int> bytes, String mimeType}) _compressBwImageInIsolate(String imagePath) {
  const maxEdge = 1920;
  const jpegQuality = 70;
  try {
    final fileBytes = File(imagePath).readAsBytesSync();
    img.Image? image = img.decodeImage(fileBytes);
    if (image == null) return (bytes: <int>[], mimeType: 'image/jpeg');

    image = img.grayscale(image);
    image = img.contrast(image, contrast: 130);
    const threshold = 128;
    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        final p = image.getPixel(x, y);
        final l = (p.r.toInt() + p.g.toInt() + p.b.toInt()) ~/ 3;
        final v = l > threshold ? 255.0 : 0.0;
        image.setPixel(x, y, image.getColor(v, v, v));
      }
    }

    final maxDim = image.width > image.height ? image.width : image.height;
    if (maxDim > maxEdge) {
      final scale = maxEdge / maxDim;
      image = img.copyResize(
        image,
        width: (image.width * scale).round(),
        height: (image.height * scale).round(),
      );
    }

    final jpegBytes = img.encodeJpg(image, quality: jpegQuality);
    return (bytes: List<int>.from(jpegBytes), mimeType: 'image/jpeg');
  } catch (_) {
    return (bytes: <int>[], mimeType: 'image/jpeg');
  }
}

/// תוצאת OCR — טקסט + סטטוס (אין טקסט מזוהה / ביטחון נמוך / תקין)
enum OcrStatus {
  /// ML Kit מחזיר 0 elements — לא לשלוח ל-Backend
  noTextDetected,
  /// טקסט קיים אך לא משמעותי (isTextMeaningful=false) — להעלות ל-Backend
  lowConfidence,
  /// טקסט משמעותי — להשתמש כתוצאה סופית
  ok,
}

/// תוצאת OCR מלאה — לשימוש ב-FileScanner/Processing
class OcrResult {
  final String text;
  final OcrStatus status;
  final int elementCount;

  const OcrResult({
    required this.text,
    required this.status,
    required this.elementCount,
  });

  bool get isNoText => status == OcrStatus.noTextDetected;
  bool get needsBackendFallback => status == OcrStatus.lowConfidence;
}

/// סף אורך מינימלי — מתחתיו מסומן No Text Detected (לא להעלות ל-Backend)
const int _minTextLengthForUpload = 5;

/// שירות OCR - חילוץ טקסט מתמונות באמצעות ML Kit (לטינית; עברית נתמכת דרך recognizer ברירת מחדל)
/// לפני OCR — עיבוד מקדים: גווני אפור, חיזוק ניגודיות, threshold לשחור-לבן (מנקה צללים ורעש)
/// אם התוצאה לא משמעותית (isTextMeaningful) — ניסיון שני עם עיבוד קל (ללא threshold)
/// לוגיקה: blocks ריקים / 0 elements / אורך < 5 → noTextDetected (לא להעלות);
/// ג'יבריש > 30% → lowConfidence (העלאת תמונה B&W ל-Backend)
class OCRService {
  static OCRService? _instance;

  /// ML Kit – Latin recognizer מטפל גם בעברית ב־V2
  final _textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

  OCRService._();

  static OCRService get instance {
    _instance ??= OCRService._();
    return _instance!;
  }

  /// מחלץ טקסט מתמונה עם בדיקת איכות ו־element count.
  /// 0 elements → noTextDetected (לא לשלוח ל-Backend).
  /// טקסט לא משמעותי → lowConfidence (להעלות תמונה ל-Backend).
  Future<OcrResult> extractTextWithStatus(String imagePath) async {
    try {
      final file = File(imagePath);
      if (!await file.exists()) return const OcrResult(text: '', status: OcrStatus.noTextDetected, elementCount: 0);

      // עיבוד B&W ראשון — אחריו בודקים element count
      final first = await _extractWithPreprocessingAndStatus(imagePath, useBinaryThreshold: true);

      // לוגיקה 1: blocks ריקים או 0 elements — אין טקסט מזוהה, לא לשלוח ל-Backend
      if (first.elementCount == 0) {
        appLog('OCRService: ML Kit found 0 text elements — marking no_text_detected');
        return OcrResult(text: '', status: OcrStatus.noTextDetected, elementCount: 0);
      }

      // לוגיקה 2: אורך טקסט < 5 — לא להעלות ל-Backend (חוסך עלות)
      if (first.text.trim().length < _minTextLengthForUpload) {
        appLog('OCRService: text length ${first.text.length} < $_minTextLengthForUpload — marking no_text_detected');
        return OcrResult(text: first.text, status: OcrStatus.noTextDetected, elementCount: first.elementCount);
      }

      if (isTextMeaningful(first.text)) {
        return first;
      }

      // טקסט קיים אך לא משמעותי — ניסיון שני עם עיבוד קל
      if (first.text.isNotEmpty) {
        appLog('OCRService: first result not meaningful, retrying with light preprocessing');
        final second = await _extractWithPreprocessingAndStatus(imagePath, useBinaryThreshold: false);
        final better = _pickBetterResult(first, second);
        if (isTextMeaningful(better.text)) return better;
        // שניהם לא משמעותיים — מחזירים את הטוב יותר עם lowConfidence
        return OcrResult(
          text: better.text,
          status: OcrStatus.lowConfidence,
          elementCount: better.elementCount,
        );
      }

      return first;
    } catch (e) {
      appLog('OCRService: extractTextWithStatus error "$imagePath" — $e');
      return const OcrResult(text: '', status: OcrStatus.noTextDetected, elementCount: 0);
    }
  }

  /// מחלץ טקסט מתמונה. API ישן — מחזיר מחרוזת בלבד. משתמש ב-extractTextWithStatus.
  Future<String> extractText(String imagePath) async {
    final result = await extractTextWithStatus(imagePath);
    return result.text;
  }

  /// בוחר את התוצאה הטובה יותר — משמעותית עדיפה, אחרת הארוכה יותר
  OcrResult _pickBetterResult(OcrResult a, OcrResult b) {
    final aOk = isTextMeaningful(a.text);
    final bOk = isTextMeaningful(b.text);
    if (bOk && !aOk) return b;
    if (aOk && !bOk) return a;
    return a.text.length >= b.text.length ? a : b;
  }

  /// סופר את כל ה־TextElement ב־RecognizedText (blocks → lines → elements)
  static int _countElements(RecognizedText rt) {
    var count = 0;
    for (final block in rt.blocks) {
      for (final line in block.lines) {
        count += line.elements.length;
      }
    }
    return count;
  }

  Future<OcrResult> _extractWithPreprocessingAndStatus(String imagePath, {required bool useBinaryThreshold}) async {
    final pathForOcr = useBinaryThreshold
        ? await _preprocessForOcr(imagePath)
        : await _preprocessForOcrLight(imagePath);
    try {
      final inputImage = InputImage.fromFilePath(pathForOcr);
      final recognizedText = await _textRecognizer.processImage(inputImage);
      final elementCount = _countElements(recognizedText);
      final text = recognizedText.text.isEmpty ? '' : _cleanupText(recognizedText.text);
      return OcrResult(
        text: text,
        status: OcrStatus.ok,
        elementCount: elementCount,
      );
    } finally {
      if (pathForOcr != imagePath) {
        try {
          await File(pathForOcr).delete();
        } catch (_) {}
      }
    }
  }

  /// עיבוד מלא: גווני אפור, ניגודיות, threshold לשחור-לבן.
  Future<String> _preprocessForOcr(String imagePath) async {
    return _preprocessImage(imagePath, applyBinaryThreshold: true);
  }

  /// עיבוד קל: גווני אפור וניגודיות בלבד — Higher Quality Scan כשהמלא מחזיר ג'יבריש.
  Future<String> _preprocessForOcrLight(String imagePath) async {
    return _preprocessImage(imagePath, applyBinaryThreshold: false);
  }

  /// עיבוד מקדים לתמונה ל-OCR — רץ ב-isolate נפרד כדי לא לחנוק את המעבד.
  Future<String> _preprocessImage(String imagePath, {required bool applyBinaryThreshold}) async {
    try {
      return await compute(_preprocessImageInIsolate, (imagePath, applyBinaryThreshold));
    } catch (e) {
      appLog('OCRService: preprocess failed, using original — $e');
      return imagePath;
    }
  }

  /// תמונה מעובדת B&W מקומפוסת — לעלייה ל-Backend (Cloud Vision לא צריך high-res צבע).
  /// מחזיר (bytes, mimeType). רץ ב-isolate נפרד כדי לא לחנוק את המעבד.
  Future<({List<int> bytes, String mimeType})> getCompressedBwImageForUpload(String imagePath) async {
    try {
      return await compute(_compressBwImageInIsolate, imagePath);
    } catch (e) {
      appLog('OCRService: getCompressedBwImageForUpload failed — $e');
      return (bytes: <int>[], mimeType: 'image/jpeg');
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
