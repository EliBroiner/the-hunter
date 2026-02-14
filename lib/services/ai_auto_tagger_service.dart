import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/ai_analysis_response.dart';
import '../models/file_metadata.dart';
import '../utils/log_sanitization.dart';
import '../utils/extracted_text_quality.dart';
import 'app_check_http_helper.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'dev_logger.dart';
import 'category_manager_service.dart';
import 'log_service.dart';
import 'ocr_service.dart';
import 'text_extraction_service.dart';

/// שירות תיוג אוטומטי ב-AI — מקומי קודם, אחר כך שרת
class AiAutoTaggerService {
  static AiAutoTaggerService? _instance;
  static AiAutoTaggerService get instance {
    _instance ??= AiAutoTaggerService._();
    return _instance!;
  }

  AiAutoTaggerService._();

  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app/api/analyze-batch';
  static const int _batchSize = 10;
  static const Duration _flushInterval = Duration(seconds: 5);
  static const int _maxTextLength = 1000;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _authCooldown = Duration(minutes: 10);

  /// אחרי 401 — עוצר קריאות AI ל־10 דקות (App Check quota reset)
  static DateTime? _authFailedUntil;

  static bool get _isInAuthCooldown =>
      _authFailedUntil != null && DateTime.now().isBefore(_authFailedUntil!);

  final List<FileMetadata> _queue = [];
  Timer? _flushTimer;
  bool _disposed = false;
  bool _backfillScheduled = false;
  /// אצווה בהעלאה — לא לבטל גם אם המשתמש פעיל
  bool _isUploading = false;
  /// ניתוח מחדש מפורש לקובץ בודד — לא לשלוח את התור במקביל
  bool _singleFileReanalyzeInProgress = false;

  bool get isUploading => _isUploading;

  /// מאתחל ומתזמן Backfill לקבצים ישנים (3 שניות עיכוב)
  void initialize() {
    if (_backfillScheduled) return;
    _backfillScheduled = true;
    Future.delayed(const Duration(seconds: 3), () {
      if (!_disposed) processUnanalyzedFiles();
    });
  }

  /// Backfill — מוסיף קבצים ישנים (extractedText קיים, ללא AI) לתור
  Future<void> processUnanalyzedFiles() async {
    if (_disposed) return;
    if (_isInAuthCooldown) return;
    try {
      final legacy = DatabaseService.instance.getUnanalyzedFilesForAiBackfill();
      appLog('AiAutoTagger: Found ${legacy.length} legacy files. Adding to AI queue...');
      for (final file in legacy) {
        if (_disposed) break;
        await addToQueue(file);
      }
    } catch (e) {
      appLog('AiAutoTagger: Backfill failed - $e');
    }
  }

  /// מוסיף קובץ לתור — בודק קודם התאמה מקומית (אלא אם skipLocalHeuristic)
  Future<void> addToQueue(FileMetadata file, {bool skipLocalHeuristic = false}) async {
    if (_disposed) return;
    if (_isInAuthCooldown) return;
    if (file.isAiAnalyzed && file.aiStatus != 'error' && file.aiStatus != 'pending_retry' && file.aiStatus != 'auth_failed_retry') return;

    String text = file.extractedText ?? '';
    if (text.isEmpty) {
      text = await _extractTextAsync(file);
    }

    // שלב Waterfall (מילון/Regex) — דילוג אם הקריאה מ-FileProcessingService (כבר נבדק)
    if (!skipLocalHeuristic && text.isNotEmpty) {
      final match = await CategoryManagerService.instance.identifyCategory(text);
      if (match != null) {
        file.tags = match.tags;
        file.category = match.category;
        file.isAiAnalyzed = true;
        file.aiStatus = null;
        _updateInIsar(file);
        appLog('AiAutoTagger: Local hit — ${file.path}');
        return;
      }
    }

    // תור לשרת — לא שולחים ל-AI טקסט עם >30% ג'יבריש
    if (text.isNotEmpty && !isExtractedTextAcceptableForAi(text)) text = '';
    if (text.isEmpty) text = file.name; // fallback
    appLog('[SCAN] File: ${file.path} — Added to AI queue (batch send when ready).');
    _queue.add(file);
    if (_queue.length >= _batchSize) {
      _startFlushTimer();
      unawaited(_flushQueue());
    } else {
      _startFlushTimer();
    }
  }

  Future<String> _extractTextAsync(FileMetadata file) async {
    final ext = file.extension.toLowerCase();
    if (TextExtractionService.isTextExtractable(ext)) {
      return TextExtractionService.instance.extractText(file.path);
    }
    if (OCRService.isSupportedImage(ext)) {
      return OCRService.instance.extractText(file.path);
    }
    return file.extractedText ?? file.name;
  }

  void _startFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushInterval, () {
      if (_queue.isNotEmpty) {
        unawaited(_flushQueue());
      }
    });
  }

  Future<void> _flushQueue() async {
    if (_queue.isEmpty || _disposed) return;
    if (_isInAuthCooldown) {
      _startFlushTimer();
      return;
    }

    if (_singleFileReanalyzeInProgress) return; // לא לשלוח תור בזמן ניתוח מחדש לקובץ בודד
    final batch = List<FileMetadata>.from(_queue);
    _queue.clear();
    _flushTimer?.cancel();
    await _sendBatch(batch);
  }

  /// מחזיר מפת path -> תוצאת ניתוח (כולל suggestions) עבור 200.
  Future<Map<String, DocumentAnalysisResult>> _sendBatch(List<FileMetadata> batch) async {
    if (batch.isEmpty) return {};
    if (_isInAuthCooldown) {
      for (final f in batch) {
        _queue.add(f);
      }
      _startFlushTimer();
      return {};
    }

    final results = <String, DocumentAnalysisResult>{};
    _isUploading = true;
    try {
      // מזהה ייחודי לכל קובץ — int אקראי, מפת id->קובץ להתאמת תשובות
      final rnd = Random();
      final idToFile = <String, FileMetadata>{};
      final documents = <Map<String, dynamic>>[];
      for (var i = 0; i < batch.length; i++) {
        final file = batch[i];
        int docId;
        do {
          docId = rnd.nextInt(0x7FFFFFFF);
        } while (idToFile.containsKey(docId.toString()));
        idToFile[docId.toString()] = file;
        String text = file.extractedText ?? '';
        if (text.isEmpty) text = await _extractTextAsync(file);
        if (text.isNotEmpty && !isExtractedTextAcceptableForAi(text)) text = '';
        if (text.isEmpty) text = file.name;
        final truncated = text.length > _maxTextLength ? text.substring(0, _maxTextLength) : text;
        documents.add({
          'id': docId.toString(),
          'filename': file.name,
          'text': truncated,
        });
      }
      final userId = AuthService.instance.currentUser?.uid ?? 'anonymous';
      final body = jsonEncode({
        'userId': userId,
        'documents': documents.map((d) => {'id': d['id'], 'filename': d['filename'], 'text': d['text']}).toList(),
      });

      final sendMsg = '🚀 sending batch of ${batch.length} files to $_baseUrl';
      debugPrint(sendMsg);
      DevLogger.instance.log(sendMsg);
      appLog('[SCAN] Sending batch of ${batch.length} files to Gemini.');
      final headers =
          await AppCheckHttpHelper.getBackendHeaders(existing: {'Content-Type': 'application/json'});

      // ניסיונות חוזרים על שגיאות רשת (SocketException, Failed host lookup)
      http.Response? response;
      for (var attempt = 0; attempt < _maxRetries; attempt++) {
        try {
          response = await http
              .post(
                Uri.parse(_baseUrl),
                headers: headers,
                body: body,
              )
              .timeout(const Duration(seconds: 60));
          break;
        } on SocketException catch (e) {
          appLog('AiAutoTagger: SocketException attempt ${attempt + 1}/$_maxRetries - $e');
          if (attempt < _maxRetries - 1) {
            await Future.delayed(_retryDelay);
          } else {
            rethrow;
          }
        } on HttpException catch (e) {
          appLog('AiAutoTagger: HttpException attempt ${attempt + 1}/$_maxRetries - $e');
          if (attempt < _maxRetries - 1) {
            await Future.delayed(_retryDelay);
          } else {
            rethrow;
          }
        } catch (e) {
          if (_isNetworkError(e) && attempt < _maxRetries - 1) {
            appLog('AiAutoTagger: Network error attempt ${attempt + 1}/$_maxRetries - $e');
            await Future.delayed(_retryDelay);
          } else {
            rethrow;
          }
        }
      }
      if (response == null) throw Exception('No response after $_maxRetries attempts');

      // X-Ray: גוף גולמי — לוג ל-Console + AI Lab
      appLog('AiAutoTagger: Response ${response.statusCode} | Body: ${bodyForLog(response.body)}');
      DevLogger.instance.log('📡 [Client] Response Status: ${response.statusCode}');
      DevLogger.instance.log('📄 [Client] Response Body: ${bodyForLog(response.body)}');
      if (response.statusCode == 200) {
        try {
          final decoded = jsonDecode(response.body);
          // תמיכה בתגובה כ־list או כ־object בודד (analyze קובץ יחיד)
          final List<dynamic> list;
          if (decoded is List<dynamic>) {
            list = decoded;
          } else if (decoded is Map<String, dynamic> &&
              decoded.containsKey('documentId') &&
              decoded.containsKey('result')) {
            appLog('[SCAN] 4. API Response: single object — normalizing to list.');
            list = [decoded];
          } else {
            appLog('[SCAN] 4. API Response: 200 but body is not a list (type: ${decoded.runtimeType}). Body: ${response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body}');
            if (decoded is Map<String, dynamic> && decoded.containsKey('error')) {
              appLog('[SCAN] 4. API Response: Server returned error object: ${decoded['error']}');
            }
            list = const [];
          }
          if (list.isEmpty) {
            appLog('[SCAN] 4. API Response: 200 but empty list []. No results to apply.');
          } else {
            DevLogger.instance.log('✅ Status: ${response.statusCode}');
            appLog('[SCAN] 4. API Response: Success (batch ${batch.length} files, list length ${list.length}).');
            for (final item in list) {
              final map = item as Map<String, dynamic>;
              final docId = map['documentId'] as String?;
              final result = map['result'] as Map<String, dynamic>?;
              if (docId == null || result == null) continue;

              // התאמה לפי מזהה ייחודי — השרת מחזיר את ה-id ששלחנו (int string)
              final file = idToFile[docId];
              if (file == null) continue;

              file.category = result['category'] as String?;
              final newTags = (result['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
              final existing = file.tags ?? [];
              file.tags = [...existing, ...newTags.where((t) => !existing.contains(t))].toList();
              file.requiresHighResOcr = (result['requires_high_res_ocr'] ?? result['requiresHighResOcr']) == true;
              final meta = result['metadata'] as Map<String, dynamic>?;
              final metadata = meta != null ? DocumentMetadata.fromJson(Map<String, dynamic>.from(meta)) : null;
              _applyAiMetadata(file, metadata);
              file.isAiAnalyzed = true;
              file.aiStatus = null;
              _updateInIsar(file);

              final suggestionsRaw = result['suggestions'] as List<dynamic>? ?? [];
              final suggestions = suggestionsRaw
                  .map((e) => AiSuggestion.fromJson(e as Map<String, dynamic>?))
                  .whereType<AiSuggestion>()
                  .toList();
              results[file.path] = DocumentAnalysisResult(
                category: file.category ?? '',
                tags: file.tags ?? [],
                suggestions: suggestions,
                requiresHighResOcr: file.requiresHighResOcr,
                metadata: metadata,
              );
              appLog('[SCAN] File: ${file.path} — 4. API Response: Success.');
            }
          }
        } catch (e, st) {
          appLog('[SCAN] 4. API Response: JSON parse failed. Error: $e. Body length: ${response.body.length}. Body preview: ${response.body.length > 300 ? response.body.substring(0, 300) : response.body}');
          rethrow;
        }
      } else if (response.statusCode == 401) {
        _authFailedUntil = DateTime.now().add(_authCooldown);
        appLog('[SCAN] 4. API Response: Fail — 401 App Check.');
        appLog('❌ AI Analysis failed due to App Check. Please ensure Debug Token is registered in Firebase Console.');
        appLog('AiAutoTagger: 401 App Check — cooldown ${_authCooldown.inMinutes} min');
        for (final file in batch) {
          file.aiStatus = 'auth_failed_retry';
          _updateInIsar(file);
          if (!_disposed) _queue.add(file);
        }
      } else if (response.statusCode == 403) {
        appLog('[SCAN] 4. API Response: Fail — 403 (quota or forbidden).');
        appLog('AiAutoTagger: 403 — סימון pending_retry ל־AutoScan הבא');
        for (final file in batch) {
          file.aiStatus = 'pending_retry';
          _updateInIsar(file);
          if (!_disposed) _queue.add(file);
        }
      } else {
        appLog('[SCAN] 4. API Response: Fail — ${response.statusCode}. ${bodyForLog(response.body)}');
        appLog('AiAutoTagger: API error ${response.statusCode} — pending_retry');
        for (final file in batch) {
          file.aiStatus = 'pending_retry';
          _updateInIsar(file);
          if (!_disposed) _queue.add(file);
        }
      }
    } catch (e, st) {
      final errStr = e.toString().toLowerCase();
      final isAppCheckError = errStr.contains('app attestation') || errStr.contains('attestation failed');
      if (isAppCheckError) {
        _authFailedUntil = DateTime.now().add(_authCooldown);
        appLog('❌ AI Analysis failed due to App Check. Please ensure Debug Token is registered in Firebase Console.');
      }
      DevLogger.instance.log('💥 Error: ${sanitizeError(e)}');
      appLog('AiAutoTagger: ${isAppCheckError ? "App Check error" : "Network error"} - ${sanitizeError(e)}');
      appLog('[SCAN] Batch API failed (${batch.length} files). ${sanitizeError(e, st)}');
      for (final file in batch) {
        file.aiStatus = isAppCheckError ? 'auth_failed_retry' : 'pending_retry';
        _updateInIsar(file);
        if (!_disposed) _queue.add(file);
      }
    } finally {
      _isUploading = false;
    }
    return results;
  }

  static bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('failed host lookup') ||
        s.contains('connection') ||
        s.contains('timeout');
  }

  void _applyAiMetadata(FileMetadata file, DocumentMetadata? metadata) {
    if (metadata == null || (metadata.names.isEmpty && metadata.ids.isEmpty && metadata.locations.isEmpty)) return;
    file.aiMetadataNames = metadata.names.isEmpty ? null : metadata.names;
    file.aiMetadataIds = metadata.ids.isEmpty ? null : metadata.ids;
    file.aiMetadataLocations = metadata.locations.isEmpty ? null : metadata.locations;
  }

  void _updateInIsar(FileMetadata file) {
    try {
      DatabaseService.instance.isar.write((isar) {
        isar.fileMetadatas.put(file);
      });
    } catch (e) {
      appLog('AiAutoTagger: Isar update failed - $e');
    }
  }

  /// שולח את התור מיד ומחכה לסיום — לשימוש ב־Re-analyze
  Future<void> flushNow() async {
    _flushTimer?.cancel();
    if (_queue.isNotEmpty) await _flushQueue();
  }

  /// מנתח קובץ בודד מיד — רק הקובץ הזה, לא דרך התור. לשימוש ב־Re-analyze.
  /// מחזיר תוצאת ניתוח (כולל suggestions) אם הצליח.
  Future<DocumentAnalysisResult?> processSingleFileImmediately(FileMetadata file, {required bool isPro}) async {
    if (_disposed || _isInAuthCooldown) return null;
    if (!isPro) return null;
    // מוציאים את הקובץ מהתור כדי שלא יישלח שוב באצווה
    _queue.removeWhere((f) => f.path == file.path);
    _singleFileReanalyzeInProgress = true;
    try {
      final batch = [file];
      final results = await _sendBatch(batch);
      return results[file.path];
    } finally {
      _singleFileReanalyzeInProgress = false;
    }
  }

  /// מנקה ומפנה את התור — שולח את כל הקבצים הנותרים
  Future<void> dispose() async {
    _disposed = true;
    _flushTimer?.cancel();
    if (_queue.isNotEmpty) {
      final remaining = List<FileMetadata>.from(_queue);
      _queue.clear();
      await _sendBatch(remaining);
    }
  }
}
