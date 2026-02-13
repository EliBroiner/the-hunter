import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/cloud_storage_service.dart';
import '../services/log_service.dart';
import '../services/localization_service.dart';
import 'cloud_storage_screen/widgets/cloud_storage_widgets.dart';

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
  final bool _isUploading = false;
  final double _uploadProgress = 0;
  
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
          CloudStorageCard(
            theme: theme,
            fileCount: _files.length,
            usedStorage: _usedStorage,
            isUploading: _isUploading,
            uploadProgress: _uploadProgress,
          ),
          
          // רשימת קבצים
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _files.isEmpty
                    ? CloudStorageEmptyState(theme: theme)
                    : _buildFilesList(theme),
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
          return CloudStorageFileItem(
            theme: theme,
            file: file,
            isDownloading: _downloadProgress.containsKey(file.cloudPath),
            downloadProgress: _downloadProgress[file.cloudPath] ?? 0,
            onAction: (action) => _handleFileAction(action, file),
          );
        },
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
      if (!mounted) return;
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
      await SharePlus.instance.share(
        ShareParams(text: url, subject: file.name),
      );
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

}
