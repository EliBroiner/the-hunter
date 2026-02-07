# שרשרת המפתחות וההגדרות — The Hunter

## פרויקט נוכחי: **thehunter-485508**
- Project ID: `thehunter-485508`
- Project Number: `105628026575`

---

## 1. Flutter / Firebase (מגדיר לאן האפליקציה מתחברת)

| קובץ | תוכן |
|------|------|
| `lib/firebase_options.dart` | projectId: `thehunter-485508`, appId: `1:105628026575:android:...` |
| `android/app/google-services.json` | project_id: `thehunter-485508`, project_number: `105628026575` |

**אימות:** `projectId` ו־`messagingSenderId` (105628026575) בכל מקום.

---

## 2. כתובות הבקאנד (Cloud Run)

| שירות | URL |
|-------|-----|
| UserRolesService | `https://the-hunter-105628026575.me-west1.run.app` |
| AiAutoTaggerService | `https://the-hunter-105628026575.me-west1.run.app/api/analyze-batch` |
| KnowledgeBaseService | `https://the-hunter-105628026575.me-west1.run.app` |
| SmartSearchService | `https://the-hunter-105628026575.me-west1.run.app` |
| AiSearchService | `https://the-hunter-105628026575.me-west1.run.app` |

**אימות:** `105628026575` = project number של thehunter-485508.

---

## 3. App Check (אימות מקור הבקשות לבקאנד)

### Debug build (`flutter run` / kDebugMode)
- **Provider:** `AndroidDebugProvider`
- **טוקן:** UUID שמודפס בלוג — להדביק ב-Firebase Console → App Check → Manage debug tokens
- **Firebase:** הוסף Debug provider → הוסף את הטוקן

### Release build (APK)
- **Provider:** `AndroidPlayIntegrityProvider`
- **אין טוקן להדביק** — משתמשים ב־**SHA-256** של ה־keystore
- **Firebase:** App Check → Play Integrity → הוסף SHA-256 certificate fingerprint

### SHA של debug keystore (משמש גם release כשאין KEYSTORE_* מוגדר)
```
SHA-1:   17:F2:FC:0C:7E:0E:70:2E:76:55:F8:E1:8B:3B:26:0F:D7:51:77:44
SHA-256: A0:02:2E:AD:D0:AE:BC:3E:9D:B0:56:44:81:88:59:77:6C:D5:0A:40:B9:69:4B:02:A8:1E:90:09:29:7B:9E:22
```

**היכן להדביק ב-Firebase:**
1. Project Settings → Your apps → Android → Add fingerprint (SHA-1, SHA-256) — ל־**Google Sign-In**
2. App Check → Play Integrity → SHA-256 certificate fingerprints — ל־**App Check**

---

## 4. Firebase Auth

- **Anonymous:** הפעל ב-Firebase Console → Authentication → Sign-in method → Anonymous
- **Google Sign-In:** צריך SHA-1 (ולפי הצורך SHA-256) ב-Project Settings → Your apps → Android

---

## 5. Cloud Run (בקאנד)

| משתנה | ערך | מטרה |
|-------|-----|------|
| `FIREBASE_PROJECT_NUMBER` | `105628026575` | ולידציה של App Check tokens |
| `GEMINI_API_KEY` | (סוד) | AI search / analyze |
| `ADMIN_KEY` | (סוד) | הגנה על Admin Dashboard |
| `INITIAL_ADMIN_EMAIL` | (אופציונלי) | Bootstrap Admin ראשון |

---

## 6. RevenueCat

- **API Key:** `goog_ffZaXsWeIyIjAdbRlvAwEhwTDSZ` (מוגדר ב-`main.dart`)
- לוודא ב-RevenueCat Dashboard חיבור ל־Google Play עם package `com.thehunter.the_hunter`

---

## בעיות נפוצות

| שגיאה | סיבה | פתרון |
|-------|------|--------|
| `access_token audience is not for this project` | Token מ־Firebase project ישן | Clear app data / התקנה מחדש |
| `App attestation failed` (403) | App Check לא מוגדר נכון | הוסף SHA-256 ל-Play Integrity או Debug token ל-Debug provider |
| `401` בבקשות לבקאנד | App Check token חסר/לא תקף | תיקון App Check (ראה למעלה) |
| `invalid-credential` | SHA לא ב-Firebase | הוסף SHA-1 ו-SHA-256 ל-Project Settings → Android app |
