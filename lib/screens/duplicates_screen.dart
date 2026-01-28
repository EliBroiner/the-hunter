import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../models/file_metadata.dart';
import '../services/database_service.dart';
import '../services/log_service.dart';
import '../services/localization_service.dart';

/// קבוצת קבצים כפולים
class DuplicateGroup {
  final String key;
  final int size;
  final List<FileMetadata> files;
  
  DuplicateGroup({
    required this.key,
    required this.size,
    required this.files,
  });
  
  /// גודל שניתן לחסוך אם מוחקים את הכפולים
  int get wastedSpace => size * (files.length - 1);
}

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
  String _statusMessage = tr('scan_duplicates');
  
  List<DuplicateGroup> _duplicateGroups = [];
  final Set<String> _selectedForDeletion = {};
  
  int get _totalWastedSpace => 
      _duplicateGroups.fold(0, (sum, g) => sum + g.wastedSpace);

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
          // כרטיס סטטוס
          _buildStatusCard(theme),
          
          // תוצאות
          Expanded(
            child: _isScanning
                ? _buildScanningView(theme)
                : _duplicateGroups.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildResultsList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.15),
            theme.colorScheme.secondary.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.find_replace,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _duplicateGroups.isEmpty 
                          ? tr('finding_duplicates')
                          : tr('duplicates_found_groups').replaceFirst('\${count}', _duplicateGroups.length.toString()),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _duplicateGroups.isEmpty
                          ? _statusMessage
                          : tr('wasted_space').replaceFirst('\${size}', _formatSize(_totalWastedSpace)),
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isScanning ? null : _startScan,
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _isScanning 
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search),
              label: Text(_isScanning ? tr('scanning') : tr('scan_duplicates')),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScanningView(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 120,
            height: 120,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox(
                  width: 120,
                  height: 120,
                  child: CircularProgressIndicator(
                    value: _progress,
                    strokeWidth: 8,
                    backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                  ),
                ),
                Text(
                  '${(_progress * 100).toInt()}%',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _statusMessage,
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 80,
            color: Colors.green.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            tr('no_duplicates_found'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('files_clean_desc'),
            style: TextStyle(
              fontSize: 14,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
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
        return _buildDuplicateGroup(group, theme);
      },
    );
  }

  Widget _buildDuplicateGroup(DuplicateGroup group, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת קבוצה
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.content_copy,
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  tr('identical_files').replaceFirst('\${count}', group.files.length.toString()),
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    tr('wasted').replaceFirst('\${size}', _formatSize(group.wastedSpace)),
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.orange,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
          
          // רשימת קבצים
          ...group.files.asMap().entries.map((entry) {
            final idx = entry.key;
            final file = entry.value;
            final isFirst = idx == 0;
            final isSelected = _selectedForDeletion.contains(file.path);
            
            return InkWell(
              onTap: isFirst ? null : () {
                HapticFeedback.selectionClick();
                setState(() {
                  if (isSelected) {
                    _selectedForDeletion.remove(file.path);
                  } else {
                    _selectedForDeletion.add(file.path);
                  }
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? Colors.red.withValues(alpha: 0.1)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                      color: theme.colorScheme.outline.withValues(alpha: 0.1),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    // סימון קובץ מקורי או checkbox למחיקה
                    if (isFirst)
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: Colors.green.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.green,
                          size: 16,
                        ),
                      )
                    else
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) {
                          setState(() {
                            if (isSelected) {
                              _selectedForDeletion.remove(file.path);
                            } else {
                              _selectedForDeletion.add(file.path);
                            }
                          });
                        },
                        activeColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    const SizedBox(width: 10),
                    
                    // מידע קובץ
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (isFirst)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: const Text(
                                    tr('original'),
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Colors.white,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              Expanded(
                                child: Text(
                                  file.name,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w500,
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface,
                                    decoration: isSelected 
                                        ? TextDecoration.lineThrough 
                                        : null,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getShortPath(file.path),
                            style: TextStyle(
                              fontSize: 10,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    
                    // גודל ופעולות
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatSize(group.size),
                          style: TextStyle(
                            fontSize: 11,
                            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        if (!isFirst)
                          IconButton(
                            icon: const Icon(Icons.open_in_new, size: 18),
                            onPressed: () => _showFileInFolder(file),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            tooltip: tr('show_in_folder'),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Future<void> _startScan() async {
    setState(() {
      _isScanning = true;
      _progress = 0;
      _statusMessage = tr('loading_files');
      _duplicateGroups.clear();
      _selectedForDeletion.clear();
    });

    try {
      // שלב 1: טעינת כל הקבצים מה-DB
      final allFiles = _databaseService.getAllFiles();
      final total = allFiles.length;
      
      if (total == 0) {
        setState(() {
          _isScanning = false;
          _statusMessage = tr('no_files_in_db');
        });
        return;
      }
      
      // שלב 2: קיבוץ לפי גודל ושם (או לפי גודל בלבד לזיהוי מדויק יותר)
      setState(() => _statusMessage = tr('identifying_duplicates'));
      
      // קיבוץ לפי גודל - קבצים זהים בהכרח באותו גודל
      final Map<int, List<FileMetadata>> sizeGroups = {};
      
      for (int i = 0; i < total; i++) {
        final file = allFiles[i];
        // דילוג על קבצים קטנים מדי (פחות מ-50KB)
        if (file.size < 50 * 1024) continue;
        
        sizeGroups.putIfAbsent(file.size, () => []);
        sizeGroups[file.size]!.add(file);
        
        // עדכון progress
        if (i % 100 == 0) {
          setState(() {
            _progress = i / total * 0.5;
            _statusMessage = tr('checking_progress').replaceFirst('\${current}', i.toString()).replaceFirst('\${total}', total.toString());
          });
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
      
      // שלב 3: סינון רק קבוצות עם יותר מקובץ אחד
      final potentialDuplicates = sizeGroups.entries
          .where((e) => e.value.length > 1)
          .toList();
      
      setState(() {
        _progress = 0.5;
        _statusMessage = tr('potential_groups_found').replaceFirst('\${count}', potentialDuplicates.length.toString());
      });
      
      // שלב 4: אימות לפי שם (יכול להיות גם לפי hash בעתיד)
      final List<DuplicateGroup> confirmedGroups = [];
      
      for (int i = 0; i < potentialDuplicates.length; i++) {
        final entry = potentialDuplicates[i];
        final files = entry.value;
        
        // קיבוץ משנה לפי שם קובץ
        final Map<String, List<FileMetadata>> nameGroups = {};
        for (final file in files) {
          nameGroups.putIfAbsent(file.name.toLowerCase(), () => []);
          nameGroups[file.name.toLowerCase()]!.add(file);
        }
        
        // הוספת קבוצות עם יותר מקובץ אחד באותו שם
        for (final nameGroup in nameGroups.entries) {
          if (nameGroup.value.length > 1) {
            confirmedGroups.add(DuplicateGroup(
              key: '${entry.key}_${nameGroup.key}',
              size: entry.key,
              files: nameGroup.value,
            ));
          }
        }
        
        // עדכון progress
        if (i % 10 == 0) {
          setState(() {
            _progress = 0.5 + (i / potentialDuplicates.length * 0.5);
          });
          await Future.delayed(const Duration(milliseconds: 1));
        }
      }
      
      // מיון לפי מקום מבוזבז (מהגדול לקטן)
      confirmedGroups.sort((a, b) => b.wastedSpace.compareTo(a.wastedSpace));
      
      setState(() {
        _isScanning = false;
        _progress = 1;
        _duplicateGroups = confirmedGroups;
        _statusMessage = confirmedGroups.isEmpty 
            ? tr('no_duplicates')
            : tr('duplicate_groups_found').replaceFirst('\${count}', confirmedGroups.length.toString());
      });
      
      appLog('DuplicatesScreen: Found ${confirmedGroups.length} duplicate groups');
      
    } catch (e) {
      appLog('DuplicatesScreen: Scan error - $e');
      setState(() {
        _isScanning = false;
        _statusMessage = 'שגיאה: $e';
      });
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedForDeletion.isEmpty) return;
    
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: Text(tr('delete_duplicates_title')),
        content: Text(
          tr('delete_duplicates_confirm').replaceFirst('\${count}', _selectedForDeletion.length.toString()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    int deleted = 0;
    int failed = 0;
    int freedSpace = 0;
    
    for (final path in _selectedForDeletion.toList()) {
      try {
        final file = File(path);
        final size = await file.length();
        await file.delete();
        await _databaseService.deleteFileByPath(path);
        deleted++;
        freedSpace += size;
      } catch (e) {
        failed++;
        appLog('DuplicatesScreen: Failed to delete $path - $e');
      }
    }
    
    // עדכון UI
    setState(() {
      _selectedForDeletion.clear();
      // הסרת קבוצות ריקות או עם קובץ אחד
      _duplicateGroups = _duplicateGroups
          .map((g) => DuplicateGroup(
            key: g.key,
            size: g.size,
            files: g.files.where((f) => !_selectedForDeletion.contains(f.path)).toList(),
          ))
          .where((g) => g.files.length > 1)
          .toList();
    });
    
    // סריקה מחדש
    await _startScan();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 8),
              Text(tr('delete_duplicates_result')
                  .replaceFirst('\${deleted}', deleted.toString())
                  .replaceFirst('\${size}', _formatSize(freedSpace))
                  .replaceFirst('\${failed}', failed > 0 ? ', $failed failed' : '')),
            ],
          ),
          backgroundColor: Colors.green,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showFileInFolder(FileMetadata file) {
    // שיתוף הקובץ כדרך להגיע אליו
    Share.shareXFiles([XFile(file.path)], text: file.name);
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  String _getShortPath(String path) {
    final parts = path.split('/');
    if (parts.length <= 3) return path;
    return '.../${parts.sublist(parts.length - 3).join('/')}';
  }
}
