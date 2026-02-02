import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/file_metadata.dart';
import '../models/search_intent.dart';
import '../utils/smart_search_parser.dart' as parser;
import 'ai_search_service.dart';
import 'database_service.dart';
import 'google_drive_service.dart';
import 'log_service.dart';
import 'relevance_engine.dart';
import 'search_result_cleanup.dart';

/// קונטרולר חיפוש: מקומי + Drive במקביל; אם שניהם ריקים — AI Rescue + RelevanceEngine
class HybridSearchController extends ChangeNotifier {
  HybridSearchController({
    required DatabaseService databaseService,
    required GoogleDriveService driveService,
    Duration debounceDuration = const Duration(milliseconds: 800),
    required bool Function() isPremium,
    bool Function()? hasNetwork,
  })  : _databaseService = databaseService,
        _driveService = driveService,
        _debounceDuration = debounceDuration,
        _isPremium = isPremium,
        _hasNetwork = hasNetwork ?? (() => true);

  final DatabaseService _databaseService;
  final GoogleDriveService _driveService;
  final Duration _debounceDuration;
  final bool Function() _isPremium;
  final bool Function() _hasNetwork;

  Timer? _debounceTimer;

  List<FileMetadata> _results = [];
  List<FileMetadata> _primaryResults = [];
  List<FileMetadata> _secondaryResults = [];
  List<FileMetadata> _localResults = [];
  List<FileMetadata> _driveResults = [];
  bool _isLocalSearching = false;
  bool _isDriveSearching = false;
  bool _isAISearching = false;
  bool _isSmartSearchActive = false;
  SearchIntent? _lastIntent;
  String _currentQuery = '';
  /// 0 = All (מקומי תמיד; Drive רק אם אין תוצאות מקומיות), 1 = Local (מקומי בלבד), 2 = Drive (מקומי + Drive במקביל)
  int _activeTab = 0;

  /// פילטרים מהממשק — תאריכים וסוג קובץ (PDF/Images) — ממוזגים ל־intent בכל חיפוש
  DateTime? _uiDateFrom;
  DateTime? _uiDateTo;
  List<String>? _uiFileTypes;

  /// כמות תוצאות מקומיות להצגה (פגינציה) — מתאפס בכל חיפוש חדש
  int visibleLocalCount = 10;

  List<FileMetadata> get results => List.unmodifiable(_results);
  /// תוצאות עם ציון >= 70% מהמקסימלי (להצגה ראשונית)
  List<FileMetadata> get primaryResults => List.unmodifiable(_primaryResults);
  /// תוצאות עם ציון < 70% (מוסתרות מאחורי "הצג עוד")
  List<FileMetadata> get secondaryResults => List.unmodifiable(_secondaryResults);
  List<FileMetadata> get localResults => List.unmodifiable(_localResults);
  List<FileMetadata> get driveResults => List.unmodifiable(_driveResults);
  bool get isLocalSearching => _isLocalSearching;
  bool get isDriveSearching => _isDriveSearching;
  bool get isAISearching => _isAISearching;

  /// מוסיף תוצאות מקומיות להצגה (פגינציה)
  void showMoreLocal() {
    visibleLocalCount += 10;
    notifyListeners();
  }
  bool get isSmartSearchActive => _isSmartSearchActive;
  SearchIntent? get lastIntent => _lastIntent;
  String get currentQuery => _currentQuery;
  int get activeTab => _activeTab;

  /// עדכון טאב תוצאות: 0 = All, 1 = Local, 2 = Drive — משפיע על executeSearch הבא
  void setActiveTab(int index) {
    if (_activeTab == index) return;
    _activeTab = index.clamp(0, 2);
    notifyListeners();
  }

  /// מגדיר פילטרים מהממשק (תאריכים, סוג קובץ) — משמשים באיחוד עם parser intent
  void setUiFilters({DateTime? dateFrom, DateTime? dateTo, List<String>? fileTypes}) {
    _uiDateFrom = dateFrom;
    _uiDateTo = dateTo;
    _uiFileTypes = fileTypes;
  }

  /// מחזיר intent ממוזג: parser + פילטרי UI (תאריכים, סוג קובץ)
  parser.SearchIntent _mergeUiFilters(parser.SearchIntent parserIntent) {
    final dateFrom = _uiDateFrom ?? parserIntent.dateFrom;
    final dateTo = _uiDateTo ?? parserIntent.dateTo;
    final useDateRange = (_uiDateFrom != null || _uiDateTo != null) || parserIntent.useDateRangeFilter;
    final fileTypes = (_uiFileTypes != null && _uiFileTypes!.isNotEmpty)
        ? _uiFileTypes!
        : parserIntent.fileTypes;
    if (dateFrom == parserIntent.dateFrom &&
        dateTo == parserIntent.dateTo &&
        useDateRange == parserIntent.useDateRangeFilter &&
        fileTypes == parserIntent.fileTypes) {
      return parserIntent;
    }
    return parser.SearchIntent(
      rawTerms: parserIntent.rawTerms,
      terms: parserIntent.terms,
      explicitYear: parserIntent.explicitYear,
      dateFrom: dateFrom,
      dateTo: dateTo,
      useDateRangeFilter: useDateRange,
      fileTypes: fileTypes,
    );
  }

  /// מריץ חיפוש עכשיו (ביטול debounce) — לשימוש כשמשנים פילטר/תאריך
  Future<void> runSearchNow() async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    final q = _currentQuery.trim();
    if (q.length >= 2) await executeSearch(q);
  }

  /// Callback לתוצאות סופיות (מקומי או AI)
  void Function(List<FileMetadata> results, {required bool isFromAI})? onResults;

  /// Callback כשמתחיל/נגמר AI loading
  void Function(bool isLoading)? onAILoading;

  /// עיבוד שינוי טקסט — debounce ואז waterfall
  void onQueryChanged(String query) {
    _debounceTimer?.cancel();

    final trimmed = query.trim();
    if (trimmed.length < 2) {
      _resetState();
      onResults?.call([], isFromAI: false);
      notifyListeners();
      return;
    }

    _debounceTimer = Timer(_debounceDuration, () => _runWaterfall(trimmed));
  }

  /// מאפס מצב ומבטל טיימר
  void cancel() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _resetState();
    notifyListeners();
  }

  void _resetState() {
    _results = [];
    _primaryResults = [];
    _secondaryResults = [];
    _localResults = [];
    _driveResults = [];
    _isLocalSearching = false;
    _isDriveSearching = false;
    _isAISearching = false;
    _isSmartSearchActive = false;
    _lastIntent = null;
    _currentQuery = '';
  }

  /// מריץ חיפוש: מקומי תמיד (baseline); Drive לפי טאב — All: רק אם מקומי ריק, Local: לא, Drive: במקביל
  Future<void> executeSearch(String query) async {
    _currentQuery = query;
    _isAISearching = false;
    _isSmartSearchActive = false;
    _lastIntent = null;
    visibleLocalCount = 10;
    notifyListeners();

    final isPro = _isPremium();
    final hasNet = _hasNetwork();
    if (isPro && !_driveService.isConnected) {
      await _driveService.restoreSessionIfPossible();
      if (!_driveService.isConnected && hasNet) {
        final connected = await _driveService.connect();
        if (connected) {
          await executeSearch(query);
          return;
        }
      }
    }
    final isSignedIn = _driveService.isConnected;
    final shouldSearchDrive = isPro && isSignedIn && hasNet;
    final parserIntent = await parser.SmartSearchParser.parseAsync(query);
    final effectiveIntent = _mergeUiFilters(parserIntent);

    try {
      // כלל: חיפוש מקומי תמיד רץ (baseline) — לעולם לא מדלגים
      final runDriveParallel = _activeTab == 2 && shouldSearchDrive; // טאב Drive: מקומי + Drive במקביל
      final runDriveAfterEmpty = _activeTab == 0 && shouldSearchDrive; // טאב All: Drive רק אם מקומי ריק

      _isLocalSearching = true;
      _isDriveSearching = runDriveParallel;
      notifyListeners();

      final localFuture = _databaseService.localSmartSearch(effectiveIntent);
      final driveFuture = runDriveParallel
          ? _driveService.searchFiles(intent: effectiveIntent)
          : Future<List<FileMetadata>>.value(<FileMetadata>[]);

      var localResults = await localFuture;
      localResults = localResults.where((file) => file.isCloud || File(file.path).existsSync()).toList();
      _localResults = localResults;
      _isLocalSearching = false;

      var driveResults = await driveFuture;
      if (runDriveAfterEmpty && localResults.isEmpty) {
        _isDriveSearching = true;
        notifyListeners();
        driveResults = await _driveService.searchFiles(intent: effectiveIntent);
      }
      _isDriveSearching = false;
      _driveResults = driveResults;

      // שלב ג: AI Rescue — רק אם מקומי + Drive ריקים, פרימיום, ויש רשת; לא Drive כשטאב Local
      if (localResults.isEmpty && driveResults.isEmpty && isPro && hasNet) {
        onAILoading?.call(true);
        _isAISearching = true;
        notifyListeners();

        final semanticIntent = await AiSearchService.instance.getSemanticIntent(query);

        onAILoading?.call(false);
        _isAISearching = false;

        if (semanticIntent != null && semanticIntent.hasContent) {
          final mergedSemantic = _mergeUiFilters(semanticIntent);
          var local2 = await _databaseService.localSmartSearch(mergedSemantic);
          final drive2 = (shouldSearchDrive && _activeTab != 1)
              ? await _driveService.searchFiles(intent: mergedSemantic)
              : <FileMetadata>[];
          local2 = local2.where((file) => file.isCloud || File(file.path).existsSync()).toList();
          final merged = [...local2, ...drive2];
          final cleaned = SearchResultCleanup.deduplicateAndFilter(merged);
          var combined = RelevanceEngine.rankAndSort(cleaned, mergedSemantic);
          combined = _applyDynamicGapFilter(combined);
          _localResults = local2;
          _driveResults = drive2;
          _results = combined;
          _splitPrimarySecondary();
          _lastIntent = _parserIntentToApi(mergedSemantic);
          _isSmartSearchActive = combined.isNotEmpty;
          onResults?.call(combined, isFromAI: true);
          notifyListeners();
          return;
        }
      }

      // מיזוג, סינון/דה־דופ, מיון — מקומי + Drive; אחר כך rankAndSort + קליפינג (כולל Drive)
      final merged = [...localResults, ...driveResults];
      final cleaned = SearchResultCleanup.deduplicateAndFilter(merged);
      var ranked = cleaned.isEmpty
          ? <FileMetadata>[]
          : RelevanceEngine.rankAndSort(cleaned, effectiveIntent);
      _results = _applyDynamicGapFilter(ranked);
      _splitPrimarySecondary();
      _isSmartSearchActive = _results.isNotEmpty;
      onResults?.call(_results, isFromAI: false);
      notifyListeners();
    } catch (e) {
      appLog('HybridSearch ERROR: $e');
      onAILoading?.call(false);
      _isLocalSearching = false;
      _isDriveSearching = false;
      _isAISearching = false;
      _results = [];
      _primaryResults = [];
      _secondaryResults = [];
      _localResults = [];
      _driveResults = [];
      onResults?.call([], isFromAI: false);
      notifyListeners();
    }
  }

  void _runWaterfall(String query) async {
    await executeSearch(query);
  }

  /// חיפוש Drive בלבד — לשימוש: מעבר לטאב Drive או לחיצה על "חפש ב-Drive"; ממזג עם _localResults הקיימים; מכבד פילטרי UI
  Future<void> executeDriveSearchOnly(String query) async {
    _currentQuery = query;
    final isPro = _isPremium();
    final hasNet = _hasNetwork();
    final parserIntent = await parser.SmartSearchParser.parseAsync(query);
    final effectiveIntent = _mergeUiFilters(parserIntent);
    if (!isPro || !_driveService.isConnected || !hasNet) {
      _driveResults = [];
      _results = List<FileMetadata>.from(_localResults);
      if (_results.isNotEmpty) {
        _results = _applyDynamicGapFilter(RelevanceEngine.rankAndSort(_results, effectiveIntent));
      }
      _splitPrimarySecondary();
      onResults?.call(_results, isFromAI: false);
      notifyListeners();
      return;
    }
    _isDriveSearching = true;
    notifyListeners();
    try {
      final driveResults = await _driveService.searchFiles(intent: effectiveIntent);
      _driveResults = driveResults;
      final merged = [..._localResults, ...driveResults];
      final cleaned = SearchResultCleanup.deduplicateAndFilter(merged);
      var ranked = RelevanceEngine.rankAndSort(cleaned, effectiveIntent);
      _results = _applyDynamicGapFilter(ranked);
      _splitPrimarySecondary();
      _isSmartSearchActive = _results.isNotEmpty;
      onResults?.call(_results, isFromAI: false);
    } catch (e) {
      appLog('HybridSearch DriveOnly ERROR: $e');
      _driveResults = [];
      _results = List<FileMetadata>.from(_localResults);
      if (_results.isNotEmpty) {
        _results = _applyDynamicGapFilter(RelevanceEngine.rankAndSort(_results, effectiveIntent));
      }
      _splitPrimarySecondary();
      onResults?.call(_results, isFromAI: false);
    } finally {
      _isDriveSearching = false;
      notifyListeners();
    }
  }

  /// קליפינג סופי: כלל פער (>50% צניחה), סף מינימלי (50), סינון רעש (top>80 → הסתר <10); שומר תוצאות Drive שנפלו
  static const double _gapRatioThreshold = 0.5;
  static const double _minScoreThreshold = 50.0;
  static const double _strongMatchThreshold = 150.0;
  static const double _topScoreNoiseGate = 80.0;
  static const double _noiseFilterThreshold = 10.0;
  static const double _drivePreserveMinScore = 20.0;
  static const int _drivePreserveMaxCount = 15;

  static List<FileMetadata> _applyDynamicGapFilter(List<FileMetadata> results) {
    if (results.isEmpty) return results;
    final list = List<FileMetadata>.from(results)
      ..sort((a, b) => (b.debugScore ?? 0).compareTo(a.debugScore ?? 0));
    final clippedSet = <String>{};

    // כלל פער: ברגע שציון יורד ביותר מ־50% מהקודם — זורקים מהנקודה הזו והלאה
    int keepCount = list.length;
    for (int i = 1; i < list.length; i++) {
      final prev = list[i - 1].debugScore ?? 0;
      final curr = list[i].debugScore ?? 0;
      if (prev > 0 && curr < prev * _gapRatioThreshold) {
        keepCount = i;
        break;
      }
    }
    var clipped = list.sublist(0, keepCount);
    for (final f in clipped) clippedSet.add(f.path + (f.cloudId ?? ''));

    // סף מוחלט: אם יש התאמות חזקות (150+) — מסירים תוצאות מתחת ל־50
    final hasStrongMatch = clipped.any((f) => (f.debugScore ?? 0) >= _strongMatchThreshold);
    if (hasStrongMatch) {
      clipped = clipped.where((f) => (f.debugScore ?? 0) >= _minScoreThreshold).toList();
      clippedSet.clear();
      for (final f in clipped) clippedSet.add(f.path + (f.cloudId ?? ''));
    }

    // סינון רעש: אם התוצאה הראשונה > 80 — מסירים תוצאות עם ציון < 10
    if (clipped.isNotEmpty && (clipped.first.debugScore ?? 0) > _topScoreNoiseGate) {
      clipped = clipped.where((f) => (f.debugScore ?? 0) >= _noiseFilterThreshold).toList();
      clippedSet.clear();
      for (final f in clipped) clippedSet.add(f.path + (f.cloudId ?? ''));
    }

    // שימור Drive: תוצאות ענן שנפלו אבל ציון >= 20 — מחזירים עד 15 כדי שלא ייעלמו
    final droppedDrive = list
        .where((f) => f.isCloud && !clippedSet.contains(f.path + (f.cloudId ?? '')) && (f.debugScore ?? 0) >= _drivePreserveMinScore)
        .toList()
      ..sort((a, b) => (b.debugScore ?? 0).compareTo(a.debugScore ?? 0));
    final toAdd = droppedDrive.take(_drivePreserveMaxCount).toList();
    if (toAdd.isNotEmpty) {
      clipped = [...clipped, ...toAdd];
      clipped.sort((a, b) => (b.debugScore ?? 0).compareTo(a.debugScore ?? 0));
    }

    final dropped = list.length - clipped.length;
    if (dropped > 0) {
      appLog('[Search] Clipping: Keeping top ${clipped.length} results, dropping $dropped results due to score gap.');
    }
    return clipped;
  }

  /// פיצול ל־Primary (ציון >= 70% מהמקסימלי) ו־Secondary (השאר) — להצגה עם "הצג עוד"
  void _splitPrimarySecondary() {
    if (_results.isEmpty) {
      _primaryResults = [];
      _secondaryResults = [];
      return;
    }
    final maxScore = _results.first.debugScore ?? 0;
    final cutoff = maxScore * 0.7;
    _primaryResults = _results.where((f) => (f.debugScore ?? 0) >= cutoff).toList();
    _secondaryResults = _results.where((f) => (f.debugScore ?? 0) < cutoff).toList();
  }

  /// המרת parser SearchIntent ל־API SearchIntent (לשימוש ב־lastIntent / תצוגה)
  SearchIntent _parserIntentToApi(parser.SearchIntent p) {
    return SearchIntent(
      terms: p.terms,
      fileTypes: p.fileTypes,
      dateRange: p.dateFrom != null
          ? DateRange(
              start: '${p.dateFrom!.year}-${p.dateFrom!.month.toString().padLeft(2, '0')}-${p.dateFrom!.day.toString().padLeft(2, '0')}',
              end: p.dateTo != null
                  ? '${p.dateTo!.year}-${p.dateTo!.month.toString().padLeft(2, '0')}-${p.dateTo!.day.toString().padLeft(2, '0')}'
                  : null,
            )
          : null,
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
