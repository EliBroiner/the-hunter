import 'package:flutter/material.dart';

/// מייצג תיקייה זמינה לסריקה
class FolderOption {
  final String name;
  final String path;
  final IconData icon;
  final Color color;
  final String description;
  final bool isCustom;
  bool exists;

  FolderOption({
    required this.name,
    required this.path,
    required this.icon,
    required this.color,
    required this.description,
    this.isCustom = false,
    this.exists = true,
  });
}

/// תיקיות מוגדרות מראש (Android)
List<FolderOption> getPredefinedFolders(String basePath) {
  return [
    FolderOption(
      name: 'folder_downloads',
      path: '$basePath/Download',
      icon: Icons.download,
      color: Colors.blue,
      description: 'folder_downloads_desc',
    ),
    FolderOption(
      name: 'folder_camera',
      path: '$basePath/DCIM',
      icon: Icons.camera_alt,
      color: Colors.green,
      description: 'folder_camera_desc',
    ),
    FolderOption(
      name: 'folder_pictures',
      path: '$basePath/Pictures',
      icon: Icons.image,
      color: Colors.purple,
      description: 'folder_pictures_desc',
    ),
    FolderOption(
      name: 'folder_documents',
      path: '$basePath/Documents',
      icon: Icons.description,
      color: Colors.orange,
      description: 'folder_documents_desc',
    ),
    FolderOption(
      name: 'folder_whatsapp',
      path: '$basePath/Android/media/com.whatsapp/WhatsApp/Media',
      icon: Icons.chat,
      color: Colors.teal,
      description: 'folder_whatsapp_desc',
    ),
    FolderOption(
      name: 'folder_telegram',
      path: '$basePath/Telegram',
      icon: Icons.send,
      color: Colors.lightBlue,
      description: 'folder_telegram_desc',
    ),
    FolderOption(
      name: 'folder_screenshots',
      path: '$basePath/Pictures/Screenshots',
      icon: Icons.screenshot,
      color: Colors.pink,
      description: 'folder_screenshots_desc',
    ),
  ];
}
