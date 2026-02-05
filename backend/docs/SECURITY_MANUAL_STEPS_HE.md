# שלבים ידניים לאבטחת ה-Backend (עברית)

## 1. Firebase App Check

### 1.1 הגדרה ב-Firebase Console
1. היכנס ל־[Firebase Console](https://console.firebase.google.com/)
2. בחר את הפרויקט (או צור חדש)
3. עבור ל־**App Check** בתפריט הצד
4. לחץ **Register** עבור האפליקציה (Android / iOS לפי הצורך)
5. בחר Provider: **Play Integrity** (Android) או **DeviceCheck** (iOS)
6. שמור את ההגדרות

### 1.2 שליפת Project Number
1. ב-Firebase Console: **Project Settings** (הגדרות הפרויקט)
2. העתק את **Project number** (מספר בן כמה ספרות)

### 1.3 הגדרת Environment Variable
הגדר את המשתנה הבא בסביבת ההרצה (Cloud Run, Docker, וכו'):

```
FIREBASE_PROJECT_NUMBER=123456789012
```

**שים לב:** אם המשתנה לא מוגדר, ה-Middleware לא ירוץ ואימות App Check לא יבוצע (מצב פיתוח).

### 1.4 עדכון Flutter Client
ודא שאפליקציית Flutter שולחת בכל בקשה ל-API את ה-header:

```
X-Firebase-AppCheck: <token>
```

השתמש בחבילה `firebase_app_check` ב-Flutter כדי לקבל את ה-token לפני קריאה ל-API.

---

## 2. מפתחות וסודות (Secrets)

### 2.1 GEMINI_API_KEY
מוגדר כיום. ודא שאינו נחשף ב-repository או ב-log.

### 2.2 Firebase Service Account (אם משתמשים ב-Firebase Admin)
אם בעתיד תבחר להשתמש ב-Firebase Admin SDK (למשל ל-Firebase Auth):
1. ב-Firebase Console: **Project Settings** → **Service Accounts**
2. לחץ **Generate new private key**
3. שמור את קובץ ה-JSON במקום מאובטח
4. הגדר `GOOGLE_APPLICATION_CREDENTIALS` לאותה נתיב

---

## 3. הגנות לולאת הלמידה (Learning Loop)

### ערכים ניתנים להגדרה בקוד
- **ApprovalFrequencyThreshold** (ברירת מחדל: 5) – מונח מאושר אוטומטית רק כשנצפה 5+ פעמים
- **MaxSuggestionsPerUserPerDay** (ברירת מחדל: 30) – מקסימום מונחים חדשים למשתמש ביום

שינוי: ערוך את הקבועים ב־`LearningService.cs` לפי הצורך.

---

## 4. המלצות נוספות

- **Rate Limiting:** שקול הוספת Rate Limiting (למשל `AspNetCoreRateLimit`) להגבלת בקשות לדקה
- **CORS:** בע production, הגבל `AllowAnyOrigin()` לרשימת דומיינים מאושרים
- **Swagger:** שקול לכבות או להגן על `/swagger` בסביבת production
