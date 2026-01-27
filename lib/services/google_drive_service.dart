import 'dart:async';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import '../models/file_metadata.dart';
import 'auth_service.dart';
import 'log_service.dart';

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

  /// חיפוש קבצים ב-Drive
  /// מחזיר רשימה של FileMetadata מותאמים
  Future<List<FileMetadata>> searchFiles(String query) async {
    if (_driveApi == null) {
      final connected = await connect();
      if (!connected) return [];
    }

    try {
      appLog('Drive: Searching for "$query"...');
      
      // בניית שאילתה ל-Drive API
      // מחפשים בשם הקובץ, לא באשפה, ורק קבצים (לא תיקיות)
      final q = "name contains '$query' and trashed = false and mimeType != 'application/vnd.google-apps.folder'";
      
      final fileList = await _driveApi!.files.list(
        q: q,
        $fields: 'files(id, name, mimeType, size, modifiedTime, webViewLink, thumbnailLink)',
        pageSize: 20, // הגבלה ל-20 תוצאות לביצועים
      );

      if (fileList.files == null || fileList.files!.isEmpty) {
        return [];
      }

      // המרה ל-FileMetadata
      return fileList.files!.map((driveFile) {
        return FileMetadata()
          ..name = driveFile.name ?? 'Unknown'
          ..path = 'Google Drive' // נתיב וירטואלי
          ..extension = _getExtensionFromMimeType(driveFile.mimeType, driveFile.name)
          ..size = int.tryParse(driveFile.size ?? '0') ?? 0
          ..lastModified = driveFile.modifiedTime ?? DateTime.now()
          ..addedAt = DateTime.now()
          ..isIndexed = false // לא סרקנו תוכן
          ..extractedText = null // וודא שאין טקסט מחולץ
          ..isCloud = true
          ..cloudId = driveFile.id
          ..cloudWebViewLink = driveFile.webViewLink
          ..cloudThumbnailLink = driveFile.thumbnailLink;
      }).toList();

    } catch (e) {
      appLog('Drive: Search error - $e');
      // אם השגיאה היא 401/403, אולי הטוקן פג תוקף
      if (e.toString().contains('401') || e.toString().contains('403')) {
        _driveApi = null; // נאלץ התחברות מחדש בפעם הבאה
      }
      return [];
    }
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
