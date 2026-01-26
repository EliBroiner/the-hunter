import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'firebase_options.dart';
import 'screens/login_screen.dart';
import 'screens/search_screen.dart';
import 'screens/subscription_screen.dart';
import 'services/auth_service.dart';
import 'services/database_service.dart';
import 'services/file_scanner_service.dart';
import 'services/file_watcher_service.dart';
import 'services/log_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';

void main() {
  // שלב 1: אתחול מינימלי - רק מה שחייב להיות סינכרוני
  WidgetsFlutterBinding.ensureInitialized();
  
  // שלב 2: הרצת האפליקציה מיד - UI יוצג מיד
  runApp(const TheHunterApp());
}

/// מנהל אתחול - מריץ את כל האתחולים ברקע
class InitializationManager {
  static final InitializationManager _instance = InitializationManager._();
  static InitializationManager get instance => _instance;
  
  InitializationManager._();
  
  bool _isInitialized = false;
  bool _isInitializing = false;
  String? _initError;
  
  bool get isInitialized => _isInitialized;
  bool get isInitializing => _isInitializing;
  String? get initError => _initError;
  
  /// Callback לעדכון סטטוס
  Function(String status)? onStatusUpdate;
  Function(String error)? onError;
  Function()? onComplete;

  /// מאתחל את כל השירותים ברקע
  Future<void> initialize() async {
    if (_isInitialized || _isInitializing) return;
    _isInitializing = true;
    
    try {
      // שלב 1: Firebase (חובה לאימות)
      onStatusUpdate?.call('מאתחל Firebase...');
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      appLog('Init: Firebase initialized');
      
      // שלב 2: מסד נתונים (Isar)
      onStatusUpdate?.call('מאתחל מסד נתונים...');
      await DatabaseService.instance.init();
      appLog('Init: Database initialized');
      
      // שלב 3: הגדרות
      onStatusUpdate?.call('טוען הגדרות...');
      await SettingsService.instance.init();
      appLog('Init: Settings initialized');
      
      // שלב 4: RevenueCat (לא חוסם)
      _initRevenueCatSafely();
      
      _isInitialized = true;
      _isInitializing = false;
      onComplete?.call();
      appLog('Init: All services initialized successfully');
      
    } catch (e, stack) {
      _initError = e.toString();
      _isInitializing = false;
      appLog('Init ERROR: $e\n$stack');
      onError?.call(e.toString());
    }
  }
  
  /// אתחול RevenueCat בצורה בטוחה (לא חוסם)
  Future<void> _initRevenueCatSafely() async {
    try {
      await Purchases.setLogLevel(LogLevel.debug);
      await Purchases.configure(
        PurchasesConfiguration('goog_ffZaXsWeIyIjAdbRlvAwEhwTDSZ'),
      );
      appLog('Init: RevenueCat initialized');
    } catch (e) {
      appLog('Init: RevenueCat failed (non-critical): $e');
    }
  }
}

/// מנהל סריקה אוטומטית ומעקב קבצים
class AutoScanManager {
  static final AutoScanManager _instance = AutoScanManager._();
  static AutoScanManager get instance => _instance;
  
  AutoScanManager._();
  
  final _permissionService = PermissionService.instance;
  
  bool _isInitialized = false;
  bool _isScanning = false;
  bool _isProcessing = false;
  
  /// callback כשסריקה הושלמה
  Function(ScanResult result)? onScanComplete;
  
  /// callback כשעיבוד הושלם
  Function(ProcessResult result)? onProcessComplete;
  
  /// callback כשנמצא קובץ חדש
  Function(String path)? onNewFileFound;
  
  /// callback לעדכון סטטוס
  Function(String status)? onStatusUpdate;
  
  /// callback לשגיאות
  Function(String error)? onError;

  bool get isScanning => _isScanning;
  bool get isProcessing => _isProcessing;

  /// מאתחל סריקה אוטומטית ומעקב (non-blocking)
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    appLog('AutoScan: Starting initialization');
    
    // בדיקת והרשאות
    final hasPermission = await _requestPermissions();
    if (!hasPermission) {
      appLog('AutoScan: No storage permission - skipping scan');
      onError?.call('אין הרשאות אחסון - לא ניתן לסרוק קבצים');
      return;
    }

    // הרצת סריקה ועיבוד ברקע (non-blocking)
    _runBackgroundScanAndProcess();
    
    // התחלת מעקב אחר תיקיות
    _startFileWatcher();
  }
  
  /// מבקש הרשאות אחסון
  Future<bool> _requestPermissions() async {
    try {
      onStatusUpdate?.call('בודק הרשאות...');
      
      final hasPermission = await _permissionService.hasStoragePermission();
      if (hasPermission) {
        appLog('AutoScan: Storage permission already granted');
        return true;
      }
      
      onStatusUpdate?.call('מבקש הרשאות אחסון...');
      final result = await _permissionService.requestStoragePermission();
      
      if (result == PermissionResult.granted) {
        appLog('AutoScan: Storage permission granted');
        return true;
      } else {
        appLog('AutoScan: Storage permission denied - $result');
        return false;
      }
    } catch (e) {
      appLog('AutoScan: Permission request failed - $e');
      return false;
    }
  }

  /// מריץ סריקה ועיבוד ברקע
  Future<void> _runBackgroundScanAndProcess() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      onStatusUpdate?.call('סורק תיקיות...');
      
      // סריקה חכמה - רק קבצים חדשים
      final result = await FileScannerService.instance.scanNewFilesOnly(
        runCleanup: true,
      );
      
      appLog('AutoScan: Scan complete - ${result.newFilesAdded} new files');
      onScanComplete?.call(result);
      
      if (result.success && result.newFilesAdded > 0) {
        // עיבוד טקסט (OCR + PDF + TXT) ברקע
        _isScanning = false;
        _isProcessing = true;
        onStatusUpdate?.call('מחלץ טקסט מקבצים...');
        
        final processResult = await FileScannerService.instance.processPendingFiles();
        appLog('AutoScan: Processing complete - ${processResult.filesWithText} files with text');
        onProcessComplete?.call(processResult);
        onStatusUpdate?.call('');
      } else {
        onStatusUpdate?.call('');
      }
    } catch (e, stack) {
      appLog('AutoScan ERROR: $e\n$stack');
      onError?.call('שגיאה בסריקה: $e');
      onStatusUpdate?.call('');
    } finally {
      _isScanning = false;
      _isProcessing = false;
    }
  }

  /// מריץ סריקה מלאה מחדש
  Future<void> runFullScan() async {
    if (_isScanning || _isProcessing) return;
    
    // בדיקת הרשאות לפני סריקה
    final hasPermission = await _permissionService.hasStoragePermission();
    if (!hasPermission) {
      onError?.call('אין הרשאות אחסון');
      return;
    }
    
    _isScanning = true;

    try {
      onStatusUpdate?.call('סריקה מלאה...');
      
      final result = await FileScannerService.instance.scanAllSources();
      onScanComplete?.call(result);
      
      if (result.success) {
        _isScanning = false;
        _isProcessing = true;
        onStatusUpdate?.call('מחלץ טקסט...');
        
        final processResult = await FileScannerService.instance.processPendingFiles();
        onProcessComplete?.call(processResult);
        onStatusUpdate?.call('');
      } else {
        onStatusUpdate?.call('');
      }
    } catch (e) {
      appLog('AutoScan: Full scan error - $e');
      onError?.call('שגיאה בסריקה: $e');
      onStatusUpdate?.call('');
    } finally {
      _isScanning = false;
      _isProcessing = false;
    }
  }

  /// מתחיל מעקב אחר קבצים חדשים
  void _startFileWatcher() {
    try {
      final watcher = FileWatcherService.instance;
      
      watcher.onNewFile = (path) async {
        onNewFileFound?.call(path);
        
        // עיבוד הקובץ החדש אוטומטית
        if (!_isProcessing) {
          _isProcessing = true;
          try {
            await FileScannerService.instance.processPendingFiles();
          } catch (e) {
            appLog('AutoScan: File watcher processing error - $e');
          }
          _isProcessing = false;
        }
      };
      
      watcher.startWatching();
      appLog('AutoScan: File watcher started');
    } catch (e) {
      appLog('AutoScan: File watcher failed to start - $e');
    }
  }

  /// עוצר את כל השירותים
  Future<void> dispose() async {
    try {
      await FileWatcherService.instance.stopWatching();
    } catch (e) {
      appLog('AutoScan: Dispose error - $e');
    }
  }
}

class TheHunterApp extends StatelessWidget {
  const TheHunterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'The Hunter',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
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
      ),
      home: const AppInitializer(),
      routes: {
        '/subscription': (context) => const SubscriptionScreen(),
      },
    );
  }
}

/// מסך אתחול - מציג UI מיד ומאתחל ברקע
class AppInitializer extends StatefulWidget {
  const AppInitializer({super.key});

  @override
  State<AppInitializer> createState() => _AppInitializerState();
}

class _AppInitializerState extends State<AppInitializer> {
  String _status = 'מאתחל...';
  bool _isInitialized = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _runInitialization();
  }

  Future<void> _runInitialization() async {
    final initManager = InitializationManager.instance;
    
    initManager.onStatusUpdate = (status) {
      if (mounted) setState(() => _status = status);
    };
    
    initManager.onError = (error) {
      if (mounted) setState(() => _error = error);
    };
    
    initManager.onComplete = () {
      if (mounted) setState(() => _isInitialized = true);
    };
    
    await initManager.initialize();
  }

  @override
  Widget build(BuildContext context) {
    // אם יש שגיאה קריטית
    if (_error != null && !_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F23),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 64),
                const SizedBox(height: 16),
                Text(
                  'שגיאה באתחול',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _error = null;
                      _status = 'מאתחל...';
                    });
                    _runInitialization();
                  },
                  child: const Text('נסה שוב'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // אם עדיין מאתחל
    if (!_isInitialized) {
      return Scaffold(
        backgroundColor: const Color(0xFF0F0F23),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // לוגו
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.4),
                      blurRadius: 30,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Icon(Icons.search, size: 50, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text(
                'The Hunter',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 24),
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(height: 16),
              Text(
                _status,
                style: const TextStyle(color: Colors.white70, fontSize: 14),
              ),
            ],
          ),
        ),
      );
    }

    // אתחול הושלם - מציג AuthWrapper
    return const AuthWrapper();
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
    // אתחול סריקה ברקע - לאחר שה-UI כבר מוצג
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeAutoScan();
    });
  }

  /// מאתחל סריקה אוטומטית ברקע
  Future<void> _initializeAutoScan() async {
    try {
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
      
      manager.onError = (error) {
        if (!mounted) return;
        _showSnackBar(error, isError: true);
      };
      
      manager.onScanComplete = (result) {
        if (!mounted) return;
        
        if (result.newFilesAdded > 0) {
          _showSnackBar('נמצאו ${result.newFilesAdded} קבצים חדשים');
        }
      };
      
      manager.onProcessComplete = (result) {
        if (!mounted) return;
        
        if (result.filesWithText > 0) {
          _showSnackBar('חולץ טקסט מ-${result.filesWithText} קבצים');
        }
        
        setState(() {
          _isFirstScan = false;
        });
      };
      
      manager.onNewFileFound = (path) {
        if (!mounted) return;
        
        final fileName = path.split('/').last;
        _showSnackBar('קובץ חדש: $fileName');
      };
      
      // הרצת אתחול - כולל בקשת הרשאות
      await manager.initialize();
    } catch (e) {
      appLog('MainScreen: AutoScan init error - $e');
      if (mounted) {
        _showSnackBar('שגיאה באתחול הסריקה', isError: true);
      }
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        backgroundColor: isError ? Colors.red.shade700 : null,
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
          // סטטוס סריקה (רק כשפעיל)
          if (_showStatus)
            _buildStatusBar(theme),
          
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

  /// בונה שורת סטטוס
  Widget _buildStatusBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.2),
            theme.colorScheme.secondary.withValues(alpha: 0.2),
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              _statusMessage,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// בונה פאנל לוגים
  Widget _buildLogPanel() {
    return Container(
      height: 150,
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
                const Text('לוגים', style: TextStyle(color: Colors.white, fontSize: 12)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: LogService.instance.getAllLogs()));
                    _showSnackBar('לוגים הועתקו');
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
