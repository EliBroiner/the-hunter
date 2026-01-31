import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/file_metadata.dart';
import 'database_service.dart';
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

  static const String _baseUrl = 'http://10.0.2.2:8080/api/analyze-batch';
  static const int _batchSize = 10;
  static const Duration _flushInterval = Duration(seconds: 5);
  static const int _maxTextLength = 1000;

  final _knowledgeBase = KnowledgeBaseService.instance;
  final List<FileMetadata> _queue = [];
  Timer? _flushTimer;
  bool _disposed = false;

  /// מוסיף קובץ לתור — בודק קודם התאמה מקומית
  Future<void> addToQueue(FileMetadata file) async {
    if (_disposed) return;
    if (file.isAiAnalyzed && file.aiStatus != 'error') return;

    // Step A: Local Heuristic
    String text = file.extractedText ?? '';
    if (text.isEmpty) {
      text = await _extractTextAsync(file);
    }
    if (text.isNotEmpty) {
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

    // Step B: Server Queue
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

    final documents = <Map<String, String>>[];
    for (final file in batch) {
      String text = file.extractedText ?? '';
      if (text.isEmpty) text = await _extractTextAsync(file);
      final truncated = text.length > _maxTextLength ? text.substring(0, _maxTextLength) : text;
      documents.add({'id': file.path, 'text': truncated});
    }

    try {
      final userId = 'anonymous'; // TODO: AuthService.instance.currentUser?.uid
      final body = jsonEncode({
        'userId': userId,
        'documents': documents.map((d) => {'id': d['id'], 'text': d['text']}).toList(),
      });

      final response = await http
          .post(
            Uri.parse(_baseUrl),
            headers: {'Content-Type': 'application/json'},
            body: body,
          )
          .timeout(const Duration(seconds: 60));

      if (response.statusCode == 200) {
        final list = jsonDecode(response.body) as List<dynamic>;
        for (final item in list) {
          final map = item as Map<String, dynamic>;
          final docId = map['documentId'] as String?;
          final result = map['result'] as Map<String, dynamic>?;
          if (docId == null || result == null) continue;

          final file = batch.where((f) => f.path == docId).firstOrNull;
          if (file == null) continue;

          file.category = result['category'] as String?;
          file.tags = (result['tags'] as List<dynamic>?)?.map((e) => e.toString()).toList();
          file.isAiAnalyzed = true;
          file.aiStatus = null;
          _updateInIsar(file);
        }
      } else if (response.statusCode == 403) {
        appLog('AiAutoTagger: Quota exceeded (403)');
        for (final file in batch) {
          file.aiStatus = 'quotaLimit';
          _updateInIsar(file);
        }
      } else {
        appLog('AiAutoTagger: API error ${response.statusCode}: ${response.body}');
        for (final file in batch) {
          file.aiStatus = 'error';
          _updateInIsar(file);
          if (!_disposed) _queue.add(file); // retry later
        }
      }
    } catch (e) {
      appLog('AiAutoTagger: Network error - $e');
      for (final file in batch) {
        file.aiStatus = 'error';
        _updateInIsar(file);
        if (!_disposed) _queue.add(file);
      }
    }
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
