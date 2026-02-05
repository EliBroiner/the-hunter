# The Hunter — Production Setup Guide

# מדריך פריסת The Hunter ל-Production

---

## 1. Firebase App Check Configuration

## 1. הגדרת Firebase App Check

### English

Firebase App Check protects your backend from unauthorized clients. Follow these steps for Android and iOS.

**Android (Play Integrity)**

1. Open [Firebase Console](https://console.firebase.google.com/) → select your project.
2. Go to **Project Settings** (gear icon) → **App Check**.
3. Click **Register** next to your Android app (or add one if missing).
4. Select **Play Integrity** as the provider.
5. Obtain your app's **SHA-256 fingerprint** (see §3).
6. Paste the SHA-256 into the registration form.
7. Enable **"Meets basic device integrity"** in [Google Play Console](https://play.google.com/console) → **Play Integrity API** if required for your region.

**iOS (App Attest)**

1. In Firebase Console → **App Check**, click **Register** for your iOS app.
2. Select **App Attest** (recommended for iOS 14+).
3. In Xcode: select your app target → **Signing & Capabilities** → **+ Capability** → add **App Attest**.
4. Save and rebuild the iOS app.

**Project Number**

- In Firebase Console → **Project Settings** (General tab).
- Copy the **Project number** (numeric, e.g. `105628026575`).
- This value is used in the backend as `FIREBASE_PROJECT_NUMBER`.

### עברית

Firebase App Check מגן על הבקאנד מפני לקוחות לא מורשים.

**Android (Play Integrity)**

1. פתח [Firebase Console](https://console.firebase.google.com/) → בחר פרויקט.
2. עבור אל **הגדרות פרויקט** → **App Check**.
3. לחץ **Register** ליד אפליקציית Android.
4. בחר **Play Integrity** כ-provider.
5. השג את **SHA-256 fingerprint** (ראה סעיף 3).
6. הדבק את SHA-256 בטופס ההרשמה.
7. הפעל **"Meets basic device integrity"** ב-Google Play Console לפי הצורך.

**iOS (App Attest)**

1. ב-Firebase Console → **App Check** → **Register** לאפליקציית iOS.
2. בחר **App Attest**.
3. ב-Xcode: הוסף **App Attest** ב-**Signing & Capabilities**.

**Project Number**

- Firebase Console → **הגדרות פרויקט** → העתק **Project number**.
- ערך זה מוגדר בבקאנד כ־`FIREBASE_PROJECT_NUMBER`.

---

## 2. Environment Variables & Secrets

## 2. משתני סביבה וסודות

### English

**Required for Backend (Cloud Run / appsettings.json)**

| Variable | Source | Purpose |
|----------|--------|---------|
| `GEMINI_API_KEY` | Secret | Gemini API for AI search and analysis |
| `FIREBASE_PROJECT_NUMBER` | Firebase Console | Validates App Check tokens |
| `ADMIN_KEY` | Secret | Protects Admin Dashboard (header `X-Admin-Key`) |
| `Admin:Key` | appsettings.json | Alternative to `ADMIN_KEY` |

**Cloud Run — Set via Console or `gcloud`**

```bash
gcloud run services update the-hunter \
  --region=me-west1 \
  --set-env-vars="FIREBASE_PROJECT_NUMBER=105628026575,GEMINI_API_KEY=your-key"
```

**appsettings.json (local / optional override)**

```json
{
  "Admin": {
    "Key": "your-secure-admin-key"
  },
  "GEMINI_API_KEY": "optional-override"
}
```

**Important**

- Do **not** commit `GEMINI_API_KEY`, `ADMIN_KEY`, or any secrets to Git.
- Add `appsettings.Development.json` and `appsettings.Production.json` to `.gitignore` if they contain secrets.
- Use Google Secret Manager or Cloud Run secrets for production.

### עברית

**נדרש לבקאנד (Cloud Run / appsettings.json)**

| משתנה | מקור | מטרה |
|-------|------|------|
| `GEMINI_API_KEY` | סוד | API של Gemini לחיפוש וניתוח |
| `FIREBASE_PROJECT_NUMBER` | Firebase Console | ולידציה של App Check tokens |
| `ADMIN_KEY` | סוד | הגנה על Admin Dashboard (header `X-Admin-Key`) |
| `Admin:Key` | appsettings.json | חלופה ל־`ADMIN_KEY` |

**Cloud Run**

```bash
gcloud run services update the-hunter \
  --region=me-west1 \
  --set-env-vars="FIREBASE_PROJECT_NUMBER=...,GEMINI_API_KEY=...,ADMIN_KEY=..."
```

**אזהרה**

- אל תעלה ל-Git את `GEMINI_API_KEY`, `ADMIN_KEY` או סודות אחרים.
- הוסף קבצי `appsettings.*.json` שמכילים סודות ל־`.gitignore`.

---

## 3. Production Signing (Flutter / Android)

## 3. חתימת Production (Flutter / Android)

### English

App Check with Play Integrity requires the **SHA-256 fingerprint** of your release keystore.

**Generate SHA-256**

```bash
keytool -list -v -keystore /path/to/your-release.keystore -alias your-key-alias
```

Enter the keystore password when prompted. Copy the **SHA256** line, e.g.:

```
SHA256: AA:BB:CC:DD:...
```

**Add to Firebase**

1. Firebase Console → **Project Settings** → **Your apps**.
2. Select the Android app.
3. Under **SHA certificate fingerprints**, click **Add fingerprint**.
4. Paste the SHA-256 (with or without colons).

**Release build with signing**

The project expects these environment variables for release signing:

- `KEYSTORE_PATH` — path to `.keystore` or `.jks`
- `KEYSTORE_PASSWORD`
- `KEY_ALIAS`
- `KEY_PASSWORD`

Set them before running `flutter build apk` or in your CI pipeline.

### עברית

App Check עם Play Integrity דורש **SHA-256 fingerprint** של ה-release keystore.

**יצירת SHA-256**

```bash
keytool -list -v -keystore /path/to/your-release.keystore -alias your-key-alias
```

העתק את שורת **SHA256**.

**הוספה ל-Firebase**

1. Firebase Console → **הגדרות פרויקט** → **Your apps**.
2. בחר אפליקציית Android.
3. תחת **SHA certificate fingerprints** → **Add fingerprint**.
4. הדבק את SHA-256.

**משתנים ל-signing:**

- `KEYSTORE_PATH`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`

---

## 4. Backend Deployment (Cloud Run)

## 4. פריסת Backend (Cloud Run)

### English

**Database**

The backend uses SQLite with `MigrateAsync()` on startup. On Cloud Run:

- The filesystem is ephemeral — the SQLite file is lost on each new instance.
- For persistent data, consider Cloud SQL (Postgres) and `ConnectionStrings:DefaultConnection`.
- For minimal setup, SQLite + migrations work for quota/usage; data resets on redeploy.

**Current flow (Program.cs)**

```csharp
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<IDbContextFactory<AppDbContext>>().CreateDbContext();
    await db.Database.MigrateAsync();
}
```

`MigrateAsync()` creates the DB and applies all migrations (LearnedTerms, RankingSettings, SearchActivities, etc.).

**Cloud Build**

The `cloudbuild.yaml` builds the Docker image and deploys to Cloud Run. Ensure:

1. `PROJECT_ID` is set (or use `$PROJECT_ID` in Cloud Build).
2. Environment variables are configured on the Cloud Run service (see §2).
3. The service has network access to Firebase and Gemini APIs.

### עברית

**מסד נתונים**

הבקאנד משתמש ב-SQLite עם `MigrateAsync()` בהפעלה. ב-Cloud Run:

- מערכת הקבצים ארעית — קובץ SQLite אובד בכל instance חדש.
- לפרסיסטנטיות השתמש ב-Cloud SQL (Postgres) ו־`ConnectionStrings:DefaultConnection`.
- להקמה מינימלית, SQLite + migrations מספיק למכסות; הנתונים מתאפסים ב-redeploy.

**הזרימה הנוכחית**

```csharp
await db.Database.MigrateAsync();
```

יוצרת את ה-DB ומריצה את כל ה-migrations.

**Cloud Build**

`cloudbuild.yaml` בונה image ומפרסם ל-Cloud Run. ודא:

1. `PROJECT_ID` מוגדר.
2. משתני סביבה מוגדרים ב-Cloud Run.
3. יש גישה לרשת עבור Firebase ו-Gemini.

---

## 5. Verification Checklist

## 5. רשימת אימות

### English

**1. X-Firebase-AppCheck header**

- Call an API endpoint that requires App Check (e.g. `/api/search/intent`, `/api/analyze-batch`) **without** the header → expect `401` with message `"App Check token required"`.
- Call **with** the header (from a real Flutter app using `FirebaseAppCheck.instance.getToken()`) → expect `200` (or appropriate success/error from the API).

**2. Admin Dashboard**

- Open `https://your-cloud-run-url/admin`.
- Without `X-Admin-Key`: expect `401 Unauthorized`.
- With header: `X-Admin-Key: your-ADMIN_KEY` → expect the dashboard UI.

**3. Health check**

- `GET /health` → should return `200` without App Check (exempt path).

### עברית

**1. כותרת X-Firebase-AppCheck**

- קריאה ל-API בלי הכותרת → צפוי `401` עם הודעה `"App Check token required"`.
- קריאה עם הכותרת מאפליקציית Flutter אמיתית → צפוי `200` (או שגיאה לוגית מהשירות).

**2. Admin Dashboard**

- פתיחת `https://your-cloud-run-url/admin`.
- בלי `X-Admin-Key` → `401`.
- עם `X-Admin-Key: your-ADMIN_KEY` → תצוגת ה-dashboard.

**3. Health check**

- `GET /health` → `200` בלי App Check (נתיב פטור).

---

## Quick Reference

## סיכום מהיר

| Item | Value |
|------|-------|
| App Check header | `X-Firebase-AppCheck` |
| Admin header | `X-Admin-Key` |
| Backend env | `FIREBASE_PROJECT_NUMBER`, `GEMINI_API_KEY`, `ADMIN_KEY` |
| Migrations | `db.Database.MigrateAsync()` on startup |
