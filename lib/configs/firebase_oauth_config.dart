/// Web Client ID (OAuth 2.0 type 3) עבור Google Sign-In עם Firebase Auth.
///
/// איפה להשיג:
/// 1. Google Cloud Console → thehunter-485508 → APIs & Services → Credentials
/// 2. חפש "Web client (auto created by Google Service)" תחת OAuth 2.0 Client IDs
/// 3. העתק את ה-Client ID (פורמט: XXXXX-XXXXX.apps.googleusercontent.com)
///
/// אם oauth_client ב-google-services.json ריק — הוסף כאן כדי לפתור "invalid-credential" (audience mismatch).
/// הערֵך 'REPLACE_ME' במזהה האמיתי — או השאר ריק לשימוש בברירת מחדל.
const String webClientId = '105628026575-svf97i1uurd42sluvk9oti7f1061p2uf.apps.googleusercontent.com';

/// מחזיר serverClientId רק אם הוגדר — אחרת null (Google Sign-In ישתמש בברירת מחדל).
String? get serverClientIdForGoogleSignIn =>
    webClientId.isNotEmpty && webClientId.contains('.apps.googleusercontent.com')
        ? webClientId
        : null;
