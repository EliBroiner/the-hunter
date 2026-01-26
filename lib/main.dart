import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'screens/login_screen.dart';
import 'screens/search_screen.dart';
import 'screens/subscription_screen.dart';
import 'services/auth_service.dart';
import 'services/backup_service.dart';
import 'services/database_service.dart';
import 'services/file_scanner_service.dart';
import 'services/file_watcher_service.dart';
import 'services/log_service.dart';
import 'services/permission_service.dart';
import 'services/settings_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // אתחול Firebase
  await Firebase.initializeApp();
  
  // אתחול RevenueCat
  await Purchases.setLogLevel(LogLevel.debug);
  await Purchases.configure(
    PurchasesConfiguration('goog_ffZaXsWeIyIjAdbRlvAwEhwTDSZ'),
  );
  
  // אתחול מסד הנתונים והגדרות
  await DatabaseService.instance.init();
  await SettingsService.instance.init();
  
  runApp(const TheHunterApp());
}

/// מנהל סריקה אוטומטית ומעקב קבצים
class AutoScanManager {
  static final AutoScanManager _instance = AutoScanManager._();
  static AutoScanManager get instance => _instance;
  
  AutoScanManager._();
  
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
  
  /// callback כשנמצא גיבוי קיים (בהתקנה ראשונה)
  Function(BackupInfo backupInfo)? onBackupFound;

  bool get isScanning => _isScanning;
  bool get isProcessing => _isProcessing;

  /// מאתחל סריקה אוטומטית ומעקב (non-blocking)
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // הרצת סריקה ועיבוד ברקע (non-blocking)
    _runBackgroundScanAndProcess();
    
    // התחלת מעקב אחר תיקיות
    _startFileWatcher();
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
            
            final processResult = await FileScannerService.instance.processPendingFiles();
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
      
      if (result.success && result.newFilesAdded > 0) {
        // עיבוד טקסט (OCR + PDF + TXT) ברקע
        _isScanning = false;
        _isProcessing = true;
        onStatusUpdate?.call('מחלץ טקסט מקבצים...');
        
        final processResult = await FileScannerService.instance.processPendingFiles();
        onProcessComplete?.call(processResult);
        onStatusUpdate?.call('');
        
        // גיבוי אוטומטי לאחר סיום עיבוד
        _runAutoBackupIfNeeded();
      } else {
        onStatusUpdate?.call('');
        // גיבוי אוטומטי גם אם לא היו קבצים חדשים
        _runAutoBackupIfNeeded();
      }
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
        
        final processResult = await FileScannerService.instance.processPendingFiles();
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
      
      // עיבוד הקובץ החדש אוטומטית
      if (!_isProcessing) {
        _isProcessing = true;
        await FileScannerService.instance.processPendingFiles();
        _isProcessing = false;
      }
    };
    
    watcher.startWatching();
  }

  /// עוצר את כל השירותים
  Future<void> dispose() async {
    await FileWatcherService.instance.stopWatching();
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
      home: const AuthWrapper(),
      routes: {
        '/subscription': (context) => const SubscriptionScreen(),
      },
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
