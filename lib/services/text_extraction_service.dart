import 'dart:io';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'log_service.dart';

/// שירות חילוץ טקסט מקבצי טקסט ו-PDF
class TextExtractionService {
  static final TextExtractionService _instance = TextExtractionService._();
  static TextExtractionService get instance => _instance;
  TextExtractionService._();

  /// חילוץ טקסט מקובץ לפי הסיומת
  Future<String> extractText(String filePath) async {
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
          return await _extractFromTextFile(filePath);
        case 'pdf':
          return await _extractFromPdf(filePath);
        default:
          return '';
      }
    } catch (e) {
      appLog('TEXT_EXTRACT ERROR: $e');
      return '';
    }
  }

  /// חילוץ טקסט מקובץ טקסט פשוט
  Future<String> _extractFromTextFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      
      // בדיקת גודל - לא קוראים קבצים גדולים מדי
      final stat = await file.stat();
      if (stat.size > 5 * 1024 * 1024) { // מקסימום 5MB
        appLog('TEXT_EXTRACT: File too large: ${stat.size} bytes');
        return '';
      }
      
      final content = await file.readAsString();
      return _cleanupText(content);
    } catch (e) {
      // יתכן שהקובץ לא בקידוד UTF-8
      appLog('TEXT_EXTRACT: Failed to read as UTF-8, trying Latin1');
      try {
        final file = File(filePath);
        final bytes = await file.readAsBytes();
        final content = String.fromCharCodes(bytes);
        return _cleanupText(content);
      } catch (e2) {
        appLog('TEXT_EXTRACT ERROR: $e2');
        return '';
      }
    }
  }

  /// חילוץ טקסט מקובץ PDF
  Future<String> _extractFromPdf(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return '';
      
      // בדיקת גודל - לא קוראים קבצים גדולים מדי
      final stat = await file.stat();
      if (stat.size > 20 * 1024 * 1024) { // מקסימום 20MB
        appLog('TEXT_EXTRACT: PDF too large: ${stat.size} bytes');
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
      appLog('TEXT_EXTRACT PDF ERROR: $e');
      return '';
    }
  }

  /// ניקוי טקסט - הסרת תווים מיותרים
  String _cleanupText(String text) {
    if (text.isEmpty) return '';
    
    // הסרת שורות ריקות מרובות
    var cleaned = text.replaceAll(RegExp(r'\n{3,}'), '\n\n');
    
    // הסרת רווחים מיותרים
    cleaned = cleaned.replaceAll(RegExp(r' {2,}'), ' ');
    
    // הסרת תווי בקרה
    cleaned = cleaned.replaceAll(RegExp(r'[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
    
    // קיצור אם הטקסט ארוך מדי (מקסימום 50,000 תווים)
    if (cleaned.length > 50000)
      cleaned = cleaned.substring(0, 50000);
    
    return cleaned.trim();
  }

  /// בדיקה אם הסיומת נתמכת לחילוץ טקסט
  static bool isTextExtractable(String extension) {
    const supportedExtensions = [
      'txt', 'text', 'log', 'md', 'json', 'xml', 'csv', 'pdf'
    ];
    return supportedExtensions.contains(extension.toLowerCase());
  }
}
