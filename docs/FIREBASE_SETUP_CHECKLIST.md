# Firebase Setup Checklist — תיקון invalid-credential ו-App Check 403

## 1. Web Client ID (תיקון Audience Mismatch)

**הבעיה:** `oauth_client` ב-`google-services.json` ריק → "invalid-credential" / "access_token audience is not for this project"

**פתרון:**

1. עבור ל-[Google Cloud Console](https://console.cloud.google.com/) → בחר פרויקט **thehunter-485508**
2. APIs & Services → **Credentials**
3. תחת OAuth 2.0 Client IDs — חפש **"Web client (auto created by Google Service)"**
4. העתק את ה-**Client ID** (פורמט: `105628026575-xxxxx.apps.googleusercontent.com`)
5. הדבק ב-`lib/configs/firebase_oauth_config.dart`:

```dart
const String webClientId = '105628026575-xxxxxxxx.apps.googleusercontent.com';  // המזהה האמיתי
```

---

## 2. App Check Debug Token (תיקון 403)

**הבעיה:** App Check 403 — הטוקן לא רשום ב-Firebase

**פתרון:**

1. הרץ את האפליקציה — חפש בלוג: `🚀 SUCCESS! APP CHECK DEBUG TOKEN: xxxxx`
2. העתק את הטוקן
3. Firebase Console → App Check → **Manage debug tokens** → Add
4. הדבק את הטוקן

---

## 3. אימות הגדרות

| רכיב | ערך נדרש | מיקום |
|------|-----------|-------|
| projectId | `thehunter-485508` | firebase_options.dart, google-services.json |
| applicationId | `com.thehunter.the_hunter` | build.gradle.kts, google-services.json |
| Web Client ID | `*.apps.googleusercontent.com` | firebase_oauth_config.dart |

---

## 4. לאחר שינויים

```bash
flutter clean
flutter pub get
```
