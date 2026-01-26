import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/file_metadata.dart';
import '../models/search_intent.dart';
import '../services/database_service.dart';
import '../services/log_service.dart';
import '../services/permission_service.dart';
import '../services/settings_service.dart';
import '../services/smart_search_filter.dart';
import '../services/smart_search_service.dart';
import 'settings_screen.dart';

/// פילטר מקומי נוסף (לא קיים ב-SearchFilter)
enum LocalFilter {
  all,
  images,
  pdfs,
  withText,  // קבצים עם טקסט מחולץ (OCR)
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
  
  LocalFilter _selectedFilter = LocalFilter.all;
  
  // Smart Search state
  bool _isSmartSearchActive = false;
  SearchIntent? _lastSearchIntent;
  Timer? _debounceTimer;
  
  // Stream לחיפוש ריאקטיבי
  Stream<List<FileMetadata>>? _searchStream;
  String _currentQuery = '';
  
  // טווח תאריכים לסינון
  DateTimeRange? _selectedDateRange;
  
  // חיפושים אחרונים
  static const String _recentSearchesKey = 'recent_searches';
  static const int _maxRecentSearches = 5;
  List<String> _recentSearches = [];
  bool _isSearchFocused = false;
  
  // חיפוש קולי
  final SpeechToText _speechToText = SpeechToText();
  bool _isListening = false;
  bool _speechEnabled = false;
  String _selectedLocale = 'he-IL'; // ברירת מחדל עברית

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

  /// מעדכן את ה-Stream לפי הפרמטרים הנוכחיים - Hybrid Flow
  void _updateSearchStream() {
    final query = _currentQuery;
    
    // אם יש שאילתה - נשתמש ב-Smart Search
    if (query.trim().length >= 2) {
      _performHybridSearch(query);
    } else {
      // שאילתה ריקה או קצרה - חיפוש רגיל
      _performSimpleSearch(query);
    }
  }
  
  /// חיפוש היברידי - כרגע משתמש בחיפוש רגיל, Smart Search יופעל רק בלחיצה על כפתור
  /// (כדי לא לשלוח המון בקשות יקרות ל-API בכל הקלדה)
  Future<void> _performHybridSearch(String query) async {
    // כרגע - חיפוש רגיל בלבד בהקלדה
    // Smart Search יופעל רק בלחיצה על כפתור ייעודי
    _performSimpleSearch(query);
  }
  
  /// מבצע חיפוש חכם עם Gemini API - נקרא רק בלחיצה על כפתור
  Future<void> _performSmartSearch(String query) async {
    if (query.trim().length < 2) {
      _performSimpleSearch(query);
      return;
    }
    
    appLog('SmartSearch: Starting for query: "$query"');
    
    // ניסיון לקבל SearchIntent מה-API
    SearchIntent? intent;
    try {
      intent = await _smartSearchService.parseSearchQuery(query);
    } catch (e) {
      appLog('SmartSearch: API call failed - $e');
    }
    
    if (intent != null && intent.hasContent) {
      // Smart Search הצליח - משתמשים בפילטר החכם
      appLog('SmartSearch: Using Smart Search with intent: $intent');
      
      // קבלת Stream של כל הקבצים ממסד הנתונים
      final baseStream = _databaseService.watchSearch(
        query: '', // לא מסננים לפי טקסט - הפילטר החכם יעשה את זה
        filter: SearchFilter.all,
      );
      
      setState(() {
        _isSmartSearchActive = true;
        _lastSearchIntent = intent;
        _searchStream = baseStream.map((files) {
          // מפעילים את הפילטר החכם
          var results = SmartSearchFilter.filterFiles(files, intent!);
          // מפעילים גם את הפילטר המקומי (WhatsApp, withText וכו')
          return _applyLocalFilter(results);
        });
      });
    } else {
      // Fallback לחיפוש רגיל
      appLog('SmartSearch: Falling back to simple search');
      _performSimpleSearch(query);
    }
  }
  
  /// חיפוש פשוט (Fallback) - מבוסס טקסט ופילטרים מקומיים
  void _performSimpleSearch(String query) {
    appLog('SimpleSearch: Starting for query: "$query"');
    
    // תאריך התחלה מהשאילתה או מטווח התאריכים שנבחר
    final queryStartDate = parseTimeQuery(query);
    final startDate = _selectedDateRange?.start ?? queryStartDate;
    final endDate = _selectedDateRange?.end;
    
    // המרת פילטר מקומי לפילטר של DatabaseService
    SearchFilter dbFilter = SearchFilter.all;
    if (_selectedFilter == LocalFilter.images) dbFilter = SearchFilter.images;
    if (_selectedFilter == LocalFilter.pdfs) dbFilter = SearchFilter.pdfs;
    if (_selectedFilter == LocalFilter.withText) dbFilter = SearchFilter.ocrOnly;
    
    setState(() {
      _isSmartSearchActive = false;
      _lastSearchIntent = null;
      _searchStream = _databaseService.watchSearch(
        query: query,
        filter: dbFilter,
        startDate: startDate,
        endDate: endDate,
      ).map((results) => _applyLocalFilter(results));
    });
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
              content: const Text('נדרשת הרשאת מיקרופון לחיפוש קולי'),
              backgroundColor: Colors.orange,
              behavior: SnackBarBehavior.floating,
              action: result == PermissionResult.permanentlyDenied
                  ? SnackBarAction(
                      label: 'הגדרות',
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
              content: Text('זיהוי קולי אינו זמין במכשיר זה'),
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
          _selectedLocale == 'he-IL' ? 'שפה: עברית' : 'Language: English',
        ),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// מחיל פילטר מקומי על התוצאות
  List<FileMetadata> _applyLocalFilter(List<FileMetadata> results) {
    // כרגע אין פילטרים מקומיים נוספים - הפילטרים מטופלים ב-DatabaseService
    return results;
  }

  /// משנה פילטר
  void _onFilterChanged(LocalFilter filter) {
    setState(() => _selectedFilter = filter);
    _currentQuery = _searchController.text;
    _updateSearchStream();
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
                Expanded(child: Text('הקובץ לא נמצא: ${file.name}')),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'הסר',
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
    if (result.type != ResultType.done && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('לא ניתן לפתוח את הקובץ: ${result.message}'),
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
      text: 'Shared from The Hunter: ${file.name}',
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
            content: Text('הקובץ כבר נמחק מהמכשיר'),
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
                Expanded(child: Text('הקובץ "${file.name}" נמחק בהצלחה')),
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
            content: Text('שגיאה במחיקת הקובץ: $e'),
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
            Text('מחיקת קובץ'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('האם אתה בטוח שברצונך למחוק את הקובץ?'),
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
              'פעולה זו לא ניתנת לביטול!',
              style: TextStyle(color: Colors.red.shade300, fontSize: 12),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('מחק'),
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
                    'פרטי קובץ',
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
                  _buildDetailRow('שם', file.name, Icons.insert_drive_file),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow('סוג', file.extension.toUpperCase(), Icons.category),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow('גודל', file.readableSize, Icons.data_usage),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow('תאריך שינוי', _formatDate(file.lastModified), Icons.calendar_today),
                  const Divider(height: 20, color: Colors.white12),
                  _buildDetailRow('נתיב', file.path, Icons.folder_open, isPath: true),
                  if (file.extractedText != null && file.extractedText!.isNotEmpty) ...[
                    const Divider(height: 20, color: Colors.white12),
                    _buildDetailRow(
                      'טקסט מחולץ', 
                      '${file.extractedText!.length} תווים',
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
                child: const Text('סגור'),
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
      builder: (context) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E3F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(20),
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
              title: 'פתח',
              subtitle: 'פתח עם אפליקציה מתאימה',
              color: theme.colorScheme.primary,
              onTap: () {
                Navigator.of(context).pop();
                _openFile(file);
              },
            ),
            const SizedBox(height: 8),
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
    );
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
              primary: theme.colorScheme.primary,
              onPrimary: Colors.white,
              surface: const Color(0xFF1E1E3F),
              onSurface: Colors.white,
            ),
            dialogBackgroundColor: const Color(0xFF0F0F23),
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
    
    return GestureDetector(
      // סגירת מקלדת בלחיצה מחוץ לשדה הטקסט
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        backgroundColor: const Color(0xFF0F0F23),
        body: SafeArea(
          child: Column(
            children: [
              // כותרת וחיפוש
              _buildSearchHeader(),
              
              // חיפושים אחרונים (כשהשדה בפוקוס וריק)
              if (showRecentSearches)
                _buildRecentSearches(),
              
              // בורר טווח תאריכים
              if (!showRecentSearches)
                _buildDateRangePicker(),
              
              // באנר חיפוש חכם (פרימיום)
              if (!showRecentSearches)
                _buildSmartAISearchBanner(),
              
              // צ'יפים לסינון מהיר
              _buildFilterChips(),
              
              // תוצאות או מצב ריק
              Expanded(
                child: _buildResults(),
              ),
            ],
          ),
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
                color: Colors.white70,
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
                  color: Colors.grey.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.close,
                  size: 12,
                  color: Colors.white54,
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
                    color: hasDateRange ? Colors.white : Colors.grey.shade400,
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
                      color: Colors.grey.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.close, size: 14, color: Colors.white70),
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
  
  /// בונה באנר חיפוש חכם
  Widget _buildSmartAISearchBanner() {
    final theme = Theme.of(context);
    final isPremium = _settingsService.isPremium;
    final hasQuery = _currentQuery.trim().length >= 2;
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: GestureDetector(
        onTap: () {
          if (!isPremium) {
            _showPremiumUpgradeMessage('חיפוש חכם');
          } else if (hasQuery) {
            // הפעלת חיפוש חכם עם ה-query הנוכחי
            _performSmartSearch(_currentQuery);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    ),
                    const SizedBox(width: 12),
                    const Text('מבצע חיפוש חכם...'),
                  ],
                ),
                duration: const Duration(seconds: 2),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            // אין query - הצג הודעה
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('הקלד לפחות 2 תווים כדי להפעיל חיפוש חכם'),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: isPremium
                ? LinearGradient(
                    colors: [
                      theme.colorScheme.primary.withValues(alpha: 0.3),
                      theme.colorScheme.secondary.withValues(alpha: 0.3),
                    ],
                  )
                : null,
            color: isPremium ? null : theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isPremium 
                  ? Colors.transparent 
                  : Colors.amber.withValues(alpha: 0.5),
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.purple, Colors.blue],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.auto_awesome, size: 16, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text(
                          'חיפוש חכם',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
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
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.green,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: const Text(
                              'פעיל',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      isPremium 
                          ? 'לחץ כדי לחפש בשפה טבעית עם AI'
                          : 'חפש בשפה טבעית עם בינה מלאכותית',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.grey.shade400,
                      ),
                    ),
                  ],
                ),
              ),
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
                  ],
                ),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              ),
              onChanged: _onSearchChanged,
            ),
          ),
        ],
      ),
    );
  }
  
  /// בונה צ'יפים לסינון - מודרני
  Widget _buildFilterChips() {
    final theme = Theme.of(context);
    
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          _buildModernFilterChip('הכל', LocalFilter.all, Icons.apps),
          const SizedBox(width: 10),
          _buildModernFilterChip('תמונות', LocalFilter.images, Icons.image),
          const SizedBox(width: 10),
          _buildModernFilterChip('PDF', LocalFilter.pdfs, Icons.picture_as_pdf),
          const SizedBox(width: 10),
          _buildModernFilterChip('עם טקסט', LocalFilter.withText, Icons.text_snippet),
        ],
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
                color: isSelected ? Colors.white : Colors.white70,
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
            // רשימת תוצאות
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: results.length,
                itemBuilder: (context, index) {
                  final file = results[index];
                  return _buildResultItem(file);
                },
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
    
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // אייקון
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary.withValues(alpha: 0.2),
                    theme.colorScheme.secondary.withValues(alpha: 0.2),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearchQuery ? Icons.search_off : (dbCount == 0 ? Icons.folder_off : Icons.search),
                size: 64,
                color: hasSearchQuery ? Colors.grey : theme.colorScheme.primary,
              ),
            ),
            const SizedBox(height: 24),
            
            // כותרת
            Text(
              hasSearchQuery 
                  ? 'לא נמצאו תוצאות' 
                  : (dbCount == 0 ? 'אין קבצים במסד' : 'מוכן לחיפוש'),
              style: theme.textTheme.headlineSmall?.copyWith(
                color: hasSearchQuery ? Colors.grey : null,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            
            // תיאור
            Text(
              hasSearchQuery
                  ? 'נסה לחפש משהו אחר או שנה את הפילטר'
                  : (dbCount == 0 
                      ? 'עבור לטאב סריקה ולחץ "סרוק הכל"' 
                      : 'חפש קבלות, צילומי מסך או מסמכים'),
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
            ),
            
            // מידע על מסד הנתונים
            if (!hasSearchQuery)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'קבצים במסד: $dbCount',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Colors.grey,
                  ),
                ),
              ),
            
            // דוגמאות חיפוש
            if (!hasSearchQuery) ...[
              const SizedBox(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildSuggestionChip('חשבונית'),
                  _buildSuggestionChip('שבוע'),
                  _buildSuggestionChip('receipt'),
                  _buildSuggestionChip('screenshot'),
                ],
              ),
            ],
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
    
    final fileColor = _getFileColor(file.extension);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasOcrMatch 
              ? theme.colorScheme.secondary.withValues(alpha: 0.3)
              : Colors.transparent,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _openFile(file),
          onLongPress: () => _showFileActionsSheet(file),
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // אייקון סוג קובץ
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: fileColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: _buildFileIcon(file.extension, isWhatsApp),
                      ),
                    ),
                    const SizedBox(width: 14),
                    
                    // תוכן
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // שם קובץ עם הדגשה
                          _buildHighlightedText(
                            file.name,
                            cleanQuery,
                            const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
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
                                      isWhatsApp ? Icons.chat_bubble : Icons.folder,
                                      size: 10,
                                      color: isWhatsApp ? Colors.green : Colors.grey.shade500,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      folderName,
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: isWhatsApp ? Colors.green : Colors.grey.shade500,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                file.readableSize,
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                              const Spacer(),
                              Text(
                                _formatDate(file.lastModified),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                              ),
                            ],
                          ),
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
