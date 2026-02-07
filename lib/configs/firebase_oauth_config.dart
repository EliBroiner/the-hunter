/// Web Client ID (OAuth 2.0 type 3) — מ־google-services.json / Firebase Auth → Google
const String webClientId =
    '105628026575-svf97i1uurd42sluvk9oti7f1061p2uf.apps.googleusercontent.com';

/// מחזיר serverClientId רק אם הוגדר — אחרת null (Google Sign-In ישתמש בברירת מחדל).
String? get serverClientIdForGoogleSignIn =>
    webClientId.isNotEmpty && webClientId.contains('.apps.googleusercontent.com')
        ? webClientId
        : null;
