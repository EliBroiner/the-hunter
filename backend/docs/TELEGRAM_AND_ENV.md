# Telegram Admin Alerts & Environment Variables

## ⚠️ תזכורת: עדכן GitHub Secrets

הוסף/עדכן ב-GitHub → Repository → Settings → Secrets and variables → Actions (ובסביבת Production, למשל Cloud Run):

- **TELEGRAM_BOT_TOKEN** — טוקן הבוט (למשל מהטופס שקבלת מ-@BotFather)
- **TELEGRAM_CHAT_ID** — מזהה הצ'אט (למשל `295062084`)

אל תשמור טוקן או Chat ID בקוד או ב-commit.

---

## GitHub / סביבת Production

הוסף ב-GitHub Secrets (או ב-Cloud Run / App Engine env):

| Secret / Env         | תיאור |
|----------------------|--------|
| `TELEGRAM_BOT_TOKEN` | טוקן הבוט מ-@BotFather |
| `TELEGRAM_CHAT_ID`   | מזהה הצ'אט (למשל `295062084`) |

**אל תעלה את הטוקן ל-Git.** השתמש ב-Secrets או ב-User Secrets מקומית.

## הגדרות אופציונליות (appsettings / env)

- `Admin:AppUrl` — כתובת בסיס האפליקציה (לכפתור ב-Telegram), למשל `https://your-service.run.app`
- `Admin:Notification:TelegramBotToken` / `Admin:Notification:TelegramChatId` — חלופה ל-env אם לא משתמשים ב-`TELEGRAM_BOT_TOKEN` / `TELEGRAM_CHAT_ID`

הקריאה: קודם משתני סביבה, אחר כך `appsettings.json`.

## לוגיקת התראות

- ההתראה נשלחת כאשר מספר המונחים הממתינים (Pending Terms) ≥ 10.
- Cooldown: לא נשלחת יותר מפעם אחת ב-30 דקות.
- ההודעה נשלחת ב-HTML עם כפתור "🚀 פתח עמוד ניהול" שמקשר ל-`/admin/login?key=<Admin:Key>` (אותו לוגין שמגדיר את עוגיית `admin_session`).
- כשיש ≥10 מונחים: כפתורים "✅ Approve All" (אישור כולם), "📋 View List" (קישור לדשבורד).
- כשיש מונח ראשון: "✅ Approve" (אישור מונח בודד), "🚫 Ban User" (חסימת משתמש — מעדכן `isBanned` ב-Firestore collection `users`).

## Webhook — רישום אצל Telegram (חובה)

ה-endpoint הוא `POST /api/telegram/webhook`. אבטחה: **רק** בקשות שבהן `message.from.id` או `callback_query.from.id` תואם ל-`TELEGRAM_CHAT_ID` (משתנה סביבה / IConfiguration) מתעבדות; אחרת מחזירים **401 Unauthorized**. אין hardcode של Token או Chat ID.

### פקודת CURL לרישום Webhook

החלף `YOUR_SERVER_URL` בכתובת השרת האמיתית (למשל `xxx.run.app` או הדומיין שלך), והחלף `YOUR_BOT_TOKEN` בטוקן הבוט.

**Linux / macOS / Git Bash:**
```bash
curl -X POST "https://api.telegram.org/botYOUR_BOT_TOKEN/setWebhook?url=https://YOUR_SERVER_URL/api/telegram/webhook"
```

**PowerShell:**
```powershell
Invoke-RestMethod -Method POST -Uri "https://api.telegram.org/botYOUR_BOT_TOKEN/setWebhook?url=https://YOUR_SERVER_URL/api/telegram/webhook"
```

תשובה מוצלחת: `{"ok":true,"result":true,"description":"Webhook was set"}`.

## דוח יומי

- נשלח אוטומטית כל יום בשעה 09:00 (אזור: Israel / Asia/Jerusalem, ניתן לשינוי ב-`Admin:Notification:DailySummaryTimeZone` ו-`DailySummaryHour`).
- טריגר ידני: POST ל-`/admin/send-daily-summary` (דורש התחברות אדמין).
- התוכן (Sparkline): 👤 New Users, 📝 Terms Pending/Approved, ⚡ Top Search — בפורמט HTML עם אימוג'ים.
