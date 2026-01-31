import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/search_intent.dart' as api;
import '../utils/smart_search_parser.dart';
import 'log_service.dart';

/// שירות חיפוש AI — ממיר שאילתות מעורפלות למונחים קונקרטיים באמצעות Gemini.
/// יש להפעיל רק כאשר תוצאות מקומיות + Drive ריקות.
class AiSearchService {
  static AiSearchService? _instance;

  AiSearchService._();

  static AiSearchService get instance {
    _instance ??= AiSearchService._();
    return _instance!;
  }

  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app';
  static const String _intentEndpoint = '/api/search/intent';
  static const Duration _timeout = Duration(seconds: 15);

  /// ממיר שאילתה מעורפלת ("kids expenses") למונחים קונקרטיים ("kindergarten", "clothes") דרך Gemini.
  /// להפעיל רק כאשר Local + Drive החזירו 0 תוצאות.
  /// מחזיר SearchIntent (parser) לשימוש ב־localSmartSearch / Drive / RelevanceEngine.
  Future<SearchIntent?> getSemanticIntent(String userQuery) async {
    if (userQuery.trim().length < 2) return null;

    try {
      appLog('AiSearch: getSemanticIntent "$userQuery"');
      final response = await http.post(
        Uri.parse('$_baseUrl$_intentEndpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'query': userQuery}),
      ).timeout(_timeout);

      if (response.statusCode != 200) {
        appLog('AiSearch: API error ${response.statusCode}: ${response.body}');
        return null;
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final apiIntent = api.SearchIntent.fromJson(json);
      if (!apiIntent.hasContent) return null;

      final parserIntent = _apiToParserIntent(userQuery, apiIntent);
      appLog('AiSearch: semantic intent -> $parserIntent');
      return parserIntent;
    } catch (e) {
      appLog('AiSearch: Exception - $e');
      return null;
    }
  }

  /// המרת SearchIntent מהבקאנד ל־SearchIntent של הפרסר (rawTerms, terms, explicitYear, dateFrom/dateTo, fileTypes)
  SearchIntent _apiToParserIntent(String userQuery, api.SearchIntent apiIntent) {
    final rawTerms = userQuery
        .trim()
        .replaceAll(RegExp(r'[^\w\s\u0590-\u05FF\-]+', unicode: true), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.isNotEmpty)
        .toList();

    String? explicitYear;
    DateTime? dateFrom;
    DateTime? dateTo;
    if (apiIntent.dateRange != null) {
      final start = apiIntent.dateRange!.startDate;
      final end = apiIntent.dateRange!.endDate;
      if (start != null) dateFrom = start;
      if (end != null) dateTo = end;
      if (start != null && end != null &&
          start.year == end.year &&
          start.month == 1 && start.day == 1 &&
          end.month == 12 && end.day == 31) {
        explicitYear = '${start.year}';
      }
    }

    return SearchIntent(
      rawTerms: rawTerms,
      terms: apiIntent.terms,
      explicitYear: explicitYear,
      dateFrom: dateFrom,
      dateTo: dateTo,
      fileTypes: apiIntent.fileTypes,
    );
  }

  /// בדיקה אם השירות זמין
  Future<bool> isAvailable() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
