import 'package:home_widget/home_widget.dart';
import 'database_service.dart';
import 'log_service.dart';

/// שירות לעדכון הווידג'ט במסך הבית
class WidgetService {
  static WidgetService? _instance;
  
  WidgetService._();
  
  static WidgetService get instance {
    _instance ??= WidgetService._();
    return _instance!;
  }

  static const String _androidWidgetName = 'SearchWidgetProvider';
  static const String _appGroupId = 'group.com.thehunter.the_hunter';

  /// אתחול שירות הווידג'ט
  Future<void> init() async {
    try {
      // הגדרת קבוצת אפליקציה (iOS)
      await HomeWidget.setAppGroupId(_appGroupId);
      
      // עדכון ראשוני
      await updateWidget();
      
      appLog('WidgetService: Initialized');
    } catch (e) {
      appLog('WidgetService: Init error - $e');
    }
  }

  /// עדכון נתוני הווידג'ט
  Future<void> updateWidget() async {
    try {
      final db = DatabaseService.instance;
      final allFiles = db.getAllFiles();
      
      // חישוב סטטיסטיקות
      int imagesCount = 0;
      int pdfsCount = 0;
      
      for (final file in allFiles) {
        final ext = file.extension.toLowerCase();
        if (_isImage(ext)) {
          imagesCount++;
        } else if (ext == 'pdf') {
          pdfsCount++;
        }
      }
      
      // שמירת נתונים
      await HomeWidget.saveWidgetData<int>('files_count', allFiles.length);
      await HomeWidget.saveWidgetData<int>('images_count', imagesCount);
      await HomeWidget.saveWidgetData<int>('pdfs_count', pdfsCount);
      
      // עדכון הווידג'ט
      await HomeWidget.updateWidget(
        androidName: _androidWidgetName,
        qualifiedAndroidName: 'com.thehunter.the_hunter.$_androidWidgetName',
      );
      
      appLog('WidgetService: Updated - files: ${allFiles.length}, images: $imagesCount, pdfs: $pdfsCount');
    } catch (e) {
      appLog('WidgetService: Update error - $e');
    }
  }

  /// בדיקה אם סיומת היא תמונה
  bool _isImage(String ext) {
    return ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp', 'heic', 'heif'].contains(ext);
  }

  /// רישום callback ללחיצה על הווידג'ט
  Future<void> registerInteractivityCallback() async {
    try {
      await HomeWidget.registerInteractivityCallback(widgetBackgroundCallback);
    } catch (e) {
      appLog('WidgetService: Register callback error - $e');
    }
  }
}

/// Callback לטיפול בלחיצות על הווידג'ט
@pragma('vm:entry-point')
Future<void> widgetBackgroundCallback(Uri? uri) async {
  appLog('WidgetService: Background callback triggered - $uri');
}
