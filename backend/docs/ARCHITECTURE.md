# The Hunter API — סקירת ארכיטקטורה

## מבנה תיקיות

```
TheHunterApi/
├── Config/          # הגדרות (GeminiConfig)
├── Constants/       # קבועים משותפים (OcrConstants, RolesConstants, SystemPromptFeatures)
├── Controllers/     # API endpoints — קובץ לכל controller
├── Data/            # EF Core (AppDbContext)
├── Filters/         # AdminKeyAuthorizationFilter
├── Middleware/      # FirebaseAppCheck, RequestLogging, GlobalException
├── Models/          # DTOs — קובץ לכל class
├── Services/        # לוגיקה עסקית — GeminiService, QuotaService, AdminFirestoreService...
└── Views/           # Razor ל-Admin Dashboard
```

## זרימת נתונים עיקרית

1. **חיפוש חכם** — SearchController → GeminiService.ParseSearchIntentAsync → Firestore/DB
2. **ניתוח מסמכים** — AnalyzeController → GeminiService.AnalyzeDocumentsBatchAsync → LearningService
3. **OCR Fallback** — AnalyzeController.OcrExtract → OcrService / GeminiService.ExtractTextFromFileAsync
4. **Admin** — AdminDashboardController, AdminAiController → AdminFirestoreService, GeminiService

## שירותים מרכזיים

| שירות | תפקיד |
|-------|-------|
| GeminiService | תקשורת עם Gemini API — חיפוש, ניתוח מסמכים, OCR |
| AdminFirestoreService | גישה ל-Firestore (knowledge_base, users, logs, scan_failures...) |
| QuotaService | מכסת סריקות יומית |
| UserRoleService | בדיקת תפקידים (Admin, DebugAccess) |
| ISystemPromptService | פרומפטים דינמיים מ-DB (Search, DocAnalysis, OcrExtraction) |

## Environment Variables

- `GEMINI_API_KEY` — מפתח ל-Gemini API
- `FIRESTORE_PROJECT_ID` — פרויקט Firebase
- `PORT` — פורט (ברירת מחדל 8080)
- `ADMIN_KEY` — מפתח גישה ל-Admin endpoints
