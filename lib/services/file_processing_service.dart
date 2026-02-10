import '../models/ai_analysis_response.dart';
import '../models/file_metadata.dart';
import 'ai_auto_tagger_service.dart';
import 'category_manager_service.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'utils/file_validator.dart';

/// צינור עיבוד קבצים: ולידציה → Waterfall (מילון/Regex) → AI (רק ל-PRO)
/// מתאים לעיבוד אלפי קבצים — עוצר בשקט ב-unreadable / dictionaryMatched
class FileProcessingService {
  static FileProcessingService? _instance;
  static FileProcessingService get instance {
    _instance ??= FileProcessingService._();
    return _instance!;
  }

  FileProcessingService._();

  final _db = DatabaseService.instance;
  final _validator = FileValidator.instance;
  final _aiTagger = AiAutoTaggerService.instance;
  final _categoryManager = CategoryManagerService.instance;

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
}
