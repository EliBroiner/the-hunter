import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/file_metadata.dart';
import '../services/database_service.dart';
import '../services/log_service.dart';
import '../services/localization_service.dart';
import '../utils/format_utils.dart';
import 'duplicates_screen/duplicates_logic.dart';
import 'duplicates_screen/widgets/duplicates_widgets.dart';

/// מסך איתור קבצים כפולים
class DuplicatesScreen extends StatefulWidget {
  const DuplicatesScreen({super.key});

  @override
  State<DuplicatesScreen> createState() => _DuplicatesScreenState();
}

class _DuplicatesScreenState extends State<DuplicatesScreen> {
  final _databaseService = DatabaseService.instance;
  
  bool _isScanning = false;
  double _progress = 0;
  String _statusMessage = '';

  @override
  void initState() {
    super.initState();
    _statusMessage = tr('scan_duplicates');
  }
  
  List<DuplicateGroup> _duplicateGroups = [];
  final Set<String> _selectedForDeletion = {};
  
  int get _totalWastedSpace => computeTotalWastedSpace(_duplicateGroups);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('duplicates_finder')),
        centerTitle: true,
        actions: [
          if (_duplicateGroups.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              onPressed: _selectedForDeletion.isEmpty 
                  ? null 
                  : _deleteSelected,
              tooltip: tr('delete_selected'),
            ),
        ],
      ),
      body: Column(
        children: [
          DuplicatesStatusCard(
            theme: theme,
            title: _duplicateGroups.isEmpty
                ? tr('finding_duplicates')
                : tr('duplicates_found_groups').replaceFirst('\${count}', _duplicateGroups.length.toString()),
            subtitle: _duplicateGroups.isEmpty
                ? _statusMessage
                : tr('wasted_space').replaceFirst('\${size}', formatBytes(_totalWastedSpace)),
            isScanning: _isScanning,
            onScan: _startScan,
          ),
          
          // תוצאות
          Expanded(
            child: _isScanning
                ? DuplicatesScanningView(theme: theme, progress: _progress, message: _statusMessage)
                : _duplicateGroups.isEmpty
                    ? DuplicatesEmptyState(theme: theme)
                    : _buildResultsList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(ThemeData theme) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _duplicateGroups.length,
      itemBuilder: (context, index) {
        final group = _duplicateGroups[index];
        return DuplicatesGroupCard(
          theme: theme,
          group: group,
          selectedPaths: _selectedForDeletion,
          onToggle: _toggleFileForDeletion,
          onShowInFolder: _showFileInFolder,
        );
      },
    );
  }

  void _toggleFileForDeletion(String path) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedForDeletion.contains(path)) {
        _selectedForDeletion.remove(path);
      } else {
        _selectedForDeletion.add(path);
      }
    });
  }

  Future<void> _startScan() async {
    _resetScanState();
    try {
      final allFiles = _databaseService.getAllFiles();
      if (allFiles.isEmpty) {
        _setScanComplete(tr('no_files_in_db'));
        return;
      }
      final sizeGroups = groupFilesBySize(allFiles);
      setState(() => _statusMessage = tr('identifying_duplicates'));
      final confirmed = findDuplicateGroups(sizeGroups);
      _setScanComplete(
        confirmed.isEmpty ? tr('no_duplicates') : tr('duplicate_groups_found').replaceFirst('\${count}', confirmed.length.toString()),
        groups: confirmed,
      );
      appLog('DuplicatesScreen: Found ${confirmed.length} duplicate groups');
    } catch (e) {
      appLog('DuplicatesScreen: Scan error - $e');
      _setScanError('שגיאה: $e');
    }
  }

  void _resetScanState() {
    setState(() {
      _isScanning = true;
      _progress = 0;
      _statusMessage = tr('loading_files');
      _duplicateGroups.clear();
      _selectedForDeletion.clear();
    });
  }

  void _setScanComplete(String message, {List<DuplicateGroup> groups = const []}) {
    setState(() {
      _isScanning = false;
      _progress = 1;
      _duplicateGroups = groups;
      _statusMessage = message;
    });
  }

  void _setScanError(String message) {
    setState(() {
      _isScanning = false;
      _statusMessage = message;
    });
  }

  Future<void> _deleteSelected() async {
    if (_selectedForDeletion.isEmpty) return;
    final confirmed = await _showDeleteConfirmDialog();
    if (confirmed != true) return;

    final pathsToDelete = _selectedForDeletion.toList();
    final result = await _performDeletion(pathsToDelete);
    _refreshGroupsAfterDeletion(pathsToDelete);
    await _startScan();
    if (mounted) _showDeletionResultSnackBar(result.deleted, result.freedSpace, result.failed);
  }

  Future<({int deleted, int freedSpace, int failed})> _performDeletion(List<String> paths) async {
    int deleted = 0, failed = 0, freedSpace = 0;
    for (final path in paths) {
      try {
        final file = File(path);
        freedSpace += await file.length();
        await file.delete();
        await _databaseService.deleteFileByPath(path);
        deleted++;
      } catch (e) {
        failed++;
        appLog('DuplicatesScreen: Failed to delete $path - $e');
      }
    }
    return (deleted: deleted, freedSpace: freedSpace, failed: failed);
  }

  void _refreshGroupsAfterDeletion(List<String> deletedPaths) {
    final deletedSet = deletedPaths.toSet();
    setState(() {
      _selectedForDeletion.clear();
      _duplicateGroups = _duplicateGroups
          .map((g) => DuplicateGroup(
                key: g.key,
                size: g.size,
                files: g.files.where((f) => !deletedSet.contains(f.path)).toList(),
              ))
          .where((g) => g.files.length > 1)
          .toList();
    });
  }

  void _showDeletionResultSnackBar(int deleted, int freedSpace, int failed) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Text(tr('delete_duplicates_result')
                .replaceFirst('\${deleted}', deleted.toString())
                .replaceFirst('\${size}', formatBytes(freedSpace))
                .replaceFirst('\${failed}', failed > 0 ? ', $failed failed' : '')),
          ],
        ),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<bool?> _showDeleteConfirmDialog() {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: Text(tr('delete_duplicates_title')),
        content: Text(tr('delete_duplicates_confirm').replaceFirst('\${count}', _selectedForDeletion.length.toString())),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: Text(tr('cancel'))),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
  }

  void _showFileInFolder(FileMetadata file) {
    // שיתוף הקובץ כדרך להגיע אליו
    SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: file.name));
  }

}
