import '../models/file_metadata.dart';
import 'ai_auto_tagger_service.dart';
import 'database_service.dart';
import 'knowledge_base_service.dart';
import 'log_service.dart';
import 'utils/file_validator.dart';

/// צינור עיבוד קבצים: ולידציה → מילון → AI (רק ל-PRO)
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
  final _knowledgeBase = KnowledgeBaseService.instance;
  final _aiTagger = AiAutoTaggerService.instance;

  /// מריץ צינור עיבוד לפי נתיב — רק primitives (מניעת Illegal argument in isolate message)
  Future<void> processFileByPath(String filePath, {required bool isPro}) async {
    final file = _db.getFileByPath(filePath);
    if (file == null) {
      appLog('FileProcessing: קובץ לא נמצא — $filePath');
      return;
    }
    await processFile(file, isPro: isPro);
  }

  /// מריץ את צינור העיבוד על קובץ בודד (לאחר חילוץ טקסט).
  /// 1) ולידציה — אם unreadable: עדכון Isar ועצירה.
  /// 2) מילון — אם יש התאמה (>= minDictionaryMatches): שמירת תגיות, dictionaryMatched, עצירה.
  /// 3) AI — רק אם עבר ו-PRO: שליחה ל-AiAutoTaggerService.
  Future<void> processFile(FileMetadata file, {required bool isPro}) async {
    final text = file.extractedText ?? '';
    // שלב 1: ולידציה איכות
    final status = _validator.validateQuality(text);
    if (status == AnalysisStatus.unreadable) {
      file.isAiAnalyzed = false;
      file.aiStatus = 'unreadable';
      _db.updateFile(file);
      appLog('FileProcessing: unreadable — ${file.path}');
      return;
    }
    // שלב 2: מילון
    if (text.isNotEmpty) {
      final match = await _knowledgeBase.findMatchingCategory(text);
      if (match != null) {
        file.category = match.category;
        file.tags = match.tags;
        file.isAiAnalyzed = true;
        file.aiStatus = 'local_match';
        _db.updateFile(file);
        appLog('FileProcessing: dictionaryMatched — ${file.path}');
        return;
      }
    }
    // שלב 3: AI רק ל-PRO
    if (isPro) {
      await _aiTagger.addToQueue(file, skipLocalHeuristic: true);
    }
  }
}
