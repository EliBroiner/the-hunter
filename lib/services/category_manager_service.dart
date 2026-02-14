import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/ai_analysis_response.dart';
import '../models/smart_category.dart';
import 'app_check_http_helper.dart';
import 'knowledge_base_service.dart';
import 'log_service.dart';
import 'sync_version_utils.dart';

/// שירות קטגוריות חכמות — טעינה מ-API, העשרת תגיות, והוספת חוק (Regex/Keyword) ל-Firestore דרך השרת.
class CategoryManagerService {
  static CategoryManagerService? _instance;
  static CategoryManagerService get instance {
    _instance ??= CategoryManagerService._();
    return _instance!;
  }

  CategoryManagerService._();

  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app';
  static const String _smartCategoriesPath = '/api/smart-categories';
  static const String _prefsKeyLastSyncTimestamp = 'smart_categories_last_sync_timestamp';
  static const Duration _timeout = Duration(seconds: 15);

  final Map<String, SmartCategory> _categories = {};
  bool _loaded = false;

  /// חותמת זמן של הסנכרון האחרון (ISO8601) — מ־SharedPreferences.
  Future<String?> get lastSyncTimestamp =>
      SyncVersionUtils.getTimestamp(_prefsKeyLastSyncTimestamp);

  /// גישה לקריאה בלבד — אחרי loadCategories().
  Map<String, SmartCategory> get categories => Map.unmodifiable(_categories);

  /// בודק גרסה — אם השרת חדש יותר, טוען (סנכרון חכם). מחזיר true אם בוצע טעינה.
  Future<bool> checkVersionAndSyncIfNeeded({bool silent = false}) async {
    try {
      invalidate();
      await loadCategories();
      return true;
    } catch (e) {
      appLog('CategoryManager: checkVersionAndSyncIfNeeded error - $e');
      return false;
    }
  }

  Future<({String version, String? lastModified})?> _fetchCategoriesVersion() =>
      SyncVersionUtils.fetchVersion('$_baseUrl$_smartCategoriesPath/version');

  Future<void> _saveLastSyncTimestamp(String ts) =>
      SyncVersionUtils.saveTimestamp(_prefsKeyLastSyncTimestamp, ts);

  /// טוען קטגוריות — סנכרון חכם: בודק גרסה, מושך רק שינויים מאז lastSyncTimestamp.
  Future<void> loadCategories() async {
    try {
      final version = await _fetchCategoriesVersion();
      final localTs = await lastSyncTimestamp;

      if (_shouldDoSmartSync(version, localTs)) {
        await _doSmartSync(version!, localTs!);
        return;
      }
      if (_hasCacheAndNoUpdates(version, localTs)) {
        appLog('[SYNC] No new updates found on server. Using local cache.');
        return;
      }
      await _loadFull();
    } catch (e) {
      appLog('CategoryManager: loadCategories error - $e');
      await _loadFull();
    } finally {
      _loaded = true;
    }
  }

  bool _shouldDoSmartSync(
    ({String version, String? lastModified})? version,
    String? localTs,
  ) =>
      _loaded &&
      version?.lastModified != null &&
      localTs != null &&
      localTs.isNotEmpty &&
      SyncVersionUtils.isServerNewer(version!.lastModified!, localTs);

  bool _hasCacheAndNoUpdates(
    ({String version, String? lastModified})? version,
    String? localTs,
  ) =>
      _loaded &&
      version?.lastModified != null &&
      localTs != null &&
      localTs.isNotEmpty &&
      version!.lastModified == localTs;

  Future<void> _doSmartSync(
    ({String version, String? lastModified}) version,
    String localTs,
  ) async {
    appLog('[SYNC] מבצע סנכרון חכם. מושך רק שינויים מאז: $localTs');
    final ok = await _loadIncremental(localTs);
    if (ok && version.lastModified != null) {
      await _saveLastSyncTimestamp(version.lastModified!);
    } else {
      appLog('[SYNC] סנכרון אינקרמנטלי נכשל — מבצע טעינה מלאה.');
      await _loadFull();
    }
  }

  Future<bool> _loadIncremental(String since) async {
    try {
      final list = await _fetchCategories(since: since);
      if (list == null) return false;
      _mergeCategoriesIntoCache(list, clearFirst: false);
      appLog('CategoryManager: merged ${list.length} categories (incremental)');
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> _loadFull() async {
    final list = await _fetchCategories();
    if (list == null) return;
    _mergeCategoriesIntoCache(list, clearFirst: true);
    final version = await _fetchCategoriesVersion();
    if (version?.lastModified != null) {
      await _saveLastSyncTimestamp(version!.lastModified!);
    }
    appLog('CategoryManager: loaded ${_categories.length} categories');
  }

  Future<List<dynamic>?> _fetchCategories({String? since}) async {
    final uri = since != null
        ? Uri.parse('$_baseUrl$_smartCategoriesPath')
            .replace(queryParameters: {'since': since})
        : Uri.parse('$_baseUrl$_smartCategoriesPath');
    final headers = await AppCheckHttpHelper.getBackendHeaders();
    final r = await http.get(uri, headers: headers).timeout(_timeout);
    if (r.statusCode != 200) {
      appLog('CategoryManager: loadCategories failed ${r.statusCode}');
      return null;
    }
    return jsonDecode(r.body) as List<dynamic>? ?? [];
  }

  void _mergeCategoriesIntoCache(List<dynamic> list, {required bool clearFirst}) {
    if (clearFirst) _categories.clear();
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final cat = SmartCategory.fromJson(item);
      if (cat.id.isNotEmpty) _categories[cat.id] = cat;
    }
  }

  /// מחזיר רשימת תגיות מועשרת: id, כל ה-labels, כל ה-synonyms — לשימוש בשמירת מטא-דאטה לחיפוש.
  List<String> getEnrichedTags(String categoryId) {
    final cat = _categories[categoryId];
    if (cat == null) return [categoryId];
    final out = <String>{categoryId};
    out.addAll(cat.labels.values.where((s) => s.isNotEmpty));
    out.addAll(cat.synonyms);
    return out.toList();
  }

  /// Waterfall: קודם מילים (synonyms), אחר כך Regex, אחר כך מילון ישן (KnowledgeBase).
  /// מחזיר AiAnalysisResult עם תגיות מועשרות אם נמצאה התאמה.
  Future<AiAnalysisResult?> identifyCategory(String rawText) async {
    if (rawText.isEmpty) return null;
    await loadCategories();
    final lower = rawText.toLowerCase();

    // שלב א: התאמת מילות מפתח
    for (final entry in _categories.entries) {
      for (final syn in entry.value.synonyms) {
        if (syn.length < 2) continue;
        final useWholeWord = syn.length < 4;
        if (_synonymMatch(lower, syn, useWholeWord)) {
          appLog('CategoryManager: keyword hit "${entry.key}" for "$syn"');
          return AiAnalysisResult(category: entry.key, tags: getEnrichedTags(entry.key));
        }
      }
    }

    // שלב ב: Regex
    for (final entry in _categories.entries) {
      for (final pattern in entry.value.regexPatterns) {
        if (pattern.isEmpty) continue;
        try {
          if (RegExp(pattern).hasMatch(rawText)) {
            appLog('CategoryManager: Regex Hit: $pattern -> ${entry.key}');
            return AiAnalysisResult(category: entry.key, tags: getEnrichedTags(entry.key));
          }
        } catch (_) {}
      }
    }

    return KnowledgeBaseService.instance.findMatchingCategory(rawText);
  }

  static bool _synonymMatch(String lowerText, String term, bool useWholeWord) {
    final t = term.toLowerCase();
    if (useWholeWord) {
      final escaped = RegExp.escape(t);
      return RegExp('(^|[^\\w])$escaped([^\\w]|\$)', unicode: true, caseSensitive: false).hasMatch(lowerText);
    }
    return lowerText.contains(t);
  }

  /// מאשר הצעות Admin — מאגד suggestedKeywords ו-suggestedRegex ושולח ל-Firestore.
  /// כל המשתמשים יקבלו את החוקים החדשים בסנכרון הבא (loadCategories).
  Future<int> approveSuggestions(String categoryId, List<AiSuggestion> suggestions) async {
    if (categoryId.isEmpty || suggestions.isEmpty) return 0;
    final keywords = <String>{};
    final regexPatterns = <String>[];
    for (final s in suggestions) {
      for (final kw in s.suggestedKeywords) {
        final t = kw.trim();
        if (t.isNotEmpty) keywords.add(t);
      }
      final r = s.suggestedRegex?.trim();
      if (r != null && r.isNotEmpty && isRegexValid(r) && !regexPatterns.contains(r)) regexPatterns.add(r);
    }
    if (keywords.isEmpty && regexPatterns.isEmpty) return 0;
    try {
      final encoded = Uri.encodeComponent(categoryId);
      final uri = Uri.parse('$_baseUrl$_smartCategoriesPath/$encoded/rules/batch');
      final headers = await AppCheckHttpHelper.getBackendHeaders(
        existing: {'Content-Type': 'application/json'},
      );
      final body = jsonEncode({
        'keywords': keywords.toList(),
        'regexPatterns': regexPatterns,
      });
      final response = await http.post(uri, headers: headers, body: body).timeout(_timeout);
      if (response.statusCode != 200) {
        appLog('CategoryManager: approveSuggestions failed ${response.statusCode}');
        return 0;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final added = (decoded?['added'] as num?)?.toInt() ?? 0;
      if (added > 0) {
        invalidate();
        appLog('CategoryManager: approveSuggestions saved $added rules to $categoryId');
      }
      return added;
    } catch (e) {
      appLog('CategoryManager: approveSuggestions error - $e');
      return 0;
    }
  }

  /// מוסיף חוק (regex או keyword) לקטגוריה — שומר ב-Firestore דרך השרת.
  /// type: 'regex' | 'keyword', rule: המחרוזת (תבנית או מילה).
  Future<bool> addRuleToCategory(String categoryId, String type, String rule) async {
    if (categoryId.isEmpty || rule.trim().isEmpty) return false;
    try {
      final uri = Uri.parse('$_baseUrl$_smartCategoriesPath/$categoryId/rules');
      final headers = await AppCheckHttpHelper.getBackendHeaders(
        existing: {'Content-Type': 'application/json'},
      );
      final body = jsonEncode({'type': type, 'value': rule.trim()});
      final response = await http.post(uri, headers: headers, body: body).timeout(_timeout);
      if (response.statusCode == 200) {
        // רענון מקומי — מוסיף ל-cache בלי לטעון מחדש מהשרת
        final cat = _categories[categoryId];
        if (cat != null) {
          if (type.toLowerCase() == 'regex') {
            _categories[categoryId] = SmartCategory(
              id: cat.id,
              labels: cat.labels,
              synonyms: cat.synonyms,
              regexPatterns: [...cat.regexPatterns, rule.trim()],
            );
          } else {
            _categories[categoryId] = SmartCategory(
              id: cat.id,
              labels: cat.labels,
              synonyms: [...cat.synonyms, rule.trim()],
              regexPatterns: cat.regexPatterns,
            );
          }
        }
        return true;
      }
      appLog('CategoryManager: addRule failed ${response.statusCode}');
      return false;
    } catch (e) {
      appLog('CategoryManager: addRuleToCategory error - $e');
      return false;
    }
  }

  /// איפוס טעינה — לאלץ רענון בפעם הבאה.
  void invalidate() {
    _loaded = false;
    _categories.clear();
  }

  /// בודק אם מילת מפתח כבר קיימת בקטגוריה (להצגה בירוק / הסתרה)
  Future<bool> hasKeywordInCategory(String categoryId, String keyword) async {
    await loadCategories();
    final cat = _categories[categoryId];
    if (cat == null) return false;
    final k = keyword.trim().toLowerCase();
    return cat.synonyms.any((s) => s.trim().toLowerCase() == k);
  }

  /// בודק אם Regex כבר קיים בקטגוריה
  Future<bool> hasRegexInCategory(String categoryId, String pattern) async {
    await loadCategories();
    final cat = _categories[categoryId];
    if (cat == null) return false;
    final p = pattern.trim();
    return cat.regexPatterns.any((r) => r.trim() == p);
  }

  /// בודק אם Regex תקין (Dart) — לפני הוספה
  static bool isRegexValid(String pattern) {
    try {
      RegExp(pattern);
      return true;
    } catch (_) {
      return false;
    }
  }
}
