import 'package:flutter/material.dart';
import 'models/file_metadata.dart';
import 'screens/search_screen.dart';
import 'services/database_service.dart';
import 'services/file_scanner_service.dart';
import 'services/file_watcher_service.dart';
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
          seedColor: Colors.teal,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
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
          // באנר סריקה אוטומטית
          if (_showScanBanner)
            MaterialBanner(
              content: Text(_scanMessage),
              leading: const Icon(Icons.sync, color: Colors.green),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer,
              actions: [
                TextButton(
                  onPressed: () => setState(() => _showScanBanner = false),
                  child: const Text('סגור'),
                ),
              ],
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
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) => setState(() => _currentIndex = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.search),
            selectedIcon: Icon(Icons.search),
            label: 'חיפוש',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_copy_outlined),
            selectedIcon: Icon(Icons.folder_copy),
            label: 'סריקה',
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('The Hunter'),
        centerTitle: true,
        actions: [
          if (_files.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearDatabase,
              tooltip: 'מחק הכל',
            ),
        ],
      ),
      body: Column(
        children: [
          // כרטיס סטטיסטיקות
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildStatItem(Icons.folder, 'קבצים', _totalFiles.toString()),
                  _buildStatItem(
                    Icons.storage,
                    'גודל כולל',
                    _calculateTotalSize(),
                  ),
                  _buildStatItem(
                    Icons.source,
                    'מקורות',
                    _scannedSources.where((s) => s.exists).length.toString(),
                  ),
                ],
              ),
            ),
          ),
          
          // כרטיס מקורות שנסרקו
          if (_scannedSources.isNotEmpty)
            _buildScannedSourcesCard(),
          
          // הודעת שגיאה
          if (_errorMessage != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_errorMessage!)),
                ],
              ),
            ),
          
          // רשימת קבצים
          Expanded(
            child: _files.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    itemCount: _files.length,
                    itemBuilder: (context, index) {
                      final file = _files[index];
                      return _buildFileItem(file);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // כפתור עיבוד OCR
          FloatingActionButton.extended(
            heroTag: 'process',
            onPressed: (_isProcessing || _isScanning) ? null : _processFiles,
            icon: _isProcessing
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.text_snippet),
            label: Text(_isProcessing ? _processingStatus : 'עבד תמונות (OCR)'),
            backgroundColor: Theme.of(context).colorScheme.secondary,
          ),
          const SizedBox(height: 12),
          // כפתור סריקה
          FloatingActionButton.extended(
            heroTag: 'scan',
            onPressed: (_isScanning || _isProcessing) ? null : _scanAllFolders,
            icon: _isScanning
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.search),
            label: Text(_isScanning ? _scanningStatus : 'סרוק הכל'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatItem(IconData icon, String label, String value) {
    return Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 8),
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        Text(value, style: Theme.of(context).textTheme.titleLarge),
      ],
    );
  }

  /// בונה כרטיס מקורות שנסרקו
  Widget _buildScannedSourcesCard() {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ExpansionTile(
        leading: const Icon(Icons.folder_special),
        title: const Text('מקורות שנסרקו'),
        subtitle: Text(
          '${_scannedSources.where((s) => s.exists).length} תיקיות נמצאו',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        children: _scannedSources.map((source) => _buildSourceItem(source)).toList(),
      ),
    );
  }

  /// בונה פריט מקור בודד
  Widget _buildSourceItem(ScanSource source) {
    return ListTile(
      dense: true,
      leading: Icon(
        source.exists ? Icons.check_circle : Icons.cancel,
        color: source.exists ? Colors.green : Colors.grey,
        size: 20,
      ),
      title: Text(
        source.name,
        style: TextStyle(
          color: source.exists ? null : Colors.grey,
        ),
      ),
      subtitle: Text(
        source.exists 
            ? '${source.filesFound} קבצים נמצאו'
            : 'לא נמצא',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
          color: source.exists ? Colors.green : Colors.grey,
        ),
      ),
      trailing: source.exists 
          ? Text(
              source.filesFound.toString(),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          : null,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_open,
            size: 80,
            color: Colors.grey.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'אין קבצים במסד הנתונים',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Colors.grey,
                ),
          ),
          const SizedBox(height: 8),
          const Text(
            'לחץ על "סרוק הכל" כדי לסרוק תמונות ו-PDF מכל התיקיות',
            style: TextStyle(color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          // כפתור אבחון
          OutlinedButton.icon(
            onPressed: _showDiagnostics,
            icon: const Icon(Icons.bug_report),
            label: const Text('בדיקת תיקיות'),
          ),
        ],
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
    final hasText = file.extractedText != null && file.extractedText!.isNotEmpty;
    
    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: _getExtensionColor(file.extension),
            child: Text(
              file.extension.isEmpty ? '?' : file.extension.substring(0, file.extension.length > 3 ? 3 : file.extension.length).toUpperCase(),
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ),
          // אינדיקטור אם נמצא טקסט
          if (hasText)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.black, width: 1.5),
                ),
                child: const Icon(Icons.check, size: 10, color: Colors.white),
              ),
            ),
        ],
      ),
      title: Text(
        file.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${file.readableSize} • ${_formatDate(file.lastModified)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (hasText)
            Text(
              file.extractedText!.length > 50 
                  ? '${file.extractedText!.substring(0, 50)}...' 
                  : file.extractedText!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                    fontStyle: FontStyle.italic,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 20),
        onPressed: () {
          _databaseService.deleteFile(file.id);
          _loadFiles();
        },
      ),
      onTap: hasText ? () => _showExtractedText(file) : null,
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
