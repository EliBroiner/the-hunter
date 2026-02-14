import 'package:flutter/material.dart';
import '../services/auto_scan_manager.dart';
import '../services/file_scanner_service.dart';
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

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: SearchScreen());
  }
}
