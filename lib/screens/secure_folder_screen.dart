import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../services/secure_folder_service.dart';
import '../services/log_service.dart';
import '../services/localization_service.dart';

/// מסך תיקייה מאובטחת
class SecureFolderScreen extends StatefulWidget {
  const SecureFolderScreen({super.key});

  @override
  State<SecureFolderScreen> createState() => _SecureFolderScreenState();
}

class _SecureFolderScreenState extends State<SecureFolderScreen> {
  final _secureFolderService = SecureFolderService.instance;
  final _pinController = TextEditingController();
  
  bool _isLoading = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    // נעילה אוטומטית ביציאה
    _secureFolderService.lock();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // אם אין PIN מוגדר - מסך הגדרת PIN
    if (!_secureFolderService.hasPin) {
      return _buildSetupPinScreen(theme);
    }
    
    // אם התיקייה נעולה - מסך נעילה
    if (!_secureFolderService.isUnlocked) {
      return _buildUnlockScreen(theme);
    }
    
    // תיקייה פתוחה - מסך קבצים
    return _buildFilesScreen(theme);
  }

  /// מסך הגדרת PIN
  Widget _buildSetupPinScreen(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('תיקייה מאובטחת'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.purple.withValues(alpha: 0.2),
                    Colors.blue.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: Colors.purple.withValues(alpha: 0.3),
                ),
              ),
              child: const Icon(
                Icons.lock_outline,
                size: 64,
                color: Colors.purple,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              tr('setup_pin'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('setup_pin_desc'),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            _buildPinInput(theme),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _setupPin,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('set_pin_button')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// מסך נעילה
  Widget _buildUnlockScreen(ThemeData theme) {
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('תיקייה מאובטחת'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.orange.withValues(alpha: 0.2),
                    Colors.red.withValues(alpha: 0.1),
                  ],
                ),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.lock,
                size: 64,
                color: Colors.orange,
              ),
            ),
            const SizedBox(height: 32),
            Text(
              tr('enter_pin'),
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('secured_files_count').replaceFirst('\${count}', _secureFolderService.fileCount.toString()),
              style: TextStyle(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 32),
            _buildPinInput(theme),
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                style: const TextStyle(color: Colors.red),
              ),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _unlock,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(tr('unlock')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// מסך קבצים
  Widget _buildFilesScreen(ThemeData theme) {
    final files = _secureFolderService.files;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_open, color: Colors.green, size: 20),
            const SizedBox(width: 8),
            Text(tr('secure_folder')),
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.lock),
            onPressed: () {
              _secureFolderService.lock();
              setState(() {});
            },
            tooltip: tr('lock'),
          ),
        ],
      ),
      body: files.isEmpty
          ? _buildEmptyState(theme)
          : _buildFilesList(theme, files),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.folder_off_outlined,
            size: 80,
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            tr('folder_empty'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('add_files_hint'),
            style: TextStyle(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilesList(ThemeData theme, List<SecureFile> files) {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: files.length,
      itemBuilder: (context, index) {
        final file = files[index];
        return _buildFileItem(theme, file);
      },
    );
  }

  Widget _buildFileItem(ThemeData theme, SecureFile file) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: _getFileColor(file.extension).withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Center(
            child: Icon(
              _getFileIcon(file.extension),
              color: _getFileColor(file.extension),
              size: 22,
            ),
          ),
        ),
        title: Text(
          '${file.name}.${file.extension}',
          style: const TextStyle(fontWeight: FontWeight.w500),
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          _formatSize(file.size),
          style: TextStyle(
            fontSize: 12,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        ),
        trailing: PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: 'open',
              child: Row(
                children: [
                  Icon(Icons.open_in_new, size: 20),
                  SizedBox(width: 12),
                  Text(tr('open')),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'share',
              child: Row(
                children: [
                  Icon(Icons.share, size: 20),
                  SizedBox(width: 12),
                  Text(tr('share')),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'restore',
              child: Row(
                children: [
                  Icon(Icons.restore, size: 20, color: Colors.blue),
                  SizedBox(width: 12),
                  Text(tr('restore_original'), style: TextStyle(color: Colors.blue)),
                ],
              ),
            ),
            const PopupMenuItem(
              value: 'delete',
              child: Row(
                children: [
                  Icon(Icons.delete, size: 20, color: Colors.red),
                  SizedBox(width: 12),
                  Text(tr('delete'), style: TextStyle(color: Colors.red)),
                ],
              ),
            ),
          ],
          onSelected: (value) => _handleFileAction(value, file),
        ),
        onTap: () => _openFile(file),
      ),
    );
  }

  Widget _buildPinInput(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: TextField(
        controller: _pinController,
        keyboardType: TextInputType.number,
        maxLength: 4,
        obscureText: true,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          letterSpacing: 16,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          counterText: '',
          hintText: '• • • •',
        ),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
        ],
      ),
    );
  }

  Future<void> _setupPin() async {
    final pin = _pinController.text;
    
    if (pin.length < 4) {
      setState(() => _error = tr('pin_length_error'));
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    final success = await _secureFolderService.setPin(pin);
    
    setState(() {
      _isLoading = false;
      if (!success) {
        _error = tr('pin_setup_error');
      }
      _pinController.clear();
    });
  }

  Future<void> _unlock() async {
    final pin = _pinController.text;
    
    if (pin.length < 4) {
      setState(() => _error = tr('pin_length_error'));
      return;
    }
    
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    await Future.delayed(const Duration(milliseconds: 300));
    
    final success = _secureFolderService.unlock(pin);
    
    setState(() {
      _isLoading = false;
      if (!success) {
        _error = tr('pin_incorrect');
        HapticFeedback.heavyImpact();
      }
      _pinController.clear();
    });
  }

  void _handleFileAction(String action, SecureFile file) async {
    switch (action) {
      case 'open':
        _openFile(file);
        break;
      case 'share':
        _shareFile(file);
        break;
      case 'restore':
        _restoreFile(file);
        break;
      case 'delete':
        _deleteFile(file);
        break;
    }
  }

  void _openFile(SecureFile file) async {
    final path = _secureFolderService.getSecureFilePath(file.secureId);
    if (path == null) return;
    
    try {
      final result = await OpenFilex.open(path);
      if (result.type != ResultType.done) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('open_error_short'))),
          );
        }
      }
    } catch (e) {
      appLog('SecureFolder: Open error - $e');
    }
  }

  void _shareFile(SecureFile file) async {
    final path = _secureFolderService.getSecureFilePath(file.secureId);
    if (path == null) return;
    
    try {
      await Share.shareXFiles([XFile(path)], text: file.name);
    } catch (e) {
      appLog('SecureFolder: Share error - $e');
    }
  }

  void _restoreFile(SecureFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('restore_file_title')),
        content: Text(tr('restore_file_confirm').replaceFirst('\${name}', file.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr('restore')),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    final success = await _secureFolderService.restoreFile(file.secureId);
    
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? tr('restore_success_short') : tr('restore_error_short')),
        ),
      );
    }
  }

  void _deleteFile(SecureFile file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('delete_file_title')),
        content: Text(tr('delete_secure_file_confirm').replaceFirst('\${name}', file.name)),
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
    
    final success = await _secureFolderService.deleteFile(file.secureId);
    
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? tr('file_deleted') : tr('delete_error_short')),
        ),
      );
    }
  }

  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
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

  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
