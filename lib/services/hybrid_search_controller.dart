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
  List<FileMetadata> _localResults = [];
  List<FileMetadata> _driveResults = [];
  bool _isLocalSearching = false;
  bool _isDriveSearching = false;
  bool _isAISearching = false;
  bool _isSmartSearchActive = false;
  SearchIntent? _lastIntent;
  String _currentQuery = '';

  /// כמות תוצאות מקומיות להצגה (פגינציה) — מתאפס בכל חיפוש חדש
  int visibleLocalCount = 10;

  List<FileMetadata> get results => List.unmodifiable(_results);
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
    _localResults = [];
    _driveResults = [];
    _isLocalSearching = false;
    _isDriveSearching = false;
    _isAISearching = false;
    _isSmartSearchActive = false;
    _lastIntent = null;
    _currentQuery = '';
  }

  /// מריץ חיפוש מלא: מקומי + Drive (מקביל); אם שניהם ריקים — AI Rescue + rankAndSort
  Future<void> executeSearch(String query) async {
    _currentQuery = query;
    _isLocalSearching = true;
    _isAISearching = false;
    _isSmartSearchActive = false;
    _lastIntent = null;
    visibleLocalCount = 10;
    notifyListeners();

    final isPro = _isPremium();
    final isSignedIn = _driveService.isConnected;
    final hasNet = _hasNetwork();
    debugPrint('User Pro: $isPro, SignedIn: $isSignedIn, Internet: $hasNet');
    final shouldSearchDrive = isPro && isSignedIn && hasNet;

    final parserIntent = parser.SmartSearchParser.parse(query);

    try {
      // שלב א (מקומי) + שלב ב (Drive) — במקביל
      _isLocalSearching = true;
      _isDriveSearching = shouldSearchDrive;
      notifyListeners();
      final localFuture = _databaseService.localSmartSearch(parserIntent);
      final driveFuture = shouldSearchDrive
          ? _driveService.searchFiles(intent: parserIntent)
          : Future<List<FileMetadata>>.value([]);

      var localResults = await localFuture;
      final driveResults = await driveFuture;
      _isLocalSearching = false;
      _isDriveSearching = false;

      // הסרת קבצים שנמחקו מהדיסק — מונע קריסה על נתיבים לא קיימים
      localResults = localResults.where((file) => file.isCloud || File(file.path).existsSync()).toList();
      _localResults = localResults;
      _driveResults = driveResults;

      // שלב ג: AI Rescue — רק אם מקומי + Drive ריקים
      if (localResults.isEmpty && driveResults.isEmpty && isPro) {
        onAILoading?.call(true);
        _isAISearching = true;
        notifyListeners();

        final semanticIntent = await AiSearchService.instance.getSemanticIntent(query);

        onAILoading?.call(false);
        _isAISearching = false;

        if (semanticIntent != null && semanticIntent.hasContent) {
          var local2 = await _databaseService.localSmartSearch(semanticIntent);
          final drive2 = shouldSearchDrive
              ? await _driveService.searchFiles(intent: semanticIntent)
              : <FileMetadata>[];
          local2 = local2.where((file) => file.isCloud || File(file.path).existsSync()).toList();
          final merged = [...local2, ...drive2];
          final combined = RelevanceEngine.rankAndSort(merged, semanticIntent);
          _localResults = local2;
          _driveResults = drive2;
          _results = combined;
          _lastIntent = _parserIntentToApi(semanticIntent);
          _isSmartSearchActive = combined.isNotEmpty;
          onResults?.call(combined, isFromAI: true);
          notifyListeners();
          return;
        }
      }

      // מיזוג ומיון — מקומי + Drive כבר ממוינים; מיישמים rankAndSort על המאוחד
      final merged = [...localResults, ...driveResults];
      _results = merged.isEmpty
          ? []
          : RelevanceEngine.rankAndSort(merged, parserIntent);
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
      _localResults = [];
      _driveResults = [];
      onResults?.call([], isFromAI: false);
      notifyListeners();
    }
  }

  void _runWaterfall(String query) async {
    await executeSearch(query);
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
