# The Hunter

אפליקציית Flutter לסריקת קבצים בתיקיית Downloads ושמירתם במסד נתונים מקומי.

## תכונות

- סריקת תיקיית Downloads
- שמירת מטאדאטה של קבצים (שם, נתיב, סיומת, גודל, תאריך שינוי)
- מסד נתונים מקומי Isar
- ניהול הרשאות אחסון
- ממשק משתמש מודרני עם Material 3

## מבנה הפרויקט

```
lib/
├── main.dart                    # נקודת כניסה ו-UI ראשי
├── models/
│   ├── file_metadata.dart       # מודל Isar לקבצים
│   └── file_metadata.g.dart     # קוד נוצר אוטומטית
└── services/
    ├── database_service.dart    # שירות מסד נתונים Isar
    ├── file_scanner_service.dart# שירות סריקת קבצים
    └── permission_service.dart  # שירות ניהול הרשאות
```

## התקנה

```bash
# התקנת חבילות
flutter pub get

# יצירת קוד Isar
dart run build_runner build --delete-conflicting-outputs

# הרצה
flutter run
```

## הרשאות נדרשות (Android)

האפליקציה דורשת את ההרשאות הבאות:
- `READ_EXTERNAL_STORAGE` - לקריאת קבצים
- `MANAGE_EXTERNAL_STORAGE` - לגישה מלאה לתיקיית Downloads

## שימוש

1. הפעל את האפליקציה
2. לחץ על כפתור "סרוק Downloads"
3. אשר הרשאות אחסון אם תתבקש
4. צפה ברשימת הקבצים שנסרקו

## טכנולוגיות

- Flutter 3.x
- Isar Database 3.1.0
- Permission Handler 11.x
- Path Provider 2.x
