import 'dart:async';
import 'dart:convert';
import 'dart:ui';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'screens/folder_selection_screen.dart';
import 'screens/duplicates_screen.dart';
import 'screens/secure_folder_screen.dart';
import 'screens/cloud_storage_screen.dart';
import 'services/secure_folder_service.dart';
import 'screens/login_screen.dart';
import 'screens/search_screen.dart';
import 'screens/subscription_screen.dart';
import 'services/ai_auto_tagger_service.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/database_service.dart';
import 'services/knowledge_base_service.dart';
import 'services/favorites_service.dart';
import 'services/recent_files_service.dart';
import 'services/tags_service.dart';
import 'services/widget_service.dart';
import 'services/file_scanner_service.dart';
import 'services/file_watcher_service.dart';
import 'services/log_service.dart';
import 'services/settings_service.dart';
import 'services/user_activity_service.dart';
import 'configs/ranking_config.dart';
import 'services/localization_service.dart';
import 'utils/smart_search_parser.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // ניקוי לוגים מההרצה הקודמת
  await LogService.instance.clearLogs();

  // אתחול Firebase
  await Firebase.initializeApp();

  // App Check — טוקן קבוע רשום ב־Firebase Console (פותר 401)
  await FirebaseAppCheck.instance.activate(
    providerAndroid: const AndroidDebugProvider(
      debugToken: '9273D0C3-6F08-4825-9416-49FCD8ABA9B6',
    ),
    providerApple: const AppleDebugProvider(),
  );
  print('🛡️ App Check activated with FIXED debug token.');

  // Force refresh — משיכת JWT טרי מיד אחרי activate
  try {
    await FirebaseAppCheck.instance.getToken(true);
  } catch (e) {
    print('❌ App Check getToken: $e');
  }

  // Crashlytics — דיווח קריסות ל־Firebase Console
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  // אתחול RevenueCat
  await Purchases.setLogLevel(LogLevel.debug);
  await Purchases.configure(
    PurchasesConfiguration('goog_ffZaXsWeIyIjAdbRlvAwEhwTDSZ'),
  );
  
  // אתחול מסד הנתונים והגדרות — smart_search_config.json נטען ב-KnowledgeBaseService
  await DatabaseService.instance.init();
  await KnowledgeBaseService.instance.initialize();
  SmartSearchParser.knowledgeBaseService = KnowledgeBaseService.instance;
  AiAutoTaggerService.instance.initialize(); // Backfill קבצים ישנים (3s delay)
  await SettingsService.instance.init();
  await RankingConfig.ensureLoaded();
  await FavoritesService.instance.init();
  await RecentFilesService.instance.init();
  await TagsService.instance.init();
  await WidgetService.instance.init();
  await SecureFolderService.instance.init();
  
  runApp(const TheHunterApp());
}

/// מנהל סריקה אוטומטית ומעקב קבצים
/// תומך ב-lifecycle - עיבוד רק כשהאפליקציה ברקע
class AutoScanManager with WidgetsBindingObserver {
  static final AutoScanManager _instance = AutoScanManager._();
  static AutoScanManager get instance => _instance;
  
  AutoScanManager._();
  
  bool _isInitialized = false;
  bool _isScanning = false;
  bool _isProcessing = false;
  bool _isPaused = false;  // האם העיבוד מושהה
  bool _hasLifecycleObserver = false;
  bool _appInBackground = false;  // אפליקציה ברקע — לא להשהות סריקה
  Timer? _resumeDebounceTimer;
  static const Duration _resumeDebounce = Duration(seconds: 3);
  
  /// callback כשסריקה הושלמה
  Function(ScanResult result)? onScanComplete;
  
  /// callback כשעיבוד הושלם
  Function(ProcessResult result)? onProcessComplete;
  
  /// callback כשנמצא קובץ חדש
  Function(String path)? onNewFileFound;
  
  /// callback לעדכון סטטוס
  Function(String status)? onStatusUpdate;
  
  /// callback כשנמצא גיבוי קיים (בהתקנה ראשונה)
  Function(BackupInfo backupInfo)? onBackupFound;

  bool get isScanning => _isScanning;
  bool get isProcessing => _isProcessing;
  bool get isPaused => _isPaused;

  /// מאתחל סריקה אוטומטית ומעקב (non-blocking)
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    
    // רישום למעקב אחר lifecycle של האפליקציה
    if (!_hasLifecycleObserver) {
      WidgetsBinding.instance.addObserver(this);
      _hasLifecycleObserver = true;
    }

    // האזנה לפעילות משתמש
    UserActivityService.instance.isUserActive.addListener(_onUserActivityChanged);

    // הרצת סריקה ועיבוד ברקע (non-blocking)
    _runBackgroundScanAndProcess();
    
    // התחלת מעקב אחר תיקיות
    _startFileWatcher();
  }
  
  void _onUserActivityChanged() {
    final isActive = UserActivityService.instance.isUserActive.value;
    if (isActive) {
      _resumeDebounceTimer?.cancel();
      // משתמש פעיל — להשהות רק אם באפליקציה (לא ברקע)
      if (!_appInBackground && !_isPaused) {
        _isPaused = true;
        appLog('AutoScan: Paused (user active)');
      }
    } else {
      // משתמש במנוחה — דיבונס 3 שניות לפני המשך (מונע Ping-Pong)
      if (_isPaused) {
        _resumeDebounceTimer?.cancel();
        _resumeDebounceTimer = Timer(_resumeDebounce, () {
          _resumeDebounceTimer = null;
          if (_isPaused) {
            _isPaused = false;
            appLog('AutoScan: Resumed (user idle, debounced)');
            _resumeProcessingIfNeeded();
          }
        });
      }
    }
  }
  
  /// מגיב לשינויים ב-lifecycle של האפליקציה
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _appInBackground = false;
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
        _appInBackground = true;
        _resumeDebounceTimer?.cancel();
        _resumeDebounceTimer = null;
        // ברקע — להמשיך סריקה בלי קשר ל"פעילות משתמש"
        if (_isPaused) {
          _isPaused = false;
          appLog('AutoScan: Resumed (app backgrounded)');
          _resumeProcessingIfNeeded();
        }
        break;
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
  
  /// ממשיך עיבוד קבצים ממתינים אם צריך
  /// shouldPause: לא מחזיר true בזמן העלאה לשרת (אצווה אטומית)
  bool _shouldPause() => _isPaused && !AiAutoTaggerService.instance.isUploading;

  Future<void> _resumeProcessingIfNeeded() async {
    if (_isProcessing || _shouldPause()) return;
    
    final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
    if (pendingCount > 0) {
      appLog('AutoScan: Resuming processing of $pendingCount pending files');
      _isProcessing = true;
      
      final result = await FileScannerService.instance.processPendingFiles(
        shouldPause: _shouldPause,
      );
      onProcessComplete?.call(result);
      
      _isProcessing = false;
    }
  }

  /// מריץ סריקה ועיבוד ברקע
  Future<void> _runBackgroundScanAndProcess() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      final isFirstRun = DatabaseService.instance.getFilesCount() == 0;
      final backupService = BackupService.instance;
      
      // בהתקנה ראשונה - בדוק אם יש גיבוי קיים
      if (isFirstRun && backupService.hasUser) {
        onStatusUpdate?.call('בודק גיבוי קיים...');
        
        final backupInfo = await backupService.getBackupInfo();
        if (backupInfo != null && backupInfo.filesCount > 0) {
          appLog('AutoScan: Found backup with ${backupInfo.filesCount} files!');
          
          // סריקה עם שחזור חכם מגיבוי!
          onStatusUpdate?.call('משחזר מגיבוי...');
          
          final result = await FileScannerService.instance.scanWithBackupRestore(
            onStatus: (status) => onStatusUpdate?.call(status),
            getBackupData: () => _getBackupData(),
          );
          
          onScanComplete?.call(result);
          
          if (result.skippedOcrCount > 0) {
            appLog('AutoScan: Saved OCR on ${result.skippedOcrCount} files from backup!');
          }
          
          // עיבוד קבצים שלא היו בגיבוי
          final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
          if (pendingCount > 0) {
            _isScanning = false;
            _isProcessing = true;
            onStatusUpdate?.call('מחלץ טקסט מ-$pendingCount קבצים חדשים...');
            
            final processResult = await FileScannerService.instance.processPendingFiles(
              shouldPause: _shouldPause,
            );
            onProcessComplete?.call(processResult);
          }
          
          onStatusUpdate?.call('');
          
          // גיבוי אוטומטי לאחר סיום
          _runAutoBackupIfNeeded();
          return;
        }
      }
      
      // סריקה רגילה (לא התקנה ראשונה או אין גיבוי)
      onStatusUpdate?.call('סורק תיקיות...');
      
      final result = await FileScannerService.instance.scanNewFilesOnly(
        runCleanup: true,
      );
      
      onScanComplete?.call(result);
      
      // עיבוד קבצים ממתינים - תמיד! גם אם לא נוספו קבצים חדשים
      // זה מבטיח המשכיות אחרי הפעלה מחדש של האפליקציה
      final pendingCount = DatabaseService.instance.getAllPendingFiles().length;
      
      if (pendingCount > 0) {
        _isScanning = false;
        _isProcessing = true;
        onStatusUpdate?.call('מחלץ טקסט מ-$pendingCount קבצים...');
        
        final processResult = await FileScannerService.instance.processPendingFiles(
          shouldPause: _shouldPause,
        );
        onProcessComplete?.call(processResult);
        onStatusUpdate?.call('');
        
        // גיבוי אוטומטי לאחר סיום עיבוד
        _runAutoBackupIfNeeded();
      } else {
        onStatusUpdate?.call('');
        _runAutoBackupIfNeeded();
      }
      
      // עדכון הווידג'ט עם הנתונים החדשים
      await WidgetService.instance.updateWidget();
    } finally {
      _isScanning = false;
      _isProcessing = false;
    }
  }
  
  /// מחזיר את נתוני הגיבוי מהענן
  Future<Map<String, dynamic>?> _getBackupData() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      
      final ref = FirebaseStorage.instance.ref('backups/${user.uid}/database_backup.json');
      final data = await ref.getData();
      
      if (data == null) return null;
      
      final jsonString = utf8.decode(data);
      return jsonDecode(jsonString) as Map<String, dynamic>;
    } catch (e) {
      appLog('AutoScan: Failed to get backup data - $e');
      return null;
    }
  }
  
  /// מריץ גיבוי אוטומטי אם צריך
  Future<void> _runAutoBackupIfNeeded() async {
    try {
      await BackupService.instance.runAutoBackupIfNeeded();
    } catch (e) {
      appLog('AutoScan: Auto backup failed - $e');
    }
  }

  /// מריץ סריקה מלאה מחדש
  Future<void> runFullScan() async {
    if (_isScanning || _isProcessing) return;
    _isScanning = true;

    try {
      onStatusUpdate?.call('סריקה מלאה...');
      
      final result = await FileScannerService.instance.scanAllSources();
      onScanComplete?.call(result);
      
      if (result.success) {
        _isScanning = false;
        _isProcessing = true;
        onStatusUpdate?.call('מחלץ טקסט...');
        
        final processResult = await FileScannerService.instance.processPendingFiles(
          shouldPause: _shouldPause,
        );
        onProcessComplete?.call(processResult);
        onStatusUpdate?.call('');
      } else {
        onStatusUpdate?.call('');
      }
    } finally {
      _isScanning = false;
      _isProcessing = false;
    }
  }

  /// מתחיל מעקב אחר קבצים חדשים
  void _startFileWatcher() {
    final watcher = FileWatcherService.instance;
    
    watcher.onNewFile = (path) async {
      onNewFileFound?.call(path);
      
      // עיבוד הקובץ החדש אוטומטית - רק אם האפליקציה ברקע
      if (!_isProcessing && !_isPaused) {
        _isProcessing = true;
        await FileScannerService.instance.processPendingFiles(
          shouldPause: _shouldPause,
        );
        _isProcessing = false;
      }
    };
    
    watcher.startWatching();
  }

  /// עוצר את כל השירותים
  Future<void> dispose() async {
    _resumeDebounceTimer?.cancel();
    await FileWatcherService.instance.stopWatching();
    UserActivityService.instance.isUserActive.removeListener(_onUserActivityChanged);
  }
}

class TheHunterApp extends StatefulWidget {
  const TheHunterApp({super.key});

  @override
  State<TheHunterApp> createState() => _TheHunterAppState();

  static ThemeData get darkTheme => _TheHunterAppState._darkTheme;
  static ThemeData get lightTheme => _TheHunterAppState._lightTheme;
}

class _TheHunterAppState extends State<TheHunterApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // לא קוראים dispose() ברקע — מונע SocketException בהעלאה אטומית
  }

  // ערכת צבעים כהה
  static ThemeData get _darkTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: Brightness.dark,
      surface: const Color(0xFF0F0F23),
      primary: const Color(0xFF818CF8),
      secondary: const Color(0xFF34D399),
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFF0F0F23),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      centerTitle: true,
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF1E1E3F),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: const Color(0xFF6366F1),
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: const Color(0xFF1E1E3F),
      headerBackgroundColor: const Color(0xFF6366F1),
      headerForegroundColor: Colors.white,
      dayForegroundColor: WidgetStateProperty.all(Colors.white),
      yearForegroundColor: WidgetStateProperty.all(Colors.white),
      surfaceTintColor: Colors.transparent,
      rangePickerBackgroundColor: const Color(0xFF1E1E3F),
      rangeSelectionBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
    ),
  );

  // ערכת צבעים בהירה - מעוצבת יפה
  static ThemeData get _lightTheme => ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6366F1),
      brightness: Brightness.light,
      surface: const Color(0xFFFAFAFC),  // רקע רך יותר
      onSurface: const Color(0xFF1E293B),  // טקסט כהה
      primary: const Color(0xFF6366F1),
      onPrimary: Colors.white,
      secondary: const Color(0xFF10B981),
      onSecondary: Colors.white,
      surfaceContainerHighest: const Color(0xFFF8FAFC),
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFF1F5F9),
    appBarTheme: const AppBarTheme(
      backgroundColor: Color(0xFFF1F5F9),
      elevation: 0,
      centerTitle: true,
      foregroundColor: Color(0xFF1E293B),
      iconTheme: IconThemeData(color: Color(0xFF6366F1)),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFFFAFAFC),  // לא לבן חזק
      elevation: 0,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: const Color(0xFF6366F1),
      foregroundColor: Colors.white,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      fillColor: const Color(0xFFFAFAFC),
      filled: true,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
    ),
    listTileTheme: const ListTileThemeData(
      textColor: Color(0xFF1E293B),
      iconColor: Color(0xFF6366F1),
    ),
    textTheme: const TextTheme(
      bodyLarge: TextStyle(color: Color(0xFF1E293B)),
      bodyMedium: TextStyle(color: Color(0xFF475569)),
      titleLarge: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
    ),
    datePickerTheme: DatePickerThemeData(
      backgroundColor: const Color(0xFFF8FAFC),
      headerBackgroundColor: const Color(0xFF6366F1),
      headerForegroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      dayForegroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) return Colors.white;
        if (states.contains(WidgetState.disabled)) return const Color(0xFFCBD5E1);
        return const Color(0xFF1E293B);
      }),
      yearForegroundColor: WidgetStateProperty.all(const Color(0xFF1E293B)),
      weekdayStyle: const TextStyle(
        color: Color(0xFF64748B),
        fontWeight: FontWeight.w600,
        fontSize: 13,
      ),
      dayStyle: const TextStyle(color: Color(0xFF1E293B)),
      todayForegroundColor: WidgetStateProperty.all(const Color(0xFF6366F1)),
      todayBackgroundColor: WidgetStateProperty.all(Colors.transparent),
      rangePickerHeaderForegroundColor: Colors.white,
      rangePickerHeaderBackgroundColor: const Color(0xFF6366F1),
      rangePickerBackgroundColor: const Color(0xFFF8FAFC),
      rangeSelectionBackgroundColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
      dividerColor: const Color(0xFFE2E8F0),
      inputDecorationTheme: const InputDecorationTheme(
        labelStyle: TextStyle(color: Color(0xFF64748B)),
        hintStyle: TextStyle(color: Color(0xFF94A3B8)),
      ),
      cancelButtonStyle: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(const Color(0xFF64748B)),
      ),
      confirmButtonStyle: ButtonStyle(
        foregroundColor: WidgetStateProperty.all(const Color(0xFF6366F1)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFFFAFAFC),
      titleTextStyle: const TextStyle(color: Color(0xFF1E293B), fontSize: 20, fontWeight: FontWeight.bold),
      contentTextStyle: const TextStyle(color: Color(0xFF475569)),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: const Color(0xFF1E293B),
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: const Color(0xFFF1F5F9),
      labelStyle: const TextStyle(color: Color(0xFF475569)),
      selectedColor: const Color(0xFF6366F1).withValues(alpha: 0.2),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFFFAFAFC),
    ),
  );

  @override
  Widget build(BuildContext context) {
    // עטיפה ב-Listener גלובלי לזיהוי נגיעות בכל מקום באפליקציה
    return Listener(
      onPointerDown: (_) => UserActivityService.instance.onUserInteraction(),
      onPointerMove: (_) => UserActivityService.instance.onUserInteraction(),
      onPointerUp: (_) => UserActivityService.instance.onUserInteraction(),
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: SettingsService.instance.themeModeNotifier,
        builder: (context, themeMode, child) {
          return ValueListenableBuilder<Locale>(
            valueListenable: SettingsService.instance.localeNotifier,
            builder: (context, locale, child) {
              return MaterialApp(
                title: 'The Hunter',
                debugShowCheckedModeBanner: false,
                // תמיכה בעברית - נדרש ל-DatePicker
                localizationsDelegates: const [
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                supportedLocales: const [
                  Locale('he', 'IL'),
                  Locale('en', 'US'),
                ],
                locale: locale,
                theme: TheHunterApp.lightTheme,
                darkTheme: TheHunterApp.darkTheme,
                themeMode: themeMode,
                home: const AuthWrapper(),
                routes: {
                  '/subscription': (context) => const SubscriptionScreen(),
                  '/folders': (context) => const FolderSelectionScreen(),
                  '/duplicates': (context) => const DuplicatesScreen(),
                  '/secure': (context) => const SecureFolderScreen(),
                  '/cloud': (context) => const CloudStorageScreen(),
                },
              );
            },
          );
        },
      ),
    );
  }
}

/// עוטף אימות - מחליט איזה מסך להציג לפי מצב ההתחברות
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: AuthService.instance.authStateChanges,
      builder: (context, snapshot) {
        // טעינה - מציג מסך טעינה
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            backgroundColor: Color(0xFF0F0F23),
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        // אם יש משתמש מחובר - הצג את המסך הראשי
        if (snapshot.hasData && snapshot.data != null) {
          return const MainScreen();
        }

        // אם אין משתמש - הצג מסך התחברות
        return const LoginScreen();
      },
    );
  }
}

/// מסך ראשי - חיפוש בלבד עם סריקה אוטומטית
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  String _statusMessage = '';
  bool _showStatus = false;
  bool _isFirstScan = true;
  bool _showLogPanel = false;

  @override
  void initState() {
    super.initState();
    _initializeAutoScan();
  }

  /// מאתחל סריקה אוטומטית ברקע
  Future<void> _initializeAutoScan() async {
    final dbCount = DatabaseService.instance.getFilesCount();
    _isFirstScan = dbCount == 0;
    
    final manager = AutoScanManager.instance;
    
    manager.onStatusUpdate = (status) {
      if (!mounted) return;
      setState(() {
        _statusMessage = status;
        _showStatus = status.isNotEmpty;
      });
    };
    
    manager.onScanComplete = (result) {
      if (!mounted) return;
      // הודעות סריקה הוסרו לבקשת המשתמש
    };
    
    manager.onProcessComplete = (result) {
      if (!mounted) return;
      setState(() {
        _isFirstScan = false;
      });
    };
    
    manager.onNewFileFound = (path) {
      if (!mounted) return;
      // הודעות קובץ חדש הוסרו לבקשת המשתמש
    };
    
    // הרצת אתחול
    manager.initialize();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: Column(
        children: [
          // סטטוס סריקה (רק כשפעיל) - הוסר לבקשת המשתמש
          // if (_showStatus)
          //   _buildStatusBar(theme),
          
          // מסך חיפוש
          const Expanded(
            child: SearchScreen(),
          ),
          
          // פאנל לוגים (לדיבוג)
          if (_showLogPanel) _buildLogPanel(),
        ],
      ),
      // כפתור לוגים (לדיבוג)
      floatingActionButtonLocation: FloatingActionButtonLocation.miniStartFloat,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'logs',
        onPressed: () => setState(() => _showLogPanel = !_showLogPanel),
        backgroundColor: _showLogPanel ? Colors.red : Colors.grey.shade800.withValues(alpha: 0.5),
        child: Icon(_showLogPanel ? Icons.close : Icons.bug_report, size: 18),
      ),
    );
  }

  /// בונה שורת סטטוס - הוסר לבקשת המשתמש
  // Widget _buildStatusBar(ThemeData theme) {
  //   return Container(...);
  // }
  
  /// בונה פאנל לוגים
  Widget _buildLogPanel() {
    return Container(
      height: 300,
      color: Colors.black87,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                Text(tr('logs_title'), style: const TextStyle(color: Colors.white, fontSize: 12)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.share, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  tooltip: tr('share_logs'),
                  onPressed: () => LogService.instance.exportLogs(),
                ),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: LogService.instance.getAllLogs()));
                    _showSnackBar(tr('logs_copied'));
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () => LogService.instance.clear(),
                ),
              ],
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: LogService.instance.logsNotifier,
              builder: (context, logs, _) {
                return ListView.builder(
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    return Text(
                      logs[index],
                      style: const TextStyle(
                        color: Colors.green,
                        fontSize: 10,
                        fontFamily: 'monospace',
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
