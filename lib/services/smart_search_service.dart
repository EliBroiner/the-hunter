import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/search_intent.dart';
import 'app_check_http_helper.dart';
import 'log_service.dart';

/// שירות חיפוש חכם - מתקשר לבקאנד AI
class SmartSearchService {
  static SmartSearchService? _instance;
  
  SmartSearchService._();
  
  static SmartSearchService get instance {
    _instance ??= SmartSearchService._();
    return _instance!;
  }

  // כתובת הבקאנד
  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app';
  static const String _intentEndpoint = '/api/search/intent';
  static const Duration _timeout = Duration(seconds: 15);

  /// מנתח שאילתת חיפוש בשפה טבעית
  /// מחזיר SearchIntent או null אם נכשל
  Future<SearchIntent?> parseSearchQuery(String query) async {
    if (query.trim().length < 2) return null;

    try {
      appLog('SmartSearch: Sending query to API: "$query"');
      final headers = await AppCheckHttpHelper.getBackendHeaders(existing: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      });
      final response = await http.post(
        Uri.parse('$_baseUrl$_intentEndpoint'),
        headers: headers,
        body: jsonEncode({'query': query}),
      ).timeout(_timeout);

      appLog('SmartSearch: API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final intent = SearchIntent.fromJson(json);
        appLog('SmartSearch: Parsed intent - $intent');
        return intent;
      } else {
        appLog('SmartSearch: API error - ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      appLog('SmartSearch: Exception - $e');
      return null;
    }
  }

  /// בודק אם השירות זמין
  Future<bool> isAvailable() async {
    try {
      final headers = await AppCheckHttpHelper.getBackendHeaders();
      final response = await http.get(
        Uri.parse('$_baseUrl/health'),
        headers: headers,
      ).timeout(const Duration(seconds: 5));
      
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
