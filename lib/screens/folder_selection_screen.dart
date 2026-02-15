import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/auto_scan_manager.dart';
import '../services/file_scanner_service.dart';
import '../services/log_service.dart';
import '../services/localization_service.dart';
import '../ui/utils/snackbar_helper.dart';
import 'folder_selection_screen/folder_selection_logic.dart';
import 'folder_selection_screen/widgets/folder_selection_widgets.dart';

/// מסך בחירת תיקיות לסריקה
/// [isInitialSetup] true = התקנה ראשונה — אין חזרה, חובה לשמור
class FolderSelectionScreen extends StatefulWidget {
  const FolderSelectionScreen({super.key, this.isInitialSetup = false});

  final bool isInitialSetup;

  @override
  State<FolderSelectionScreen> createState() => _FolderSelectionScreenState();
}

class _FolderSelectionScreenState extends State<FolderSelectionScreen> {
  static const String _selectedFoldersKey = 'selected_scan_folders';
  
  final List<FolderOption> _availableFolders = [];
  Set<String> _selectedPaths = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadFolders();
  }

  Future<void> _loadFolders() async {
    // טעינת הגדרות קיימות
    final prefs = await SharedPreferences.getInstance();
    final savedPaths = prefs.getStringList(_selectedFoldersKey);
    
    final basePath = '/storage/emulated/0';
    final folders = getPredefinedFolders(basePath);

    // בדיקה אילו תיקיות קיימות - מציגים רק קיימות
    final predefinedPaths = folders.map((f) => f.path).toSet();
    for (final folder in folders) {
      final dir = Directory(folder.path);
      folder.exists = await dir.exists();
      if (folder.exists) {
        _availableFolders.add(folder);
      }
    }

    // תיקיות מותאמות אישית (מהשמור או שנוספו בעבר)
    if (savedPaths != null) {
      for (final p in savedPaths) {
        if (p.isNotEmpty && !predefinedPaths.contains(p)) {
          final dir = Directory(p);
          if (await dir.exists()) {
            _availableFolders.add(FolderOption(
              name: p.split(Platform.pathSeparator).last,
              path: p,
              icon: Icons.folder_open,
              color: Colors.amber,
              description: p,
              isCustom: true,
            ));
          }
        }
      }
      _selectedPaths = savedPaths.toSet();
    } else {
      // התקנה ראשונה — אין נבחרות, המשתמש בוחר ידנית
      _selectedPaths = {};
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedFoldersKey, _selectedPaths.toList());
    await FileScannerService.markFolderSetupCompleted();
    appLog('[UI] Folders updated. Triggering immediate scan and UI refresh.');
    appLog('FolderSelection: Saved ${_selectedPaths.length} folders');
    AutoScanManager.instance.runFullScan().catchError((e) {
      appLog('FolderSelection: Scan after save failed - $e');
    });
  }

  Future<void> _addFolderViaBrowse() async {
    final path = await FilePicker.platform.getDirectoryPath();
    if (path == null || path.isEmpty) return;
    final name = path.split(Platform.pathSeparator).last;
    final exists = await Directory(path).exists();
    if (!exists) return;

    setState(() {
      final existing = _availableFolders.any((f) => f.path == path);
      if (!existing) {
        _availableFolders.add(FolderOption(
          name: name,
          path: path,
          icon: Icons.folder_open,
          color: Colors.amber,
          description: path,
          isCustom: true,
        ));
        _selectedPaths.add(path);
      }
    });
  }

  void _toggleFolder(FolderOption folder) {
    setState(() {
      if (_selectedPaths.contains(folder.path)) {
        _selectedPaths.remove(folder.path);
      } else {
        _selectedPaths.add(folder.path);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          widget.isInitialSetup ? tr('folder_setup_initial_title') : tr('scan_folders_title'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: widget.isInitialSetup
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _saveFolders();
              if (!context.mounted) return;
              showSuccessSnackBar(context, tr('settings_saved'));
              Navigator.of(context).pop(true);
            },
            icon: const Icon(Icons.save),
            label: Text(tr('save')),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // הסבר
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                    ),
                  ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, 
                             color: theme.colorScheme.primary, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            widget.isInitialSetup
                                ? tr('folder_setup_initial_explanation')
                                : tr('scan_folders_explanation'),
                          style: TextStyle(
                            color: theme.colorScheme.primary,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                
                // סטטיסטיקה
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondary.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          tr('folders_selected').replaceFirst('\${count}', _selectedPaths.length.toString()),
                          style: TextStyle(
                            color: theme.colorScheme.secondary,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      const Spacer(),
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _selectedPaths = _availableFolders
                                .map((f) => f.path)
                                .toSet();
                          });
                        },
                        child: Text(tr('select_all')),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedPaths.clear());
                        },
                        child: Text(tr('clear'), 
                          style: TextStyle(color: Colors.grey.shade500)),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 8),

                // כפתור הוסף תיקייה (עיון)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: OutlinedButton.icon(
                    onPressed: _addFolderViaBrowse,
                    icon: const Icon(Icons.create_new_folder),
                    label: Text(tr('add_folder_browse')),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(height: 8),

                // רשימת תיקיות
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _availableFolders.length,
                    itemBuilder: (context, index) {
                      final folder = _availableFolders[index];
                      return FolderSelectionTile(
                        theme: theme,
                        folder: folder,
                        isSelected: _selectedPaths.contains(folder.path),
                        onToggle: () => _toggleFolder(folder),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }

}
