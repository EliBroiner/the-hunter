import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/file_metadata.dart';
import '../models/search_intent.dart';
import '../services/database_service.dart';
import '../services/favorites_service.dart';
import '../services/recent_files_service.dart';
import '../services/log_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../services/smart_search_filter.dart';
import '../services/smart_search_service.dart';
import '../services/tags_service.dart';
import '../services/secure_folder_service.dart';
import '../services/cloud_storage_service.dart';
import '../services/widget_service.dart';
import '../services/google_drive_service.dart';
import 'settings_screen.dart';
import '../services/localization_service.dart';

/// פילטר מקומי נוסף (לא קיים ב-SearchFilter)
enum LocalFilter {
  all,
  favorites, // מועדפים - פרימיום בלבד
  images,
  pdfs,
  whatsapp,
  withText,
}

/// מסך חיפוש - מסך ראשי לחיפוש קבצים
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _databaseService = DatabaseService.instance;
  final _permissionService = PermissionService.instance;
  final _settingsService = SettingsService.instance;
  final _smartSearchService = SmartSearchService.instance;
  final _favoritesService = FavoritesService.instance;
  final _googleDriveService = GoogleDriveService.instance;
  
  LocalFilter _selectedFilter = LocalFilter.all;
  Timer? _debounceTimer;
  
  // Stream לחיפוש ריאקטיבי
  Stream<List<FileMetadata>>? _searchStream;
  List<FileMetadata> _cloudResults = []; // תוצאות ענן
  bool _isSearchingCloud = false;
  String _currentQuery = '';
  
  // טווח תאריכים לסינון
  DateTimeRange? _selectedDateRange;
  
  // חיפושים אחרונים
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 3;
  List<String> _recentSearches = [];
  bool _isSearchFocused = false;
  
  // חיפוש קולי
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _selectedLocale = 'he-IL'; // ברירת מחדל עברית
  
  // חיפוש חכם (AI)
  bool _isSmartSearching = false;
  bool _isSmartSearchActive = false;
  SearchIntent? _lastSmartIntent;
  
  // מצב בחירה מרובה
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {};

  @override
  void initState() {
    super.initState();
    _updateSearchStream();
    _initSpeech();
    _loadRecentSearches();
    
    // מאזין לפוקוס על שדה החיפוש
    _searchFocusNode.addListener(_onFocusChange);
  }
  
  /// מטפל בשינוי פוקוס
  void _onFocusChange() {
    setState(() {
      _isSearchFocused = _searchFocusNode.hasFocus;
    });
  }
  
  /// טוען חיפושים אחרונים מ-SharedPreferences
  Future<void> _loadRecentSearches() async {
    final prefs = await SharedPreferences.getInstance();
    final searches = prefs.getStringList(_recentSearchesKey) ?? [];
    if (mounted) {
      setState(() => _recentSearches = searches);
    }
  }
  
  /// שומר חיפוש לרשימת החיפושים האחרונים
  Future<void> _saveRecentSearch(String query) async {
    // לא שומר שאילתות ריקות או קצרות מדי
    final trimmed = query.trim();
    if (trimmed.length < 2) return;
    
    // מסיר כפילויות ומוסיף בתחילת הרשימה
    _recentSearches.remove(trimmed);
    _recentSearches.insert(0, trimmed);
    
    // מגביל ל-5 חיפושים אחרונים
    if (_recentSearches.length > _maxRecentSearches) {
      _recentSearches = _recentSearches.sublist(0, _maxRecentSearches);
    }
    
    // שומר ב-SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
    
    if (mounted) setState(() {});
  }
  
  /// מוחק חיפוש מהרשימה
  Future<void> _removeRecentSearch(String query) async {
    _recentSearches.remove(query);
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_recentSearchesKey, _recentSearches);
    
    if (mounted) setState(() {});
  }
  
  /// בוחר חיפוש מהרשימה
  void _selectRecentSearch(String query) {
    _searchController.text = query;
    _currentQuery = query;
    _updateSearchStream();
    // מעביר את החיפוש לראש הרשימה
    _saveRecentSearch(query);
  }

  /// מאתחל את מנוע הזיהוי הקולי
  Future<void> _initSpeech() async {
    _speechEnabled = await _speechToText.initialize(
      onError: (error) {
        // טיפול בשגיאות זיהוי קולי
        if (mounted) {
          setState(() => _isListening = false);
        }
      },
      onStatus: (status) {
        // עדכון סטטוס הקשבה
        if (status == 'done' || status == 'notListening') {
          if (mounted) setState(() => _isListening = false);
        }
      },
    );
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.removeListener(_onFocusChange);
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _speechToText.stop();
    super.dispose();
  }

  /// מעדכן את ה-Stream לפי הפרמטרים הנוכחיים
  void _updateSearchStream() {
    final query = _currentQuery;
    
    // תאריך התחלה מהשאילתה או מטווח התאריכים שנבחר
    final queryStartDate = parseTimeQuery(query);
    final startDate = _selectedDateRange?.start ?? queryStartDate;
    final endDate = _selectedDateRange?.end;
    
    // המרת פילטר מקומי לפילטר של DatabaseService
    SearchFilter dbFilter = SearchFilter.all;
    if (_selectedFilter == LocalFilter.images) dbFilter = SearchFilter.images;
    if (_selectedFilter == LocalFilter.pdfs) dbFilter = SearchFilter.pdfs;
    
    // אם נבחר פילטר תמונות או PDF, נסנן גם את תוצאות הענן בהתאם
    List<FileMetadata> filteredCloudResults = _cloudResults;
    if (_selectedFilter == LocalFilter.images) {
      filteredCloudResults = _cloudResults.where((f) => ['jpg', 'jpeg', 'png', 'gif', 'webp'].contains(f.extension)).toList();
    } else if (_selectedFilter == LocalFilter.pdfs) {
      filteredCloudResults = _cloudResults.where((f) => f.extension == 'pdf').toList();
    }

    setState(() {
      _searchStream = _databaseService.watchSearch(
        query: query,
        filter: dbFilter,
        startDate: startDate,
        endDate: endDate,
      ).map((results) {
          // שילוב תוצאות ענן (אם יש) - תוך סינון כפילויות
          final localPaths = results.map((f) => f.name.toLowerCase()).toSet();
          final uniqueCloudResults = filteredCloudResults.where((f) => !localPaths.contains(f.name.toLowerCase())).toList();
          
          final combined = [...results, ...uniqueCloudResults];
        // מיון לפי תאריך (חדש לישן)
        combined.sort((a, b) => b.lastModified.compareTo(a.lastModified));
        return _applyLocalFilter(combined);
      });
    });

    // חיפוש בענן אם מחובר ויש שאילתה
    if (query.isNotEmpty && query.length > 2 && _googleDriveService.isConnected) {
      _searchCloud(query);
    } else {
      setState(() => _cloudResults = []);
    }
  }

  /// חיפוש בענן
  Future<void> _searchCloud(String query) async {
    if (_isSearchingCloud) return;
    setState(() => _isSearchingCloud = true);
    
    try {
      final results = await _googleDriveService.searchFiles(query);
      if (mounted) {
        setState(() {
          _cloudResults = results;
          // רענון הסטרים כדי להציג את התוצאות החדשות
          // (בגלל שהסטרים מבוסס על map, שינוי _cloudResults ישפיע בריצה הבאה)
          // אבל אנחנו צריכים לעורר אותו.
          // דרך פשוטה: קריאה חוזרת ל-_updateSearchStream (קצת בזבזני אבל עובד)
          // או פשוט להסתמך על setState שיבנה מחדש אם היינו משתמשים ב-FutureBuilder
          // כאן אנחנו ב-StreamBuilder, אז צריך טריק.
          // הפתרון הנכון: StreamController משולב (RxDart) אבל נשמור על פשטות:
          // נעדכן את ה-Stream מחדש.
        });
        // עדכון הסטרים עם התוצאות החדשות
        final dbFilter = _selectedFilter == LocalFilter.images ? SearchFilter.images 
                       : _selectedFilter == LocalFilter.pdfs ? SearchFilter.pdfs 
                       : SearchFilter.all;
                       
        final queryStartDate = parseTimeQuery(query);
        final startDate = _selectedDateRange?.start ?? queryStartDate;
        final endDate = _selectedDateRange?.end;

        setState(() {
          _searchStream = _databaseService.watchSearch(
            query: query,
            filter: dbFilter,
            startDate: startDate,
            endDate: endDate,
          ).map((results) {
            final localPaths = results.map((f) => f.name.toLowerCase()).toSet();
            final uniqueCloudResults = _cloudResults.where((f) => !localPaths.contains(f.name.toLowerCase())).toList();
            
            final combined = [...results, ...uniqueCloudResults];
            combined.sort((a, b) => b.lastModified.compareTo(a.lastModified));
            return _applyLocalFilter(combined);
          });
        });
      }
    } finally {
      if (mounted) setState(() => _isSearchingCloud = false);
    }
  }

  /// מבצע חיפוש עם debounce
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _currentQuery = query;
      _updateSearchStream();
      
      // שומר חיפוש תקין לרשימת החיפושים האחרונים
      if (query.trim().length >= 2) {
        _saveRecentSearch(query);
      }
    });
  }

  /// מתחיל הקשבה קולית
  Future<void> _startListening() async {
    // בדיקה והרשאת מיקרופון
    final hasPermission = await _permissionService.hasMicrophonePermission();
    if (!hasPermission) {
      final result = await _permissionService.requestMicrophonePermission();
      if (result != PermissionResult.granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('search_voice_permission')),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              action: result == PermissionResult.permanentlyDenied
                  ? SnackBarAction(
                      label: tr('settings_title'),
                      textColor: Colors.white,
                      onPressed: () => _permissionService.openSettings(),
                    )
                  : null,
            ),
          );
        }
        return;
      }
    }

    // בדיקה אם הזיהוי הקולי זמין
    if (!_speechEnabled) {
      await _initSpeech();
      if (!_speechEnabled) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(tr('search_voice_not_available')),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
    }

    setState(() => _isListening = true);

    await _speechToText.listen(
      onResult: _onSpeechResult,
      localeId: _selectedLocale,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      listenOptions: SpeechListenOptions(
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.search,
      ),
    );
  }

  /// מפסיק הקשבה קולית
  Future<void> _stopListening() async {
    await _speechToText.stop();
    setState(() => _isListening = false);
  }

  /// מטפל בתוצאת זיהוי קולי
  void _onSpeechResult(SpeechRecognitionResult result) {
    // עדכון טקסט החיפוש בזמן אמת
    setState(() {
      _searchController.text = result.recognizedWords;
      _searchController.selection = TextSelection.fromPosition(
        TextPosition(offset: _searchController.text.length),
      );
    });

    // אם הזיהוי סיים - מפעיל את החיפוש
    if (result.finalResult) {
      _currentQuery = result.recognizedWords;
      _updateSearchStream();
      setState(() => _isListening = false);
    }
  }

  /// מחליף בין עברית לאנגלית
  void _toggleLocale() {
    setState(() {
      _selectedLocale = _selectedLocale == 'he-IL' ? 'en-US' : 'he-IL';
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _selectedLocale == 'he-IL' ? tr('search_language_he') : tr('search_language_en'),
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// מחיל פילטר מקומי על התוצאות
  List<FileMetadata> _applyLocalFilter(List<FileMetadata> results) {
    // סינון לפי WhatsApp
    if (_selectedFilter == LocalFilter.whatsapp) {
      return results.where((f) => 
        f.path.toLowerCase().contains('whatsapp')
      ).toList();
    }
    
    // סינון לפי מועדפים
    if (_selectedFilter == LocalFilter.favorites) {
      final favoriteResults = results.where((f) => 
        _favoritesService.isFavorite(f.path)
      ).toList();
      return favoriteResults;
    }
    
    // מיון: מועדפים קודם (אם לא בפילטר מועדפים)
    if (_selectedFilter != LocalFilter.favorites) {
      results.sort((a, b) {
        final aFav = _favoritesService.isFavorite(a.path);
        final bFav = _favoritesService.isFavorite(b.path);
        if (aFav && !bFav) return -1;
        if (!aFav && bFav) return 1;
        return 0; // שמור על המיון הקיים
      });
    }
    
    return results;
  }

  /// משנה פילטר
  void _onFilterChanged(LocalFilter filter) {
    HapticFeedback.selectionClick();
    setState(() => _selectedFilter = filter);
    _currentQuery = _searchController.text;
    _updateSearchStream();
  }
  
  /// מפעיל/מכבה מצב בחירה מרובה
  void _toggleSelectionMode() {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) {
        _selectedFiles.clear();
      }
    });
  }
  
  /// בוחר/מבטל בחירת קובץ
  void _toggleFileSelection(String path) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedFiles.contains(path)) {
        _selectedFiles.remove(path);
        // אם אין עוד קבצים נבחרים - יציאה ממצב בחירה
        if (_selectedFiles.isEmpty) {
          _isSelectionMode = false;
        }
      } else {
        _selectedFiles.add(path);
      }
    });
  }
  
  /// בוחר את כל הקבצים
  void _selectAll(List<FileMetadata> files) {
    setState(() {
      _selectedFiles.clear();
      _selectedFiles.addAll(files.map((f) => f.path));
    });
  }
  
  /// מבטל את כל הבחירות
  void _clearSelection() {
    setState(() {
      _selectedFiles.clear();
      _isSelectionMode = false;
    });
  }
  
  /// מוחק קבצים נבחרים
  Future<void> _deleteSelectedFiles(List<FileMetadata> allFiles) async {
    final selectedCount = _selectedFiles.length;
    
    // אישור מחיקה
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.orange),
            const SizedBox(width: 12),
            const Text(tr('delete_files_title')),
          ],
        ),
        content: Text(tr('delete_multiple_confirm').replaceFirst('\$selectedCount', selectedCount.toString())),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(tr('delete'), style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    int deleted = 0;
    int failed = 0;
    
    for (final path in _selectedFiles.toList()) {
      try {
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
          // הסרה מהמסד
          await _databaseService.deleteFileByPath(path);
          deleted++;
        }
      } catch (e) {
        failed++;
      }
    }
    
    _clearSelection();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(failed > 0 
              ? tr('delete_multiple_partial').replaceFirst('\$deleted', deleted.toString()).replaceFirst('\$failed', failed.toString())
              : tr('delete_multiple_success').replaceFirst('\$deleted', deleted.toString())),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }
  
  /// משתף קבצים נבחרים
  Future<void> _shareSelectedFiles() async {
    final files = _selectedFiles.map((path) => XFile(path)).toList();
    
    try {
      await Share.shareXFiles(files);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('share_error').replaceFirst('\$e', e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  /// רענון בגרירה למטה
  Future<void> _onRefresh() async {
    // רענון הסטרים
    _updateSearchStream();
    
    // המתנה קצרה לתחושת רענון
    await Future.delayed(const Duration(milliseconds: 500));
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.refresh, color: Colors.white, size: 18),
              const SizedBox(width: 8),
              const Text(tr('refresh_complete')),
            ],
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E3F),
        ),
      );
    }
  }

  /// פותח קובץ
  Future<void> _openFile(FileMetadata file) async {
    // בדיקה אם הקובץ קיים
    final fileExists = await File(file.path).exists();
    if (!fileExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('file_not_found').replaceFirst('\${file.name}', file.name))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: tr('remove_from_list'),
              textColor: Colors.white,
              onPressed: () {
                _databaseService.deleteFile(file.id);
                _updateSearchStream(); // רענון לאחר מחיקה
              },
            ),
          ),
        );
      }
      return;
    }

    final result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done) {
      // שמירה בקבצים אחרונים
      RecentFilesService.instance.addRecentFile(
        path: file.path,
        name: file.name,
        extension: file.extension,
      );
      // עדכון הווידג'ט עם הקובץ האחרון
      WidgetService.instance.updateRecentFile(file.name, file.path, file.extension);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(tr('open_error').replaceFirst('\${result.message}', result.message)),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// משתף קובץ
  Future<void> _shareFile(FileMetadata file) async {
    // בדיקה אם הקובץ קיים
    final fileExists = await File(file.path).exists();
    if (!fileExists) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('הקובץ לא נמצא'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await Share.shareXFiles(
      [XFile(file.path)],
      text: tr('share_text').replaceFirst('\${file.name}', file.name),
    );
  }
  
  /// מוחק קובץ מהמכשיר ומהמסד
  Future<void> _deleteFile(FileMetadata file) async {
    // בדיקה אם הקובץ קיים
    final deviceFile = File(file.path);
    final fileExists = await deviceFile.exists();
    
    if (!fileExists) {
      // הקובץ לא קיים - נמחק רק מהמסד
      _databaseService.deleteFile(file.id);
      _updateSearchStream();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(tr('file_already_deleted')),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    
    try {
      // מחיקת הקובץ מהמכשיר
      await deviceFile.delete();
      
      // מחיקה מהמסד
      _databaseService.deleteFile(file.id);
      _updateSearchStream();
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('file_deleted_success').replaceFirst('\${file.name}', file.name))),
              ],
            ),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('delete_error_details').replaceFirst('\$e', e.toString())),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
  
  /// מציג דיאלוג אישור מחיקה
  Future<void> _showDeleteConfirmation(FileMetadata file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 12),
            Text(tr('delete_file_title')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('delete_file_confirm')),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.insert_drive_file, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      file.name,
                      style: const TextStyle(fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tr('delete_irreversible'),
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
            ),
          ],
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
    
    if (confirmed == true) {
      await _deleteFile(file);
    }
  }
  
  /// מציג פרטי קובץ
  void _showFileDetails(FileMetadata file) {
    final theme = Theme.of(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E3F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ידית למשיכה
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            
            // כותרת
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.info_outline,
                    color: theme.colorScheme.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('file_details_title'),
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // פרטים
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F0F23),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  _buildDetailRow(tr('detail_name'), file.name, Icons.insert_drive_file),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow(tr('detail_type'), file.extension.toUpperCase(), Icons.category),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow(tr('detail_size'), file.readableSize, Icons.data_usage),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow(tr('detail_date'), _formatDate(file.lastModified), Icons.calendar_today),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow(tr('detail_path'), file.path, Icons.folder_open, isPath: true),
                  if (file.extractedText != null && file.extractedText!.isNotEmpty) ...[
                    const Divider(height: 20, color: Colors.white12),
                    _buildDetailRow(
                      tr('detail_extracted_text'), 
                      '${file.extractedText!.length} ${tr('detail_chars')}',
                      Icons.text_snippet,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            
            // כפתור סגירה
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(tr('close')),
              ),
            ),
            
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }
  
  /// בונה שורת פרט
  Widget _buildDetailRow(String label, String value, IconData icon, {bool isPath = false}) {
    return Row(
      crossAxisAlignment: isPath ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, size: 18, color: Colors.grey.shade500),
        const SizedBox(width: 12),
        SizedBox(
          width: 80,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 13),
            textDirection: _isHebrew(value) ? TextDirection.rtl : TextDirection.ltr,
            maxLines: isPath ? 3 : 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
  
  /// מציג תפריט פעולות לקובץ
  void _showFileActionsSheet(FileMetadata file) {
    final theme = Theme.of(context);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E3F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
            // ידית למשיכה
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade600,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            
            // שם הקובץ
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: _getFileColor(file.extension).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: _buildFileIcon(file.extension, file.path.toLowerCase().contains('whatsapp')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        file.name,
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        file.readableSize,
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            
            // פעולות
            _buildActionTile(
              icon: Icons.open_in_new,
              title: tr('action_open'),
              subtitle: tr('action_open_subtitle'),
              color: theme.colorScheme.primary,
              onTap: () {
                Navigator.of(context).pop();
                _openFile(file);
              },
            ),
            const SizedBox(height: 8),
            // מועדפים - פרימיום בלבד
            _buildFavoriteActionTile(file),
            const SizedBox(height: 8),
            // תגיות - פרימיום בלבד
            _buildTagsActionTile(file),
            const SizedBox(height: 8),
            // תיקייה מאובטחת - פרימיום בלבד
            _buildSecureFolderActionTile(file),
            const SizedBox(height: 8),
            // העלאה לענן - פרימיום בלבד - הוסר
            // _buildCloudUploadActionTile(file),
            // const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.share,
              title: 'שתף',
              subtitle: 'שלח לאפליקציה אחרת',
              color: Colors.blue,
              onTap: () {
                Navigator.of(context).pop();
                _shareFile(file);
              },
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.info_outline,
              title: 'פרטים',
              subtitle: 'הצג מידע על הקובץ',
              color: Colors.teal,
              onTap: () {
                Navigator.of(context).pop();
                _showFileDetails(file);
              },
            ),
            const SizedBox(height: 8),
            _buildActionTile(
              icon: Icons.delete_outline,
              title: 'מחק',
              subtitle: 'מחק את הקובץ לצמיתות',
              color: Colors.red,
              onTap: () {
                Navigator.of(context).pop();
                _showDeleteConfirmation(file);
              },
            ),
            
            SizedBox(height: MediaQuery.of(context).padding.bottom + 8),
          ],
        ),
      ),
      ),
    );
  }
  
  /// בונה פריט פעולה מועדפים
  Widget _buildFavoriteActionTile(FileMetadata file) {
    final isPremium = _settingsService.isPremium;
    final isFavorite = _favoritesService.isFavorite(file.path);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (!isPremium) {
            Navigator.of(context).pop();
            _showPremiumUpgradeMessage('מועדפים');
            return;
          }
          
          await _favoritesService.toggleFavorite(file.path);
          Navigator.of(context).pop();
          
          setState(() {}); // רענון UI
          
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  Icon(
                    isFavorite ? Icons.star_outline : Icons.star,
                    color: Colors.amber,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Text(isFavorite ? 'הוסר מהמועדפים' : 'נוסף למועדפים'),
                ],
              ),
              backgroundColor: const Color(0xFF1E1E3F),
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F23),
            borderRadius: BorderRadius.circular(12),
            border: !isPremium 
                ? Border.all(color: Colors.amber.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isFavorite ? Icons.star : Icons.star_outline,
                  color: Colors.amber,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          isFavorite ? 'הסר מהמועדפים' : 'הוסף למועדפים',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPremium ? null : Colors.grey,
                          ),
                        ),
                        if (!isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                    const SizedBox(height: 2),
                    Text(
                      isPremium 
                          ? (isFavorite ? 'הקובץ במועדפים שלך' : 'גישה מהירה לקבצים חשובים')
                          : 'שדרג לפרימיום',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPremium)
                Icon(
                  Icons.chevron_left,
                  color: Colors.grey.shade600,
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// בונה פריט תגיות
  Widget _buildTagsActionTile(FileMetadata file) {
    final isPremium = _settingsService.isPremium;
    final tagsService = TagsService.instance;
    final fileTags = tagsService.getFileTags(file.path);
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          if (!isPremium) {
            Navigator.of(context).pop();
            _showPremiumUpgradeMessage('תגיות');
            return;
          }
          Navigator.of(context).pop();
          _showTagsDialog(file);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F23),
            borderRadius: BorderRadius.circular(12),
            border: !isPremium 
                ? Border.all(color: Colors.purple.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.label_outline, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'תגיות',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPremium ? null : Colors.grey,
                          ),
                        ),
                        if (!isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    if (isPremium && fileTags.isNotEmpty)
                      Wrap(
                        spacing: 4,
                        children: fileTags.take(3).map((tag) => Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: tag.color.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            tag.name,
                            style: TextStyle(fontSize: 10, color: tag.color),
                          ),
                        )).toList(),
                      )
                    else
                      Text(
                        isPremium ? 'הוסף תגיות לארגון קבצים' : 'שדרג לפרימיום',
                        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (isPremium)
                Icon(Icons.chevron_left, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
  
  /// מציג דיאלוג ניהול תגיות
  void _showTagsDialog(FileMetadata file) {
    final tagsService = TagsService.instance;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          final allTags = tagsService.tags;
          
          return Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ידית
                Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                
                // כותרת
                Row(
                  children: [
                    const Icon(Icons.label, color: Colors.purple),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'בחר תגיות',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showCreateTagDialog(setModalState),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text('חדשה'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                
                // רשימת תגיות
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: allTags.map((tag) {
                    final hasTag = tagsService.hasTag(file.path, tag.id);
                    
                    return GestureDetector(
                      onTap: () async {
                        HapticFeedback.selectionClick();
                        await tagsService.toggleFileTag(file.path, tag.id);
                        setModalState(() {});
                        setState(() {});
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: hasTag 
                              ? tag.color.withValues(alpha: 0.25)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: hasTag ? tag.color : Colors.grey.withValues(alpha: 0.3),
                            width: hasTag ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(tag.icon, size: 16, color: tag.color),
                            const SizedBox(width: 8),
                            Text(
                              tag.name,
                              style: TextStyle(
                                color: hasTag ? tag.color : null,
                                fontWeight: hasTag ? FontWeight.w600 : FontWeight.normal,
                              ),
                            ),
                            if (hasTag) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.check, size: 16, color: tag.color),
                            ],
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                
                SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
              ],
            ),
          );
        },
      ),
    );
  }
  
  /// מציג דיאלוג יצירת תגית חדשה
  void _showCreateTagDialog(StateSetter setModalState) {
    final nameController = TextEditingController();
    Color selectedColor = Colors.purple;
    
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          title: const Text('תגית חדשה'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'שם התגית',
                  hintText: 'לדוגמה: מסמכים',
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              const Text('בחר צבע:', style: TextStyle(fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: TagsService.availableColors.map((color) {
                  final isSelected = selectedColor == color;
                  return GestureDetector(
                    onTap: () => setDialogState(() => selectedColor = color),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: isSelected 
                            ? Border.all(color: Colors.white, width: 3)
                            : null,
                        boxShadow: isSelected ? [
                          BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8),
                        ] : null,
                      ),
                      child: isSelected 
                          ? const Icon(Icons.check, color: Colors.white, size: 18)
                          : null,
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                
                final newTag = CustomTag(
                  id: DateTime.now().millisecondsSinceEpoch.toString(),
                  name: name,
                  color: selectedColor,
                );
                
                await TagsService.instance.addTag(newTag);
                Navigator.of(context).pop();
                setModalState(() {});
              },
              child: const Text('צור'),
            ),
          ],
        ),
      ),
    );
  }
  
  /// בונה פריט תיקייה מאובטחת
  Widget _buildSecureFolderActionTile(FileMetadata file) {
    final isPremium = _settingsService.isPremium;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (!isPremium) {
            Navigator.of(context).pop();
            _showPremiumUpgradeMessage('תיקייה מאובטחת');
            return;
          }
          
          Navigator.of(context).pop();
          _moveToSecureFolder(file);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F23),
            borderRadius: BorderRadius.circular(12),
            border: !isPremium 
                ? Border.all(color: Colors.purple.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.purple.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.lock, color: Colors.purple, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'העבר לתיקייה מאובטחת',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPremium ? null : Colors.grey,
                          ),
                        ),
                        if (!isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPremium ? 'הסתר קובץ מאחורי קוד PIN' : 'שדרג לפרימיום',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isPremium)
                Icon(Icons.chevron_left, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
  
  /// מעביר קובץ לתיקייה המאובטחת
  Future<void> _moveToSecureFolder(FileMetadata file) async {
    final secureFolderService = SecureFolderService.instance;
    
    // אם אין PIN - לנווט להגדרה
    if (!secureFolderService.hasPin) {
      Navigator.of(context).pushNamed('/secure');
      return;
    }
    
    // בקשת אישור
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        title: const Text('העברה לתיקייה מאובטחת'),
        content: Text('האם להעביר את "${file.name}" לתיקייה המאובטחת?\n\nהקובץ יוסר מהחיפוש הרגיל.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.purple,
            ),
            child: const Text('העבר'),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // אם התיקייה נעולה - לבקש PIN
    if (!secureFolderService.isUnlocked) {
      Navigator.of(context).pushNamed('/secure');
      return;
    }
    
    // העברת הקובץ
    final success = await secureFolderService.addFile(file.path, moveFile: true);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(success ? 'הקובץ הועבר לתיקייה המאובטחת' : 'שגיאה בהעברת הקובץ'),
            ],
          ),
          backgroundColor: success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      
      if (success) {
        setState(() {});
      }
    }
  }
  
  /// בונה פריט העלאה לענן
  Widget _buildCloudUploadActionTile(FileMetadata file) {
    final isPremium = _settingsService.isPremium;
    
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () async {
          if (!isPremium) {
            Navigator.of(context).pop();
            _showPremiumUpgradeMessage('אחסון בענן');
            return;
          }
          
          Navigator.of(context).pop();
          _uploadToCloud(file);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F23),
            borderRadius: BorderRadius.circular(12),
            border: !isPremium 
                ? Border.all(color: Colors.blue.withValues(alpha: 0.3))
                : null,
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.cloud_upload, color: Colors.blue, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'העלה לענן',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPremium ? null : Colors.grey,
                          ),
                        ),
                        if (!isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'PRO',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPremium ? 'שמור העתק בענן לגישה מכל מקום' : 'שדרג לפרימיום',
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (isPremium)
                Icon(Icons.chevron_left, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }
  
  /// מעלה קובץ לענן
  Future<void> _uploadToCloud(FileMetadata file) async {
    final cloudService = CloudStorageService.instance;
    
    // בדיקת חיבור
    if (!cloudService.hasUser) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('יש להתחבר לחשבון כדי להעלות לענן')),
      );
      return;
    }
    
    // הצגת דיאלוג התקדמות
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            backgroundColor: Theme.of(context).colorScheme.surface,
            title: Row(
              children: [
                const Icon(Icons.cloud_upload, color: Colors.blue),
                const SizedBox(width: 12),
                const Text('מעלה לענן'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(file.name),
                const SizedBox(height: 16),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text('מעלה...', style: TextStyle(fontSize: 12)),
              ],
            ),
          );
        },
      ),
    );
    
    // העלאה
    final result = await cloudService.uploadFile(
      file.path,
      onProgress: (progress) {
        // עדכון התקדמות (לא נגישה ישירות אבל תופיע בקונסול)
      },
    );
    
    // סגירת הדיאלוג
    if (mounted) Navigator.of(context).pop();
    
    // הודעה
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(
                result != null ? Icons.check_circle : Icons.error,
                color: Colors.white,
              ),
              const SizedBox(width: 8),
              Text(result != null ? 'הקובץ הועלה בהצלחה' : 'שגיאה בהעלאה'),
            ],
          ),
          backgroundColor: result != null ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// בונה פריט פעולה
  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFF0F0F23),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: Colors.grey.shade600),
            ],
          ),
        ),
      ),
    );
  }

  /// מחלץ שם התיקייה מהנתיב
  String _getFolderName(String path) {
    final parts = path.split('/');
    if (parts.length < 2) return 'Unknown';
    
    // מחפש שמות תיקיות מוכרים
    final knownFolders = {
      'Download': 'Downloads',
      'Downloads': 'Downloads', 
      'DCIM': 'DCIM',
      'Screenshots': 'Screenshots', 
      'Pictures': 'Pictures',
      'WhatsApp': 'WhatsApp', 
      'Telegram': 'Telegram', 
      'Documents': 'Documents', 
      'Desktop': 'Desktop',
    };
    
    for (final entry in knownFolders.entries) {
      if (path.contains(entry.key)) return entry.value;
    }
    
    return parts.length > 1 ? parts[parts.length - 2] : 'Unknown';
  }

  /// בודק אם טקסט מכיל עברית
  bool _isHebrew(String text) {
    return RegExp(r'[\u0590-\u05FF]').hasMatch(text);
  }

  /// מנקה מונחי זמן מהשאילתה להדגשה
  String _getCleanQuery(String query) {
    var clean = query;
    const timeTerms = [
      'שבועיים', '2 שבועות', 'שבוע', 'חודש', 'היום', 'אתמול',
      'week', 'month', 'today', 'yesterday',
    ];
    for (final term in timeTerms) {
      clean = clean.replaceAll(RegExp(term, caseSensitive: false), '');
    }
    return clean.trim();
  }

  /// פותח בורר טווח תאריכים
  Future<void> _showDateRangePicker() async {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final firstDate = DateTime(2020, 1, 1);
    
    final picked = await showDateRangePicker(
      context: context,
      firstDate: firstDate,
      lastDate: now,
      initialDateRange: _selectedDateRange,
      locale: const Locale('he', 'IL'),
      builder: (context, child) {
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: const Color(0xFF6366F1),
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1E3F),
              onSurface: Colors.white,
              onSurfaceVariant: Colors.grey.shade300,
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF818CF8),
              ),
            ),
          ),
          child: child!,
        );
      },
    );
    
    if (picked != null) {
      setState(() => _selectedDateRange = picked);
      _updateSearchStream();
    }
  }
  
  /// מנקה טווח תאריכים
  void _clearDateRange() {
    setState(() => _selectedDateRange = null);
    _updateSearchStream();
  }
  
  /// מציג הודעת שדרוג לפרימיום
  void _showPremiumUpgradeMessage(String feature) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber, Colors.orange],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.star, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            const Text('שדרג לפרימיום'),
          ],
        ),
        content: Text(
          'פיצ\'ר "$feature" זמין רק למשתמשי פרימיום.\n\nשדרג עכשיו כדי ליהנות מכל היכולות המתקדמות!',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('אחר כך'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).pop();
              Navigator.pushNamed(context, '/subscription');
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('שדרג עכשיו'),
          ),
        ],
      ),
    );
  }
  
  /// פורמט טווח תאריכים לתצוגה
  String _formatDateRange(DateTimeRange range) {
    final start = '${range.start.day}/${range.start.month}/${range.start.year}';
    final end = '${range.end.day}/${range.end.month}/${range.end.year}';
    return '$start - $end';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final showRecentSearches = _isSearchFocused && 
        _searchController.text.isEmpty && 
        _recentSearches.isNotEmpty;
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // כותרת וחיפוש (או בר בחירה)
            _isSelectionMode
                ? _buildSelectionHeader(theme)
                : _buildSearchHeader(),
            
            // חיפושים אחרונים (כשהשדה בפוקוס וריק)
            if (showRecentSearches && !_isSelectionMode)
              _buildRecentSearches(),
            
            // בורר טווח תאריכים
            if (!showRecentSearches && !_isSelectionMode)
              _buildDateRangePicker(),
            
            // באנר חיפוש AI חכם (פרימיום)
            if (!showRecentSearches && !_isSelectionMode)
              _buildSmartAISearchBanner(),
            
            // צ'יפים לסינון מהיר
            if (!_isSelectionMode)
              _buildFilterChips(),
            
            // תוצאות או מצב ריק
            Expanded(
              child: _buildResults(),
            ),
          ],
        ),
      ),
      // בר פעולות בחירה מרובה
      bottomNavigationBar: _isSelectionMode ? _buildSelectionActionBar(theme) : null,
    );
  }
  
  /// בונה כותרת מצב בחירה
  Widget _buildSelectionHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _clearSelection,
            icon: const Icon(Icons.close),
            tooltip: 'ביטול',
          ),
          const SizedBox(width: 8),
          Text(
            '${_selectedFiles.length} נבחרו',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.primary,
            ),
          ),
          const Spacer(),
          TextButton(
            onPressed: () {
              // בחירת הכל - צריך גישה לרשימת הקבצים
              // יתבצע דרך StreamBuilder
            },
            child: Text(
              'בחר הכל',
              style: TextStyle(color: theme.colorScheme.primary),
            ),
          ),
        ],
      ),
    );
  }
  
  /// בונה בר פעולות בחירה מרובה
  Widget _buildSelectionActionBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            // שיתוף
            _buildSelectionAction(
              icon: Icons.share,
              label: 'שתף',
              onTap: _shareSelectedFiles,
              color: theme.colorScheme.primary,
            ),
            // מועדפים
            _buildSelectionAction(
              icon: Icons.star_border,
              label: 'מועדפים',
              onTap: () {
                for (final path in _selectedFiles) {
                  _favoritesService.addFavorite(path);
                }
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('${_selectedFiles.length} קבצים נוספו למועדפים'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _clearSelection();
              },
              color: Colors.amber,
            ),
            // מחיקה
            _buildSelectionAction(
              icon: Icons.delete_outline,
              label: 'מחק',
              onTap: () => _deleteSelectedFiles([]),
              color: Colors.red,
            ),
          ],
        ),
      ),
    );
  }
  
  /// בונה כפתור פעולה בבר בחירה
  Widget _buildSelectionAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 26),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// בונה רשימת חיפושים אחרונים
  Widget _buildRecentSearches() {
    final theme = Theme.of(context);
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // כותרת
          Row(
            children: [
              Icon(
                Icons.history,
                size: 16,
                color: Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              Text(
                'חיפושים אחרונים',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          
          // צ'יפים של חיפושים אחרונים
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _recentSearches.map((query) {
              return _buildRecentSearchChip(query, theme);
            }).toList(),
          ),
        ],
      ),
    );
  }
  
  /// בונה צ'יפ חיפוש אחרון
  Widget _buildRecentSearchChip(String query, ThemeData theme) {
    return GestureDetector(
      onTap: () => _selectRecentSearch(query),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search,
              size: 14,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              query,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 6),
            // כפתור מחיקה
            GestureDetector(
              onTap: () => _removeRecentSearch(query),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.close,
                  size: 12,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
  
  /// בונה בורר טווח תאריכים
  Widget _buildDateRangePicker() {
    final theme = Theme.of(context);
    final hasDateRange = _selectedDateRange != null;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: GestureDetector(
        onTap: _showDateRangePicker,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: hasDateRange 
                  ? theme.colorScheme.secondary 
                  : theme.colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.calendar_today,
                size: 18,
                color: hasDateRange 
                    ? theme.colorScheme.secondary 
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  hasDateRange 
                      ? _formatDateRange(_selectedDateRange!)
                      : 'כל הזמנים',
                  style: TextStyle(
                    color: hasDateRange 
                        ? theme.colorScheme.onSurface 
                        : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
              ),
              if (hasDateRange)
                GestureDetector(
                  onTap: _clearDateRange,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.close, size: 14, color: theme.colorScheme.onSurface.withValues(alpha: 0.7)),
                  ),
                )
              else
                Icon(
                  Icons.arrow_drop_down,
                  color: theme.colorScheme.primary,
                ),
            ],
          ),
        ),
      ),
    );
  }
  
  /// מבצע חיפוש חכם עם AI
  Future<void> _performSmartSearch() async {
    final query = _currentQuery.trim();
    if (query.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('הקלד לפחות 2 תווים לחיפוש חכם'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSmartSearching = true);

    try {
      appLog('SmartSearch: Starting for query: "$query"');
      
      final intent = await _smartSearchService.parseSearchQuery(query);

      if (intent != null && intent.hasContent) {
        appLog('SmartSearch: Got intent - $intent');
        
        // קבלת כל הקבצים וסינון לפי intent
        final baseStream = _databaseService.watchSearch(
          query: '', // לא משתמשים בחיפוש רגיל
          filter: SearchFilter.all,
        );

        setState(() {
          _isSmartSearchActive = true;
          _lastSmartIntent = intent;
          _searchStream = baseStream.map((files) {
            return SmartSearchFilter.filterFiles(files, intent);
          });
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text('חיפוש חכם: ${intent.terms.join(", ")}'),
              ],
            ),
            backgroundColor: Colors.purple.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        appLog('SmartSearch: No intent returned, falling back to regular search');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('לא הצלחתי להבין את החיפוש, נסה ניסוח אחר'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      appLog('SmartSearch ERROR: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('שגיאה בחיפוש חכם: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      setState(() => _isSmartSearching = false);
    }
  }

  /// בונה באנר חיפוש AI חכם
  Widget _buildSmartAISearchBanner() {
    final theme = Theme.of(context);
    final isPremium = _settingsService.isPremium;
    final hasQuery = _currentQuery.trim().length >= 2;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: GestureDetector(
        onTap: () {
          if (!isPremium) {
            _showPremiumUpgradeMessage('חיפוש AI חכם');
          } else if (_isSmartSearching) {
            // כבר בחיפוש
          } else if (hasQuery) {
            _performSmartSearch();
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('הקלד משהו לחיפוש'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: _isSmartSearchActive
                ? const LinearGradient(
                    colors: [Colors.purple, Colors.blue],
                  )
                : (isPremium
                    ? LinearGradient(
                        colors: [
                          theme.colorScheme.primary.withValues(alpha: 0.3),
                          theme.colorScheme.secondary.withValues(alpha: 0.3),
                        ],
                      )
                    : null),
            color: isPremium ? null : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _isSmartSearchActive
                  ? Colors.transparent
                  : (isPremium 
                      ? Colors.transparent 
                      : Colors.amber.withValues(alpha: 0.5)),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: _isSmartSearchActive
                      ? null
                      : const LinearGradient(
                          colors: [Colors.purple, Colors.blue],
                        ),
                  color: _isSmartSearchActive ? Colors.white.withValues(alpha: 0.2) : null,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _isSmartSearching
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : Icon(
                        Icons.auto_awesome,
                        size: 16,
                        color: _isSmartSearchActive ? Colors.white : Colors.white,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          _isSmartSearchActive ? 'חיפוש חכם פעיל' : 'חיפוש AI חכם',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                            color: _isSmartSearchActive ? Colors.white : null,
                          ),
                        ),
                        if (!isPremium) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                        if (_isSmartSearchActive) ...[
                          const SizedBox(width: 8),
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isSmartSearchActive = false;
                                _lastSmartIntent = null;
                              });
                              _updateSearchStream();
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.3),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                tr('cancel'),
                                style: const TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      _isSmartSearchActive
                          ? 'מציג תוצאות לפי AI'
                          : 'חפש בשפה טבעית עם בינה מלאכותית',
                      style: TextStyle(
                        fontSize: 11,
                        color: _isSmartSearchActive 
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
              if (!_isSmartSearchActive)
                Icon(
                  Icons.chevron_left,
                  color: isPremium ? theme.colorScheme.primary : Colors.amber,
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// בונה את כותרת החיפוש - מודרני
  Widget _buildSearchHeader() {
    final theme = Theme.of(context);
    
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // לוגו וכותרת
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      theme.colorScheme.primary,
                      theme.colorScheme.secondary,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.search, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                'חיפוש',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              // כפתור הגדרות
              IconButton(
                icon: Icon(
                  Icons.settings,
                  color: theme.colorScheme.primary,
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const SettingsScreen(),
                    ),
                  );
                },
                tooltip: 'הגדרות',
              ),
            ],
          ),
          const SizedBox(height: 16),
          // שדה חיפוש
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: _isListening 
                    ? Colors.red 
                    : theme.colorScheme.primary.withValues(alpha: 0.3),
                width: _isListening ? 2 : 1,
              ),
              boxShadow: [
                if (_isListening)
                  BoxShadow(
                    color: Colors.red.withValues(alpha: 0.2),
                    blurRadius: 12,
                  ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: TextField(
                controller: _searchController,
                focusNode: _searchFocusNode,
                textDirection: _isHebrew(_searchController.text) ? TextDirection.rtl : TextDirection.ltr,
                decoration: InputDecoration(
                  hintText: 'חפש קבצים, תמונות, מסמכים...',
                  hintStyle: TextStyle(color: Colors.grey.shade500),
                  prefixIcon: Icon(
                    Icons.search,
                    color: theme.colorScheme.primary,
                  ),
                  suffixIcon: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // כפתור ניקוי
                      if (_searchController.text.isNotEmpty)
                        IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        ),
                      // כפתור מיקרופון
                      _buildMicrophoneButton(),
                      // כפתור חיבור ל-Drive
                      if (!_googleDriveService.isConnected)
                        IconButton(
                          icon: const Icon(Icons.add_to_drive, size: 20),
                          tooltip: 'חבר Google Drive',
                          onPressed: _connectDrive,
                        ),
                    ],
                  ),
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  filled: false,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
          ),
        ],
      ),
    );
  }
  
  /// חיבור ל-Google Drive
  Future<void> _connectDrive() async {
    if (!_settingsService.isPremium) {
      _showPremiumUpgradeMessage('Google Drive');
      return;
    }

    final success = await _googleDriveService.connect();
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('מחובר ל-Google Drive בהצלחה!'),
            backgroundColor: Colors.green,
          ),
        );
        setState(() {}); // רענון להסתרת הכפתור
        
        // אם יש כבר טקסט בשדה החיפוש - נבצע חיפוש מיידי בענן
        if (_searchController.text.isNotEmpty && _searchController.text.length > 2) {
          _searchCloud(_searchController.text);
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('שגיאה בחיבור ל-Google Drive'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// בונה צ'יפים לסינון - מודרני
  Widget _buildFilterChips() {
    final theme = Theme.of(context);
    final isPremium = _settingsService.isPremium;
    final favoritesCount = _favoritesService.count;
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _buildModernFilterChip('הכל', LocalFilter.all, Icons.apps),
          const SizedBox(width: 10),
          // מועדפים - פרימיום בלבד
          _buildFavoritesChip(isPremium, favoritesCount),
          const SizedBox(width: 10),
          _buildModernFilterChip('תמונות', LocalFilter.images, Icons.image),
          const SizedBox(width: 10),
          _buildModernFilterChip('PDF', LocalFilter.pdfs, Icons.picture_as_pdf),
        ],
      ),
    );
  }
  
  /// בונה צ'יפ מועדפים
  Widget _buildFavoritesChip(bool isPremium, int count) {
    final theme = Theme.of(context);
    final isSelected = _selectedFilter == LocalFilter.favorites;
    
    return GestureDetector(
      onTap: () {
        if (!isPremium) {
          _showPremiumUpgradeMessage('מועדפים');
        } else {
          _onFilterChanged(LocalFilter.favorites);
        }
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected 
              ? const LinearGradient(
                  colors: [Colors.amber, Colors.orange],
                )
              : null,
          color: isSelected ? null : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: isSelected 
              ? null 
              : Border.all(
                  color: isPremium 
                      ? Colors.amber.withValues(alpha: 0.5)
                      : Colors.grey.withValues(alpha: 0.3),
                ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.star,
              size: 16,
              color: isSelected 
                  ? Colors.white 
                  : (isPremium ? Colors.amber : Colors.grey),
            ),
            const SizedBox(width: 6),
            Text(
              'מועדפים',
              style: TextStyle(
                color: isSelected 
                    ? Colors.white 
                    : (isPremium ? theme.colorScheme.onSurface : Colors.grey),
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 13,
              ),
            ),
            if (count > 0 && isPremium) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected 
                      ? Colors.white.withValues(alpha: 0.3)
                      : Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  count.toString(),
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? Colors.white : Colors.amber,
                  ),
                ),
              ),
            ],
            if (!isPremium) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// בונה צ'יפ סינון בודד - מודרני
  Widget _buildModernFilterChip(String label, LocalFilter filter, IconData icon) {
    final theme = Theme.of(context);
    final isSelected = _selectedFilter == filter;
    
    return GestureDetector(
      onTap: () => _onFilterChanged(filter),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          gradient: isSelected 
              ? LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                )
              : null,
          color: isSelected ? null : theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: isSelected 
              ? null 
              : Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? Colors.white : theme.colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? Colors.white : theme.colorScheme.onSurface.withValues(alpha: 0.8),
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// בונה כפתור מיקרופון לחיפוש קולי
  Widget _buildMicrophoneButton() {
    final isPremium = _settingsService.isPremium;
    
    return GestureDetector(
      onLongPress: isPremium ? _toggleLocale : null, // לחיצה ארוכה להחלפת שפה
      child: Stack(
        children: [
          IconButton(
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: _isListening
                  ? Icon(
                      Icons.mic,
                      key: const ValueKey('mic_on'),
                      color: Colors.red,
                    )
                  : Icon(
                      Icons.mic_none,
                      key: const ValueKey('mic_off'),
                      color: isPremium 
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey,
                    ),
            ),
            onPressed: () {
              if (!isPremium) {
                _showPremiumUpgradeMessage('חיפוש קולי');
              } else if (_isListening) {
                _stopListening();
              } else {
                _startListening();
              }
            },
            tooltip: isPremium
                ? (_isListening ? 'הפסק הקלטה' : 'חיפוש קולי (לחיצה ארוכה להחלפת שפה)')
                : 'חיפוש קולי (פרימיום)',
            style: IconButton.styleFrom(
              backgroundColor: _isListening
                  ? Colors.red.withValues(alpha: 0.1)
                  : null,
            ),
          ),
          // תג PRO למשתמשים לא פרימיום
          if (!isPremium)
            Positioned(
              right: 4,
              top: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 7,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// בונה את אזור התוצאות
  Widget _buildResults() {
    final theme = Theme.of(context);
    
    return StreamBuilder<List<FileMetadata>>(
      stream: _searchStream,
      builder: (context, snapshot) {
        // טעינה
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return Center(
            child: CircularProgressIndicator(
              color: theme.colorScheme.primary,
            ),
          );
        }

        final results = snapshot.data ?? [];

        // מצב ריק
        if (results.isEmpty) {
          return _buildEmptyState();
        }

        return Column(
          children: [
            // מספר תוצאות
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${results.length} תוצאות',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (_searchController.text.isNotEmpty)
                    Text(
                      'ממוין לפי תאריך',
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            // רשימת תוצאות עם Pull to Refresh
            Expanded(
              child: RefreshIndicator(
                onRefresh: _onRefresh,
                color: theme.colorScheme.primary,
                backgroundColor: theme.colorScheme.surface,
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final file = results[index];
                    // אנימציית כניסה מדורגת
                    return TweenAnimationBuilder<double>(
                      key: ValueKey(file.path),
                      tween: Tween(begin: 0.0, end: 1.0),
                      duration: Duration(milliseconds: 200 + (index.clamp(0, 10) * 30)),
                      curve: Curves.easeOutCubic,
                      builder: (context, value, child) {
                        return Opacity(
                          opacity: value,
                          child: Transform.translate(
                            offset: Offset(0, 20 * (1 - value)),
                            child: child,
                          ),
                        );
                      },
                      child: _buildResultItem(file),
                    );
                  },
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// בונה מצב ריק - מודרני
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final hasSearchQuery = _searchController.text.isNotEmpty;
    final dbCount = _databaseService.getFilesCount();
    final isFavoritesFilter = _selectedFilter == LocalFilter.favorites;
    
    // מצב מיוחד - מועדפים ריקים
    if (isFavoritesFilter) {
      return _buildEmptyFavoritesState(theme);
    }
    
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // אנימציית אייקון
            TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1.0),
              duration: const Duration(milliseconds: 600),
              curve: Curves.elasticOut,
              builder: (context, scale, child) {
                return Transform.scale(scale: scale, child: child);
              },
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: hasSearchQuery 
                        ? [Colors.grey.shade800, Colors.grey.shade700]
                        : [
                            theme.colorScheme.primary.withValues(alpha: 0.2),
                            theme.colorScheme.secondary.withValues(alpha: 0.2),
                          ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: hasSearchQuery ? null : [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.3),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: Icon(
                  hasSearchQuery 
                      ? Icons.search_off_rounded 
                      : (dbCount == 0 ? Icons.folder_open_rounded : Icons.search_rounded),
                  size: 56,
                  color: hasSearchQuery ? Colors.grey.shade400 : theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 28),
            
            // כותרת
            Text(
              hasSearchQuery 
                  ? 'לא נמצאו תוצאות' 
                  : (dbCount == 0 ? 'מתחילים!' : 'מה מחפשים?'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: hasSearchQuery ? Colors.grey.shade400 : null,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            // תיאור
            Text(
              hasSearchQuery
                  ? 'נסה מילים אחרות או בדוק את האיות'
                  : (dbCount == 0 
                      ? 'הקבצים שלך נסרקים ברקע...' 
                      : 'חפש בשפה טבעית - "קבלה מאתמול", "תמונות מהחופשה"'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey.shade500,
              ),
              textAlign: TextAlign.center,
            ),
            
            // טיפים לחיפוש כשאין תוצאות
            if (hasSearchQuery) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.lightbulb_outline, color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        Text('טיפים', style: TextStyle(fontWeight: FontWeight.w600)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildTipRow('נסה מילה באנגלית או בעברית'),
                    _buildTipRow('חפש חלק משם הקובץ'),
                    _buildTipRow('הסר את הפילטר הנוכחי'),
                  ],
                ),
              ),
            ],
            
            // סטטיסטיקות
            if (!hasSearchQuery && dbCount > 0) ...[
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.inventory_2_outlined, 
                         color: theme.colorScheme.primary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      '$dbCount קבצים מוכנים לחיפוש',
                      style: TextStyle(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            // דוגמאות חיפוש
            if (!hasSearchQuery) ...[
              const SizedBox(height: 28),
              Text(
                'נסה לחפש:',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildSuggestionChip('חשבונית'),
                  _buildSuggestionChip('תעודת זהות'),
                  _buildSuggestionChip('חוזה'),
                  _buildSuggestionChip('receipt'),
                ],
              ),
            ],
            
            // קבצים אחרונים
            if (!hasSearchQuery) _buildRecentFilesSection(theme),
          ],
        ),
      ),
    );
  }
  
  /// בונה סקשן קבצים אחרונים
  Widget _buildRecentFilesSection(ThemeData theme) {
    final recentFiles = RecentFilesService.instance.recentFiles;
    if (recentFiles.isEmpty) return const SizedBox.shrink();
    
    // הצגת עד 5 קבצים אחרונים
    final filesToShow = recentFiles.take(5).toList();
    
    return Column(
      children: [
        const SizedBox(height: 32),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.history, size: 16, color: Colors.grey.shade500),
            const SizedBox(width: 8),
            Text(
              'נפתחו לאחרונה',
              style: TextStyle(
                color: Colors.grey.shade500,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...filesToShow.map((recent) => _buildRecentFileItem(recent, theme)),
      ],
    );
  }
  
  /// בונה פריט קובץ אחרון
  Widget _buildRecentFileItem(RecentFile recent, ThemeData theme) {
    final fileColor = _getFileColor(recent.extension);
    
    return GestureDetector(
      onTap: () async {
        final file = File(recent.path);
        if (await file.exists()) {
          final result = await OpenFilex.open(recent.path);
          if (result.type != ResultType.done && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('לא ניתן לפתוח: ${result.message}'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } else {
          // הקובץ לא קיים - הסרה מהרשימה
          RecentFilesService.instance.removeRecentFile(recent.path);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('הקובץ לא נמצא'),
                behavior: SnackBarBehavior.floating,
              ),
            );
            setState(() {}); // רענון
          }
        }
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: fileColor.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                _getFileIcon(recent.extension),
                size: 18,
                color: fileColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recent.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    _formatRecentTime(recent.accessedAt),
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_left,
              size: 18,
              color: Colors.grey.shade400,
            ),
          ],
        ),
      ),
    );
  }
  
  /// מחזיר אייקון לפי סוג קובץ
  IconData _getFileIcon(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'heic':
        return Icons.image;
      case 'pdf':
        return Icons.picture_as_pdf;
      case 'doc': case 'docx':
        return Icons.description;
      case 'xls': case 'xlsx':
        return Icons.table_chart;
      case 'mp4': case 'mov': case 'avi':
        return Icons.video_file;
      case 'mp3': case 'wav': case 'aac':
        return Icons.audio_file;
      default:
        return Icons.insert_drive_file;
    }
  }
  
  /// מפרמט זמן יחסי
  String _formatRecentTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);
    
    if (diff.inMinutes < 1) return 'עכשיו';
    if (diff.inMinutes < 60) return 'לפני ${diff.inMinutes} דקות';
    if (diff.inHours < 24) return 'לפני ${diff.inHours} שעות';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    return '${time.day}/${time.month}/${time.year}';
  }
  
  Widget _buildTipRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, color: Colors.green, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
            ),
          ),
        ],
      ),
    );
  }
  
  Widget _buildEmptyFavoritesState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.amber.withValues(alpha: 0.2), Colors.orange.withValues(alpha: 0.2)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.star_outline_rounded, size: 56, color: Colors.amber),
            ),
            const SizedBox(height: 28),
            const Text(
              'אין מועדפים עדיין',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'לחץ ארוך על קובץ והוסף למועדפים\nלגישה מהירה',
              style: TextStyle(color: Colors.grey.shade500),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: () {
                setState(() => _selectedFilter = LocalFilter.all);
                _updateSearchStream();
              },
              icon: const Icon(Icons.arrow_back),
              label: const Text('חזרה לכל הקבצים'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.amber,
                side: const BorderSide(color: Colors.amber),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// בונה צ'יפ הצעה לחיפוש - מודרני
  Widget _buildSuggestionChip(String text) {
    final theme = Theme.of(context);
    
    return GestureDetector(
      onTap: () {
        _searchController.text = text;
        _currentQuery = text;
        _updateSearchStream();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              text,
              style: TextStyle(
                color: theme.colorScheme.primary,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// בונה פריט תוצאה - מודרני
  Widget _buildResultItem(FileMetadata file) {
    final theme = Theme.of(context);
    final rawQuery = _searchController.text;
    final cleanQuery = _getCleanQuery(rawQuery);
    final folderName = _getFolderName(file.path);
    
    // בדיקה אם יש התאמה בטקסט מחולץ
    final hasOcrMatch = cleanQuery.isNotEmpty && 
        file.extractedText?.toLowerCase().contains(cleanQuery.toLowerCase()) == true;
    
    // בדיקה אם זה קובץ מ-WhatsApp
    final isWhatsApp = file.path.toLowerCase().contains('whatsapp');
    
    // בדיקה אם מועדף
    final isFavorite = _favoritesService.isFavorite(file.path);
    
    // בדיקה אם נבחר (מצב בחירה מרובה)
    final isSelected = _selectedFiles.contains(file.path);
    
    // תגיות הקובץ
    final fileTags = TagsService.instance.getFileTags(file.path);
    
    final fileColor = _getFileColor(file.extension);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isSelected 
            ? theme.colorScheme.primary.withValues(alpha: 0.15)
            : theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? theme.colorScheme.primary
              : isFavorite
                  ? Colors.amber.withValues(alpha: 0.5)
                  : (hasOcrMatch 
                      ? theme.colorScheme.secondary.withValues(alpha: 0.3)
                      : Colors.transparent),
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSelectionMode 
              ? () => _toggleFileSelection(file.path)
              : () => _openFile(file),
          onLongPress: _isSelectionMode 
              ? null 
              : () {
                  // כניסה למצב בחירה בלחיצה ארוכה
                  HapticFeedback.mediumImpact();
                  setState(() {
                    _isSelectionMode = true;
                    _selectedFiles.add(file.path);
                  });
                },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Checkbox במצב בחירה
                    if (_isSelectionMode) ...[
                      Checkbox(
                        value: isSelected,
                        onChanged: (_) => _toggleFileSelection(file.path),
                        activeColor: theme.colorScheme.primary,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    // תמונה ממוזערת או אייקון
                    _buildFileThumbnail(file, fileColor, isWhatsApp),
                    const SizedBox(width: 14),
                    
                    // תוכן
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // שם קובץ עם הדגשה
                          Row(
                            children: [
                              if (isFavorite) ...[
                                const Icon(Icons.star, color: Colors.amber, size: 14),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: _buildHighlightedText(
                                  file.name,
                                  cleanQuery,
                                  TextStyle(
                                    fontWeight: FontWeight.w600, 
                                    fontSize: 14,
                                    color: theme.colorScheme.onSurface,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          
                          // מידע על הקובץ
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: isWhatsApp 
                                      ? Colors.green.withValues(alpha: 0.2)
                                      : Colors.grey.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isWhatsApp ? Icons.chat_bubble : (file.isCloud ? Icons.cloud : Icons.folder),
                                      size: 10,
                                      color: isWhatsApp ? Colors.green : (file.isCloud ? Colors.blue : Colors.grey.shade500),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      file.isCloud ? 'Google Drive' : folderName,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isWhatsApp ? Colors.green : (file.isCloud ? Colors.blue : Colors.grey.shade500),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                file.readableSize,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                textDirection: TextDirection.ltr,
                              ),
                              const SizedBox(width: 12),
                              Text(
                                _formatDate(file.lastModified),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                textDirection: TextDirection.ltr,
                              ),
                            ],
                          ),
                          // תגיות (אם יש)
                          if (fileTags.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 4,
                              runSpacing: 4,
                              children: fileTags.take(3).map((tag) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: tag.color.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: tag.color.withValues(alpha: 0.3),
                                    width: 0.5,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(tag.icon, size: 10, color: tag.color),
                                    const SizedBox(width: 3),
                                    Text(
                                      tag.name,
                                      style: TextStyle(fontSize: 9, color: tag.color),
                                    ),
                                  ],
                                ),
                              )).toList(),
                            ),
                          ],
                        ],
                      ),
                    ),
                    
                    // כפתור תפריט פעולות
                    IconButton(
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () => _showFileActionsSheet(file),
                      tooltip: 'אפשרויות נוספות',
                    ),
                  ],
                ),
                
                // קטע טקסט מחולץ אם יש התאמה (עם תמיכה ב-RTL)
                if (hasOcrMatch && file.extractedText != null) ...[
                  const SizedBox(height: 12),
                  _buildOcrSnippet(file.extractedText!, cleanQuery),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
  
  /// מחזיר צבע לפי סוג קובץ
  Color _getFileColor(String extension) {
    switch (extension.toLowerCase()) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'bmp': case 'heic': case 'heif':
        return Colors.purple;
      case 'mp4': case 'mov': case 'avi': case 'mkv': case 'webm': case '3gp':
        return Colors.pink;
      case 'pdf':
        return Colors.red;
      case 'doc': case 'docx':
        return Colors.blue;
      case 'xls': case 'xlsx':
        return Colors.green;
      case 'txt': case 'rtf':
        return Colors.orange;
      case 'mp3': case 'wav': case 'm4a': case 'ogg': case 'aac':
        return Colors.teal;
      default:
        return Colors.grey;
    }
  }
  
  /// בונה אייקון קובץ
  /// סיומות תמונה שנציג להן thumbnail
  static const _imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'webp', 'bmp'];
  
  /// בונה תמונה ממוזערת או אייקון
  Widget _buildFileThumbnail(FileMetadata file, Color fileColor, bool isWhatsApp) {
    final ext = file.extension.toLowerCase();
    final isImage = _imageExtensions.contains(ext);
    
    // גודל התמונה הממוזערת
    const double size = 52;
    const double borderRadius = 12;
    
    // אם זו תמונה - נציג thumbnail
    if (isImage) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(borderRadius),
          color: fileColor.withValues(alpha: 0.15),
        ),
        clipBehavior: Clip.antiAlias,
        child: Image.file(
          File(file.path),
          fit: BoxFit.cover,
          width: size,
          height: size,
          cacheWidth: 150, // קאשינג לביצועים
          cacheHeight: 150,
          errorBuilder: (context, error, stackTrace) {
            // אם נכשל - נציג אייקון
            return Center(
              child: _buildFileIcon(file.extension, isWhatsApp),
            );
          },
          frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
            if (wasSynchronouslyLoaded) return child;
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 200),
              child: frame != null
                  ? child
                  : Container(
                      color: fileColor.withValues(alpha: 0.15),
                      child: Center(
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: fileColor,
                          ),
                        ),
                      ),
                    ),
            );
          },
        ),
      );
    }
    
    // אם לא תמונה - אייקון רגיל
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: fileColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      child: Center(
        child: _buildFileIcon(file.extension, isWhatsApp),
      ),
    );
  }

  Widget _buildFileIcon(String extension, bool isWhatsApp) {
    IconData icon;
    Color color = _getFileColor(extension);
    
    if (isWhatsApp) {
      return const Icon(Icons.chat_bubble, size: 22, color: Colors.green);
    }
    
    switch (extension.toLowerCase()) {
      case 'jpg': case 'jpeg': case 'png': case 'gif': case 'webp': case 'bmp': case 'heic': case 'heif':
        icon = Icons.image; break;
      case 'mp4': case 'mov': case 'avi': case 'mkv': case 'webm': case '3gp':
        icon = Icons.video_file; break;
      case 'pdf':
        icon = Icons.picture_as_pdf; break;
      case 'doc': case 'docx':
        icon = Icons.description; break;
      case 'xls': case 'xlsx':
        icon = Icons.table_chart; break;
      case 'txt': case 'rtf':
        icon = Icons.article; break;
      case 'mp3': case 'wav': case 'm4a': case 'ogg': case 'aac':
        icon = Icons.audio_file; break;
      default:
        icon = Icons.insert_drive_file;
    }
    
    return Icon(icon, size: 22, color: color);
  }

  /// בונה קטע טקסט OCR עם תמיכה ב-RTL
  Widget _buildOcrSnippet(String text, String query) {
    final snippet = _getTextSnippet(text, query);
    final isRtl = _isHebrew(snippet);
    
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.format_quote,
            size: 16,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Directionality(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              child: _buildHighlightedText(
                snippet,
                query,
                Theme.of(context).textTheme.bodySmall!.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// בונה אייקון לפי סוג קובץ
  Widget _buildFileTypeIcon(String extension, bool isWhatsApp) {
    IconData icon;
    Color color;

    if (isWhatsApp) {
      icon = Icons.chat;
      color = Colors.green;
    } else {
      switch (extension.toLowerCase()) {
        // תמונות
        case 'jpg':
        case 'jpeg':
        case 'png':
        case 'gif':
        case 'webp':
        case 'bmp':
        case 'heic':
        case 'heif':
          icon = Icons.image;
          color = Colors.purple;
          break;
        // וידאו
        case 'mp4':
        case 'mov':
        case 'avi':
        case 'mkv':
        case 'webm':
        case '3gp':
          icon = Icons.video_file;
          color = Colors.pink;
          break;
        // מסמכים
        case 'pdf':
          icon = Icons.picture_as_pdf;
          color = Colors.red;
          break;
        case 'doc':
        case 'docx':
          icon = Icons.description;
          color = Colors.blue;
          break;
        case 'xls':
        case 'xlsx':
          icon = Icons.table_chart;
          color = Colors.green;
          break;
        case 'txt':
        case 'rtf':
          icon = Icons.article;
          color = Colors.orange;
          break;
        // אודיו
        case 'mp3':
        case 'wav':
        case 'm4a':
        case 'ogg':
        case 'aac':
          icon = Icons.audio_file;
          color = Colors.teal;
          break;
        default:
          icon = Icons.insert_drive_file;
          color = Colors.grey;
      }
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }

  /// בונה טקסט עם הדגשת מונח חיפוש
  Widget _buildHighlightedText(String text, String query, TextStyle baseStyle) {
    if (query.isEmpty) {
      return Text(text, style: baseStyle, maxLines: 2, overflow: TextOverflow.ellipsis);
    }

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }

      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }

      // הדגשה בצבע ובולד
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          backgroundColor: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.4),
          color: Theme.of(context).colorScheme.onTertiaryContainer,
          fontWeight: FontWeight.bold,
        ),
      ));

      start = index + query.length;
    }

    return RichText(
      text: TextSpan(style: baseStyle, children: spans),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// מחזיר קטע טקסט סביב מונח החיפוש (30 תווים לפני ואחרי)
  String _getTextSnippet(String text, String query) {
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final index = lowerText.indexOf(lowerQuery);

    // אם לא נמצא - מחזיר התחלה של הטקסט
    if (index == -1) return text.substring(0, text.length.clamp(0, 60));

    // 30 תווים לפני ו-30 אחרי מונח החיפוש
    const charsBeforeAfter = 30;
    int start = (index - charsBeforeAfter).clamp(0, text.length);
    int end = (index + query.length + charsBeforeAfter).clamp(0, text.length);

    String snippet = text.substring(start, end);
    
    // הוספת ... בהתאם לחיתוך
    if (start > 0) snippet = '...$snippet';
    if (end < text.length) snippet = '$snippet...';

    // ניקוי רווחים מיותרים ושורות חדשות
    return snippet.replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  /// פורמט תאריך
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inDays == 0) return 'היום';
    if (diff.inDays == 1) return 'אתמול';
    if (diff.inDays < 7) return 'לפני ${diff.inDays} ימים';
    
    return '${date.day}/${date.month}/${date.year}';
  }
}
