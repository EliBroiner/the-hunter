import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/file_metadata.dart';
import '../utils/extracted_text_quality.dart';
import 'app_check_http_helper.dart';
import 'auth_service.dart';
import 'database_service.dart';
import 'dev_logger.dart';
import 'knowledge_base_service.dart';
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

  final _knowledgeBase = KnowledgeBaseService.instance;
  final List<FileMetadata> _queue = [];
  Timer? _flushTimer;
  bool _disposed = false;
  bool _backfillScheduled = false;
  /// אצווה בהעלאה — לא לבטל גם אם המשתמש פעיל
  bool _isUploading = false;

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
    try {
      final legacy = DatabaseService.instance.getUnanalyzedFilesForAiBackfill();
      debugPrint('Found ${legacy.length} legacy files. Adding to AI queue...');
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
    if (file.isAiAnalyzed && file.aiStatus != 'error' && file.aiStatus != 'pending_retry') return;

    String text = file.extractedText ?? '';
    if (text.isEmpty) {
      text = await _extractTextAsync(file);
    }

    // שלב מילון — דילוג אם הקריאה מ-FileProcessingService (כבר נבדק)
    if (!skipLocalHeuristic && text.isNotEmpty) {
      final match = await _knowledgeBase.findMatchingCategory(text);
      if (match != null) {
        file.tags = match.tags;
        file.category = match.category;
        file.isAiAnalyzed = true;
        file.aiStatus = null;
        _updateInIsar(file);
        debugPrint('⚡ Local Hit: ${file.path}');
        return;
      }
    }

    // תור לשרת — לא שולחים ל-AI טקסט עם >30% ג'יבריש
    if (text.isNotEmpty && !isExtractedTextAcceptableForAi(text)) text = '';
    if (text.isEmpty) text = file.name; // fallback
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

    final batch = List<FileMetadata>.from(_queue);
    _queue.clear();
    _flushTimer?.cancel();
    await _sendBatch(batch);
  }

  Future<void> _sendBatch(List<FileMetadata> batch) async {
    if (batch.isEmpty) return;

    _isUploading = true;
    try {
      final documents = <Map<String, String>>[];
      for (final file in batch) {
        String text = file.extractedText ?? '';
        if (text.isEmpty) text = await _extractTextAsync(file);
        if (text.isNotEmpty && !isExtractedTextAcceptableForAi(text)) text = ''; // מונע הזיות מ־ג'יבריש
        if (text.isEmpty) text = file.name;
        final truncated = text.length > _maxTextLength ? text.substring(0, _maxTextLength) : text;
        documents.add({'id': file.path, 'text': truncated});
      }
      final userId = AuthService.instance.currentUser?.uid ?? 'anonymous';
      final body = jsonEncode({
        'userId': userId,
        'documents': documents.map((d) => {'id': d['id'], 'text': d['text']}).toList(),
      });

      final sendMsg = '🚀 sending batch of ${batch.length} files to $_baseUrl';
      debugPrint(sendMsg);
      DevLogger.instance.log(sendMsg);
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

      debugPrint('📡 [Client] Response Status: ${response.statusCode}');
      debugPrint('📄 [Client] Response Body: ${response.body}');
      DevLogger.instance.log('📡 [Client] Response Status: ${response!.statusCode}');
      DevLogger.instance.log('📄 [Client] Response Body: ${response.body}');
      if (response.statusCode == 200) {
        DevLogger.instance.log('✅ Status: ${response.statusCode}');
        final list = jsonDecode(response.body) as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final docId = map['documentId'] as String?;
          final result = map['result'] as Map<String, dynamic>?;
          if (docId == null || result == null) continue;

          final file = batch.where((f) => f.path == docId).firstOrNull;
          if (file == null) continue;

          file.category = result['category'] as String?;
          final newTags = (result['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
          final existing = file.tags ?? [];
          file.tags = [...existing, ...newTags.where((t) => !existing.contains(t))].toList();
          file.isAiAnalyzed = true;
          file.aiStatus = null;
          _updateInIsar(file);
        }
      } else if (response.statusCode == 403) {
        appLog('AiAutoTagger: 403 — סימון pending_retry ל־AutoScan הבא');
        for (final file in batch) {
          file.aiStatus = 'pending_retry';
          _updateInIsar(file);
          if (!_disposed) _queue.add(file);
        }
      } else {
        appLog('AiAutoTagger: API error ${response.statusCode} — pending_retry');
        for (final file in batch) {
          file.aiStatus = 'pending_retry';
          _updateInIsar(file);
          if (!_disposed) _queue.add(file);
        }
      }
    } catch (e) {
      final errMsg = '💥 Error: $e';
      debugPrint(errMsg);
      DevLogger.instance.log(errMsg);
      appLog('AiAutoTagger: Network error - $e');
      for (final file in batch) {
        file.aiStatus = 'pending_retry';
        _updateInIsar(file);
        if (!_disposed) _queue.add(file);
      }
    } finally {
      _isUploading = false;
    }
  }

  static bool _isNetworkError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('socket') ||
        s.contains('failed host lookup') ||
        s.contains('connection') ||
        s.contains('timeout');
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
