import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_service.dart';

/// מסך בחירת תיקיות לסריקה
class FolderSelectionScreen extends StatefulWidget {
  const FolderSelectionScreen({super.key});

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
    
    // תיקיות זמינות
    final basePath = '/storage/emulated/0';
    final folders = [
      FolderOption(
        name: 'הורדות',
        path: '$basePath/Download',
        icon: Icons.download,
        color: Colors.blue,
        description: 'קבצים שהורדת',
      ),
      FolderOption(
        name: 'מצלמה',
        path: '$basePath/DCIM',
        icon: Icons.camera_alt,
        color: Colors.green,
        description: 'תמונות וסרטונים מהמצלמה',
      ),
      FolderOption(
        name: 'תמונות',
        path: '$basePath/Pictures',
        icon: Icons.image,
        color: Colors.purple,
        description: 'תמונות מאפליקציות',
      ),
      FolderOption(
        name: 'מסמכים',
        path: '$basePath/Documents',
        icon: Icons.description,
        color: Colors.orange,
        description: 'מסמכים ו-PDF',
      ),
      FolderOption(
        name: 'WhatsApp',
        path: '$basePath/Android/media/com.whatsapp/WhatsApp/Media',
        icon: Icons.chat,
        color: Colors.teal,
        description: 'מדיה מוואטסאפ',
        isPremium: true,
      ),
      FolderOption(
        name: 'טלגרם',
        path: '$basePath/Telegram',
        icon: Icons.send,
        color: Colors.lightBlue,
        description: 'קבצים מטלגרם',
        isPremium: true,
      ),
      FolderOption(
        name: 'Screenshots',
        path: '$basePath/Pictures/Screenshots',
        icon: Icons.screenshot,
        color: Colors.pink,
        description: 'צילומי מסך',
      ),
    ];

    // בדיקה אילו תיקיות קיימות - מציגים רק קיימות
    for (final folder in folders) {
      final dir = Directory(folder.path);
      folder.exists = await dir.exists();
      if (folder.exists) {
        _availableFolders.add(folder);
      }
    }

    // הגדרת ברירת מחדל או טעינה מהשמור
    if (savedPaths != null) {
      _selectedPaths = savedPaths.toSet();
    } else {
      // ברירת מחדל - תיקיות בסיסיות
      _selectedPaths = {
        '$basePath/Download',
        '$basePath/DCIM',
        '$basePath/Pictures',
        '$basePath/Documents',
      };
    }

    setState(() => _isLoading = false);
  }

  Future<void> _saveFolders() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_selectedFoldersKey, _selectedPaths.toList());
    appLog('FolderSelection: Saved ${_selectedPaths.length} folders');
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
      backgroundColor: const Color(0xFF0F0F23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text(
          'תיקיות לסריקה',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await _saveFolders();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.white, size: 18),
                        SizedBox(width: 8),
                        Text('ההגדרות נשמרו'),
                      ],
                    ),
                    behavior: SnackBarBehavior.floating,
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.of(context).pop(true);
              }
            },
            icon: const Icon(Icons.save),
            label: const Text('שמור'),
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
                          'בחר אילו תיקיות לסרוק. תיקיות נוספות = יותר קבצים לחיפוש.',
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
                          '${_selectedPaths.length} תיקיות נבחרו',
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
                                .where((f) => !f.isPremium)
                                .map((f) => f.path)
                                .toSet();
                          });
                        },
                        child: const Text('בחר הכל'),
                      ),
                      TextButton(
                        onPressed: () {
                          setState(() => _selectedPaths.clear());
                        },
                        child: Text('נקה', 
                          style: TextStyle(color: Colors.grey.shade500)),
                      ),
                    ],
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
                      return _buildFolderTile(folder, theme);
                    },
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildFolderTile(FolderOption folder, ThemeData theme) {
    final isSelected = _selectedPaths.contains(folder.path);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? folder.color.withValues(alpha: 0.5)
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _toggleFolder(folder),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // אייקון
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: folder.color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    folder.icon,
                    color: folder.color,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                
                // פרטים
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            folder.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                          ),
                          if (folder.isPremium) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                'PRO',
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        folder.description,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Checkbox
                Checkbox(
                  value: isSelected,
                  onChanged: (_) => _toggleFolder(folder),
                  activeColor: folder.color,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// מייצג תיקייה זמינה לסריקה
class FolderOption {
  final String name;
  final String path;
  final IconData icon;
  final Color color;
  final String description;
  final bool isPremium;
  bool exists;

  FolderOption({
    required this.name,
    required this.path,
    required this.icon,
    required this.color,
    required this.description,
    this.isPremium = false,
    this.exists = true,
  });
}
