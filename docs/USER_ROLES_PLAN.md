# תוכנית: ניהול משתמשים ותפקידים (User Roles)

## סקירה

מערכת ניהול משתמשים ותפקידים — טבלה מרכזית, API לבירור הרשאות, וממשק ניהול בדשבורד. ניתנת להרחבה לשימושים עתידיים (למשל feature flags, beta testers).

---

## 1. טבלה: `AppManagedUser`

| עמודה | סוג | תיאור |
|-------|-----|--------|
| Id | int (PK) | מזהה פנימי |
| UserId | string(256) | Firebase UID — מפתח לזיהוי במערכת |
| Email | string(256) | כתובת מייל (לצורך תצוגה וחיפוש) |
| DisplayName | string(256), nullable | שם לתצוגה |
| Role | string(64) | תפקיד — ראה מטה |
| CreatedAt | DateTime | תאריך יצירה |
| UpdatedAt | DateTime | תאריך עדכון אחרון |

**אינדקס:** `UserId` (ייחודי) — משתמש אחד = רשומה אחת.

### תפקידים (Roles)

| Role | תיאור | הרשאות |
|------|--------|---------|
| `Admin` | מנהל | גישה מלאה לדשבורד, ניהול משתמשים |
| `DebugAccess` | גישה ל־Debug | הצגת Debug Token בשכבת ההגדרות |
| `User` | משתמש רגיל | ברירת מחדל, ללא הרשאות נוספות |

**הערה:** `Admin` כולל אוטומטית את `DebugAccess` (לוגיקה בקוד).

---

## 2. API Endpoints

### 2.1 בירור הרשאה (לאפליקציית Flutter)

```
GET /api/users/check-role?userId={firebaseUid}&role={roleName}
```

**Headers:** `X-Firebase-AppCheck` (חובה, כמו כל API).

**Response:**
```json
{ "hasRole": true }
```
או
```json
{ "hasRole": false }
```

**דוגמה:** Flutter שולח `userId` מ־`AuthService.instance.currentUser?.uid` ו־`role=DebugAccess`.

### 2.2 ניהול משתמשים (Admin only)

כל הנתיבים תחת `/admin`, עם `X-Admin-Key` + `ServiceFilter<AdminKeyAuthorizationFilter>`.

| Method | Route | תיאור |
|--------|-------|--------|
| GET | /admin/users | רשימת כל המשתמשים המנוהלים |
| POST | /admin/users | הוספת משתמש (Email, Role) |
| PUT | /admin/users/{id} | עדכון תפקיד |
| DELETE | /admin/users/{id} | הסרת משתמש |

**הוספת משתמש:**  
הקלט: `Email`, `Role`.  
השרת לא יכול להפיק Firebase UID ממייל לבד — יש שתי אפשרויות:
- **אופציה א':** המשתמש מתבקש להתחבר פעם אחת; השרת מזהה אותו מ־Firebase Auth ומאפשר הוספה ידנית לפי מייל (פשוט יותר).
- **אופציה ב':** Admin מזין גם `UserId` (Firebase UID) — מצריך ידע טכני.

**המלצה:** טופס הוספה עם `Email` + `Role`. ה־`UserId` ימולא אוטומטית כשהמשתמש יתחבר לראשונה (או דרך מנגנון עתידי). כרגע — Admin מזין ידנית גם `UserId` אם צריך.

---

## 3. ממשק ניהול בדשבורד

### עמוד חדש: `/admin/users` (או טאב בתוך Index)

- כותרת: "ניהול משתמשים"
- טבלה: Email | UserId | Role | פעולות (עריכה / מחיקה)
- כפתור "הוסף משתמש" → טופס: Email, UserId (אופציונלי בשלב ראשון), Role
- **גישה:** רק לבעלי תפקיד `Admin` — יש להוסיף בדיקה בטבלה (או ב־Filter): האם ה־Admin המחובר מופיע כ־Admin ב־`AppManagedUser`.  
  **בשלב ראשון:** כל מי שעבר את `AdminKeyAuthorizationFilter` נחשב Admin (ללא בדיקה בטבלה).

---

## 4. Bootstrap — המנהל הראשון

**אפשרות א':** Seed ב־Migration  
- רשומה ראשונה: `UserId` ו־`Email` מ־`INITIAL_ADMIN_EMAIL` או מ־env var.  
- חסרון: אין Firebase UID ידוע מראש.

**אפשרות ב':** env var  
- `INITIAL_ADMIN_EMAIL=dev@gmail.com`  
- בהרצה ראשונה, אם הטבלה ריקה, יצירת רשומת Admin לפי המייל.  
- `UserId` יכול להישאר ריק עד ההתחברות הראשונה, ואז להיתעדכן.

**אפשרות ג':** Script / Endpoint חד־פעמי  
- `POST /admin/bootstrap-admin?email=xxx` — יוצר Admin ראשון (רק כשהטבלה ריקה).

**המלצה:** Seed עם `UserId` ו־`Email` מ־env (אם מוגדר), או Admin ידני ראשון דרך הממשק.

---

## 5. אינטגרציה באפליקציית Flutter

1. **שירות חדש:** `UserRolesService` (או הרחבה ל־`AuthService`)
   - `Future<bool> hasRole(String role)`  
   - קורא `GET /api/users/check-role?userId=...&role=...`  
   - Cache ל־5–10 דקות כדי להפחית קריאות.

2. **מסך הגדרות**
   - תנאי הצגת Debug Token:
     ```dart
     (kDebugMode || _isDevMode) && await UserRolesService.hasRole('DebugAccess')
     ```

3. **משתמש לא מחובר:** אין הצגת Debug — `hasRole` מחזיר `false`.

---

## 6. סדר מימוש מוצע

| שלב | משימה |
|-----|--------|
| 1 | הוספת `AppManagedUser` ל־DbContext + Migration |
| 2 | Seed / Bootstrap ל־Admin ראשון |
| 3 | `UserRoleService` ב־Backend — בדיקת `hasRole` מול DB |
| 4 | `GET /api/users/check-role` (ב־Controller חדש או קיים) |
| 5 | עמוד ניהול משתמשים בדשבורד (CRUD) |
| 6 | Flutter: `UserRolesService` + עדכון תנאי הצגת Debug Token |

---

## 7. הרחבות עתידיות

- **Feature flags:** עמודה `Flags` (JSON) או טבלת `UserFlags` לצורך התנהגות לפי משתמש.
- **Beta testers:** תפקיד `Beta` שמפעיל פיצ'רים ניסיוניים.
- **Firebase Auth verification:** ולידציית Id Token בשרת במקום להסתמך רק על `UserId` מהלקוח.
