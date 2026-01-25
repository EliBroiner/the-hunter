import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/file_metadata.dart';
import 'screens/search_screen.dart';
import 'services/database_service.dart';
import 'services/file_scanner_service.dart';
import 'services/file_watcher_service.dart';
import 'services/log_service.dart';
import 'services/permission_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // אתחול מסד הנתונים
  await DatabaseService.instance.init();
  
  runApp(const TheHunterApp());
}

/// מנהל סריקה אוטומטית ומעקב קבצים
class AutoScanManager {
  static final AutoScanManager _instance = AutoScanManager._();
  static AutoScanManager get instance => _instance;
  
  AutoScanManager._();
  
  bool _isInitialized = false;
  bool _isScanning = false;
  
  /// callback כשסריקה הושלמה
  Function(ScanResult result)? onScanComplete;
  
  /// callback כשנמצא קובץ חדש
  Function(String path)? onNewFileFound;

  /// מאתחל סריקה אוטומטית ומעקב (non-blocking)
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    // הרצת סריקה ברקע (non-blocking)
    _runBackgroundScan();
    
    // התחלת מעקב אחר תיקיות
    _startFileWatcher();
  }

  /// מריץ סריקה ברקע
  Future<void> _runBackgroundScan() async {
    if (_isScanning) return;
    _isScanning = true;

    try {
      // סריקה חכמה - רק קבצים חדשים
      final result = await FileScannerService.instance.scanNewFilesOnly(
        runCleanup: true,
      );
      
      onScanComplete?.call(result);
    } finally {
      _isScanning = false;
    }
  }

  /// מתחיל מעקב אחר קבצים חדשים
  void _startFileWatcher() {
    final watcher = FileWatcherService.instance;
    
    watcher.onNewFile = (path) {
      onNewFileFound?.call(path);
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
          seedColor: const Color(0xFF6366F1), // אינדיגו מודרני
          brightness: Brightness.dark,
          surface: const Color(0xFF0F0F23), // רקע כהה יותר
          primary: const Color(0xFF818CF8), // סגול בהיר
          secondary: const Color(0xFF34D399), // ירוק מנטה
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFF0F0F23),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
        cardTheme: CardTheme(
          color: const Color(0xFF1E1E3F),
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: const Color(0xFF1E1E3F),
          indicatorColor: const Color(0xFF6366F1).withValues(alpha: 0.3),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: const Color(0xFF6366F1),
          foregroundColor: Colors.white,
          elevation: 4,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
      ),
      home: const MainScreen(),
    );
  }
}

/// מסך ראשי עם ניווט תחתון
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentIndex = 0;
  bool _showScanBanner = false;
  String _scanMessage = '';
  bool _showLogPanel = false;

  @override
  void initState() {
    super.initState();
    _initializeAutoScan();
  }

  /// מאתחל סריקה אוטומטית ברקע
  Future<void> _initializeAutoScan() async {
    final manager = AutoScanManager.instance;
    
    manager.onScanComplete = (result) {
      if (!mounted) return;
      
      if (result.newFilesAdded > 0 || result.staleFilesRemoved > 0) {
        setState(() {
          _showScanBanner = true;
          _scanMessage = result.toString();
        });
        
        // הסתרת הבאנר אחרי 4 שניות
        Future.delayed(const Duration(seconds: 4), () {
          if (mounted) setState(() => _showScanBanner = false);
        });
      }
    };
    
    manager.onNewFileFound = (path) {
      if (!mounted) return;
      
      final fileName = path.split('/').last;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('קובץ חדש נמצא: $fileName'),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    };
    
    // הרצת אתחול (non-blocking)
    manager.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // באנר סריקה אוטומטית - מודרני
          if (_showScanBanner)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
                    Theme.of(context).colorScheme.secondary.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      color: Theme.of(context).colorScheme.secondary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _scanMessage,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => setState(() => _showScanBanner = false),
                    padding: EdgeInsets.zero,
                  ),
                ],
              ),
            ),
          // המסך הנוכחי - IndexedStack שומר את המצב של כל הטאבים
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: const [
                SearchScreen(),
                ScannerScreen(),
              ],
            ),
          ),
          // פאנל לוגים
          if (_showLogPanel) _buildLogPanel(),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF1E1E3F),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 10,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildNavItem(0, Icons.search, Icons.search, 'חיפוש'),
                _buildNavItem(1, Icons.radar_outlined, Icons.radar, 'סריקה'),
              ],
            ),
          ),
        ),
      ),
      // כפתור צף להצגת לוגים - מוסתר בברירת מחדל
      floatingActionButtonLocation: FloatingActionButtonLocation.miniStartFloat,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'logs',
        onPressed: () => setState(() => _showLogPanel = !_showLogPanel),
        backgroundColor: _showLogPanel ? Colors.red : Colors.grey.shade800.withValues(alpha: 0.5),
        child: Icon(_showLogPanel ? Icons.close : Icons.bug_report, size: 18),
      ),
    );
  }
  
  /// בונה פריט ניווט מודרני
  Widget _buildNavItem(int index, IconData icon, IconData selectedIcon, String label) {
    final isSelected = _currentIndex == index;
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: () {
        LogService.instance.clear();
        setState(() => _currentIndex = index);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: EdgeInsets.symmetric(
          horizontal: isSelected ? 20 : 16,
          vertical: 10,
        ),
        decoration: BoxDecoration(
          gradient: isSelected 
              ? LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.3),
                    theme.colorScheme.secondary.withValues(alpha: 0.3),
                  ],
                )
              : null,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Icon(
              isSelected ? selectedIcon : icon,
              color: isSelected ? theme.colorScheme.primary : Colors.grey,
              size: 22,
            ),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ],
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
          // כותרת
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: Colors.grey.shade900,
            child: Row(
              children: [
                const Icon(Icons.terminal, size: 16, color: Colors.green),
                const SizedBox(width: 8),
                const Text('לוגים', style: TextStyle(color: Colors.white, fontSize: 12)),
                const Spacer(),
                // כפתור העתקה
                IconButton(
                  icon: const Icon(Icons.copy, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: LogService.instance.getAllLogs()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('לוגים הועתקו'), duration: Duration(seconds: 1)),
                    );
                  },
                ),
                // כפתור ניקוי
                IconButton(
                  icon: const Icon(Icons.delete_outline, size: 16, color: Colors.white70),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  onPressed: () {
                    LogService.instance.clear();
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
          // תוכן הלוגים
          Expanded(
            child: ValueListenableBuilder<List<String>>(
              valueListenable: LogService.instance.logsNotifier,
              builder: (context, logs, _) {
                if (logs.isEmpty) {
                  return const Center(
                    child: Text('אין לוגים', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(8),
                  itemCount: logs.length,
                  itemBuilder: (context, index) {
                    final log = logs[logs.length - 1 - index];
                    return Text(
                      log,
                      style: TextStyle(
                        color: log.contains('ERROR') ? Colors.red : Colors.green.shade300,
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

/// מסך סריקה - סריקת קבצים ועיבוד OCR
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final _fileScannerService = FileScannerService.instance;
  final _databaseService = DatabaseService.instance;
  
  bool _isScanning = false;
  bool _isProcessing = false;
  String _processingStatus = '';
  String _scanningStatus = '';
  List<FileMetadata> _files = [];
  List<ScanSource> _scannedSources = [];
  String? _errorMessage;
  int _totalFiles = 0;

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  /// טוען את הקבצים מהמסד
  void _loadFiles() {
    final files = _databaseService.getAllFiles();
    final count = _databaseService.getFilesCount();
    setState(() {
      _files = files;
      _totalFiles = count;
    });
  }

  /// סורק את כל התיקיות הנתמכות
  Future<void> _scanAllFolders() async {
    setState(() {
      _isScanning = true;
      _scanningStatus = 'מתחיל סריקה...';
      _errorMessage = null;
      _scannedSources = [];
    });

    final result = await _fileScannerService.scanAllSources(
      onProgress: (sourceName, current, total) {
        if (mounted) {
          setState(() => _scanningStatus = 'סורק $sourceName ($current/$total)');
        }
      },
    );

    if (result.success) {
      _loadFiles();
      setState(() => _scannedSources = result.scannedSources);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('נסרקו ${result.filesScanned} קבצים מ-${result.availableSourcesCount} מקורות'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      setState(() => _errorMessage = result.error);
      
      if (result.permissionDenied && mounted) {
        _showPermissionDialog();
      }
    }

    setState(() {
      _isScanning = false;
      _scanningStatus = '';
    });
  }

  /// מעבד קבצי תמונות עם OCR
  Future<void> _processFiles() async {
    setState(() {
      _isProcessing = true;
      _processingStatus = 'מתחיל עיבוד...';
      _errorMessage = null;
    });

    final result = await _fileScannerService.processPendingFiles(
      onProgress: (current, total) {
        if (mounted) {
          setState(() => _processingStatus = 'מעבד קובץ $current מתוך $total');
        }
      },
    );

    if (result.success) {
      _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'העיבוד הושלם'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      setState(() => _errorMessage = result.error);
    }

    setState(() {
      _isProcessing = false;
      _processingStatus = '';
    });
  }

  /// מציג דיאלוג הרשאות
  void _showPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('נדרשות הרשאות'),
        content: const Text(
          'לאפליקציה נדרשות הרשאות גישה לאחסון כדי לסרוק את תיקיית Downloads.\n\n'
          'אנא אשר את ההרשאות בהגדרות האפליקציה.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              PermissionService.instance.openSettings();
            },
            child: const Text('פתח הגדרות'),
          ),
        ],
      ),
    );
  }

  /// מוחק את כל הקבצים מהמסד
  Future<void> _clearDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('מחיקת נתונים'),
        content: const Text('האם אתה בטוח שברצונך למחוק את כל הקבצים מהמסד?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('מחק'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      _databaseService.clearAll();
      _loadFiles();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('כל הנתונים נמחקו')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // Header מודרני
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                theme.colorScheme.primary,
                                theme.colorScheme.secondary,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.radar, color: Colors.white, size: 28),
                        ),
                        const SizedBox(width: 16),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'The Hunter',
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'סורק קבצים חכם',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    
                    // כרטיסי סטטיסטיקות
                    Row(
                      children: [
                        Expanded(child: _buildModernStatCard(
                          icon: Icons.folder_copy,
                          value: _totalFiles.toString(),
                          label: 'קבצים',
                          color: theme.colorScheme.primary,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildModernStatCard(
                          icon: Icons.storage,
                          value: _calculateTotalSize(),
                          label: 'גודל',
                          color: theme.colorScheme.secondary,
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildModernStatCard(
                          icon: Icons.source,
                          value: _scannedSources.where((s) => s.exists).length.toString(),
                          label: 'מקורות',
                          color: Colors.orange,
                        )),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            
            // כפתורי פעולה
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.search,
                        label: _isScanning ? _scanningStatus : 'סרוק הכל',
                        isLoading: _isScanning,
                        onPressed: (_isScanning || _isProcessing) ? null : _scanAllFolders,
                        isPrimary: true,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildActionButton(
                        icon: Icons.text_snippet,
                        label: _isProcessing ? _processingStatus : 'OCR',
                        isLoading: _isProcessing,
                        onPressed: (_isScanning || _isProcessing) ? null : _processFiles,
                        isPrimary: false,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            
            // כרטיס מקורות שנסרקו
            if (_scannedSources.isNotEmpty)
              SliverToBoxAdapter(child: _buildScannedSourcesCard()),
            
            // הודעת שגיאה
            if (_errorMessage != null)
              SliverToBoxAdapter(
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(child: Text(_errorMessage!)),
                    ],
                  ),
                ),
              ),
            
            // רשימת קבצים או מצב ריק
            if (_files.isEmpty)
              SliverFillRemaining(child: _buildEmptyState())
            else
              SliverPadding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                sliver: SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) => _buildFileItem(_files[index]),
                    childCount: _files.length,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
  
  /// בונה כפתור פעולה מודרני
  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isLoading,
    required VoidCallback? onPressed,
    required bool isPrimary,
  }) {
    final theme = Theme.of(context);
    
    return Material(
      color: isPrimary 
          ? theme.colorScheme.primary 
          : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: isPrimary ? null : Border.all(
              color: theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (isLoading)
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: isPrimary ? Colors.white : theme.colorScheme.primary,
                  ),
                )
              else
                Icon(icon, size: 20, color: isPrimary ? Colors.white : theme.colorScheme.primary),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? Colors.white : theme.colorScheme.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// בונה כרטיס סטטיסטיקה מודרני
  Widget _buildModernStatCard({
    required IconData icon,
    required String value,
    required String label,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  // הוסר: כפתור מחיקה מסוכן
  // _clearDatabase() עדיין קיים אבל לא נגיש מה-UI
  
  /// בונה כרטיס מקורות שנסרקו - מודרני
  Widget _buildScannedSourcesCard() {
    final theme = Theme.of(context);
    final availableSources = _scannedSources.where((s) => s.exists).toList();
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
      ),
      child: ExpansionTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(Icons.folder_special, color: theme.colorScheme.primary, size: 20),
        ),
        title: const Text('מקורות שנסרקו', style: TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${availableSources.length} תיקיות פעילות',
          style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
        ),
        children: _scannedSources.map((source) => _buildSourceItem(source)).toList(),
      ),
    );
  }

  /// בונה פריט מקור בודד - מודרני
  Widget _buildSourceItem(ScanSource source) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: source.exists 
            ? theme.colorScheme.secondary.withValues(alpha: 0.1)
            : Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            source.exists ? Icons.check_circle : Icons.cancel,
            color: source.exists ? theme.colorScheme.secondary : Colors.grey,
            size: 18,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              source.name,
              style: TextStyle(
                color: source.exists ? Colors.white : Colors.grey,
                fontWeight: source.exists ? FontWeight.w500 : FontWeight.normal,
              ),
            ),
          ),
          if (source.exists)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${source.filesFound}',
                style: TextStyle(
                  color: theme.colorScheme.secondary,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                    theme.colorScheme.secondary.withValues(alpha: 0.2),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.radar,
                size: 64,
                color: theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'מוכן לסריקה',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'לחץ על "סרוק הכל" למעלה כדי למצוא\nתמונות, וידאו ומסמכים',
              style: TextStyle(color: Colors.grey.shade400),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
  
  /// מציג מידע אבחוני על התיקיות
  Future<void> _showDiagnostics() async {
    final sources = _fileScannerService.getScanSources();
    final results = <String>[];
    
    for (final source in sources) {
      final exists = await _fileScannerService.directoryExists(source.path);
      results.add('${source.name}: ${exists ? "✓ קיים" : "✗ לא נמצא"}\n${source.path}');
    }
    
    if (mounted) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('אבחון תיקיות'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('נתיב בסיס: ${_fileScannerService.basePath}'),
                const Divider(),
                ...results.map((r) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Text(r, style: const TextStyle(fontSize: 12)),
                )),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('סגור'),
            ),
          ],
        ),
      );
    }
  }

  Widget _buildFileItem(FileMetadata file) {
    final theme = Theme.of(context);
    final hasText = file.extractedText != null && file.extractedText!.isNotEmpty;
    final color = _getExtensionColor(file.extension);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasText 
              ? theme.colorScheme.secondary.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: hasText ? () => _showExtractedText(file) : null,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // אייקון סוג קובץ
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      file.extension.isEmpty 
                          ? '?' 
                          : file.extension.substring(0, file.extension.length > 3 ? 3 : file.extension.length).toUpperCase(),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: color,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                // פרטי קובץ
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(Icons.storage, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            file.readableSize,
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                          const SizedBox(width: 12),
                          Icon(Icons.access_time, size: 12, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            _formatDate(file.lastModified),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                          ),
                        ],
                      ),
                      if (hasText) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(Icons.text_snippet, size: 12, color: theme.colorScheme.secondary),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                file.extractedText!.replaceAll('\n', ' ').length > 40 
                                    ? '${file.extractedText!.replaceAll('\n', ' ').substring(0, 40)}...' 
                                    : file.extractedText!.replaceAll('\n', ' '),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: theme.colorScheme.secondary,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                // אייקון טקסט נמצא
                if (hasText)
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.secondary.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.check,
                      size: 14,
                      color: theme.colorScheme.secondary,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// מציג את הטקסט שחולץ מהקובץ
  void _showExtractedText(FileMetadata file) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(file.name),
        content: SingleChildScrollView(
          child: Text(file.extractedText ?? 'אין טקסט'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('סגור'),
          ),
        ],
      ),
    );
  }

  Color _getExtensionColor(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return Colors.red;
      case 'doc':
      case 'docx':
        return Colors.blue;
      case 'xls':
      case 'xlsx':
        return Colors.green;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Colors.purple;
      case 'mp3':
      case 'wav':
      case 'flac':
        return Colors.orange;
      case 'mp4':
      case 'avi':
      case 'mkv':
        return Colors.pink;
      case 'zip':
      case 'rar':
      case '7z':
        return Colors.brown;
      default:
        return Colors.grey;
    }
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }

  String _calculateTotalSize() {
    if (_files.isEmpty) return '0 B';
    final totalBytes = _files.fold<int>(0, (sum, file) => sum + file.size);
    if (totalBytes < 1024) return '$totalBytes B';
    if (totalBytes < 1024 * 1024) return '${(totalBytes / 1024).toStringAsFixed(1)} KB';
    if (totalBytes < 1024 * 1024 * 1024) return '${(totalBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(totalBytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}
