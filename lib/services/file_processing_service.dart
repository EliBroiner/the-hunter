import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_analysis_response.dart';
import '../models/file_metadata.dart';
import 'ai_auto_tagger_service.dart';
import 'app_check_http_helper.dart';
import 'auth_service.dart';
import 'category_manager_service.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'ocr_service.dart';
import 'text_extraction_service.dart';
import '../utils/extracted_text_quality.dart';
import 'utils/file_validator.dart';

/// תוצאת ניתוח מחדש — להצגת Snackbar ב-UI
class ForceReprocessResult {
  final bool success;
  final String message;
  final List<AiSuggestion> suggestions;
  const ForceReprocessResult({
    required this.success,
    required this.message,
    this.suggestions = const [],
  });
}

/// צינור עיבוד קבצים: ולידציה → Waterfall (מילון/Regex) → AI (רק ל-PRO)
/// מתאים לעיבוד אלפי קבצים — עוצר בשקט ב-unreadable / dictionaryMatched
class FileProcessingService {
  static FileProcessingService? _instance;
  static FileProcessingService get instance {
    _instance ??= FileProcessingService._();
    return _instance!;
  }

  FileProcessingService._();

  static const String _backendBase = 'https://the-hunter-105628026575.me-west1.run.app';

  final _db = DatabaseService.instance;
  final _validator = FileValidator.instance;
  final _aiTagger = AiAutoTaggerService.instance;
  final _categoryManager = CategoryManagerService.instance;

  /// OCR Fallback — העלאת תמונה B&W ל-Backend (Cloud Vision + Gemini). מחזיר (text, isPureImageNoText, geminiResult).
  Future<({String? text, bool isPureImageNoText, DocumentAnalysisResult? geminiResult})> _callOcrExtract(String imagePath, {String? documentId, String? filename}) async {
    try {
      final compressed = await OCRService.instance.getCompressedBwImageForUpload(imagePath);
      if (compressed.bytes.isEmpty) return (text: null, isPureImageNoText: false, geminiResult: null);
      final uri = Uri.parse('$_backendBase/api/ocr-extract');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', compressed.bytes, filename: filename ?? 'image.jpg'));
      if (documentId != null) request.fields['documentId'] = documentId;
      if (filename != null) request.fields['filename'] = filename;
      final uid = AuthService.instance.currentUser?.uid;
      if (uid != null) request.fields['userId'] = uid;
      request.headers.addAll(await AppCheckHttpHelper.getBackendHeaders());
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode != 200) return (text: null, isPureImageNoText: false, geminiResult: null);
      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final text = decoded?['text'] as String? ?? '';
      final isPure = decoded?['isPureImageNoText'] as bool? ?? false;
      DocumentAnalysisResult? geminiResult;
      final gr = decoded?['geminiResult'] as Map<String, dynamic>?;
      if (gr != null) {
        final cat = gr['category'] as String? ?? '';
        final tagsList = gr['tags'];
        final tags = tagsList is List
            ? tagsList.map((e) => (e?.toString() ?? '').trim()).where((s) => s.isNotEmpty).toList()
            : <String>[];
        final sugg = gr['suggestions'];
        final suggestions = sugg is List
            ? sugg.map((e) => AiSuggestion.fromJson(e is Map ? Map<String, dynamic>.from(e as Map) : null)).whereType<AiSuggestion>().toList()
            : <AiSuggestion>[];
        geminiResult = DocumentAnalysisResult(category: cat, tags: tags, suggestions: suggestions);
      }
      return (text: text.isEmpty ? null : text, isPureImageNoText: isPure, geminiResult: geminiResult);
    } catch (e) {
      appLog('OCR fallback (forceReprocess): $e');
      return (text: null, isPureImageNoText: false, geminiResult: null);
    }
  }

  /// דיווח תמונה שדולגה (No Text Detected) — fire-and-forget לסטטיסטיקת חיסכון. משתמש ב-Headers מאומתים (App Check).
  static void reportNoTextDetected() {
    _reportNoTextDetectedAsync().catchError((e) {
      appLog('reportNoTextDetected error: $e');
    });
  }

  static Future<void> _reportNoTextDetectedAsync() async {
    final uri = Uri.parse('$_backendBase/api/report-no-text-detected');
    final headers = await AppCheckHttpHelper.getBackendHeaders();
    headers['Content-Type'] = 'application/json';
    final r = await http.post(uri, headers: headers, body: '{}');
    if (r.statusCode != 200) appLog('reportNoTextDetected failed: ${r.statusCode}');
  }

  /// דיווח כשלון ל-Scanning Health — fire-and-forget. משתמש ב-Headers מאומתים (App Check).
  void _reportScanFailure(FileMetadata file, String rawText) {
    _reportScanFailureAsync(file, rawText).catchError((e) {
      appLog('ScanFailure report error: $e');
    });
  }

  Future<void> _reportScanFailureAsync(FileMetadata file, String rawText) async {
    final uri = Uri.parse('$_backendBase/api/report-scan-failure');
    final headers = await AppCheckHttpHelper.getBackendHeaders();
    headers['Content-Type'] = 'application/json';
    final body = jsonEncode({
      'documentId': file.id.toString(),
      'filename': file.name,
      'rawText': rawText.length > 50000 ? rawText.substring(0, 50000) : rawText,
      'garbageRatioPercent': getGarbageRatio(rawText) * 100,
      'userId': AuthService.instance.currentUser?.uid,
      'reasonForUpload': 'Local OCR Low Confidence',
    });
    final r = await http.post(uri, headers: headers, body: body);
    if (r.statusCode != 200) appLog('ScanFailure report failed: ${r.statusCode}');
  }

  /// מריץ צינור עיבוד לפי נתיב. מחזיר תוצאת AI (כולל suggestions) אם immediate ו-PRO ונשלח לשרת.
  Future<DocumentAnalysisResult?> processFileByPath(String filePath, {required bool isPro, bool immediate = false}) async {
    final file = _db.getFileByPath(filePath);
    if (file == null) {
      appLog('FileProcessing: קובץ לא נמצא — $filePath');
      return null;
    }
    return processFile(file, isPro: isPro, immediate: immediate);
  }

  /// מריץ את צינור העיבוד על קובץ בודד (לאחר חילוץ טקסט).
  /// מחזיר תוצאת ניתוח מהשרת (כולל suggestions) רק כאשר immediate ו-PRO ונשלח ל-AI.
  Future<DocumentAnalysisResult?> processFile(FileMetadata file, {required bool isPro, bool immediate = false}) async {
    final text = file.extractedText ?? '';
    final path = file.path;

    appLog('[SCAN] File: $path — 1. OCR finished. Text length: ${text.length}');

    // שלב 1: ולידציה איכות — קבצים unreadable לא נשלחים ל-Gemini, dropped
    final status = _validator.validateQuality(text);
    if (status == AnalysisStatus.unreadable) {
      file.isAiAnalyzed = false;
      file.aiStatus = 'unreadable';
      _db.updateFile(file);
      _reportScanFailure(file, text);
      appLog('[SCAN] File: $path — 2. Quality: UNREADABLE (low confidence / too short). 3. DECISION: Skipping AI (file dropped, not sent to Gemini).');
      return null;
    }

    appLog('[SCAN] File: $path — 2. Checking AI eligibility (isPro: $isPro, Quota: server-side).');

    // שלב 2: Waterfall (קטגוריות חכמות + מילון ישן)
    if (text.isNotEmpty) {
      final match = await _categoryManager.identifyCategory(text);
      if (match != null) {
        file.category = match.category;
        file.tags = match.tags;
        file.isAiAnalyzed = true;
        file.aiStatus = 'local_match';
        _db.updateFile(file);
        appLog('[SCAN] File: $path — 3. DECISION: Local match (waterfall). Skipping AI.');
        return null;
      }
    }

    // שלב 3: AI רק ל-PRO
    if (!isPro) {
      appLog('[SCAN] File: $path — 3. DECISION: Skipping AI because not PRO.');
      return null;
    }

    if (immediate) {
      appLog('[SCAN] File: $path — 3. DECISION: Sending to Gemini (immediate).');
      final result = await _aiTagger.processSingleFileImmediately(file, isPro: isPro);
      appLog('[SCAN] File: $path — 4. API Response: ${result != null ? "Success" : "Fail/empty"}');
      return result;
    }

    appLog('[SCAN] File: $path — 3. DECISION: Adding to AI queue (batch send).');
    await _aiTagger.addToQueue(file, skipLocalHeuristic: true);
    return null;
  }

  /// ניתוח מחדש סינכרוני לקובץ בודד: איפוס → OCR → Waterfall → AI (ללא תור). מחזיר תוצאה להצגה.
  Future<ForceReprocessResult> forceReprocessFile(
    FileMetadata file, {
    required bool isPro,
    void Function(String)? reportProgress,
    bool Function()? isCanceled,
  }) async {
    final path = file.path;
    bool canceled() => isCanceled?.call() ?? false;

    reportProgress?.call('מאפס...');
    _db.resetFileForReanalysis(file);
    if (canceled()) return const ForceReprocessResult(success: false, message: 'בוטל');

    reportProgress?.call('מחלץ טקסט...');
    final ext = file.extension.toLowerCase();
    String text;
    if (TextExtractionService.isTextExtractable(ext)) {
      text = await TextExtractionService.instance.extractText(path);
    } else if (OCRService.isSupportedImage(ext)) {
      final ocrResult = await OCRService.instance.extractTextWithStatus(path);
      if (ocrResult.isNoText) {
        file.aiStatus = 'no_text_detected';
        file.extractedText = null;
        file.isIndexed = true;
        _db.updateFile(file);
        FileProcessingService.reportNoTextDetected();
        return const ForceReprocessResult(success: false, message: 'לא נמצא טקסט בתמונה');
      }
      if (ocrResult.needsBackendFallback) {
        reportProgress?.call('מעלה לשרת...');
        final fallback = await _callOcrExtract(path, documentId: file.id.toString(), filename: file.name);
        if (fallback.isPureImageNoText && fallback.text == null) {
          file.aiStatus = 'no_text_detected';
          file.extractedText = null;
          file.isIndexed = true;
          _db.updateFile(file);
          FileProcessingService.reportNoTextDetected();
          return const ForceReprocessResult(success: false, message: 'לא נמצא טקסט בתמונה');
        }
        text = fallback.text?.trim().isNotEmpty == true ? fallback.text! : ocrResult.text;
        file.extractedText = text.isEmpty ? null : text;
        file.isIndexed = true;
        if (fallback.geminiResult != null) {
          file.category = fallback.geminiResult!.category;
          file.tags = fallback.geminiResult!.tags;
          file.isAiAnalyzed = true;
          file.aiStatus = null;
          _db.updateFile(file);
          return ForceReprocessResult(
            success: true,
            message: 'עובד ב-Cloud Vision + Gemini: ${fallback.geminiResult!.category}',
            suggestions: fallback.geminiResult!.suggestions,
          );
        }
      } else {
        text = ocrResult.text;
      }
    } else {
      text = file.extractedText ?? '';
    }
    if (canceled()) return const ForceReprocessResult(success: false, message: 'בוטל');

    file.extractedText = text.isEmpty ? null : text;
    file.isIndexed = true;
    _db.saveFile(file);

    final status = _validator.validateQuality(text);
    if (status == AnalysisStatus.unreadable) {
      file.isAiAnalyzed = false;
      file.aiStatus = 'unreadable';
      _db.updateFile(file);
      _reportScanFailure(file, text);
      appLog('[FORCE] File: $path — UNREADABLE.');
      return const ForceReprocessResult(success: false, message: 'הטקסט לא קריא');
    }

    reportProgress?.call('בודק מילון וחוקים...');
    if (text.isNotEmpty) {
      final match = await _categoryManager.identifyCategory(text);
      if (match != null) {
        file.category = match.category;
        file.tags = match.tags;
        file.isAiAnalyzed = true;
        file.aiStatus = 'local_match';
        _db.updateFile(file);
        appLog('[FORCE] File: $path — Local match: ${match.category}');
        return ForceReprocessResult(success: true, message: 'זוהה מקומית: ${match.category}');
      }
    }

    if (!isPro) {
      return const ForceReprocessResult(success: false, message: 'ניתוח AI זמין למשתמש PRO בלבד');
    }

    reportProgress?.call('שולח ל-AI...');
    final result = await _aiTagger.processSingleFileImmediately(file, isPro: isPro);
    if (canceled()) return const ForceReprocessResult(success: false, message: 'בוטל');

    if (result != null) {
      final cat = file.category ?? '—';
      appLog('[FORCE] File: $path — AI: $cat');
      return ForceReprocessResult(
        success: true,
        message: 'נותח ב-AI: $cat',
        suggestions: result.suggestions,
      );
    }
    return ForceReprocessResult(
      success: false,
      message: 'שגיאה בניתוח AI${file.aiStatus != null ? ' (${file.aiStatus})' : ''}',
    );
  }
}
