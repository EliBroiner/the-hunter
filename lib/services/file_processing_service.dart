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

/// תוצאת צינור עיבוד מרכזי — לשימוש פנימי ו־forceReprocessFile
class ProcessWorkflowResult {
  final bool success;
  final String message;
  final List<AiSuggestion> suggestions;
  final DocumentAnalysisResult? documentResult;
  ProcessWorkflowResult({
    required this.success,
    required this.message,
    this.suggestions = const [],
    this.documentResult,
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
            ? sugg.map((e) => AiSuggestion.fromJson(e is Map ? Map<String, dynamic>.from(e) : null)).whereType<AiSuggestion>().toList()
            : <AiSuggestion>[];
        final requiresHighResOcr = (gr['requires_high_res_ocr'] ?? gr['requiresHighResOcr']) == true;
        final meta = gr['metadata'] as Map<String, dynamic>?;
        final metadata = meta != null ? DocumentMetadata.fromJson(Map<String, dynamic>.from(meta)) : null;
        geminiResult = DocumentAnalysisResult(category: cat, tags: tags, suggestions: suggestions, requiresHighResOcr: requiresHighResOcr, metadata: metadata);
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

  /// מחיל מטא־דאטה מ-AI על הקובץ
  void _applyAiMetadata(FileMetadata file, DocumentMetadata? metadata) {
    if (metadata == null || (metadata.names.isEmpty && metadata.ids.isEmpty && metadata.locations.isEmpty)) return;
    file.aiMetadataNames = metadata.names.isEmpty ? null : metadata.names;
    file.aiMetadataIds = metadata.ids.isEmpty ? null : metadata.ids;
    file.aiMetadataLocations = metadata.locations.isEmpty ? null : metadata.locations;
  }

  /// מחיל תוצאת Gemini על הקובץ
  void _applyGeminiResult(FileMetadata file, DocumentAnalysisResult result) {
    file.category = result.category;
    file.tags = result.tags;
    file.requiresHighResOcr = result.requiresHighResOcr;
    _applyAiMetadata(file, result.metadata);
  }

  void _saveVisionResultToFile(FileMetadata file, DocumentAnalysisResult result) {
    _applyGeminiResult(file, result);
    file.isAiAnalyzed = true;
    file.aiStatus = null;
    _db.updateFile(file);
  }

  /// ביצוע סריקה חוזרת באמצעות Google Vision בגלל זיהוי איכות נמוכה על ידי Gemini.
  /// מחזיר תוצאה אם הצליח; null אם לא. מונע לולאה — קורא רק כש־התוצאה מ־analyze-batch (לא מ־Vision).
  Future<DocumentAnalysisResult?> _runVisionFallbackForLowQuality(FileMetadata file) async {
    if (!OCRService.isSupportedImage(file.extension.toLowerCase())) return null;
    final fallback = await _callOcrExtract(file.path, documentId: file.id.toString(), filename: file.name);
    return fallback.geminiResult;
  }

  /// אם requiresHighResOcr מהתוצאה מ־analyze-batch — מפעיל Vision; אחרת null.
  Future<DocumentAnalysisResult?> _tryVisionFallbackWhenLowQuality(
      FileMetadata file, DocumentAnalysisResult? result, bool isPro) async {
    if (result == null || !result.requiresHighResOcr || !isPro) return null;
    appLog('[SCAN] File: ${file.path} — ביצוע סריקה חוזרת באמצעות Google Vision בגלל זיהוי איכות נמוכה על ידי Gemini.');
    final visionResult = await _runVisionFallbackForLowQuality(file);
    if (visionResult == null) return null;
    _saveVisionResultToFile(file, visionResult);
    return visionResult;
  }

  /// צינור עיבוד מרכזי — שלב 1: חילוץ טקסט (OCR/TextExtraction)
  Future<String> _workflowStep1ExtractText(
      FileMetadata file, void Function(String)? reportProgress, {bool useExistingIfPresent = false}) async {
    appLog('[WORKFLOW] מתחיל תהליך עיבוד מרכזי: ${file.path}');
    final existing = file.extractedText?.trim() ?? '';
    if (useExistingIfPresent && existing.isNotEmpty) {
      appLog('[WORKFLOW] משתמש בטקסט קיים — אורך: ${existing.length}');
      return existing;
    }
    reportProgress?.call('מחלץ טקסט...');
    final ext = file.extension.toLowerCase();
    if (TextExtractionService.isTextExtractable(ext)) {
      return TextExtractionService.instance.extractText(file.path);
    }
    if (OCRService.isSupportedImage(ext)) {
      return _workflowStep1OcrImage(file, reportProgress);
    }
    return file.extractedText ?? '';
  }

  Future<String> _workflowStep1OcrImage(FileMetadata file, void Function(String)? reportProgress) async {
    final ocrResult = await OCRService.instance.extractTextWithStatus(file.path);
    if (ocrResult.isNoText) {
      file.aiStatus = 'no_text_detected';
      file.extractedText = null;
      FileProcessingService.reportNoTextDetected();
      return '';
    }
    if (ocrResult.needsBackendFallback) {
      reportProgress?.call('מעלה לשרת...');
      appLog('[WORKFLOW] איכות ML Kit נמוכה — מעלה ל-Cloud Vision');
      final fallback = await _callOcrExtract(file.path, documentId: file.id.toString(), filename: file.name);
      if (fallback.isPureImageNoText && fallback.text == null) {
        file.aiStatus = 'no_text_detected';
        file.extractedText = null;
        FileProcessingService.reportNoTextDetected();
        return '';
      }
      final text = fallback.text?.trim().isNotEmpty == true ? fallback.text! : ocrResult.text;
      file.extractedText = text.isEmpty ? null : text;
      if (fallback.geminiResult != null) {
        _applyGeminiResult(file, fallback.geminiResult!);
        file.isAiAnalyzed = true;
        file.aiStatus = null;
      }
      return text;
    }
    return ocrResult.text;
  }

  /// צינור עיבוד מרכזי — שלב 2: בדיקת איכות
  bool _workflowStep2QualityCheck(FileMetadata file, String text) {
    appLog('[WORKFLOW] בדיקת איכות טקסט — אורך: ${text.length}');
    final status = _validator.validateQuality(text);
    if (status == AnalysisStatus.unreadable) {
      appLog('[WORKFLOW] איכות נמוכה — UNREADABLE');
      file.isAiAnalyzed = false;
      file.aiStatus = 'unreadable';
      _reportScanFailure(file, text);
      return false;
    }
    return true;
  }

  /// צינור עיבוד מרכזי — שלב 3: Waterfall + Gemini (אם נדרש)
  Future<DocumentAnalysisResult?> _workflowStep3GeminiIfNeeded(
      FileMetadata file, String text, bool isPro, bool Function()? isCanceled) async {
    appLog('[WORKFLOW] בודק מילון וחוקים...');
    if (text.isNotEmpty) {
      final match = await _categoryManager.identifyCategory(text);
      if (match != null) {
        appLog('[WORKFLOW] התאמה מקומית — ${match.category}');
        file.category = match.category;
        file.tags = match.tags;
        file.isAiAnalyzed = true;
        file.aiStatus = 'local_match';
        return null;
      }
    }
    if (!isPro) return null;
    if (isCanceled?.call() == true) return null;
    appLog('[WORKFLOW] שולח ל-Gemini לניתוח');
    return _aiTagger.processSingleFileImmediately(file, isPro: isPro);
  }

  /// צינור עיבוד מרכזי — שלב 4: Vision fallback אם requiresHighResOcr
  Future<DocumentAnalysisResult?> _workflowStep4VisionIfNeeded(
      FileMetadata file, DocumentAnalysisResult? result, bool isPro) async {
    final visionResult = await _tryVisionFallbackWhenLowQuality(file, result, isPro);
    if (visionResult != null) {
      appLog('[WORKFLOW] מפעיל סריקה איכותית בגלל דרישת AI — הושלם');
    }
    return visionResult ?? result;
  }

  /// צינור עיבוד מרכזי — שלב 5: שמירה סופית
  void _workflowStep5Save(FileMetadata file, String text) {
    file.extractedText = text.isEmpty ? null : text;
    file.isIndexed = true;
    _db.updateFile(file);
    appLog('[WORKFLOW] שמירת מטא־דאטה סופית — isIndexed=true');
  }

  /// צינור עיבוד מרכזי — נקודת כניסה יחידה. מחזיר תוצאה להמרה ל־ForceReprocessResult או DocumentAnalysisResult.
  Future<ProcessWorkflowResult> processFileWorkflow(
    FileMetadata file, {
    required bool isPro,
    bool resetFirst = false,
    bool useExistingText = false,
    void Function(String)? reportProgress,
    bool Function()? isCanceled,
  }) async {
    if (resetFirst) {
      reportProgress?.call('מאפס...');
      _db.resetFileForReanalysis(file);
    }
    if (isCanceled?.call() == true) {
      return ProcessWorkflowResult(success: false, message: 'בוטל');
    }

    String text = await _workflowStep1ExtractText(file, reportProgress, useExistingIfPresent: useExistingText);
    if (isCanceled?.call() == true) return ProcessWorkflowResult(success: false, message: 'בוטל');

    if (file.aiStatus == 'no_text_detected') {
      _workflowStep5Save(file, '');
      return ProcessWorkflowResult(success: false, message: 'לא נמצא טקסט בתמונה');
    }

    if (text.isEmpty && (file.extractedText ?? '').isEmpty) {
      _workflowStep5Save(file, '');
      return ProcessWorkflowResult(success: false, message: 'לא נמצא טקסט');
    }

    if (text.isEmpty) text = file.extractedText ?? '';
    if (!_workflowStep2QualityCheck(file, text)) {
      _db.updateFile(file);
      return ProcessWorkflowResult(success: false, message: 'הטקסט לא קריא');
    }

    if (file.isAiAnalyzed && file.aiStatus == 'local_match') {
      _workflowStep5Save(file, text);
      return ProcessWorkflowResult(success: true, message: 'זוהה מקומית: ${file.category}');
    }

    if (file.isAiAnalyzed && file.aiStatus == null && file.category != null) {
      appLog('[WORKFLOW] תוצאה מ-Vision כבר הוחלה — דילוג על Gemini');
      _workflowStep5Save(file, text);
      return ProcessWorkflowResult(
        success: true,
        message: 'עובד ב-Cloud Vision + Gemini: ${file.category}',
        documentResult: DocumentAnalysisResult(
          category: file.category!,
          tags: file.tags ?? [],
          suggestions: const [],
          requiresHighResOcr: file.requiresHighResOcr,
          metadata: file.aiMetadata != null
              ? DocumentMetadata(
                  names: file.aiMetadataNames ?? [],
                  ids: file.aiMetadataIds ?? [],
                  locations: file.aiMetadataLocations ?? [],
                )
              : null,
        ),
      );
    }

    var result = await _workflowStep3GeminiIfNeeded(file, text, isPro, isCanceled);
    if (isCanceled?.call() == true) return ProcessWorkflowResult(success: false, message: 'בוטל');

    result = await _workflowStep4VisionIfNeeded(file, result, isPro);
    if (result != null) _saveVisionResultToFile(file, result);

    _workflowStep5Save(file, text);
    final cat = file.category ?? '—';
    return ProcessWorkflowResult(
      success: result != null || file.isAiAnalyzed,
      message: result != null ? 'נותח ב-AI: $cat' : (file.aiStatus != null ? 'שגיאה: ${file.aiStatus}' : 'לא נותח'),
      suggestions: result?.suggestions ?? const [],
      documentResult: result,
    );
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

  /// מריץ את צינור העיבוד על קובץ בודד (משתמש בטקסט קיים). מפנה ל־processFileWorkflow.
  Future<DocumentAnalysisResult?> processFile(FileMetadata file, {required bool isPro, bool immediate = false}) async {
    if (!immediate) {
      appLog('[SCAN] File: ${file.path} — הוספה לתור AI');
      await _aiTagger.addToQueue(file, skipLocalHeuristic: true);
      return null;
    }
    final r = await processFileWorkflow(file, isPro: isPro, useExistingText: true);
    return r.documentResult;
  }

  /// ניתוח מחדש סינכרוני — מפנה ל־processFileWorkflow עם resetFirst.
  Future<ForceReprocessResult> forceReprocessFile(
    FileMetadata file, {
    required bool isPro,
    void Function(String)? reportProgress,
    bool Function()? isCanceled,
  }) async {
    final r = await processFileWorkflow(
      file,
      isPro: isPro,
      resetFirst: true,
      reportProgress: reportProgress,
      isCanceled: isCanceled,
    );
    return ForceReprocessResult(success: r.success, message: r.message, suggestions: r.suggestions);
  }
}
