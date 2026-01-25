import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import '../models/file_metadata.dart';
import '../services/database_service.dart';
import '../services/permission_service.dart';

/// פילטר מקומי נוסף (לא קיים ב-SearchFilter)
enum LocalFilter {
  all,
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
  final _databaseService = DatabaseService.instance;
  final _permissionService = PermissionService.instance;
  
  LocalFilter _selectedFilter = LocalFilter.all;
  Timer? _debounceTimer;
  
  // Stream לחיפוש ריאקטיבי
  Stream<List<FileMetadata>>? _searchStream;
  String _currentQuery = '';
  
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
    _debounceTimer?.cancel();
    _speechToText.stop();
    super.dispose();
  }

  /// מעדכן את ה-Stream לפי הפרמטרים הנוכחיים
  void _updateSearchStream() {
    final query = _currentQuery;
    final startDate = parseTimeQuery(query);
    
    // המרת פילטר מקומי לפילטר של DatabaseService
    SearchFilter dbFilter = SearchFilter.all;
    if (_selectedFilter == LocalFilter.images) dbFilter = SearchFilter.images;
    if (_selectedFilter == LocalFilter.pdfs) dbFilter = SearchFilter.pdfs;
    if (_selectedFilter == LocalFilter.withText) dbFilter = SearchFilter.ocrOnly;
    
    setState(() {
      _searchStream = _databaseService.watchSearch(
        query: query,
        filter: dbFilter,
        startDate: startDate,
      ).map((results) => _applyLocalFilter(results));
    });
  }

  /// מבצע חיפוש עם debounce
  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      _currentQuery = query;
      _updateSearchStream();
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
    if (_selectedFilter == LocalFilter.whatsapp) {
      return results.where((f) => 
        f.path.toLowerCase().contains('whatsapp')
      ).toList();
    }
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      body: SafeArea(
        child: Column(
          children: [
            // כותרת וחיפוש
            _buildSearchHeader(),
            
            // צ'יפים לסינון מהיר
            _buildFilterChips(),
            
            // תוצאות או מצב ריק
            Expanded(
              child: _buildResults(),
            ),
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
          _buildModernFilterChip('WhatsApp', LocalFilter.whatsapp, Icons.chat_bubble),
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
    return GestureDetector(
      onLongPress: _toggleLocale, // לחיצה ארוכה להחלפת שפה
      child: IconButton(
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
                  color: Theme.of(context).colorScheme.primary,
                ),
        ),
        onPressed: _isListening ? _stopListening : _startListening,
        tooltip: _isListening
            ? 'הפסק הקלטה'
            : 'חיפוש קולי (לחיצה ארוכה להחלפת שפה)',
        style: IconButton.styleFrom(
          backgroundColor: _isListening
              ? Colors.red.withValues(alpha: 0.1)
              : null,
        ),
      ),
    );
  }

  /// בונה את אזור התוצאות
  Widget _buildResults() {
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
                    
                    // כפתור שיתוף
                    IconButton(
                      icon: Icon(
                        Icons.share_rounded,
                        size: 20,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () => _shareFile(file),
                      tooltip: 'שתף',
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
