import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/auto_scan_manager.dart';
import '../services/file_scanner_service.dart';
import '../services/log_service.dart';
import '../services/localization_service.dart';
import '../services/permission_service.dart';
import 'folder_selection_screen.dart';
import 'search_screen.dart';

/// מסך ראשי — חיפוש + סריקה אוטומטית
class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  bool _showLogPanel = false;

  @override
  void initState() {
    super.initState();
    _initializeAutoScan();
  }

  Future<void> _initializeAutoScan() async {
    final hasPermission = await PermissionService.instance.hasStoragePermission();
    if (!hasPermission) {
      final result = await PermissionService.instance.requestStoragePermission();
      if (result != PermissionResult.permanentlyDenied && result != PermissionResult.denied) {
        // משתמש דחה — יוכל לנסות שוב מהגדרות
      }
    }

    final hasCompleted = await FileScannerService.hasCompletedFolderSetup();
    if (!hasCompleted && mounted) {
      final completed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (context) => const FolderSelectionScreen(isInitialSetup: true),
          fullscreenDialog: true,
        ),
      );
      if (!mounted) return;
      if (completed != true) return;
    }

    final manager = AutoScanManager.instance;

    manager.onStatusUpdate = (status) {
      if (!mounted) return;
    };

    manager.onScanComplete = (result) {
      if (!mounted) return;
    };

    manager.onProcessComplete = (result) {
      if (!mounted) return;
    };

    manager.onNewFileFound = (path) {
      if (!mounted) return;
    };

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
    return Scaffold(
      body: Column(
        children: [
          const Expanded(child: SearchScreen()),
          if (_showLogPanel) _buildLogPanel(),
        ],
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.miniStartFloat,
      floatingActionButton: FloatingActionButton.small(
        heroTag: 'logs',
        onPressed: () => setState(() => _showLogPanel = !_showLogPanel),
        backgroundColor: _showLogPanel ? Colors.red : Colors.grey.shade800.withValues(alpha: 0.5),
        child: Icon(_showLogPanel ? Icons.close : Icons.bug_report, size: 18),
      ),
    );
  }

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
