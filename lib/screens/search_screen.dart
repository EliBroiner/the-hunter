import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/file_metadata.dart';
import '../utils/file_type_helper.dart';
import '../utils/path_utils.dart';
import '../utils/regex_tester.dart';
import '../services/database_service.dart';
import '../services/favorites_service.dart';
import '../services/recent_files_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../services/hybrid_search_controller.dart';
import '../services/tags_service.dart';
import '../services/secure_folder_service.dart';
import '../services/widget_service.dart';
import '../services/google_drive_service.dart';
import '../models/ai_analysis_response.dart';
import '../services/category_manager_service.dart';
import '../services/file_processing_service.dart';
import 'settings_screen.dart';
import '../services/localization_service.dart';
import '../ui/utils/snackbar_helper.dart';
import 'search_screen/local_filter.dart';
import 'search_screen/search_helpers.dart';
import 'search_screen/search_logic.dart';
import 'search_screen/widgets/search_result_widgets.dart';
import 'search_screen/widgets/search_file_details_modal.dart';
import 'search_screen/widgets/search_file_actions_sheet.dart';

/// מסך חיפוש - מסך ראשי לחיפוש קבצים
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> with SingleTickerProviderStateMixin {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  final _databaseService = DatabaseService.instance;
  final _permissionService = PermissionService.instance;
  final _settingsService = SettingsService.instance;
  final _favoritesService = FavoritesService.instance;
  final _googleDriveService = GoogleDriveService.instance;
  
  LocalFilter _selectedFilter = LocalFilter.all;
  
  // Hybrid search — debounce + waterfall (local → AI fallback)
  late final HybridSearchController _hybridController;
  List<FileMetadata>? _hybridResultsOverride;
  bool _isAILoading = false;
  
  // Stream לחיפוש ריאקטיבי
  Stream<List<FileMetadata>>? _searchStream;
  List<FileMetadata> _cloudResults = []; // תוצאות ענן
  bool _isSearchingCloud = false;
  String _currentQuery = '';
  
  // טווח תאריכים לסינון
  DateTime? _selectedStartDate;
  DateTime? _selectedEndDate;
  
  // חיפוש קולי
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _selectedLocale = 'he-IL'; // ברירת מחדל עברית
  
  // חיפוש חכם (AI) — נשלט על ידי HybridSearchController
  bool _isSmartSearchActive = false;
  /// האם להציג גם תוצאות Secondary (ציון < 70% מהמקסימלי)
  bool _showAllSearchResults = false;

  /// הצעות למידה מ-Gemini אחרי Re-analyze — path -> רשימת הצעות (להצגת כרטיס Smart Learning)
  final Map<String, List<AiSuggestion>> _pendingSuggestionsByPath = {};
  /// החל כחוק קבוע — שמירה ל־SmartCategories בשרת (ברירת מחדל: true)
  bool _applyAsHardRule = true;

  late TabController _resultsTabController;
  
  // מצב בחירה מרובה
  bool _isSelectionMode = false;
  final Set<String> _selectedFiles = {};

  /// Temporary: Force show score even in Release mode for QA. Change to false before publishing to Store!
  static const bool _showDebugScore = true;

  @override
  void initState() {
    super.initState();
    _hybridController = HybridSearchController(
      databaseService: _databaseService,
      driveService: _googleDriveService,
      debounceDuration: const Duration(milliseconds: 800),
      isPremium: () => _settingsService.isPremium,
    )
      ..onResults = _onHybridResults
      ..onAILoading = _onHybridAILoading;
    _hybridController.addListener(_onHybridControllerChanged);
    _resultsTabController = TabController(length: 3, vsync: this);
    _resultsTabController.addListener(_onResultsTabChanged);
    _updateSearchStream();
    _initSpeech();
    _settingsService.isPremiumNotifier.addListener(_onPremiumChanged);
    // שחזור חיבור Drive בהפעלה — אם המשתמש כבר התחבר בעבר, חיפוש יכלול Drive בלי ללחוץ "חבר Drive"
    _googleDriveService.restoreSessionIfPossible();
  }

  void _onHybridControllerChanged() {
    if (mounted) setState(() {});
  }

  /// סנכרון טאב תוצאות עם הקונטרולר; מעבר לטאב Drive מפעיל חיפוש מקומי+Drive במקביל
  void _onResultsTabChanged() {
    if (_resultsTabController.indexIsChanging) return; // מריצים רק כשהאנימציה נגמרת
    final index = _resultsTabController.index.clamp(0, 2);
    _hybridController.setActiveTab(index);
    if (index == 2) {
      final q = _searchController.text.trim();
      if (q.length >= 2) {
        _applyUiFiltersToController();
        _hybridController.executeSearch(q);
      }
    }
    if (mounted) setState(() {});
  }

  void _onHybridResults(List<FileMetadata> results, {required bool isFromAI}) {
    if (!mounted) return;
    setState(() {
      _hybridResultsOverride = results.isNotEmpty ? results : null;
      _isSmartSearchActive = results.isNotEmpty;
      _showAllSearchResults = false; // איפוס "הצג עוד" בכל חיפוש חדש
      if (_hybridResultsOverride != null) _cloudResults = [];
    });
    _updateSearchStream();
  }

  void _onHybridAILoading(bool isLoading) {
    if (!mounted) return;
    setState(() => _isAILoading = isLoading);
  }

  void _onPremiumChanged() {
    if (mounted) setState(() {});
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
    _resultsTabController.removeListener(_onResultsTabChanged);
    _resultsTabController.dispose();
    _settingsService.isPremiumNotifier.removeListener(_onPremiumChanged);
    _hybridController.removeListener(_onHybridControllerChanged);
    _hybridController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _speechToText.stop();
    super.dispose();
  }

  /// מעדכן את ה-Stream — אם יש hybrid override משתמשים בו, אחרת watchSearch
  void _updateSearchStream() {
    final query = _currentQuery;
    
    final queryStartDate = parseTimeQuery(query);
    final startDate = _selectedStartDate ?? queryStartDate;
    final endDate = _selectedEndDate;
    
    final dbFilter = dbFilterForLocalFilter(_selectedFilter);
    
    final filteredCloud = filterCloudByLocalFilter(_cloudResults, _selectedFilter);

    List<FileMetadata> mergeWithCloud(List<FileMetadata> local) {
      return mergeLocalWithCloud(
        local,
        filteredCloud,
        (r) => applyLocalFilter(r, _selectedFilter, _favoritesService.isFavorite),
      );
    }

    setState(() {
      if (_hybridResultsOverride != null) {
        _searchStream = Stream.value(mergeWithCloud(_hybridResultsOverride!));
      } else {
        _isSmartSearchActive = false;
        _searchStream = _databaseService.watchSearch(
          query: query,
          filter: dbFilter,
          startDate: startDate,
          endDate: endDate,
        ).map((results) => mergeWithCloud(results));
      }
    });

    // Drive רץ כבר מתוך HybridSearchController.executeSearch — לא קוראים שוב כשמתקבלות תוצאות היברידיות
    if (query.isEmpty || query.length <= 2 || _hybridResultsOverride == null) {
      if (query.isNotEmpty && query.length > 2 && _googleDriveService.isConnected) {
        _searchCloud(query);
      } else {
        setState(() => _cloudResults = []);
      }
    }
  }

  /// חיפוש בענן — שאילתה פשוטה
  Future<void> _searchCloud(String query) async {
    if (_isSearchingCloud) return;
    setState(() => _isSearchingCloud = true);
    try {
      final results = await _googleDriveService.searchFiles(query: query);
      if (mounted) {
        setState(() => _cloudResults = results);
        _updateSearchStream();
      }
    } finally {
      if (mounted) setState(() => _isSearchingCloud = false);
    }
  }

  /// מעדכן פילטרי UI בקונטרולר (תאריכים, סוג קובץ) — לפני כל חיפוש; "הכל" = רשימה ריקה (כל הסוגים)
  void _applyUiFiltersToController() {
    final fileTypes = getFileTypesForFilter(_selectedFilter);
    _hybridController.setUiFilters(
      dateFrom: _selectedStartDate,
      dateTo: _selectedEndDate,
      fileTypes: fileTypes,
    );
  }

  /// חיפוש היברידי — debounce 800ms, אחר כך waterfall (מקומי → AI); מכבד פילטרי UI
  void _onSearchChanged(String query) {
    _currentQuery = query;
    setState(() => _hybridResultsOverride = null);
    _applyUiFiltersToController();
    _hybridController.onQueryChanged(query);
    _updateSearchStream(); // watchSearch עד שההיבריד מחזיר תוצאות
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
            SnackBar(
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

  /// משנה פילטר — מעדכן UI ומריץ חיפוש מחדש עם הפילטר החדש
  void _onFilterChanged(LocalFilter filter) {
    HapticFeedback.selectionClick();
    setState(() => _selectedFilter = filter);
    _currentQuery = _searchController.text;
    _applyUiFiltersToController();
    _hybridController.runSearchNow();
    _updateSearchStream();
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
            Text(tr('delete_files_title')),
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
      await SharePlus.instance.share(ShareParams(files: files));
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
              Text(tr('refresh_complete')),
            ],
          ),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF1E1E3F),
        ),
      );
    }
  }

  /// פותח קובץ — קבצי ענן: הורדה לקובץ זמני ופתיחה
  Future<void> _openFile(FileMetadata file) async {
    if (file.isCloud || file.path.isEmpty || file.path == 'Google Drive') {
      await _downloadAndOpenCloudFile(file);
      return;
    }
    await _openLocalFile(file);
  }

  Future<void> _downloadAndOpenCloudFile(FileMetadata file) async {
    final cloudId = file.cloudId;
    if (cloudId == null || cloudId.isEmpty) {
      if (mounted) _showFileNotFoundSnackBar();
      return;
    }
    if (mounted) _showDownloadingSnackBar();
    try {
      final bytes = await _googleDriveService.downloadFile(cloudId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      if (bytes == null || bytes.isEmpty) {
        if (mounted) _showFileNotFoundSnackBar();
        return;
      }
      final tempPath = await _saveTempFile(file, bytes);
      final result = await OpenFilex.open(tempPath);
      if (result.type == ResultType.done) {
        RecentFilesService.instance.addRecentFile(path: tempPath, name: file.name, extension: file.extension);
        WidgetService.instance.updateRecentFile(file.name, tempPath, file.extension);
      } else if (mounted) {
        _showOpenErrorSnackBar(result.message);
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        _showFileNotFoundSnackBar();
      }
    }
  }

  void _showFileNotFoundSnackBar() {
    showErrorSnackBar(context, 'Could not download file');
  }

  void _showDownloadingSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Row(children: [SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)), const SizedBox(width: 12), const Text('Downloading...')]), duration: const Duration(minutes: 1), behavior: SnackBarBehavior.floating, backgroundColor: const Color(0xFF1E1E3F)));
  }

  void _showOpenErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(tr('open_error').replaceFirst('\${result.message}', message)), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating));
  }

  Future<String> _saveTempFile(FileMetadata file, List<int> bytes) async {
    final tempDir = await getTemporaryDirectory();
    final ext = FileTypeHelper.effectiveExtensionFromName(file.name);
    final effectiveExt = ext.isNotEmpty ? ext : file.extension.toLowerCase();
    final baseName = file.name.contains('.') ? file.name.substring(0, file.name.lastIndexOf('.')) : file.name;
    final safeBase = baseName.replaceAll(RegExp(r'[^\w\s\-\.]'), '_');
    final tempFileName = effectiveExt.isNotEmpty ? '$safeBase.$effectiveExt' : safeBase;
    final tempPath = '${tempDir.path}/$tempFileName';
    await File(tempPath).writeAsBytes(bytes);
    return tempPath;
  }

  Future<void> _openLocalFile(FileMetadata file) async {
    // קובץ מקומי: בדיקה אם קיים
    final fileExists = await File(file.path).exists();
    if (!fileExists) {
      if (mounted) {
        showErrorSnackBarWithAction(
          context,
          tr('file_not_found').replaceFirst('\${file.name}', file.name),
          actionLabel: tr('remove_from_list'),
          onAction: () {
            _databaseService.deleteFile(file.id);
            _updateSearchStream();
          },
        );
      }
      return;
    }
    final result = await OpenFilex.open(file.path);
    if (result.type == ResultType.done) {
      RecentFilesService.instance.addRecentFile(path: file.path, name: file.name, extension: file.extension);
      WidgetService.instance.updateRecentFile(file.name, file.path, file.extension);
    } else if (mounted) {
      _showOpenErrorSnackBar(result.message);
    }
  }

  /// משתף קובץ
  Future<void> _shareFile(FileMetadata file) async {
    // בדיקה אם הקובץ קיים
    final fileExists = await File(file.path).exists();
    if (!fileExists) {
      if (mounted) showErrorSnackBar(context, 'הקובץ לא נמצא');
      return;
    }

    await SharePlus.instance.share(ShareParams(
      files: [XFile(file.path)],
      text: tr('share_text').replaceFirst('\${file.name}', file.name),
    ));
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
          SnackBar(
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
        title: Row(
          children: [
            const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 28),
            const SizedBox(width: 12),
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
    final textColor = theme.textTheme.bodyLarge?.color ?? (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
    final secondaryColor = theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurfaceVariant;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SearchFileDetailsModal(
        file: file,
        theme: theme,
        pendingSuggestions: _pendingSuggestionsByPath[file.path],
        detailsCard: _buildFileDetailsCard(file, theme, textColor, secondaryColor),
        onReanalyze: (report, isCanceled) => _reanalyzeFile(file, reportProgress: report, isCanceled: isCanceled),
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }

  Widget _buildFileDetailsCard(FileMetadata file, ThemeData theme, Color textColor, Color secondaryColor) {
    final cardBg = theme.colorScheme.surfaceContainerHighest;
    final dividerColor = theme.dividerColor;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: cardBg, borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          _buildAnalysisSmartBadge(file),
          Divider(height: 20, color: dividerColor),
          SearchDetailRow(theme: theme, label: tr('detail_name'), value: file.name, icon: Icons.insert_drive_file),
          Divider(height: 20, color: dividerColor),
          SearchDetailRow(theme: theme, label: tr('detail_type'), value: file.extension.toUpperCase(), icon: Icons.category),
          Divider(height: 20, color: dividerColor),
          SearchDetailRow(theme: theme, label: tr('detail_size'), value: file.readableSize, icon: Icons.data_usage),
          Divider(height: 20, color: dividerColor),
          SearchDetailRow(theme: theme, label: tr('detail_date'), value: formatDate(file.lastModified), icon: Icons.calendar_today),
          Divider(height: 20, color: dividerColor),
          SearchDetailRow(theme: theme, label: tr('detail_path'), value: getShortPath(file.path), icon: Icons.folder_open, isPath: true),
          if (file.extractedText != null && file.extractedText!.isNotEmpty) ...[
            Divider(height: 20, color: dividerColor),
            _buildExtractedTextExpansion(file, theme, textColor, secondaryColor),
          ],
          Divider(height: 20, color: dividerColor),
          _buildAIDetailSection(file, theme, textColor, secondaryColor, _pendingSuggestionsByPath[file.path]),
        ],
      ),
    );
  }
  
  /// Smart Badge — מציג מקור התיוג (מילון / AI / מכסה / שגיאה / ממתין)
  Widget _buildAnalysisSmartBadge(FileMetadata file) {
    final String label;
    final IconData icon;
    final Color color;
    if (file.aiStatus == 'no_text_detected') {
      label = '📷 No Text Detected';
      icon = Icons.image_not_supported;
      color = Colors.grey;
    } else if (file.aiStatus == 'local_match') {
      label = '⚡ Auto-Tagged (Dictionary)';
      icon = Icons.bolt;
      color = const Color(0xFF26A69A); // Green/Teal
    } else if (file.isAiAnalyzed && file.aiStatus == null) {
      label = '✨ AI Analysis (Gemini)';
      icon = Icons.auto_awesome;
      color = const Color(0xFF9C27B0); // Purple
    } else if (file.aiStatus == 'quotaLimit') {
      label = '⚠️ Analysis Skipped (Quota)';
      icon = Icons.warning_amber_rounded;
      color = const Color(0xFFFF9800); // Orange
    } else if (file.aiStatus == 'pending_retry') {
      label = '⏳ Pending Retry';
      icon = Icons.sync;
      color = Colors.grey;
    } else if (file.aiStatus == 'auth_failed_retry') {
      label = '🔐 Auth Cooldown';
      icon = Icons.lock_clock;
      color = Colors.grey;
    } else if (file.aiStatus == 'error') {
      label = '❌ Analysis Failed';
      icon = Icons.error_outline;
      color = const Color(0xFFE53935); // Red
    } else {
      label = '⏳ Pending Analysis...';
      icon = Icons.schedule;
      color = Colors.grey;
    }
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 14),
          ),
        ),
      ],
    );
  }

  /// ExpansionTile לטקסט מחולץ — תצוגה מקוצרת, הרחבה, והעתקה
  Widget _buildExtractedTextExpansion(FileMetadata file, ThemeData theme, Color textColor, Color secondaryColor) {
    final text = file.extractedText ?? '';
    final previewLines = text.split('\n').take(3).join('\n');
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.text_snippet, size: 18, color: secondaryColor),
              const SizedBox(width: 8),
              Text(
                '📄 ${tr('detail_extracted_text')} (OCR)',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: textColor),
              ),
            ],
          ),
          if (previewLines.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              previewLines,
              style: TextStyle(color: secondaryColor, fontSize: 12),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textDirection: isHebrew(previewLines) ? TextDirection.rtl : TextDirection.ltr,
            ),
          ],
        ],
      ),
      initiallyExpanded: false,
      children: [
        SelectableText(
          text,
          style: TextStyle(fontSize: 13, color: textColor),
          textDirection: isHebrew(text) ? TextDirection.rtl : TextDirection.ltr,
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('Copied'),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  backgroundColor: theme.canvasColor,
                ),
              );
            },
            icon: Icon(Icons.copy, size: 18, color: theme.colorScheme.primary),
            label: Text('Copy', style: TextStyle(color: theme.colorScheme.primary)),
          ),
        ),
      ],
    );
  }

  /// בונה סקציית AI — קטגוריה + תגיות כ־Chips + כרטיס Smart Learning אם יש הצעות
  Widget _buildAIDetailSection(
    FileMetadata file,
    ThemeData theme,
    Color textColor,
    Color secondaryColor, [
    List<AiSuggestion>? pendingSuggestions,
  ]) {
    final suggestions = pendingSuggestions ?? [];
    const aiColor = Color(0xFF26A69A);
    const aiIcon = Icons.psychology;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: aiColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SearchDetailRow(theme: theme, label: tr('detail_ai_category'), value: file.category ?? '—', icon: aiIcon, accentColor: aiColor),
          if (file.tags != null && file.tags!.isNotEmpty) ...[
            Divider(height: 16, color: theme.dividerColor),
            Text(
              tr('detail_ai_tags'),
              style: TextStyle(color: secondaryColor, fontSize: 13),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: file.tags!.map((tag) => Chip(
                label: Text(tag, style: TextStyle(fontSize: 12, color: textColor)),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              )).toList(),
            ),
          ],
          if (suggestions.isNotEmpty) ...[
            Divider(height: 20, color: theme.dividerColor),
            _buildSmartLearningCard(file, suggestions, theme, textColor, secondaryColor),
          ],
        ],
      ),
    );
  }

  /// כרטיס "Smart Learning" — הצעות מג'מיני: Regex/מילים, כפתורי [הוסף חוק] / [התעלם]
  Widget _buildSmartLearningCard(
    FileMetadata file,
    List<AiSuggestion> suggestions,
    ThemeData theme,
    Color textColor,
    Color secondaryColor,
  ) {
    final hasAnyTechnicalRules = suggestions.any((s) => s.hasTechnicalRules);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF9C27B0).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFF9C27B0).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb_outline, color: Color(0xFF9C27B0), size: 20),
              const SizedBox(width: 8),
              Text(
                'Smart Learning',
                style: TextStyle(fontWeight: FontWeight.w600, color: textColor, fontSize: 14),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Gemini suggests a new rule to automate this category:',
            style: TextStyle(color: secondaryColor, fontSize: 12),
          ),
          if (hasAnyTechnicalRules) ...[
            const SizedBox(height: 12),
            _buildSuggestedRulesSection(suggestions, textColor, secondaryColor),
          ],
          const SizedBox(height: 12),
          CheckboxListTile(
            value: _applyAsHardRule,
            onChanged: (v) => setState(() => _applyAsHardRule = v ?? true),
            title: Text(
              'Apply as Hard Rule / החל כחוק קבוע',
              style: TextStyle(fontSize: 12, color: textColor),
            ),
            controlAffinity: ListTileControlAffinity.leading,
            contentPadding: EdgeInsets.zero,
            dense: true,
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  setState(() => _pendingSuggestionsByPath.remove(file.path));
                },
                child: const Text('Dismiss'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _onAddRule(file, suggestions),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Rule'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// סעיף "חוקים מוצעים" — Chips למילות מפתח, קוד ל-Regex
  Widget _buildSuggestedRulesSection(
    List<AiSuggestion> suggestions,
    Color textColor,
    Color secondaryColor,
  ) {
    final allKeywords = suggestions.expand((s) => s.suggestedKeywords).where((k) => k.isNotEmpty).toSet().toList();
    final allRegex = suggestions
        .map((s) => s.suggestedRegex)
        .whereType<String>()
        .where((r) => r.trim().isNotEmpty)
        .toList();
    if (allKeywords.isEmpty && allRegex.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Suggested Rules / חוקים מוצעים',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: secondaryColor,
          ),
        ),
        const SizedBox(height: 8),
        if (allKeywords.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: allKeywords.map((kw) => Chip(
              label: Text(kw, style: TextStyle(fontSize: 11, color: textColor)),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
            )).toList(),
          ),
        if (allRegex.isNotEmpty) ...[
          if (allKeywords.isNotEmpty) const SizedBox(height: 8),
          ...allRegex.map((r) => _buildRegexRow(r, textColor, secondaryColor)),
        ],
      ],
    );
  }

  /// שורת Regex — טקסט, Copy, Test
  Widget _buildRegexRow(String regex, Color textColor, Color secondaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white24),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SelectableText(
              regex,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 11,
                color: Colors.white70,
              ),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: regex));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Regex copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: const Text('Copy', style: TextStyle(fontSize: 11)),
          ),
          TextButton(
            onPressed: () => _showRegexTestDialog(regex),
            child: const Text('Test', style: TextStyle(fontSize: 11)),
          ),
        ],
      ),
    );
  }

  void _showRegexTestDialog(String pattern) {
    final controller = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => _RegexTestDialog(
        pattern: pattern,
        sampleController: controller,
        onClose: () => Navigator.of(ctx).pop(),
      ),
    );
  }

  Future<void> _onAddRule(FileMetadata file, List<AiSuggestion> suggestions) async {
    final categoryId = file.category?.trim() ?? suggestions.firstOrNull?.suggestedCategory ?? '';
    if (categoryId.isEmpty) return;
    if (!mounted) return;
    setState(() => _pendingSuggestionsByPath.remove(file.path));

    if (!_applyAsHardRule) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Suggestions dismissed (Apply as Hard Rule was unchecked).'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final catManager = CategoryManagerService.instance;
    final added = await catManager.approveSuggestions(categoryId, suggestions);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(added > 0 ? 'Rule saved to SmartCategories! Future documents will be detected locally.' : 'No rule added.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  /// ניתוח מחדש סינכרוני: forceReprocessFile (איפוס → OCR → Waterfall → AI). מציג Snackbar עם תוצאה ומרענן.
  Future<void> _reanalyzeFile(
    FileMetadata file, {
    void Function(String)? reportProgress,
    bool Function()? isCanceled,
  }) async {
    final isPro = _settingsService.isPremium;

    void report(String msg) {
      if (reportProgress != null) {
        reportProgress(msg);
      } else if (mounted) {
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(msg, style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
              ],
            ),
            duration: const Duration(days: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    try {
      final result = await FileProcessingService.instance.forceReprocessFile(
        file,
        isPro: isPro,
        reportProgress: report,
        isCanceled: isCanceled,
      );
      if (!mounted) return;
      if (result.suggestions.isNotEmpty) {
        setState(() => _pendingSuggestionsByPath[file.path] = result.suggestions);
      }
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.success ? Colors.green : Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('הניתוח נכשל: $e'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      rethrow;
    }
  }

  /// מציג גיליון ניתוח דירוג — ציון ופירוט רלוונטיות
  void _showRankingAnalysisSheet(FileMetadata file) {
    final score = file.debugScore;
    final breakdown = file.debugScoreBreakdown ?? '';
    final theme = Theme.of(context);
    final sheetBg = theme.canvasColor;
    final cardBg = theme.colorScheme.surfaceContainerHighest;
    final textColor = theme.textTheme.bodyLarge?.color ?? (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
    final secondaryColor = theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurfaceVariant;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        top: false,
        bottom: true,
        child: Container(
          constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.85),
          decoration: BoxDecoration(
            color: sheetBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.outline.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'ניתוח ציון רלוונטיות',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 16),
                if (score != null) ...[
                  Center(
                    child: Container(
                      width: 88,
                      height: 88,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: cardBg,
                        border: Border.all(color: Colors.amber, width: 2),
                      ),
                      child: Center(
                        child: Text(
                          score.round().toString(),
                          style: const TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  ..._parseBreakdownToRows(breakdown, textColor, secondaryColor),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: cardBg,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text('פורמולה', style: TextStyle(fontSize: 12, color: secondaryColor)),
                            TextButton.icon(
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: breakdown));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text('הועתק ללוח'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 1),
                                    backgroundColor: theme.canvasColor,
                                  ),
                                );
                              },
                              icon: Icon(Icons.copy, size: 16, color: theme.colorScheme.primary),
                              label: Text('העתק', style: TextStyle(color: theme.colorScheme.primary, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          breakdown.isEmpty ? '—' : breakdown,
                          style: TextStyle(fontSize: 11, fontFamily: 'monospace', color: secondaryColor),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(
                      'אין נתוני דירוג — הקובץ לא דורג בחיפוש זה.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: secondaryColor, fontSize: 14),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// מפרק מחרוזת פירוט (Fn(31) + Content(133)...) לרשימת שורות לתצוגה
  List<Widget> _parseBreakdownToRows(String breakdown, [Color? labelColor, Color? valueColor]) {
    final labelC = labelColor ?? Colors.grey;
    final valueC = valueColor ?? Colors.amber;
    final rows = parseBreakdown(breakdown);
    return rows.map((r) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(r.label, style: TextStyle(color: labelC, fontSize: 13)),
          if (r.value.isNotEmpty)
            Text(r.value, style: TextStyle(color: valueC, fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    )).toList();
  }

  /// מציג תפריט פעולות לקובץ
  void _showFileActionsSheet(FileMetadata file) {
    final theme = Theme.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => SearchFileActionsSheet(
        file: file,
        theme: theme,
        actionTiles: [
          _buildActionTile(
            icon: Icons.open_in_new,
            title: tr('action_open'),
            subtitle: tr('action_open_subtitle'),
            color: theme.colorScheme.primary,
            onTap: () {
              Navigator.of(ctx).pop();
              _openFile(file);
            },
          ),
          const SizedBox(height: 8),
          _buildFavoriteActionTile(file),
          const SizedBox(height: 8),
          _buildTagsActionTile(file),
          const SizedBox(height: 8),
          _buildSecureFolderActionTile(file),
          const SizedBox(height: 8),
          _buildActionTile(
            icon: Icons.share,
            title: tr('action_share'),
            subtitle: tr('action_share_subtitle'),
            color: Colors.blue,
            onTap: () {
              Navigator.of(ctx).pop();
              _shareFile(file);
            },
          ),
          const SizedBox(height: 8),
          _buildActionTile(
            icon: Icons.info_outline,
            title: tr('action_details'),
            subtitle: tr('action_details_subtitle'),
            color: Colors.teal,
            onTap: () {
              Navigator.of(ctx).pop();
              _showFileDetails(file);
            },
          ),
          const SizedBox(height: 8),
          _buildActionTile(
            icon: Icons.analytics_outlined,
            title: 'ניתוח דירוג',
            subtitle: 'ציון רלוונטיות ופירוט',
            color: Colors.amber,
            onTap: () {
              Navigator.of(ctx).pop();
              _showRankingAnalysisSheet(file);
            },
          ),
          const SizedBox(height: 8),
          _buildActionTile(
            icon: Icons.refresh,
            title: 'ניתוח מחדש',
            subtitle: 'חילוץ טקסט + AI מחדש',
            color: Colors.deepPurple,
            onTap: () {
              Navigator.of(ctx).pop();
              _reanalyzeFile(file);
            },
          ),
          const SizedBox(height: 8),
          _buildActionTile(
            icon: Icons.delete_outline,
            title: tr('action_delete'),
            subtitle: tr('action_delete_subtitle'),
            color: Colors.red,
            onTap: () {
              Navigator.of(ctx).pop();
              _showDeleteConfirmation(file);
            },
          ),
        ],
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
            _showPremiumUpgradeMessage(tr('premium_feature_favorites'));
            return;
          }
          
          await _favoritesService.toggleFavorite(file.path);
          if (!mounted) return;
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
                  Text(isFavorite ? tr('favorite_removed') : tr('favorite_added')),
                ],
              ),
              backgroundColor: Theme.of(context).canvasColor,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          isFavorite ? tr('action_remove_favorite') : tr('action_add_favorite'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPremium ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey,
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
                            child: Text(
                              tr('pro_badge'),
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
                          ? (isFavorite ? tr('favorite_in_list') : tr('favorites_quick_access'))
                          : tr('upgrade_premium'),
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
            _showPremiumUpgradeMessage(tr('premium_feature_tags'));
            return;
          }
          Navigator.of(context).pop();
          _showTagsDialog(file);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          tr('action_tags_title'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPremium ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey,
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
                            child: Text(
                              tr('pro_badge'),
                              style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
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
                        isPremium ? tr('action_tags_subtitle') : tr('upgrade_premium'),
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
      builder: (context) => SafeArea(
        top: false,
        bottom: true,
        child: StatefulBuilder(
          builder: (context, setModalState) {
            final allTags = tagsService.tags;
            final theme = Theme.of(context);
            return Container(
              decoration: BoxDecoration(
                color: theme.canvasColor,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.outline.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 16),
                
                // כותרת
                Row(
                  children: [
                    const Icon(Icons.label, color: Colors.purple),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        tr('tags_dialog_title'),
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () => _showCreateTagDialog(setModalState),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(tr('tags_new_button')),
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
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            );
          },
        ),
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
          title: Text(tr('tags_new_dialog_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: InputDecoration(
                  labelText: tr('tags_name_label'),
                  hintText: tr('tags_name_hint'),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 16),
              Text(tr('tags_color_label'), style: const TextStyle(fontWeight: FontWeight.w500)),
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
                if (!context.mounted) return;
                Navigator.of(context).pop();
                setModalState(() {});
              },
              child: Text(tr('tags_create_button')),
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
            _showPremiumUpgradeMessage(tr('premium_feature_secure'));
            return;
          }
          
          Navigator.of(context).pop();
          _moveToSecureFolder(file);
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
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
                          tr('action_secure_title'),
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: isPremium ? Theme.of(context).textTheme.bodyLarge?.color : Colors.grey,
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
                            child: Text(
                              tr('pro_badge'),
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isPremium ? tr('action_secure_subtitle') : tr('upgrade_premium'),
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
        title: Text(tr('secure_move_title')),
        content: Text(tr('secure_move_confirm').replaceFirst('\${name}', file.name)),
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
            child: Text(tr('secure_move_button')),
          ),
        ],
      ),
    );
    
    if (confirmed != true) return;
    
    // אם התיקייה נעולה - לבקש PIN
    if (!secureFolderService.isUnlocked) {
      if (mounted) Navigator.of(context).pushNamed('/secure');
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
              Text(success ? tr('secure_move_success') : tr('secure_move_error')),
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
  
  /// בונה פריט פעולה
  Widget _buildActionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final tileBg = theme.colorScheme.surfaceContainerHighest;
    final textColor = theme.textTheme.bodyLarge?.color ?? (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
    final secondaryColor = theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: tileBg,
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
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15, color: textColor),
                    ),
                    Text(
                      subtitle,
                      style: TextStyle(color: secondaryColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, color: secondaryColor),
            ],
          ),
        ),
      ),
    );
  }

  /// בורר תאריך — start או end
  Future<void> _showDatePicker({required bool isStart}) async {
    final theme = Theme.of(context);
    final now = DateTime.now();
    final firstDate = isStart ? DateTime(2020, 1, 1) : (_selectedStartDate ?? DateTime(2020, 1, 1));
    final initial = isStart ? (_selectedStartDate ?? now) : (_selectedEndDate ?? now);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: now,
      locale: const Locale('he', 'IL'),
      builder: (context, child) => _buildDatePickerTheme(theme, child),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _selectedStartDate = picked;
        if (_selectedEndDate != null && _selectedEndDate!.isBefore(picked)) _selectedEndDate = null;
      } else {
        _selectedEndDate = picked;
      }
    });
    _applyUiFiltersToController();
    _hybridController.runSearchNow();
    _updateSearchStream();
  }

  /// מעביר את ה־Theme-is — ה־DatePickerThemeData ב־main.dart מטפל בצבעים
  Theme _buildDatePickerTheme(ThemeData theme, Widget? child) {
    return Theme(data: theme, child: child!);
  }

  /// מנקה תאריכים
  void _clearDateRange() {
    setState(() {
      _selectedStartDate = null;
      _selectedEndDate = null;
    });
    _applyUiFiltersToController();
    _hybridController.runSearchNow();
    _updateSearchStream();
  }
  
  /// מציג הודעת שדרוג לפרימיום — צבעים דינמיים לפי ערכת הנושא
  void _showPremiumUpgradeMessage(String feature) {
    final theme = Theme.of(context);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.canvasColor,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Colors.amber, Colors.orange],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.star, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              tr('upgrade_premium'),
              style: TextStyle(color: theme.colorScheme.onSurface),
            ),
          ],
        ),
        content: Text(
          tr('premium_feature_dialog_content').replaceFirst('\${feature}', feature),
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr('later')),
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
            child: Text(tr('upgrade_now')),
          ),
        ],
      ),
    );
  }
  

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: SafeArea(
        child: Column(
          children: [
            // כותרת וחיפוש (או בר בחירה)
            _isSelectionMode
                ? _buildSelectionHeader(theme)
                : _buildSearchHeader(),
            
            // בורר טווח תאריכים
            if (!_isSelectionMode)
              _buildDateRangePicker(),
            
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
  
  /// בונה בורר תאריכים — מתאריך ו/או עד תאריך (כל אחד אופציונלי)
  Widget _buildDateRangePicker() {
    final theme = Theme.of(context);
    final hasAny = _selectedStartDate != null || _selectedEndDate != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: hasAny
                ? theme.colorScheme.secondary
                : theme.colorScheme.primary.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.calendar_today,
              size: 18,
              color: hasAny ? theme.colorScheme.secondary : theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showDatePicker(isStart: true),
                      child: Row(
                        children: [
                          Text(
                            tr('date_from_label'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _selectedStartDate != null
                                  ? formatDate(_selectedStartDate!)
                                  : tr('date_range_all'),
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedStartDate != null
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => _showDatePicker(isStart: false),
                      child: Row(
                        children: [
                          Text(
                            tr('date_to_label'),
                            style: TextStyle(
                              fontSize: 12,
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                          Flexible(
                            child: Text(
                              _selectedEndDate != null
                                  ? formatDate(_selectedEndDate!)
                                  : tr('date_none'),
                              style: TextStyle(
                                fontSize: 14,
                                color: _selectedEndDate != null
                                    ? theme.colorScheme.onSurface
                                    : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasAny)
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
              Icon(Icons.arrow_drop_down, color: theme.colorScheme.primary),
          ],
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
          _buildSearchHeaderRow(theme),
          const SizedBox(height: 16),
          _buildSearchField(theme),
        ],
      ),
    );
  }

  Widget _buildSearchHeaderRow(ThemeData theme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [theme.colorScheme.primary, theme.colorScheme.secondary]),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.search, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        Text('חיפוש', style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        const Spacer(),
        _buildHeaderFavoritesButton(theme),
        IconButton(
          icon: Icon(Icons.settings, color: theme.colorScheme.primary),
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          tooltip: 'הגדרות',
        ),
      ],
    );
  }

  Widget _buildSearchField(ThemeData theme) {
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isListening ? Colors.red : theme.colorScheme.primary.withValues(alpha: 0.3),
          width: _isListening ? 2 : 1,
        ),
        boxShadow: _isListening ? [BoxShadow(color: Colors.red.withValues(alpha: 0.2), blurRadius: 12)] : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: TextField(
          controller: _searchController,
          focusNode: _searchFocusNode,
          textDirection: isHebrew(_searchController.text) ? TextDirection.rtl : TextDirection.ltr,
          decoration: InputDecoration(
            hintText: tr('search_hint'),
            hintStyle: TextStyle(color: Colors.grey.shade500),
            prefixIcon: Icon(Icons.search, color: theme.colorScheme.primary),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, size: 20),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
                _buildMicrophoneButton(),
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
    );
  }
  
  /// בונה צ'יפים לסינון - מודרני
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _buildModernFilterChip(tr('filter_chip_all'), LocalFilter.all, Icons.apps),
          const SizedBox(width: 10),
          _buildModernFilterChip(tr('filter_chip_images'), LocalFilter.images, Icons.image),
          const SizedBox(width: 10),
          _buildModernFilterChip(tr('filter_chip_pdf'), LocalFilter.pdfs, Icons.picture_as_pdf),
        ],
      ),
    );
  }

  /// כפתור מועדפים בכותרת — PRO: כוכב (זהב כשפעיל); לא־PRO: מנעול + לחיצה פותחת Buy PRO
  Widget _buildHeaderFavoritesButton(ThemeData theme) {
    final isPremium = _settingsService.isPremium;
    final favoritesCount = _favoritesService.count;
    final isActive = _selectedFilter == LocalFilter.favorites;

    Widget button;
    if (!isPremium) {
      button = IconButton(
        icon: Icon(Icons.lock_outline, color: theme.colorScheme.primary),
        onPressed: () => Navigator.pushNamed(context, '/subscription'),
        tooltip: tr('filter_favorites'),
      );
      return button;
    }

    button = IconButton(
      icon: Icon(
        isActive ? Icons.star : Icons.star_border,
        color: isActive ? Colors.amber : theme.colorScheme.primary,
      ),
      onPressed: () {
        if (isActive) {
          _onFilterChanged(LocalFilter.all);
        } else {
          _onFilterChanged(LocalFilter.favorites);
        }
      },
      tooltip: tr('filter_favorites'),
    );

    if (favoritesCount > 0) {
      return Badge(
        isLabelVisible: true,
        label: Text('$favoritesCount'),
        child: button,
      );
    }
    return button;
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

        // חיפוש חכם: שני אזורים — במכשיר + Google Drive
        if (_hybridResultsOverride != null) {
          return _buildSmartSearchResults(theme);
        }

        if (results.isEmpty) return _buildEmptyState();

        return Column(
          children: [
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
                      _searchController.text.trim().isEmpty
                          ? 'סך הכל קבצים: ${results.length}'
                          : 'נמצאו ${results.length} תוצאות',
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
                      tr('sort_date'),
                      style: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
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

  /// תוצאות חיפוש חכם — טאבים "הכל" / "מקומי" / "Drive"; מקומי תמיד רץ; Drive לפי טאב + כפתור "חפש ב-Drive"
  Widget _buildSmartSearchResults(ThemeData theme) {
    final primary = _hybridController.primaryResults;
    final secondary = _hybridController.secondaryResults;
    final totalCount = primary.length + secondary.length;
    final tabIndex = _resultsTabController.index.clamp(0, 2);
    final isAllTab = tabIndex == 0;
    final isLocalTab = tabIndex == 1;
    final isDriveTab = tabIndex == 2;
    final localOnly = _hybridController.results.where((f) => !f.isCloud).toList();
    final driveOnly = _hybridController.results.where((f) => f.isCloud).toList();
    final canSearchDrive = _settingsService.isPremium && _googleDriveService.isConnected;
    final showSearchDriveChip = shouldShowSearchDriveChip(
      isAllTab: isAllTab,
      haveLocalResults: _hybridController.localResults.isNotEmpty,
      haveDriveResults: _hybridController.driveResults.isNotEmpty,
      canSearchDrive: canSearchDrive,
      queryLength: _searchController.text.trim().length,
    );
    final countLabel = smartSearchCountLabel(
      isDriveTab: isDriveTab,
      isLocalTab: isLocalTab,
      driveCount: driveOnly.length,
      localCount: localOnly.length,
      totalCount: totalCount,
    );

    return Column(
      children: [
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
                  countLabel,
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
              const Spacer(),
              TextButton(
                onPressed: () {
                  setState(() {
                    _hybridResultsOverride = null;
                    _isSmartSearchActive = false;
                  });
                  _hybridController.cancel();
                  _updateSearchStream();
                },
                child: Text(tr('cancel_smart_search'), style: const TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
        TabBar(
          controller: _resultsTabController,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
          tabs: const [
            Tab(text: 'הכל'),
            Tab(text: 'מקומי'),
            Tab(text: 'Drive'),
          ],
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _onRefresh,
            color: theme.colorScheme.primary,
            backgroundColor: theme.colorScheme.surface,
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              children: [
                if (isDriveTab)
                  if (driveOnly.isEmpty)
                    if (_hybridController.isDriveSearching)
                      ...[_buildSmartSearchLoadingView(theme, tr('searching_cloud'))]
                    else
                      ...[_buildSmartSearchEmptyView(theme)]
                  else
                    ...driveOnly.asMap().entries.map((e) => _buildAnimatedResultItem(e.value, e.key)),
                if (isLocalTab)
                  if (localOnly.isEmpty)
                    if (_hybridController.isLocalSearching)
                      ...[_buildSmartSearchLoadingView(theme, tr('ai_scanning_deeper'))]
                    else
                      ...[_buildSmartSearchEmptyView(theme)]
                  else
                    ...localOnly.asMap().entries.map((e) => _buildAnimatedResultItem(e.value, e.key)),
                if (isAllTab) ...[
                  ...primary.asMap().entries.map((e) => _buildAnimatedResultItem(e.value, e.key)),
                  if (secondary.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: TextButton(
                          onPressed: () => setState(() => _showAllSearchResults = true),
                          child: Text('הצג עוד ${secondary.length} תוצאות...'),
                        ),
                      ),
                    ),
                  if (_showAllSearchResults)
                    ...secondary.asMap().entries.map((e) => _buildAnimatedResultItem(e.value, e.key)),
                  if (showSearchDriveChip)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: ActionChip(
                          label: const Text('חפש ב-Drive'),
                          onPressed: () {
                            _hybridController.executeDriveSearchOnly(_searchController.text.trim());
                          },
                        ),
                      ),
                    ),
                ],
                if (_settingsService.isPremium && _searchController.text.trim().length >= 2)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: FilledButton.icon(
                        onPressed: _isAILoading
                            ? null
                            : () => _hybridController.triggerDeepSearch(),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Deep AI Search / חיפוש AI עמוק'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSmartSearchLoadingView(ThemeData theme, String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(width: 32, height: 32, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
            const SizedBox(height: 16),
            Text(message, style: TextStyle(color: Colors.grey.shade500, fontSize: 14)),
          ],
        ),
      ),
    );
  }

  Widget _buildSmartSearchEmptyView(ThemeData theme) {
    return Center(child: Padding(padding: const EdgeInsets.all(40), child: Text(tr('no_results'), style: TextStyle(color: Colors.grey.shade500, fontSize: 14))));
  }

  Widget _buildAnimatedResultItem(FileMetadata file, int index) {
    return TweenAnimationBuilder<double>(
      key: ValueKey('${file.path}_${file.cloudId ?? ""}'),
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
  }

  /// בונה מצב ריק - מודרני
  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final hasSearchQuery = _searchController.text.isNotEmpty;
    final dbCount = _databaseService.getFilesCount();
    if (_selectedFilter == LocalFilter.favorites) return _buildEmptyFavoritesState(theme);

    final isAIScanning = hasSearchQuery && _isAILoading;
    final isDriveScanning = hasSearchQuery && _hybridController.isDriveSearching;
    final loadingTitle = _getEmptyStateLoadingTitle(isAIScanning, isDriveScanning, hasSearchQuery);
    final emptyTitle = _getEmptyStateTitle(hasSearchQuery, dbCount, loadingTitle, isAIScanning);
    final emptyDesc = _getEmptyStateDesc(hasSearchQuery, dbCount, isAIScanning, isDriveScanning);

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildEmptyStateMainContent(theme, hasSearchQuery, dbCount, emptyTitle, emptyDesc, isAIScanning),
            if (hasSearchQuery) ...[const SizedBox(height: 24), _buildEmptyStateTips(theme)],
            if (!hasSearchQuery && dbCount > 0) ...[const SizedBox(height: 24), _buildEmptyStateStats(theme, dbCount)],
            if (!hasSearchQuery) ...[const SizedBox(height: 28), _buildEmptyStateSuggestions(theme)],
            if (!hasSearchQuery) _buildRecentFilesSection(theme),
          ],
        ),
      ),
    );
  }

  String? _getEmptyStateLoadingTitle(bool isAIScanning, bool isDriveScanning, bool hasSearchQuery) {
    if (isAIScanning) return tr('ai_analyzing');
    if (isDriveScanning) return tr('searching_cloud');
    return hasSearchQuery && _hybridController.isLocalSearching ? tr('ai_scanning_deeper') : null;
  }

  String _getEmptyStateTitle(bool hasSearchQuery, int dbCount, String? loadingTitle, bool isAIScanning) {
    if (hasSearchQuery) return loadingTitle ?? (_isSmartSearchActive && !isAIScanning ? tr('smart_search_no_results') : 'לא נמצאו תוצאות');
    return dbCount == 0 ? 'מתחילים!' : 'מה מחפשים?';
  }

  String _getEmptyStateDesc(bool hasSearchQuery, int dbCount, bool isAIScanning, bool isDriveScanning) {
    if (hasSearchQuery) return (isAIScanning || isDriveScanning) ? '' : tr('empty_state_desc_search');
    return dbCount == 0 ? tr('empty_state_desc_scanning') : tr('empty_state_desc_start');
  }

  Widget _buildEmptyStateMainContent(ThemeData theme, bool hasSearchQuery, int dbCount, String emptyTitle, String emptyDesc, bool isAIScanning) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildEmptyStateIcon(theme, hasSearchQuery, dbCount),
        const SizedBox(height: 28),
        _buildEmptyStateTitleRow(theme, emptyTitle, emptyDesc, isAIScanning, hasSearchQuery),
      ],
    );
  }

  Widget _buildEmptyStateIcon(ThemeData theme, bool hasSearchQuery, int dbCount) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.8, end: 1.0),
      duration: const Duration(milliseconds: 600),
      curve: Curves.elasticOut,
      builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
      child: Container(
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: hasSearchQuery
                ? [Colors.grey.shade800, Colors.grey.shade700]
                : [theme.colorScheme.primary.withValues(alpha: 0.2), theme.colorScheme.secondary.withValues(alpha: 0.2)],
          ),
          shape: BoxShape.circle,
          boxShadow: hasSearchQuery ? null : [BoxShadow(color: theme.colorScheme.primary.withValues(alpha: 0.3), blurRadius: 20, spreadRadius: 5)],
        ),
        child: Icon(
          hasSearchQuery ? Icons.search_off_rounded : (dbCount == 0 ? Icons.folder_open_rounded : Icons.search_rounded),
          size: 56,
          color: hasSearchQuery ? Colors.grey.shade400 : theme.colorScheme.primary,
        ),
      ),
    );
  }

  Widget _buildEmptyStateTitleRow(ThemeData theme, String emptyTitle, String emptyDesc, bool isAIScanning, bool hasSearchQuery) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (isAIScanning)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: theme.colorScheme.primary)),
              const SizedBox(width: 12),
              Text(emptyTitle, style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey.shade400)),
            ],
          )
        else
          Text(emptyTitle, style: theme.textTheme.headlineSmall?.copyWith(color: hasSearchQuery ? Colors.grey.shade400 : null, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
        const SizedBox(height: 12),
        if (emptyDesc.isNotEmpty) Text(emptyDesc, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500), textAlign: TextAlign.center),
      ],
    );
  }

  Widget _buildEmptyStateTips(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [Icon(Icons.lightbulb_outline, color: Colors.amber, size: 18), const SizedBox(width: 8), Text(tr('tips_title'), style: const TextStyle(fontWeight: FontWeight.w600))]),
          const SizedBox(height: 12),
          SearchTipRow(text: tr('tip_1')),
          SearchTipRow(text: tr('tip_2')),
          SearchTipRow(text: tr('tip_3')),
        ],
      ),
    );
  }

  Widget _buildEmptyStateStats(ThemeData theme, int dbCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(color: theme.colorScheme.primary.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined, color: theme.colorScheme.primary, size: 18),
          const SizedBox(width: 8),
          Text(tr('stats_ready').replaceFirst('\$dbCount', dbCount.toString()), style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  Widget _buildEmptyStateSuggestions(ThemeData theme) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(tr('suggestions_title'), style: TextStyle(color: Colors.grey.shade600, fontSize: 12, fontWeight: FontWeight.w500)),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [_buildSuggestionChip(tr('suggestion_invoice')), _buildSuggestionChip(tr('suggestion_id')), _buildSuggestionChip(tr('suggestion_contract')), _buildSuggestionChip('receipt')],
        ),
      ],
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
    final fileColor = getFileColor(recent.extension);
    
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
                getFileIcon(recent.extension),
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
                    formatRecentTime(recent.accessedAt),
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
  
  Widget _buildEmptyFavoritesState(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            FittedBox(
              fit: BoxFit.contain,
              child: Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.amber.withValues(alpha: isDark ? 0.25 : 0.15),
                      Colors.orange.withValues(alpha: isDark ? 0.25 : 0.15),
                    ],
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.star_outline_rounded,
                  size: 56,
                  color: Colors.amber.shade700,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'אין מועדפים עדיין',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'לחץ ארוך על קובץ והוסף למועדפים\nלגישה מהירה',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    final cleanQuery = getCleanQuery(_searchController.text);
    final folderName = getFolderName(file.path);
    final hasOcrMatch = cleanQuery.isNotEmpty && file.extractedText?.toLowerCase().contains(cleanQuery.toLowerCase()) == true;
    final isWhatsApp = file.path.toLowerCase().contains('whatsapp');
    final isFavorite = _favoritesService.isFavorite(file.path);
    final isSelected = _selectedFiles.contains(file.path);
    final fileTags = TagsService.instance.getFileTags(file.path);
    final fileColor = getFileColor(file.extension);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _buildResultItemDecoration(theme, isSelected, isFavorite, hasOcrMatch),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isSelectionMode ? () => _toggleFileSelection(file.path) : () => _openFile(file),
          onLongPress: _isSelectionMode ? null : () => _enterSelectionMode(file.path),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildResultItemMainRow(file, theme, cleanQuery, folderName, isWhatsApp, isFavorite, isSelected, fileColor, fileTags),
                if (hasOcrMatch && file.extractedText != null) ...[const SizedBox(height: 12), SearchOcrSnippet(text: file.extractedText!, query: cleanQuery)],
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _enterSelectionMode(String path) {
    HapticFeedback.mediumImpact();
    setState(() {
      _isSelectionMode = true;
      _selectedFiles.add(path);
    });
  }

  BoxDecoration _buildResultItemDecoration(ThemeData theme, bool isSelected, bool isFavorite, bool hasOcrMatch) {
    return BoxDecoration(
      color: isSelected ? theme.colorScheme.primary.withValues(alpha: 0.15) : theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: isSelected ? theme.colorScheme.primary : (isFavorite ? Colors.amber.withValues(alpha: 0.5) : (hasOcrMatch ? theme.colorScheme.secondary.withValues(alpha: 0.3) : Colors.transparent)),
        width: isSelected ? 2 : 1,
      ),
    );
  }

  Widget _buildResultItemMainRow(FileMetadata file, ThemeData theme, String cleanQuery, String folderName, bool isWhatsApp, bool isFavorite, bool isSelected, Color fileColor, List<CustomTag> fileTags) {
    return Row(
      children: [
        if (_isSelectionMode) ...[
          Checkbox(value: isSelected, onChanged: (_) => _toggleFileSelection(file.path), activeColor: theme.colorScheme.primary, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4))),
          const SizedBox(width: 8),
        ],
        SearchFileThumbnail(file: file, fileColor: fileColor, isWhatsApp: isWhatsApp),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    if (isFavorite) ...[const Icon(Icons.star, color: Colors.amber, size: 14), const SizedBox(width: 4)],
                    Expanded(
                      child: SearchHighlightedText(
                        text: file.name,
                        query: cleanQuery,
                        baseStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: theme.colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
                _buildContentPreviewSubtitle(file),
                const SizedBox(height: 6),
                SearchResultSourceTag(folderName: folderName, isWhatsApp: isWhatsApp, isCloud: file.isCloud),
                const SizedBox(height: 4),
                SearchResultMetaRow(file: file, showDebugScore: _showDebugScore),
                if (fileTags.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Wrap(spacing: 4, runSpacing: 4, children: fileTags.take(3).map((tag) => SearchTagChip(tag: tag)).toList()),
                ],
              ],
            ),
          ),
        ),
        IconButton(icon: Icon(Icons.more_vert, size: 20, color: theme.colorScheme.primary), onPressed: () => _showFileActionsSheet(file), tooltip: tr('more_options')),
      ],
    );
  }

  /// תצוגת מקדימה: משפטים ראשונים מתוך extractedText, או "מעבד תוכן..." אם עדיין לא עובד
  static const int _contentPreviewMaxLength = 120;

  Widget _buildContentPreviewSubtitle(FileMetadata file) {
    final subtitleStyle = TextStyle(
      fontSize: 12,
      color: Colors.grey.shade600,
      fontWeight: FontWeight.normal,
    );
    if (!file.isIndexed) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          'Processing content...',
          style: subtitleStyle,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }
    final text = file.extractedText?.trim();
    if (text == null || text.isEmpty) return const SizedBox.shrink();
    final normalized = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final preview = normalized.length <= _contentPreviewMaxLength
        ? normalized
        : '${normalized.substring(0, _contentPreviewMaxLength).trim()}...';
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        preview,
        style: subtitleStyle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}

/// דיאלוג בדיקת Regex — שדה טקסט לדוגמה + אינדיקציה בזמן אמת
class _RegexTestDialog extends StatefulWidget {
  const _RegexTestDialog({
    required this.pattern,
    required this.sampleController,
    required this.onClose,
  });

  final String pattern;
  final TextEditingController sampleController;
  final VoidCallback onClose;

  @override
  State<_RegexTestDialog> createState() => _RegexTestDialogState();
}

class _RegexTestDialogState extends State<_RegexTestDialog> {
  @override
  void initState() {
    super.initState();
    widget.sampleController.addListener(_onSampleChanged);
  }

  @override
  void dispose() {
    widget.sampleController.removeListener(_onSampleChanged);
    super.dispose();
  }

  void _onSampleChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final sample = widget.sampleController.text;
    final matches = RegexTester.test(widget.pattern, sample);
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Regex Test'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pattern:', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                widget.pattern,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
            const SizedBox(height: 16),
            Text('Sample Text:', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurface.withValues(alpha: 0.7))),
            const SizedBox(height: 4),
            TextField(
              controller: widget.sampleController,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'Paste OCR text here...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  matches ? Icons.check_circle : Icons.cancel,
                  size: 24,
                  color: matches ? Colors.green : Colors.red,
                ),
                const SizedBox(width: 8),
                Text(
                  matches ? 'Match' : 'No match',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: matches ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: widget.onClose, child: const Text('Close')),
      ],
    );
  }
}
