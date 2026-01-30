import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/file_metadata.dart';
import '../models/search_intent.dart';
import 'database_service.dart';
import 'log_service.dart';
import 'smart_search_service.dart';

/// קונטרולר חיפוש היברידי: מקומי קודם, AI כ-fallback
/// Debounce + Waterfall: localSmartSearch → אם ריק, AI → searchByIntent
class HybridSearchController extends ChangeNotifier {
  HybridSearchController({
    required DatabaseService databaseService,
    required SmartSearchService smartSearchService,
    Duration debounceDuration = const Duration(milliseconds: 800),
    required bool Function() isPremium,
  })  : _databaseService = databaseService,
        _smartSearchService = smartSearchService,
        _debounceDuration = debounceDuration,
        _isPremium = isPremium;

  final DatabaseService _databaseService;
  final SmartSearchService _smartSearchService;
  final Duration _debounceDuration;
  final bool Function() _isPremium;

  Timer? _debounceTimer;

  List<FileMetadata> _results = [];
  bool _isLocalSearching = false;
  bool _isAISearching = false;
  bool _isSmartSearchActive = false;
  SearchIntent? _lastIntent;
  String _currentQuery = '';

  List<FileMetadata> get results => List.unmodifiable(_results);
  bool get isLocalSearching => _isLocalSearching;
  bool get isAISearching => _isAISearching;
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
    _isLocalSearching = false;
    _isAISearching = false;
    _isSmartSearchActive = false;
    _lastIntent = null;
    _currentQuery = '';
  }

  Future<void> _runWaterfall(String query) async {
    _currentQuery = query;
    _isLocalSearching = true;
    _isAISearching = false;
    _isSmartSearchActive = false;
    _lastIntent = null;
    notifyListeners();

    try {
      // שלב א: חיפוש מקומי מהיר
      final localResults = await _databaseService.localSmartSearch(query);
      _isLocalSearching = false;

      if (localResults.isNotEmpty) {
        _results = localResults;
        _isSmartSearchActive = true;
        onResults?.call(localResults, isFromAI: false);
        notifyListeners();
        return;
      }

      // שלב ב: fallback ל-AI — רק אם 0 תוצאות מקומיות + פרימיום
      if (!_isPremium()) {
        _results = [];
        onResults?.call([], isFromAI: false);
        notifyListeners();
        return;
      }

      onAILoading?.call(true);
      _isAISearching = true;
      notifyListeners();

      final intent = await _smartSearchService.parseSearchQuery(query);

      onAILoading?.call(false);
      _isAISearching = false;

      if (intent == null || !intent.hasContent) {
        _results = [];
        onResults?.call([], isFromAI: true);
        notifyListeners();
        return;
      }

      // שלב ג: חיפוש ב-DB לפי Intent מה-AI
      final aiResults = await _databaseService.searchByIntent(intent);
      _lastIntent = intent;
      _results = aiResults;
      _isSmartSearchActive = true;
      onResults?.call(aiResults, isFromAI: true);
      notifyListeners();
    } catch (e) {
      appLog('HybridSearch ERROR: $e');
      onAILoading?.call(false);
      _isLocalSearching = false;
      _isAISearching = false;
      _results = [];
      onResults?.call([], isFromAI: false);
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }
}
