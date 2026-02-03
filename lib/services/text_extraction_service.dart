import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:pdfx/pdfx.dart' as pdfx;
import '../utils/extracted_text_quality.dart';
import 'log_service.dart';
import 'ocr_service.dart';

import 'dart:isolate';

/// שירות חילוץ טקסט מקבצי טקסט ו-PDF
/// PDF: קודם חילוץ raw; אם התוצאה ג'יבריש (עברית מקולקלת) — רינדור דף ראשון + OCR
class TextExtractionService {
  static final TextExtractionService _instance = TextExtractionService._();
  static TextExtractionService get instance => _instance;
  TextExtractionService._();

  /// חילוץ טקסט מקובץ לפי הסיומת
  Future<String> extractText(String filePath) async {
    try {
      String result = await Isolate.run(() => _extractTextInIsolate(filePath));
      final ext = filePath.split('.').last.toLowerCase();
      // PDF: אם החילוץ הישיר מחזיר ג'יבריש — חילוץ ויזואלי (דף ראשון → OCR)
      if (ext == 'pdf' && result.isNotEmpty && !isExtractedTextAcceptableForAi(result)) {
        final ocrText = await _extractPdfViaOcr(filePath);
        if (ocrText.isNotEmpty) result = ocrText;
      }
      final maxLen = ext == 'pdf' ? maxTextLengthForPdf : maxTextLengthForTextFiles;
      return _limitText(result, maxLen);
    } catch (e) {
      appLog('TEXT_EXTRACT ISOLATE ERROR: $e');
      return '';
    }
  }

  /// רינדור דף ראשון של PDF לתמונה והרצת ML Kit OCR (למסמכי עברית)
  Future<String> _extractPdfViaOcr(String filePath) async {
    pdfx.PdfDocument? document;
    try {
      document = await pdfx.PdfDocument.openFile(filePath);
      if (document.pagesCount < 1) return '';
      final page = await document.getPage(1);
      // רזולוציה גבוהה ל־OCR (כ־2x לדף A4)
      final w = (page.width * 2).clamp(800.0, 2400.0);
      final h = (page.height * 2).clamp(800.0, 2400.0);
      final image = await page.render(width: w, height: h, format: pdfx.PdfPageImageFormat.png);
      await page.close();
      if (image == null || image.bytes.isEmpty) return '';
      final tempDir = Directory.systemTemp;
      final tempFile = File('${tempDir.path}/pdf_ocr_${DateTime.now().millisecondsSinceEpoch}.png');
      await tempFile.writeAsBytes(image.bytes);
      try {
        final text = await OCRService.instance.extractText(tempFile.path);
        return text;
      } finally {
        try { await tempFile.delete(); } catch (_) {}
      }
    } catch (e) {
      appLog('TEXT_EXTRACT PDF OCR fallback error: $e');
      return '';
    } finally {
      await document?.close();
    }
  }

  /// פונקציה סטטית שרצה בתוך ה-Isolate (PDF מחזיר טקסט גולמי — הגבלה וגיבוי OCR במארח)
  static Future<String> _extractTextInIsolate(String filePath) async {
    final extension = filePath.split('.').last.toLowerCase();
    try {
      switch (extension) {
        case 'txt':
        case 'text':
        case 'log':
        case 'md':
        case 'json':
        case 'xml':
        case 'csv':
          final text = await _extractFromTextFile(filePath);
          return _limitText(text, maxTextLengthForTextFiles);
        case 'pdf':
          final text = await _extractFromPdf(filePath);
          return text; // ללא הגבלה כאן — extractText עושה OCR fallback ואז _limitText
        default:
          return '';
      }
    } catch (e) {
      print('TEXT_EXTRACT ERROR IN ISOLATE: $e');
      return '';
    }
  }

  /// חילוץ טקסט מקובץ טקסט פשוט (סטטי לשימוש ב-Isolate)
  static Future<String> _extractFromTextFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      
      // בדיקת גודל - לא קוראים קבצים גדולים מדי
      final stat = await file.stat();
      if (stat.size > 5 * 1024 * 1024) { // מקסימום 5MB
        return '';
      }
      
      final content = await file.readAsString();
      return _cleanupText(content);
    } catch (e) {
      // יתכן שהקובץ לא בקידוד UTF-8
      try {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final content = String.fromCharCodes(bytes);
        return _cleanupText(content);
      } catch (e2) {
        return '';
      }
    }
  }

  /// חילוץ טקסט מקובץ PDF (סטטי לשימוש ב-Isolate)
  static Future<String> _extractFromPdf(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      
      // בדיקת גודל - לא קוראים קבצים גדולים מדי
      final stat = await file.stat();
      if (stat.size > 20 * 1024 * 1024) { // מקסימום 20MB
        return '';
      }
      
      final bytes = await file.readAsBytes();
      final document = PdfDocument(inputBytes: bytes);
      
      // חילוץ טקסט מכל הדפים
      final textExtractor = PdfTextExtractor(document);
      final text = textExtractor.extractText();
      
      document.dispose();
      
      return _cleanupText(text);
    } catch (e) {
      print('TEXT_EXTRACT PDF ERROR: $e');
      return '';
    }
  }

  /// מקסימום תווים לשמירה
  static const int maxTextLengthForTextFiles = 15000; // 15K לקבצי טקסט
  static const int maxTextLengthForPdf = 5000; // 5K ל-PDF
  
  /// ניקוי טקסט - הסרת תווים מיותרים (סטטי)
  static String _cleanupText(String text) {
    if (text.isEmpty) return '';
    
    // הסרת שורות ריקות מרובות
    var cleaned = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    // הסרת רווחים מיותרים
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    
    // הסרת תווי בקרה
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    
    return cleaned.trim();
  }
  
  /// קיצור חכם - שומרים התחלה + סוף (סטטי)
  static String _limitText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    
    // 70% מההתחלה (כותרות, תוכן עניינים)
    // 30% מהסוף (סיכומים, חתימות)
    final startLength = (maxLength * 0.7).toInt();
    final endLength = maxLength - startLength - 10;
    
    final start = text.substring(0, startLength);
    final end = text.substring(text.length - endLength);
    
    return '$start\n...\n$end';
  }

  /// בדיקה אם הסיומת נתמכת לחילוץ טקסט
  static bool isTextExtractable(String extension) {
    const supportedExtensions = [
      'txt', 'text', 'log', 'md', 'json', 'xml', 'csv', 'pdf'
    ];
    return supportedExtensions.contains(extension.toLowerCase());
  }
}
