# Firestore — אימות ותחזוקה

## Project ID והתאמה ל-Flutter

| מקור | Project ID |
|------|------------|
| Flutter (firebase_options.dart) | `thehunter-485508` |
| Backend (AdminFirestoreService) | `FIRESTORE_PROJECT_ID` env / ברירת מחדל `thehunter-485508` |
| deploy.yml (PROJECT_ID) | `thehunter-485508` |

**בדיקה:** ודא ש־`FIRESTORE_PROJECT_ID` ב-GitHub Secrets זהה ל־`thehunter-485508` (או לפרויקט Firebase שבו Firestore מופעל).

---

## Collections (Backend ↔ firestore.rules)

| Collection | שימוש | מי כותב |
|------------|--------|---------|
| `knowledge_base` | מונחים שנלמדו מ-AI | Flutter API → Backend |
| `users` | משתמשי Admin / רולים | Admin Dashboard |
| `logs` | לוגי חיפוש / פעילות | Backend (SearchActivityService) |
| `ranking_settings` | משקלי דירוג | Admin Dashboard |

**הערה:** אפליקציית Flutter לא ניגשת ישירות ל-Firestore — היא קוראת ל-API, והבקאנד משתמש ב-Admin SDK.

---

## Service Account ו־Permission Denied

### חובה: Cloud Datastore User
- הבקאנד רץ תחת **Cloud Run Service Account** (ברירת מחדל: `PROJECT_NUMBER-compute@developer.gserviceaccount.com`)
- **יש להעניק ל-Service Account את התפקיד:** `Cloud Datastore User` (`roles/datastore.user`)
- חלופה: `Firestore Admin` (`roles/datastore.owner`) — יותר הרשאות

### בדיקה ב-Google Cloud Console
1. IAM & Admin → IAM
2. מצא את ה-Service Account של Cloud Run (השירות the-hunter)
3. וודא ש־**Cloud Datastore User** קיים ברשימת התפקידים
4. אם חסר: לחץ Edit → Add another role → Cloud Datastore User → Save

### Permission Denied בלוגים
- הקוד ב־`AdminFirestoreService` מזהה `RpcException` עם `StatusCode.PermissionDenied`
- מודפס ל-console: `[FIRESTORE PERMISSION DENIED] operation=..., ProjectId=..., Detail=...`
- ב-Cloud Run: לוגים → חפש `FIRESTORE PERMISSION DENIED` או `PermissionDenied`

### פיתוח מקומי
- הגדר `GOOGLE_APPLICATION_CREDENTIALS` לנתיב לקובץ JSON של Service Account
- ה-Service Account חייב Firestore permissions באותו פרויקט

---

## בדיקת לוגים ב-Cloud Run

```bash
gcloud run services logs read the-hunter --region=me-west1 --limit=100
```

או: Google Cloud Console → Cloud Run → the-hunter → Logs.

חפש:
- `[FIRESTORE PERMISSION DENIED]`
- `ERROR fetching from Firestore`
- `Failed to create FirestoreDb`
