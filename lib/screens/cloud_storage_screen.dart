import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/cloud_storage_service.dart';
import '../services/log_service.dart';
import '../services/localization_service.dart';

/// מסך אחסון ענן
class CloudStorageScreen extends StatefulWidget {
  const CloudStorageScreen({super.key});

  @override
  State<CloudStorageScreen> createState() => _CloudStorageScreenState();
}

class _CloudStorageScreenState extends State<CloudStorageScreen> {
  final _cloudService = CloudStorageService.instance;
  
  bool _isLoading = true;
  List<CloudFile> _files = [];
  int _usedStorage = 0;
  
  // העלאה
  bool _isUploading = false;
  double _uploadProgress = 0;
  
  // הורדה
  final Map<String, double> _downloadProgress = {};

  @override
  void initState() {
    super.initState();
    _loadFiles();
  }

  Future<void> _loadFiles() async {
    setState(() => _isLoading = true);
    
    try {
      final files = await _cloudService.listFiles();
      final storage = await _cloudService.getUsedStorage();
      
      setState(() {
        _files = files;
        _usedStorage = storage;
        _isLoading = false;
      });
    } catch (e) {
      appLog('CloudScreen: Load error - $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(tr('cloud_storage_title')),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadFiles,
          ),
        ],
      ),
      body: Column(
        children: [
          // כרטיס סטטיסטיקות
          _buildStorageCard(theme),
          
          // רשימת קבצים
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? _buildEmptyState(theme)
                    : _buildFilesList(theme),
          ),
        ],
      ),
    );
  }

  Widget _buildStorageCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.withValues(alpha: 0.15),
            Colors.cyan.withValues(alpha: 0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: Colors.blue.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Colors.blue, Colors.cyan]),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.cloud, color: Colors.white, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tr('cloud_storage_title'),
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      tr('cloud_storage_subtitle').replaceFirst('\${count}', _files.length.toString()).replaceFirst('\${size}', _cloudService.formatSize(_usedStorage)),
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
          if (_isUploading) ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _uploadProgress,
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
            ),
            const SizedBox(height: 8),
            Text(
              tr('uploading_progress').replaceFirst('\${percent}', (_uploadProgress * 100).toInt().toString()),
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
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
            Icons.cloud_off,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            tr('no_files_cloud'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('upload_files_hint'),
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList(ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadFiles,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _files.length,
        itemBuilder: (context, index) {
          final file = _files[index];
          return _buildFileItem(theme, file);
        },
      ),
    );
  }

  Widget _buildFileItem(ThemeData theme, CloudFile file) {
    final isDownloading = _downloadProgress.containsKey(file.cloudPath);
    final progress = _downloadProgress[file.cloudPath] ?? 0;
    
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _getFileColor(file.name).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(
                child: Icon(
                  _getFileIcon(file.name),
                  color: _getFileColor(file.name),
                  size: 22,
                ),
              ),
            ),
            title: Text(
              file.name,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${_cloudService.formatSize(file.size)} • ${_formatDate(file.uploadedAt)}',
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
            trailing: PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'download',
                  child: Row(
                    children: [
                      const Icon(Icons.download, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('download')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'share',
                  child: Row(
                    children: [
                      const Icon(Icons.share, size: 20),
                      const SizedBox(width: 12),
                      Text(tr('share_link')),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'delete',
                  child: Row(
                    children: [
                      const Icon(Icons.delete, size: 20, color: Colors.red),
                      const SizedBox(width: 12),
                      Text(tr('delete'), style: const TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
              onSelected: (value) => _handleFileAction(value, file),
            ),
          ),
          if (isDownloading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _handleFileAction(String action, CloudFile file) async {
    switch (action) {
      case 'download':
        await _downloadFile(file);
        break;
      case 'share':
        await _shareLink(file);
        break;
      case 'delete':
        await _deleteFile(file);
        break;
    }
  }

  Future<void> _downloadFile(CloudFile file) async {
    final downloadsDir = await getExternalStorageDirectory();
    if (downloadsDir == null) {
      _showMessage(tr('access_storage_error'));
      return;
    }
    
    final localPath = '${downloadsDir.path}/${file.name}';
    
    setState(() {
      _downloadProgress[file.cloudPath] = 0;
    });
    
    final result = await _cloudService.downloadFile(
      file.cloudPath,
      localPath,
      onProgress: (progress) {
        setState(() {
          _downloadProgress[file.cloudPath] = progress;
        });
      },
    );
    
    setState(() {
      _downloadProgress.remove(file.cloudPath);
    });
    
    if (result != null) {
      HapticFeedback.mediumImpact();
      
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(tr('download_complete_title')),
          content: Text(tr('download_complete_content')),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('close')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('open')),
            ),
          ],
        ),
      );
      
      if (open == true) {
        await OpenFilex.open(localPath);
      }
    } else {
      _showMessage(tr('download_error'));
    }
  }

  Future<void> _shareLink(CloudFile file) async {
    final url = await _cloudService.getDownloadUrl(file.cloudPath);
    
    if (url != null) {
      await Share.share(url, subject: file.name);
    } else {
      _showMessage(tr('create_link_error'));
    }
  }

  Future<void> _deleteFile(CloudFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('delete_file_title')),
        content: Text(tr('delete_cloud_file_confirm').replaceFirst('\${name}', file.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('delete')),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final success = await _cloudService.deleteFile(file.cloudPath);
    
    if (success) {
      _showMessage(tr('file_deleted'));
      _loadFiles();
    } else {
      _showMessage(tr('delete_error_short'));
    }
  }

  void _showMessage(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  Color _getFileColor(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return Colors.purple;
      case 'mp4': case 'mov': case 'avi':
        return Colors.pink;
      case 'pdf':
        return Colors.red;
      case 'doc': case 'docx':
        return Colors.blue;
      case 'xls': case 'xlsx':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  IconData _getFileIcon(String name) {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    switch (ext) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp':
        return Icons.image;
      case 'mp4': case 'mov': case 'avi':
        return Icons.movie;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc': case 'docx':
        return Icons.description;
      case 'xls': case 'xlsx':
        return Icons.table_chart;
      default:
        return Icons.insert_drive_file;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) {
      return 'היום';
    } else if (diff.inDays == 1) {
      return 'אתמול';
    } else if (diff.inDays < 7) {
      return 'לפני ${diff.inDays} ימים';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }
}
