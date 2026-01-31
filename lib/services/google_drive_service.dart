import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../models/file_metadata.dart';
import '../utils/smart_search_parser.dart';
import 'log_service.dart';
import 'relevance_engine.dart';

/// שירות לניהול אינטגרציה עם Google Drive
class GoogleDriveService {
  static GoogleDriveService? _instance;
  
  GoogleDriveService._();
  
  static GoogleDriveService get instance {
    _instance ??= GoogleDriveService._();
    return _instance!;
  }

  // לקוח ה-API של Drive
  drive.DriveApi? _driveApi;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.readonly',
    ],
  );

  /// האם השירות מחובר
  bool get isConnected => _driveApi != null;

  /// התחברות ל-Google Drive
  Future<bool> connect() async {
    try {
      appLog('Drive: Connecting...');
      
      // אם כבר מחובר ב-AuthService, נשתמש בזה
      final user = _googleSignIn.currentUser ?? await _googleSignIn.signInSilently();
      
      if (user == null) {
        // אם לא מחובר, נבקש התחברות
        final account = await _googleSignIn.signIn();
        if (account == null) return false;
      }

      // יצירת לקוח HTTP מאומת
      final authHeaders = await _googleSignIn.currentUser!.authHeaders;
      final authenticateClient = GoogleAuthClient(authHeaders);
      
      _driveApi = drive.DriveApi(authenticateClient);
      appLog('Drive: Connected successfully');
      return true;
    } catch (e) {
      appLog('Drive: Connection failed - $e');
      return false;
    }
  }

  /// התנתקות
  Future<void> disconnect() async {
    _driveApi = null;
    // לא מתנתקים מ-Google Sign In כי זה ישפיע על כל האפליקציה
    // רק מנקים את ה-API client
  }

  /// חיפוש קבצים ב-Drive — תומך ב-SearchIntent (מונחים, שנה מפורשת, MIME); מיון ב-RelevanceEngine
  /// [intent] — intent מפרסר; [query] — חיפוש פשוט כאשר אין intent
  Future<List<FileMetadata>> searchFiles({SearchIntent? intent, String? query}) async {
    if (_driveApi == null) {
      final connected = await connect();
      if (!connected) return [];
    }

    final effectiveIntent = intent ?? (query != null && query.trim().isNotEmpty
        ? SearchIntent(terms: [query.trim()], rawTerms: [query.trim()])
        : null);
    if (effectiveIntent == null) return [];

    try {
      appLog('Drive: Searching with intent: $effectiveIntent');
      final q = _buildDriveQuery(effectiveIntent);
      if (q.isEmpty) return [];

      final fileList = await _driveApi!.files.list(
        q: q,
        $fields: 'files(id, name, mimeType, size, modifiedTime, webViewLink, thumbnailLink)',
        pageSize: 100,
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return [];
      }

      // המרה ל-FileMetadata ואז מיון רלוונטיות — לא מסתמכים על orderBy של ה-API
      final list = fileList.files!.map((driveFile) {
        return FileMetadata()
          ..name = driveFile.name ?? 'Unknown'
          ..path = 'Google Drive'
          ..extension = _getExtensionFromMimeType(driveFile.mimeType, driveFile.name)
          ..size = int.tryParse(driveFile.size ?? '0') ?? 0
          ..lastModified = driveFile.modifiedTime ?? DateTime.now()
          ..addedAt = DateTime.now()
          ..isIndexed = false
          ..extractedText = null
          ..isCloud = true
          ..cloudId = driveFile.id
          ..cloudWebViewLink = driveFile.webViewLink
          ..cloudThumbnailLink = driveFile.thumbnailLink;
      }).toList();

      return RelevanceEngine.rankAndSort(list, effectiveIntent);
    } catch (e) {
      appLog('Drive: Search error - $e');
      if (e.toString().contains('401') || e.toString().contains('403')) {
        _driveApi = null;
      }
      return [];
    }
  }

  /// בונה שאילתת q ל-Drive API: trashed = false AND (terms) AND (year) AND (MIME)
  String _buildDriveQuery(SearchIntent intent) {
    final parts = <String>[];

    // תמיד: לא באשפה, לא תיקיות
    parts.add("trashed = false");
    parts.add("mimeType != 'application/vnd.google-apps.folder'");

    // מונחים — OR: (name contains 'term1' or name contains 'term2')
    if (intent.terms.isNotEmpty) {
      final escaped = intent.terms.map((t) => _escapeDriveQuery(t.trim())).where((t) => t.isNotEmpty).toList();
      if (escaped.isNotEmpty) {
        final orGroup = escaped.map((t) => "name contains '$t'").join(' or ');
        parts.add('($orGroup)');
      }
    }

    // שנה מפורשת — AND (name contains '2014' OR modifiedTime בטווח השנה)
    if (intent.explicitYear != null && intent.explicitYear!.trim().isNotEmpty) {
      final yearStr = _escapeDriveQuery(intent.explicitYear!.trim());
      final yearNum = int.tryParse(intent.explicitYear!.trim());
      if (yearNum != null) {
        final startIso = _toDriveDateTime(DateTime(yearNum, 1, 1), startOfDay: true);
        final endIso = _toDriveDateTime(DateTime(yearNum, 12, 31, 23, 59, 59), startOfDay: false);
        parts.add("(name contains '$yearStr' or (modifiedTime >= '$startIso' and modifiedTime <= '$endIso'))");
      } else {
        parts.add("name contains '$yearStr'");
      }
    } else if (intent.dateFrom != null) {
      // טווח תאריכים (ללא שנה מפורשת): modifiedTime
      final startIso = _toDriveDateTime(intent.dateFrom!, startOfDay: true);
      parts.add("modifiedTime >= '$startIso'");
      if (intent.dateTo != null) {
        final endIso = _toDriveDateTime(intent.dateTo!, startOfDay: false);
        parts.add("modifiedTime <= '$endIso'");
      }
    }

    // סוגי קבצים — MIME
    if (intent.fileTypes.isNotEmpty) {
      final mimeConditions = _fileTypesToMimeConditions(intent.fileTypes);
      if (mimeConditions.isNotEmpty) {
        parts.add('(${mimeConditions.join(' or ')})');
      }
    }

    return parts.join(' and ');
  }

  String _escapeDriveQuery(String s) => s.replaceAll("'", "\\'").replaceAll('\\', '\\\\');

  String _toDriveDateTime(DateTime dt, {required bool startOfDay}) {
    final d = startOfDay
        ? DateTime(dt.year, dt.month, dt.day, 0, 0, 0)
        : DateTime(dt.year, dt.month, dt.day, 23, 59, 59);
    return d.toUtc().toIso8601String();
  }

  static final Map<String, List<String>> _extensionToMime = {
    'pdf': ["mimeType = 'application/pdf'"],
    'jpg': ["mimeType contains 'image/'"],
    'jpeg': ["mimeType contains 'image/'"],
    'png': ["mimeType contains 'image/'"],
    'gif': ["mimeType contains 'image/'"],
    'webp': ["mimeType contains 'image/'"],
    'heic': ["mimeType contains 'image/'"],
    'bmp': ["mimeType contains 'image/'"],
    'doc': ["mimeType = 'application/msword'", "mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'", "mimeType = 'application/vnd.google-apps.document'"],
    'docx': ["mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'", "mimeType = 'application/vnd.google-apps.document'"],
    'txt': ["mimeType = 'text/plain'"],
    'rtf': ["mimeType = 'application/rtf'", "mimeType = 'text/rtf'"],
    'xls': ["mimeType = 'application/vnd.ms-excel'", "mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'", "mimeType = 'application/vnd.google-apps.spreadsheet'"],
    'xlsx': ["mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'", "mimeType = 'application/vnd.google-apps.spreadsheet'"],
    'csv': ["mimeType = 'text/csv'", "mimeType = 'application/vnd.google-apps.spreadsheet'"],
    'sheets': ["mimeType = 'application/vnd.google-apps.spreadsheet'"],
    'ppt': ["mimeType = 'application/vnd.ms-powerpoint'", "mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation'", "mimeType = 'application/vnd.google-apps.presentation'"],
    'pptx': ["mimeType = 'application/vnd.openxmlformats-officedocument.presentationml.presentation'", "mimeType = 'application/vnd.google-apps.presentation'"],
    'mp4': ["mimeType contains 'video/'"],
    'mov': ["mimeType contains 'video/'"],
    'avi': ["mimeType contains 'video/'"],
    'mkv': ["mimeType contains 'video/'"],
    'mp3': ["mimeType contains 'audio/'"],
    'm4a': ["mimeType contains 'audio/'"],
    'wav': ["mimeType contains 'audio/'"],
    'flac': ["mimeType contains 'audio/'"],
  };

  List<String> _fileTypesToMimeConditions(List<String> fileTypes) {
    final conditions = <String>{};
    for (final ext in fileTypes) {
      final key = ext.toLowerCase().trim();
      final mimes = _extensionToMime[key];
      if (mimes != null) {
        conditions.addAll(mimes);
      } else if (key == 'image' || key == 'images') {
        conditions.add("mimeType contains 'image/'");
      } else if (key == 'video' || key == 'videos') {
        conditions.add("mimeType contains 'video/'");
      } else if (key == 'audio') {
        conditions.add("mimeType contains 'audio/'");
      } else if (key == 'doc' || key == 'docs' || key == 'document') {
        conditions.add("mimeType = 'application/vnd.google-apps.document'");
        conditions.add("mimeType = 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'");
        conditions.add("mimeType = 'application/msword'");
      } else if (key == 'excel' || key == 'spreadsheet') {
        conditions.add("mimeType = 'application/vnd.google-apps.spreadsheet'");
        conditions.add("mimeType = 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet'");
      }
    }
    return conditions.toList();
  }

  /// המרת MIME type לסיומת קובץ
  String _getExtensionFromMimeType(String? mimeType, String? name) {
    if (name != null && name.contains('.')) {
      return name.split('.').last.toLowerCase();
    }
    
    switch (mimeType) {
      case 'application/vnd.google-apps.document': return 'gdoc';
      case 'application/vnd.google-apps.spreadsheet': return 'gsheet';
      case 'application/vnd.google-apps.presentation': return 'gslides';
      case 'application/pdf': return 'pdf';
      case 'image/jpeg': return 'jpg';
      case 'image/png': return 'png';
      default: return 'file';
    }
  }
}

/// לקוח HTTP פשוט שמוסיף את ה-Headers של האימות
class GoogleAuthClient extends http.BaseClient {
  final Map<String, String> _headers;
  final _client = http.Client();

  GoogleAuthClient(this._headers);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }
}
