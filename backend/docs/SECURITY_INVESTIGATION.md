# Phase 1: Security Investigation

## 1. Authentication / Authorization

### Current State
| Endpoint | Protection | Notes |
|----------|------------|-------|
| `POST api/analyze-batch` | **None** | ציבורי – כל אחד יכול לקרוא |
| `POST api/semantic-search` | **None** | ציבורי |
| `POST api/Search/intent` | **None** | ציבורי |
| `GET api/Search/status` | **None** | ציבורי |
| `GET api/Dictionary/updates` | **None** | ציבורי – חשוף לקבצי JSON |

### Findings
- **אין JWT** – לא קיים `AddAuthentication` / `AddJwtBearer`
- **אין Firebase Auth** – לא מיושם אימות משתמשים
- **אין Firebase App Check** – אין ולידציה שרק האפליקציה שלנו קוראת ל-API
- `app.UseAuthorization()` קיים אך לא מופעל בפועל כי אין `[Authorize]` וה-auth לא מוגדר

---

## 2. Rate Limiting & Request Validation

### Current State
- **אין Rate Limiting** – אין הגבלה על מספר הבקשות לדקה
- **Validation בסיסית** – רק בדיקת null/empty ב-controllers
- **QuotaService** – מגביל 50 סריקות לחודש למשתמש, אך ה-`UserId` מגיע מה-client ללא אימות – ניתן לזייף

---

## 3. Learning Loop – סיכונים

| סיכון | תיאור |
|-------|--------|
| **Dictionary Stuffing** | תוקף יכול להציף מונחים מזויפים/ספאם כדי לזהם את המילון |
| **Input Injection** | מונחים ארוכים, תווים מיוחדים, SQL/NoSQL injection (EF מסנן חלקית) |
| **Gibberish** | מונחים חסרי משמעות שמורידים איכות תוצאות החיפוש |
| **מכסת משתמש** | אין הגבלה על כמה מונחים חדשים משתמש יכול "להציע" ביום |

---

## 4. CORS
- `AllowAnyOrigin()` – כל origin מורשה (מתאים לפיתוח ו-mobile)

---

## סיכום
ה-API כרגע **לא מאובטח**: אין אימות, אין App Check, אין Rate Limiting, ולולאת הלמידה פגיעה ל-Dictionary Stuffing.
