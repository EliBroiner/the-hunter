# Firestore Database Audit & Data Model

## 1. Collections Overview

| Collection | Purpose | Written By | Read By |
|------------|---------|------------|---------|
| **users** | משתמשי Admin, תפקידים (role), isBanned | Admin Dashboard, Firebase Auth sync | AdminFirestoreService, UserRoleService, TelegramService |
| **smart_categories** | מילון מאוחד — sourceType: "term" \| "rule" | SmartCategoriesService, AdminFirestoreService (Approve) | DictionaryController, Flutter sync |
| **suggestions** | הצעות מונחים מ-AI — status: pending_approval | LearningService (GeminiService, AnalyzeController) | AdminFirestoreService (pending terms) |
| **knowledge_base** | *(deprecated)* הועבר ל-smart_categories — למחיקה אחרי מיגרציה | — | — |
| **scan_stats** | סטטיסטיקות — imagesSkippedNoText (חיסכון) | AdminFirestoreService | Admin Dashboard |
| **processing_chains** | לוג בלבד — File X-Ray (אין סנכרון Flutter) | AnalyzeController, GeminiService | AdminFirestoreService |
| **quotas** | מכסת סריקות יומית — userId_yyyyMMdd | QuotaService | QuotaService, AnalyzeController |
| **scan_failures** | כשלונות Meaningful Text Check | ReportScanFailure API | AdminFirestoreService (Scanning Health) |
| **logs** | פעילות חיפוש — term, count, lastSearch | (לקוח) | Admin Dashboard |
| **ranking_settings** | משקלי דירוג — filenameWeight, contentWeight... | Admin Dashboard | AdminFirestoreService |
| **scanner_settings** | garbageThresholdPercent, minMeaningfulLength... | Admin Dashboard | ScannerSettingsService |

---

## 2. Fix: Pending Terms Disconnect (RESOLVED)

**Problem:** Admin Dashboard showed 0 pending terms even when AI suggested new terms.

**Root Cause:** 
- **LearningService** writes to `suggestions` with `status: "pending_approval"`
- **AdminFirestoreService** was reading from `knowledge_base` where `isApproved == false`

**Solution:** AdminFirestoreService now:
- `GetPendingTermsAsync()` — reads from `suggestions` where `status == "pending_approval"`
- `GetPendingTermsCountAsync()` — counts from `suggestions`
- `ApproveTermAsync()` — if in suggestions: copy to smart_categories (sourceType=term), delete from suggestions
- `DeleteTermAsync()` — tries suggestions first, then smart_categories
- `GetTermByIdAsync()`, `UpdateTermAsync()` — check suggestions, smart_categories

---

## 3. smart_categories (מקור אמת יחיד)

**בוצע:** אוסף `smart_categories` מאחד מונחים וחוקים.

| sourceType | מקור | שדות |
|------------|------|------|
| `ai_suggestion` | AI suggestions מאושרים | term, category, frequency, lastModified, userId |
| `term` | (legacy) מיגרציה מ-knowledge_base | term, category, frequency, lastModified |
| `rule` | Debugger, Admin batch | key, keywords, regex_patterns, display_names, last_updated |

**מיגרציה:** `POST /admin/migrate-knowledge-base-to-smart-categories` — מעתיק knowledge_base → smart_categories, מוחק knowledge_base.

**Deprecated:** `knowledge_base` — למחיקה אחרי מיגרציה.

---

## 4. סיכום מודל הנתונים (עברית)

### אוספים פעילים

1. **users** — ניהול משתמשים, תפקידים, חסימות
2. **suggestions** — הצעות מונחים מ-AI (ממתינות לאישור)
3. **unified_dictionary** — מונחים (type=term) + חוקי קטגוריות (type=rule) — ייצוא ל-Flutter
5. **scan_stats** — מונה תמונות שדולגו (No Text)
6. **processing_chains** — שרשרת עיבוד למסמך (File X-Ray)
7. **quotas** — מכסת סריקות יומית למשתמש
8. **scan_failures** — כשלונות OCR/Meaningful Text
9. **logs** — סטטיסטיקות חיפוש
10. **ranking_settings** — משקלי דירוג
11. **scanner_settings** — הגדרות סריקה

### זרימת נתונים

```
AI (Gemini) → LearningService.ProcessAiResultAsync → suggestions (status: pending_approval)
                                                    ↓
Admin Dashboard ← GetPendingTermsAsync ← suggestions
                                                    ↓
Admin מאשר → ApproveTermAsync → smart_categories (sourceType=term) + delete from suggestions
                                                    ↓
Flutter ← Dictionary API ← smart_categories (כל sourceType)
```
