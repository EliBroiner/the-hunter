import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'log_service.dart';

/// תוצאת אימות
class AuthResult {
  final bool success;
  final String? errorMessage;
  final User? user;
  
  AuthResult({
    required this.success,
    this.errorMessage,
    this.user,
  });
  
  factory AuthResult.success(User user) => AuthResult(
    success: true,
    user: user,
  );
  
  factory AuthResult.failure(String message) => AuthResult(
    success: false,
    errorMessage: message,
  );
}

/// שירות אימות - מנהל התחברות והרשמה
class AuthService {
  static AuthService? _instance;
  
  AuthService._();
  
  static AuthService get instance {
    _instance ??= AuthService._();
    return _instance!;
  }
  
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: [
      'email',
      'https://www.googleapis.com/auth/drive.readonly',
    ],
  );
  
  /// המשתמש הנוכחי
  User? get currentUser => _auth.currentUser;
  
  /// האם המשתמש מחובר
  bool get isLoggedIn => currentUser != null;
  
  /// האם המשתמש אורח (אנונימי)
  bool get isGuest => currentUser?.isAnonymous ?? false;
  
  /// Stream של מצב האימות - מתעדכן בזמן אמת
  Stream<User?> get authStateChanges => _auth.authStateChanges();
  
  /// התחברות עם Google
  Future<AuthResult> signInWithGoogle() async {
    try {
      appLog('AUTH: Starting Google Sign-In...');
      
      // פתיחת חלון התחברות Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        // המשתמש ביטל את ההתחברות
        appLog('AUTH: Google Sign-In cancelled by user');
        return AuthResult.failure('ההתחברות בוטלה');
      }
      
      // קבלת פרטי האימות
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      // יצירת credential ל-Firebase
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      // התחברות ל-Firebase
      final userCredential = await _auth.signInWithCredential(credential);
      
      appLog('AUTH: Google Sign-In successful: ${userCredential.user?.email}');
      return AuthResult.success(userCredential.user!);
      
    } on FirebaseAuthException catch (e) {
      appLog('AUTH ERROR: Firebase Auth Exception: ${e.code} - ${e.message}');
      return AuthResult.failure(_getErrorMessage(e.code));
    } catch (e) {
      appLog('AUTH ERROR: $e');
      return AuthResult.failure('שגיאה בהתחברות: $e');
    }
  }
  
  /// התחברות כאורח (אנונימי)
  Future<AuthResult> signInAnonymously() async {
    try {
      appLog('AUTH: Starting Anonymous Sign-In...');
      
      final userCredential = await _auth.signInAnonymously();
      
      appLog('AUTH: Anonymous Sign-In successful: ${userCredential.user?.uid}');
      return AuthResult.success(userCredential.user!);
      
    } on FirebaseAuthException catch (e) {
      appLog('AUTH ERROR: Firebase Auth Exception: ${e.code} - ${e.message}');
      return AuthResult.failure(_getErrorMessage(e.code));
    } catch (e) {
      appLog('AUTH ERROR: $e');
      return AuthResult.failure('שגיאה בהתחברות: $e');
    }
  }
  
  /// התנתקות
  Future<void> signOut() async {
    try {
      appLog('AUTH: Signing out...');
      
      // התנתקות מ-Google אם היה מחובר
      if (await _googleSignIn.isSignedIn()) {
        await _googleSignIn.signOut();
      }
      
      // התנתקות מ-Firebase
      await _auth.signOut();
      
      appLog('AUTH: Sign out successful');
    } catch (e) {
      appLog('AUTH ERROR: Sign out failed: $e');
    }
  }
  
  /// שדרוג חשבון אורח לחשבון Google
  Future<AuthResult> upgradeAnonymousToGoogle() async {
    try {
      if (!isGuest) {
        return AuthResult.failure('המשתמש אינו אורח');
      }
      
      appLog('AUTH: Upgrading anonymous account to Google...');
      
      // התחברות ל-Google
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      
      if (googleUser == null) {
        return AuthResult.failure('ההתחברות בוטלה');
      }
      
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      
      // קישור החשבון האנונימי לחשבון Google
      final userCredential = await currentUser!.linkWithCredential(credential);
      
      appLog('AUTH: Account upgrade successful: ${userCredential.user?.email}');
      return AuthResult.success(userCredential.user!);
      
    } on FirebaseAuthException catch (e) {
      appLog('AUTH ERROR: Account upgrade failed: ${e.code}');
      
      // אם החשבון כבר קיים, התחבר אליו במקום
      if (e.code == 'credential-already-in-use') {
        await signOut();
        return signInWithGoogle();
      }
      
      return AuthResult.failure(_getErrorMessage(e.code));
    } catch (e) {
      appLog('AUTH ERROR: $e');
      return AuthResult.failure('שגיאה בשדרוג החשבון: $e');
    }
  }
  
  /// מחזיר הודעת שגיאה בעברית
  String _getErrorMessage(String code) {
    switch (code) {
      case 'account-exists-with-different-credential':
        return 'חשבון קיים כבר עם אימייל זה';
      case 'invalid-credential':
        return 'פרטי ההתחברות לא תקינים';
      case 'operation-not-allowed':
        return 'שיטת התחברות זו לא מופעלת';
      case 'user-disabled':
        return 'החשבון הושעה';
      case 'user-not-found':
        return 'המשתמש לא נמצא';
      case 'wrong-password':
        return 'סיסמה שגויה';
      case 'network-request-failed':
        return 'בעיית רשת. בדוק את החיבור לאינטרנט';
      case 'too-many-requests':
        return 'יותר מדי ניסיונות. נסה שוב מאוחר יותר';
      case 'credential-already-in-use':
        return 'החשבון כבר משויך למשתמש אחר';
      default:
        return 'שגיאה בהתחברות ($code)';
    }
  }
}
