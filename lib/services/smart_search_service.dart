import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/search_intent.dart';
import 'log_service.dart';

/// שירות לקריאת ה-API של Gemini לפענוח שאילתות חיפוש
class SmartSearchService {
  static SmartSearchService? _instance;
  
  // כתובת ה-API - Cloud Run
  static const String _baseUrl = 'https://the-hunter-105628026575.me-west1.run.app';
  static const String _intentEndpoint = '/api/search/intent';
  
  // Timeout לבקשות
  static const Duration _timeout = Duration(seconds: 10);

  SmartSearchService._();

  static SmartSearchService get instance {
    _instance ??= SmartSearchService._();
    return _instance!;
  }

  /// שולח שאילתה ל-API ומקבל SearchIntent
  /// מחזיר null במקרה של שגיאה (fallback לחיפוש רגיל)
  Future<SearchIntent?> parseSearchQuery(String query) async {
    if (query.trim().isEmpty) {
      return null;
    }

    try {
      appLog('SmartSearch: Sending query to API: "$query"');
      
      final response = await http.post(
        Uri.parse('$_baseUrl$_intentEndpoint'),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
        body: jsonEncode({'query': query}),
      ).timeout(_timeout);

      appLog('SmartSearch: API response status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final intent = SearchIntent.fromJson(json);
        
        appLog('SmartSearch: Parsed intent - Terms: ${intent.terms}, FileTypes: ${intent.fileTypes}, DateRange: ${intent.dateRange}');
        
        return intent;
      } else {
        appLog('SmartSearch: API error - ${response.statusCode}: ${response.body}');
        return null;
      }
    } catch (e) {
      // שגיאת רשת או timeout - חוזרים לחיפוש רגיל
      appLog('SmartSearch: Exception - $e');
      return null;
    }
  }

  /// בודק אם ה-API זמין
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
