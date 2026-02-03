# The Hunter

**Find anything. Search by name, content, or meaning.**

---

## תיאור מפורט בעברית

**The Hunter** היא אפליקציית חיפוש וניהול קבצים חכמה למובייל. היא הופכת את המכשיר לארכיון חיפושי: סריקת תיקיות נבחרות, אינדוקס תוכן באמצעות OCR ו-AI, ומציאת קבצים בשניות — לפי שם, תוכן או משמעות.

### מנוע החיפוש (Search Intelligence)

מנוע **הרלוונטיות** (`relevance_engine.dart`) מחשב ציון אחד לכל קובץ וממיין את התוצאות כך שההתאמות הטובות ביותר עולות לראש.

- **משקלים:** שם קובץ — **200 נקודות**; תוכן (טקסט מחולץ) — **עד 120 נקודות**; נתיב תיקייה — **80 נקודות**.
- **לוגיקת "פער חכם" (Smart Gap):** אם *כל* מונחי השאילתה נמצאו — הציון מוכפל ב-**1.2** ומוסיפים **+50**. אם פחות ממחצית התאימו — קנס **×0.2**. בונוס סמיכות: זוגות מונחים שמופיעים רצוף בתוכן (+25 לכל זוג, מקסימום 4). בונוס ביטוי מדויק (+150), מטאדאטת AI (+80), קנסות לשמות מערכת (GUID, pdf.123).
- **ניתוח דירוג (X-Ray):** בממשק אפשר לראות פירוט ציון (למשל Fn(200), Content(60), Adj(2), MultiWord(x1.2+50)) — למה קובץ דורג כפי שדורג.

### OCR ויזואלי ל-PDF עברי (Hebrew Visual OCR)

קובצי PDF בעברית (ו-RTL אחרים) לא פעם מחזירים **ג'יבריש** (למשל `ãåîò`) בחילוץ טקסט ישיר. האפליקציה פותרת את זה עם **צינור היברידי**:

1. חילוץ טקסט משכבת הטקסט (Syncfusion).
2. בדיקת איכות: אם מעל **30%** תווים "זבל" — התוצאה לא אמינה.
3. **גיבוי — OCR ויזואלי:** דף ראשון **מרונדר לתמונה** (pdfx) ונשלח ל-**Google ML Kit Text Recognition**. התוצאה — טקסט עברי (ולטיני) קריא.

מימוש: `text_extraction_service.dart` (חילוץ ב-Isolate → בדיקת ג'יבריש → `_extractPdfViaOcr` בעת הצורך).

### אינטגרציית AI ומסנן ג'יבריש

- **Google Gemini:** הטקסט המחולץ (ובאופציה שמות קבצים) נשלח לבקאנד שמשתמש ב-**Gemini** להציע **קטגוריה** ו**תגיות** (למשל חשבונית, חוזה, אישי). התוצאות נשמרות מקומית ומשמשות לתצוגה ולדירוג.
- **מסנן ג'יבריש:** לפני שליחה ל-AI, האפליקציה בודקת איכות OCR (`extracted_text_quality.dart`). אם מעל **30%** מהתווים "זבל" — הטקסט **לא** נשלח לתיוג. זה מונע **הזיות AI** (למשל תגיות שגויות כמו "army" או "idf" מ-OCR מקולקל). **ניקוי** בהגדרות מנקה תגיות AI ישנות שגויות ומחזיר קבצים לאינדוקס מחדש.

### PRO ו-RevenueCat

- **מועדפים:** מערכת **המועדפים** בכותרת (אייקון כוכב ליד הגדרות). משתמשי PRO: לחיצה מפעילה/מבטלת סינון מועדפים; כוכב **זהב** כשפעיל; תג עם מספר. לא-PRO: אייקון מנעול; לחיצה פותחת מסך **שדרג ל-PRO**.
- **מוניטיזציה:** מנויים מנוהלים דרך **RevenueCat**. האפליקציה שולפת חבילות (חודשי/שנתי), רוכשת דרך Google Play Billing, ומשחזרת רכישות. Entitlements (למשל pro / premium) שולטים בתכונות PRO (מועדפים, תגיות, תיקייה מאובטחת, ענן, חיפוש קולי).

### ממשק ומצב בהיר/כהה

- **ערכת נושא:** תמיכה מלאה ב**מצב בהיר / כהה** והתאמה לערכת המערכת. מסכי מנוי וגיבוי משתמשים בצבעי ערכת הנושא (לא כחול כהה קבוע).
- **ניתוח דירוג (X-Ray):** תצוגה אופציונלית שמראה למה קובץ דורג — פירוט ציון (שם, תוכן, נתיב, סמיכות, רב־מילים, ביטוי מדויק, AI).

### הדגשים להעברה לפרודקשן (Production & Google Play)

**מה חסר לפתח לפני פרודקשן**

- **טסטים:** unit / widget / integration לזרימות קריטיות (חיפוש, דירוג, חילוץ טקסט, OCR היברידי, תיוג AI, מכסה).
- **סודות:** לוודא שכל מפתחות API (Firebase, RevenueCat, בקאנד) לא בקוד — רק דרך environment / Secrets (GitHub Secrets, Cloud Run env).
- **גרסאות ו־Release notes:** ניהול גרסה עקבי (`pubspec.yaml`, `versionCode` ב־Android); תיאור שינויים בעברית/אנגלית לכל העלאה.
- **מדיניות פרטיות ותנאי שימוש:** דף או קישור — חובה ל־Play Store ולמנויים.
- **טיפול בשגיאות:** התנהגות מסודרת כש־בקאנד לא זמין, מכסה נגמרת, או RevenueCat מחזיר שגיאה (הודעות ברורות, לא קריסות).
- **אופטימיזציה:** בדיקת ביצועים על מכשירים חלשים; ProGuard/R8 אם צריך.

**העלאת האפליקציה ל־Google Play**

- **חשבון מפתח:** חשבון Google Play Developer (תשלום רישום חד־פעמי).
- **חתימת Release:** יצירת **upload keystore** (JKS), שמירה במקום מאובטח. ב־GitHub Actions: למלא Secrets — `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` — ולבנות APK חתום (`flutter build apk --release`). להפעיל **Google Play App Signing** ב־Play Console.
- **Store listing:** כותרת, תיאור קצר וארוך (עברית + אנגלית), צילומי מסך, אייקון 512×512. דירוג תוכן (Content rating). קישור למדיניות פרטיות.
- **הרשאות:** אם משתמשים ב-**גישה לכל הקבצים** (MANAGE_EXTERNAL_STORAGE) — Google Play דורש **Video Declaration**: סרטון קצר שמסביר *למה* נדרשת ההרשאה ואיך המשתמש נהנה. **טיפ:** בסרטון להראות במפורש **חיפוש בתוך תוכן** (OCR) — למשל: פתיחת מסמך PDF או תמונה, הקלדת מילה שמופיעה *בתוך* המסמך בחיפוש, והצגת התוצאה. כך מוכיחים שהגישה לקבצים נחוצה לחיפוש עמוק בתוכן, ולא רק לשמות קבצים. להעלות ב־Play Console (תוכן האפליקציה → הרשאות רגישות). בהצגת החנות להסביר בשפה פשוטה למה נדרשת גישה לקבצים (למשל "לחיפוש בתוך המסמכים והתמונות שלך").
- **מנויים:** חיבור **Google Play Billing** ל־RevenueCat; הגדרת מוצרים (חודשי/שנתי) ב־Play Console ו־RevenueCat עם מזהים תואמים.

**בטיחות נתונים (Data Safety)**

- טקסט מחולץ (כולל OCR) משמש **במכשיר** לחיפוש ואינדוקס. בתיוג AI — **טקסט מקוצר** ונתיב קובץ נשלחים לבקאנד, שמעביר ל-**Gemini API** ומחזיר קטגוריה ותגיות. לא מאמנים מודלים של Google על הנתונים; משתמשים רק בבקשה. מטאדאטה נשמרת מקומית. בטופס **Data safety** ב־Play Console: להצהיר שנתונים נאספים (טקסט מחולץ) ונשלחים לשרת לתיוג AI; מעובדים ב־Gemini; לא משותפים לצד שלישי לשיווק; לא משמשים לאימון מודלים. להצהיר גם על Firebase / RevenueCat לפי השימוש.

**פרטיות AI (AI Privacy):** ה-**OCR** (זיהוי טקסט בתמונות וב-PDF) מתבצע **כולו במכשיר** (Google ML Kit). רק לאחר החילוץ — אם בוחרים בתיוג AI — **טקסט מקוצר** נשלח לשרת שלנו ומשם ל-**Gemini** אך ורק כדי לקבל **קטגוריה ותגיות**. הנתונים **לא** משמשים לאימון מודלים של Google; הם משמשים רק לבקשה הבודדת. הדגש: חיפוש ואינדוקס מבוססי תוכן קורים במכשיר; השליחה לענן היא רק לתיוג אוטומטי.

**מנהגי חנות (Store best practices)**

- **RevenueCat:** להגדיר **Products** ו-**Entitlements** בהתאמה ל־Google Play (מזהי חבילות תואמים). לוודא ש־Restore Purchase עובד אחרי התקנה מחדש או החלפת מכשיר.
- **שחזור רכישות:** לשמור על כפתור **שחזר רכישות** גלוי (למשל במסך המנוי). ב־Play Console לוודא שמנויים מקושרים ל־RevenueCat ולא חסומים.
- **Firebase Crashlytics:** לניטור קריסות ושגיאות. להשתמש בפרויקט Firebase **פרודקשן** ו־`firebase_options.dart` ל־release. לעקוב אחרי Crashlytics ולתקן בעיות מובילות לפני/אחרי השקה.
- **Store listing:** מדיניות פרטיות, פירוט Data safety, דירוג תוכן, תיאורים; להזכיר תכונות PRO ותשלום דרך Google Play.

**שרת, לוגים, תשלומים ומשתמשים**

- **שרת:** פריסה ל-**Cloud Run** (למשל דרך `cloudbuild.yaml`). להגדיר **`GEMINI_API_KEY`** (ו־`PORT` אם רלוונטי). לפרודקשן בקנה גדול — לשקול מעבר ממעקב מכסה ב־SQLite מקומי ל-**Cloud SQL** (או DB מנוהל אחר).
- **לוגים:** בקאנד — **Serilog** (קונסול + קובץ); ב־Cloud Run הלוגים עוברים ל-**Cloud Logging**. אפליקציה — **Firebase Crashlytics** לניטור קריסות ושגיאות.
- **תשלומים:** **RevenueCat** — לחבר Google Play כ־Store, להזין Service Account JSON מ־Play Console, להגדיר Products/Entitlements (למשל pro / premium) תואמים. **שחזור רכישות** — לוודא שהמנויים מסונכרנים.
- **משתמשים:** **Firebase Auth** מזהה משתמשים; **QuotaService** בבקאנד עוקב אחרי שימוש AI לפי `userId`. להגדיר ב־Firebase דומיינים מורשים, אופציונלי לאכוף התחברות; כללי **Storage** לגיבוי (משתמש רואה רק את הקבצים שלו).

**צ'קליסט קצר**

| נושא | פעולה |
|------|--------|
| **קוד** | טסטים, הסרת סודות, טיפול בשגיאות ו־fallback |
| **גרסאות** | `pubspec.yaml` + versionCode, Release notes |
| **Play Store** | חשבון מפתח, keystore ב־Secrets, Store listing, דירוג, מדיניות פרטיות, Video Declaration אם גישה לכל הקבצים |
| **מנויים** | Play Billing + RevenueCat (Products תואמים), שחזור רכישות |
| **שרת** | Cloud Run + GEMINI_API_KEY; אופציונלי: מעבר מ־SQLite ל־Cloud SQL למכסה |
| **לוגים** | Serilog → Cloud Logging; Crashlytics ב־Firebase |
| **משתמשים** | Firebase Auth, מכסה AI, כללי Storage לגיבוי |

### התקנה והרצה

```bash
flutter pub get
dart run build_runner build --delete-conflicting-outputs
flutter run
```

**מבנה הריפו (בקצרה):** `lib/` — main, models, screens, services, utils; `backend/` — .NET API (Gemini, מכסה).

**תוכנית עתידית (Future Roadmap):** **The Shark** — ניתוח מסמכים משפטיים (זיהוי סעיפים, תאריכים, צדדים); **Smart Benefits** — אינטגרציה עם זיהוי הטבות וזכויות ממסמכים (למשל ביטוח, פנסיה).

---

*להלן גרסת README מלאה באנגלית.*

---

## 1. Project Overview

The Hunter is a Flutter app that scans selected folders (e.g. Downloads, Documents), extracts text from files and images via OCR, and stores metadata in a local Isar database. You search with natural queries; results are ranked by a **weighted Relevance Engine** and can be filtered by type (All, Images, PDFs) or **Favorites** (PRO). AI-powered tagging via **Google Gemini** adds categories and tags automatically, while a **Garbage Filter** validates OCR quality before sending text to the AI to prevent hallucinations. The app supports **Hebrew PDFs** through a unique **Visual OCR** fallback (render PDF page to image → ML Kit) when raw text encoding fails. The UI offers full **Light/Dark** theme support, Favorites in the header, and an optional **Ranking Analysis (X-Ray)** view.

---

## 2. Search Intelligence

### Relevance Engine

The **Relevance Engine** (`relevance_engine.dart`) computes a single relevance score per file and sorts results so the best matches rise to the top.

| Signal | Weight | Description |
|--------|--------|-------------|
| **Filename** | **200 pts** | Query terms matching the file name (with density factor). |
| **Content** | **up to 120 pts** | Query Coverage Ratio: terms found in extracted text; score shared across query words. |
| **Location** | **80 pts** | Terms in folder path (e.g. `/Documents/Contracts`). |

### Smart logic: partial vs full match

- **Multi-Word sequence:**  
  - If **all** query terms are found → score is multiplied by **1.2** and **+50** is added.  
  - If fewer than **half** of the terms match → a **×0.2** penalty is applied.  
  This “smart gap” between partial and full match keeps results relevant for multi-word queries.
- **Adjacency bonus:** Pairs of query terms that appear **consecutively** in the content get **+25 pts each** (capped at 4 pairs = 100 pts).
- **Exact phrase:** A phrase match in name or content adds **+150 pts**.
- **AI metadata:** Matches in AI-assigned category or tags add **+80 pts**.
- **Penalties:** GUID-like filenames and `pdf.123`-style names get **-35 pts** so system/junk files rank lower.

Files are sorted by this score. The optional **Ranking Analysis (X-Ray)** in the UI shows the numeric breakdown (e.g. `Fn(200)`, `Content(60)`, `Adj(2)`, `MultiWord(x1.2+50)`) so you can see why a file was ranked.

---

## 3. Hebrew Visual OCR

Hebrew (and other RTL) PDFs often store text in a way that produces **gibberish** (e.g. `ãåîò`) when extracted as raw streams. The Hunter fixes this with a **hybrid pipeline**:

1. **Primary:** Extract text from the PDF using the standard text layer (Syncfusion).
2. **Quality check:** If the extracted text fails the **garbage ratio** check (more than 30% invalid/non-Hebrew characters), it is treated as unreliable.
3. **Fallback — Visual OCR:** The **first page is rendered to a high-resolution image** (via `pdfx`), then sent to **Google ML Kit Text Recognition** (the same engine used for photos). The result is clean, readable Hebrew (and Latin) text.

This ensures **reliable indexing and AI tagging** for Hebrew PDFs without changing how Latin PDFs or other documents are processed. Implementation: `text_extraction_service.dart` (raw extract in isolate → garbage check → `_extractPdfViaOcr` when needed).

---

## 4. AI Integration

- **Google Gemini:** Extracted text (and optionally file names) is sent to a backend that uses **Gemini** (e.g. `gemini-1.5-flash`) to suggest **category** and **tags** (e.g. "Invoice", "Contract", "Personal"). Results are stored locally and used for display and relevance (AI metadata bonus).
- **Garbage Filter:** Before sending any text to the AI, the app checks **OCR quality** (`extracted_text_quality.dart`). If more than **30%** of characters are “garbage” (non-alphanumeric, non-Hebrew, non-punctuation), that text is **not** sent for tagging. This prevents **AI hallucinations** (e.g. wrong tags like "army" or "idf" from corrupted OCR). A one-time **Cleanup** in Settings clears previously wrong AI tags and re-queues files for re-indexing with the new pipeline.

---

## 5. PRO Features & RevenueCat

- **Favorites:** The **Favorites** system is now in the **header** (star icon next to Settings). PRO users: tap toggles the favorites filter; star turns **amber** when active; a badge shows the count. Non-PRO: lock icon; tap opens the **Buy PRO** (subscription) screen.
- **Monetization:** Subscriptions are managed via **RevenueCat**. The app fetches offerings (monthly/yearly), purchases through Google Play Billing, and restores purchases. Entitlements (e.g. `pro` / `premium`) gate PRO features (Favorites, Tags, Secure Folder, Cloud, Voice search).

---

## 6. UI/UX

- **Theme:** Full **Light / Dark** mode support with **system theme adaptation**. Subscription and backup panels use theme colors (`canvasColor`, `surfaceContainerHighest`) instead of hardcoded dark blue.
- **Favorites in header:** See §5.
- **Ranking Analysis (X-Ray):** Optional view that shows **why** a file was ranked—score breakdown (filename, content, location, adjacency, multi-word, exact phrase, AI). Helps power users understand and trust results.

---

## 7. Technical Stack

| Layer | Technology |
|-------|------------|
| **App** | Flutter (Dart), Material 3 |
| **Local DB** | Isar (high-performance NoSQL for Flutter) |
| **OCR** | Google ML Kit Text Recognition (images + PDF first-page render) |
| **PDF** | Syncfusion Flutter PDF (text extraction), pdfx (page render to image) |
| **AI** | Backend: Google Gemini for tagging; optional AI search (query expansion) |
| **Cloud** | Google Drive API (optional), Firebase (Auth, Storage, Crashlytics) |
| **Payments** | RevenueCat (Pro subscription) |

---

## 8. Future Roadmap

- **The Shark:** Legal document analysis—extract clauses, dates, parties, and key terms from contracts and legal PDFs.
- **Smart Benefits:** Integration to detect benefits and entitlements from documents (e.g. insurance, pension, subsidies) and surface them in the app.

---

## 9. Production & Google Play

### 9.1 Permission handling

- The app requests **storage permissions** (e.g. `READ_EXTERNAL_STORAGE`, `MANAGE_EXTERNAL_STORAGE`) to scan selected folders and index file content.
- **All Files Access:** If your app uses **MANAGE_EXTERNAL_STORAGE** (or similar “all files” access) on Android, Google Play requires a **Video Declaration**: a short video that shows *why* the app needs this permission and how the user benefits. **Video Declaration tip:** In the video, explicitly **demonstrate deep-content search (OCR)**—e.g. open a PDF or image, type a word that appears *inside* the document in the search box, and show the file appearing in results. This proves that file access is needed for searching *inside* document content, not just filenames. Submit the video in Play Console (App content → Sensitive permissions). In the Store listing, explain in plain language why folder/file access is needed (e.g. “To search inside your documents and photos”).

### 9.2 Data safety

- **OCR and extracted text:** Text extracted from files (including OCR from images and PDFs) is used **on-device** for search and indexing. When AI tagging is used, **truncated extracted text** (and file path as ID) is sent to our backend, which forwards it to the **Gemini API** to return category and tags. We do not train Google’s models on this data; it is used only for the request. Stored metadata (tags, category) is kept locally on the device; the backend may log usage (e.g. for quota) but should not retain document content. Describe this in the **Play Console Data safety form**: e.g. “Data is collected (extracted text) and sent to our server for AI tagging; processed by Google Gemini API; not shared with third parties for marketing; not used to train ML models.”
- **AI privacy (dedicated):** **OCR** (text recognition in images and PDFs) runs **entirely on-device** (Google ML Kit). Only after extraction—if the user has AI tagging enabled—**truncated text** is sent to our server and then to **Gemini solely to obtain category and tags**. The data is **not** used to train Google’s models; it is used only for that single request. Summary: search and content-based indexing happen on-device; cloud send is only for automatic tagging.
- **Firebase / RevenueCat:** Declare Auth identifiers, Crashlytics (crash data), and purchase data as per their policies and your actual usage.

### 9.3 Store best practices

- **RevenueCat offerings:** Configure **Products** and **Entitlements** in RevenueCat to match Google Play (e.g. monthly/annual subscriptions). Ensure the app’s package IDs and product IDs match so purchases and restores work reliably.
- **Restore Purchase:** The app includes **Restore Purchase**; keep it visible (e.g. on the subscription screen) so users can restore after reinstall or device change. In Play Console, ensure subscriptions are correctly linked and not blocked.
- **Firebase Crashlytics:** Integrated for **monitoring** crashes and non-fatal errors. Use a **production** Firebase project and `firebase_options.dart` for release builds. Monitor Crashlytics in the Firebase console and fix top issues before/after launch.
- **Store listing:** Provide a clear **privacy policy** URL, **Data safety** details, **Content rating**, and **short/long descriptions**. Mention PRO features (Favorites, cloud, etc.) and that payment is via Google Play.

### 9.4 Server, logs, and users (summary)

- **Backend:** Deploy to **Cloud Run** (e.g. via `cloudbuild.yaml`). Set **`GEMINI_API_KEY`** (and optionally **`PORT`**). For production scale, consider moving quota storage from local SQLite to **Cloud SQL** (or another managed DB).
- **Logs:** Backend uses **Serilog** (console + file); on Cloud Run logs go to **Cloud Logging**. The app uses **Firebase Crashlytics** for crash and error monitoring.
- **Users:** **Firebase Auth** identifies users; backend **QuotaService** tracks AI usage per `userId`. Configure Firebase (authorized domains, optional enforced login) and Storage rules for backup.

---

## 10. Installation & Run

```bash
# Install dependencies
flutter pub get

# Generate Isar code
dart run build_runner build --delete-conflicting-outputs

# Run
flutter run
```

**Android:** The app may request storage permissions for scanning selected folders. If you use “All Files Access,” comply with Play policy and the Video Declaration (see §9.1).

---

## 11. Repository structure (high level)

```
lib/
├── main.dart                 # Entry, routes, theme, RevenueCat init
├── models/                   # FileMetadata, search intents
├── screens/                  # Search, Settings, Subscription, etc.
├── services/                 # DB, scanner, OCR, text extraction, relevance, AI tagger, hybrid search
├── utils/                    # Extracted text quality, file type helper, smart search parser
backend/                      # .NET API (Gemini tagging, quota)
```

---

**For Hebrew readers:** תיאור מפורט בעברית נמצא **בתחילת הקובץ** (סעיף "תיאור מפורט בעברית").

---

The Hunter is built to be **smart**—weighted relevance, Visual OCR for Hebrew, and guarded AI tagging—so you can find and manage files quickly and reliably.
