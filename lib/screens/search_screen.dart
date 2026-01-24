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
      // ignore: deprecated_member_use
      partialResults: true,
      // ignore: deprecated_member_use
      cancelOnError: true,
      // ignore: deprecated_member_use
      listenMode: ListenMode.search,
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
              onPressed: () async {
                await _databaseService.deleteFile(file.id);
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
    return Scaffold(
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

  /// בונה את כותרת החיפוש
  Widget _buildSearchHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // לוגו וכותרת
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.manage_search,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'The Hunter',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'חפש קבלות, צילומי מסך ומסמכים',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // שדה חיפוש
          TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            textDirection: _isHebrew(_searchController.text) 
                ? TextDirection.rtl 
                : TextDirection.ltr,
            decoration: InputDecoration(
              hintText: 'חפש... (נסה: "חשבונית שבוע", "receipt")',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // כפתור ניקוי
                  if (_searchController.text.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.clear),
                      onPressed: () {
                        _searchController.clear();
                        _currentQuery = '';
                        _updateSearchStream();
                      },
                    ),
                  // כפתור מיקרופון לחיפוש קולי
                  _buildMicrophoneButton(),
                ],
              ),
              filled: true,
              fillColor: Theme.of(context).colorScheme.surfaceContainerHighest,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(16),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  /// בונה צ'יפים לסינון
  Widget _buildFilterChips() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          _buildFilterChip('הכל', LocalFilter.all, Icons.folder),
          const SizedBox(width: 8),
          _buildFilterChip('תמונות', LocalFilter.images, Icons.image),
          const SizedBox(width: 8),
          _buildFilterChip('PDF', LocalFilter.pdfs, Icons.picture_as_pdf),
          const SizedBox(width: 8),
          _buildFilterChip('WhatsApp', LocalFilter.whatsapp, Icons.chat),
          const SizedBox(width: 8),
          _buildFilterChip('עם טקסט', LocalFilter.withText, Icons.text_snippet),
        ],
      ),
    );
  }

  /// בונה צ'יפ סינון בודד
  Widget _buildFilterChip(String label, LocalFilter filter, IconData icon) {
    final isSelected = _selectedFilter == filter;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: isSelected 
                ? Theme.of(context).colorScheme.onPrimary 
                : Theme.of(context).colorScheme.onSurface,
          ),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (_) => _onFilterChanged(filter),
      selectedColor: Theme.of(context).colorScheme.primary,
      checkmarkColor: Theme.of(context).colorScheme.onPrimary,
      labelStyle: TextStyle(
        color: isSelected 
            ? Theme.of(context).colorScheme.onPrimary 
            : Theme.of(context).colorScheme.onSurface,
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
          return const Center(child: CircularProgressIndicator());
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
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Text(
                    '${results.length} תוצאות',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                  const Spacer(),
                  if (_searchController.text.isNotEmpty)
                    Text(
                      'ממוין לפי תאריך',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                      ),
                    ),
                ],
              ),
            ),
            // רשימת תוצאות
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 8),
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

  /// בונה מצב ריק
  Widget _buildEmptyState() {
    final hasSearchQuery = _searchController.text.isNotEmpty;
    
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
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                hasSearchQuery ? Icons.search_off : Icons.manage_search,
                size: 80,
                color: hasSearchQuery 
                    ? Colors.grey.withValues(alpha: 0.6)
                    : Theme.of(context).colorScheme.primary.withValues(alpha: 0.6),
              ),
            ),
            const SizedBox(height: 24),
            
            // כותרת
            Text(
              hasSearchQuery 
                  ? 'לא נמצאו תוצאות' 
                  : 'The Hunter מוכן...',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
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
                  : 'חפש קבלות, צילומי מסך או מסמכים',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Colors.grey,
              ),
              textAlign: TextAlign.center,
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

  /// בונה צ'יפ הצעה לחיפוש
  Widget _buildSuggestionChip(String text) {
    return ActionChip(
      label: Text(text),
      avatar: const Icon(Icons.search, size: 16),
      onPressed: () {
        _searchController.text = text;
        _currentQuery = text;
        _updateSearchStream();
      },
    );
  }

  /// בונה פריט תוצאה
  Widget _buildResultItem(FileMetadata file) {
    final rawQuery = _searchController.text;
    final cleanQuery = _getCleanQuery(rawQuery);
    final folderName = _getFolderName(file.path);
    
    // בדיקה אם יש התאמה בטקסט מחולץ
    final hasOcrMatch = cleanQuery.isNotEmpty && 
        file.extractedText?.toLowerCase().contains(cleanQuery.toLowerCase()) == true;
    
    // בדיקה אם זה קובץ מ-WhatsApp
    final isWhatsApp = file.path.toLowerCase().contains('whatsapp');

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: InkWell(
        onTap: () => _openFile(file),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // אייקון סוג קובץ
              _buildFileTypeIcon(file.extension, isWhatsApp),
              const SizedBox(width: 12),
              
              // תוכן
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // שם קובץ עם הדגשה
                    _buildHighlightedText(
                      file.name,
                      cleanQuery,
                      Theme.of(context).textTheme.titleSmall!,
                    ),
                    const SizedBox(height: 4),
                    
                    // מידע על הקובץ
                    Row(
                      children: [
                        Icon(
                          isWhatsApp ? Icons.chat : Icons.folder_outlined,
                          size: 14,
                          color: isWhatsApp ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          folderName,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: isWhatsApp ? Colors.green : Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          file.readableSize,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          _formatDate(file.lastModified),
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                    
                    // קטע טקסט מחולץ אם יש התאמה (עם תמיכה ב-RTL)
                    if (hasOcrMatch && file.extractedText != null) ...[
                      const SizedBox(height: 8),
                      _buildOcrSnippet(file.extractedText!, cleanQuery),
                    ],
                  ],
                ),
              ),
              
              // כפתורי פעולה
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // כפתור שיתוף
                  IconButton(
                    icon: Icon(
                      Icons.share,
                      size: 20,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    onPressed: () => _shareFile(file),
                    tooltip: 'שתף',
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                  // כפתור פתיחה
                  const Icon(
                    Icons.open_in_new,
                    size: 18,
                    color: Colors.grey,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
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
        case 'pdf':
          icon = Icons.picture_as_pdf;
          color = Colors.red;
          break;
        case 'jpg':
        case 'jpeg':
        case 'png':
        case 'gif':
        case 'webp':
        case 'bmp':
          icon = Icons.image;
          color = Colors.purple;
          break;
        case 'doc':
        case 'docx':
          icon = Icons.description;
          color = Colors.blue;
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
