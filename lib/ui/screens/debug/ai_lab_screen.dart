import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../models/file_metadata.dart';
import '../../../models/search_synonym.dart';
import '../../../services/app_check_http_helper.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/ocr_service.dart';
import '../../../services/user_roles_service.dart';

/// בסיס כתובת הבקאנד — AI Lab
const String _kBackendBase = 'https://the-hunter-105628026575.me-west1.run.app';

/// מסך דיבאג — Pipeline, Local DB, Dictionary. מוגבל למשתמש Admin.
class AiLabScreen extends StatefulWidget {
  const AiLabScreen({super.key});

  @override
  State<AiLabScreen> createState() => _AiLabScreenState();
}

class _AiLabScreenState extends State<AiLabScreen> {
  // Admin — רק לתצוגת Badge ב-Stage 2 (המסך תמיד מוצג)
  bool _isAdmin = false;

  // Pipeline: שלב 1 — OCR (גודל קובץ לשקלול צפיפות: תווים/בייטים)
  String _ocrFilePath = '';
  int _ocrFileSizeBytes = 0;
  String _ocrExtractedText = '';
  /// סף מינימלי לצפיפות (אחוז): (extractedText.length / fileSizeBytes) * 100. נשמר בין rebuilds.
  double _garbageThreshold = 0.3;
  bool _ocrFailedByThreshold = false;

  // Pipeline: שלב 1 — תצוגת טקסט OCR (מקבל עדכון אחרי חילוץ)
  final TextEditingController _ocrDisplayController = TextEditingController();

  // Pipeline: שלב 2 — Server AI
  final TextEditingController _serverJsonController = TextEditingController();
  String _customPrompt = '';

  // Pipeline: שלב 3 — Save to DB
  String _saveStatus = ''; // Success / Error
  bool _saveSuccess = false;

  // Local DB
  List<FileMetadata> _fileList = [];
  int _fileTotalCount = 0;
  int _page = 0;
  static const int _pageSize = 20;

  // Dictionary
  DateTime? _lastSyncTime;
  int _synonymsCount = 0;
  List<SearchSynonym> _synonymsPreview = [];
  final TextEditingController _dictionarySearchController = TextEditingController();
  Timer? _dictionarySearchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 300);

  // לוג קונסול בתחתית המסך
  final List<String> _labLogs = [];
  static const int _maxLabLogs = 200;

  @override
  void initState() {
    super.initState();
    _checkAdmin();
    _loadFilePage();
    _loadSynonymsStats();
    _dictionarySearchController.addListener(_onDictionarySearchChanged);
  }

  void _onDictionarySearchChanged() {
    _dictionarySearchDebounce?.cancel();
    _dictionarySearchDebounce = Timer(_searchDebounceDuration, () {
      if (!mounted) return;
      _runSynonymsQuery(_dictionarySearchController.text.trim());
    });
  }

  @override
  void dispose() {
    _dictionarySearchController.removeListener(_onDictionarySearchChanged);
    _dictionarySearchDebounce?.cancel();
    _ocrDisplayController.dispose();
    _serverJsonController.dispose();
    _dictionarySearchController.dispose();
    super.dispose();
  }

  void _labLog(String message) {
    final line = '${DateTime.now().toString().substring(11, 19)} $message';
    setState(() {
      _labLogs.add(line);
      if (_labLogs.length > _maxLabLogs) _labLogs.removeAt(0);
    });
  }

  Future<void> _checkAdmin() async {
    final user = AuthService.instance.currentUser;
    if (user == null) {
    setState(() => _isAdmin = false);
      return;
    }
    // UID ספציפי או תפקיד Admin
    const allowedUids = <String>{}; // הוסף UID לדיבאג מקומי אם צריך
    final byUid = allowedUids.contains(user.uid);
    final byRole = await UserRolesService.instance.hasRole('Admin');
    setState(() => _isAdmin = byUid || byRole);
  }

  /// צפיפות טקסט לפי גודל קובץ — (extractedText.length / fileSizeInBytes) * 100 (כמו FileProcessingService)
  static double _textDensityScore(int textLength, int fileSizeBytes) {
    if (fileSizeBytes <= 0) return 0;
    return (textLength / fileSizeBytes) * 100;
  }

  Future<void> _pickAndRunOcr() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) {
        _labLog('OCR: no file selected');
        return;
      }
      final file = result.files.single;
      final path = file.path;
      if (path == null || path.isEmpty) {
        _labLog('OCR: path empty');
        return;
      }
      final fileSizeBytes = file.size;
      final sizeBytes = fileSizeBytes > 0 ? fileSizeBytes : 1;
      if (!OCRService.isSupportedImage(path.split('.').last)) {
        _labLog('OCR: unsupported image type');
        setState(() {
          _ocrFilePath = path;
          _ocrFileSizeBytes = fileSizeBytes;
          _ocrExtractedText = '';
          _ocrFailedByThreshold = true;
        });
        return;
      }
      _labLog('OCR: processing $path (${sizeBytes}B)');
      final text = await OCRService.instance.extractText(path);
      final density = _textDensityScore(text.length, sizeBytes);
      final fail = text.isEmpty || density < _garbageThreshold;
      setState(() {
        _ocrFilePath = path;
        _ocrFileSizeBytes = fileSizeBytes;
        _ocrExtractedText = text;
        _ocrFailedByThreshold = fail;
        _ocrDisplayController.text = text;
      });
      _labLog('OCR: done density=${density.toStringAsFixed(2)}% needed=>$_garbageThreshold% fail=$fail');
    } catch (e) {
      _labLog('OCR error: $e');
      setState(() {
        _ocrFileSizeBytes = 0;
        _ocrExtractedText = '';
        _ocrFailedByThreshold = true;
        _ocrDisplayController.text = '';
      });
    }
  }

  Future<void> _sendToServer() async {
    final text = _ocrExtractedText.isEmpty
        ? _serverJsonController.text
        : _ocrExtractedText;
    if (text.isEmpty) {
      _labLog('Send: no text');
      return;
    }
    setState(() {
      _serverJsonController.text = '...';
      _saveStatus = '';
    });
    try {
      final uri = Uri.parse('$_kBackendBase/api/analyze-debug');
      final body = jsonEncode({
        'text': text,
        'customPrompt': _customPrompt.isEmpty ? null : _customPrompt,
      });
      final headers = await AppCheckHttpHelper.getBackendHeaders();
      headers['Content-Type'] = 'application/json';
      _labLog('POST $uri');
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
      _labLog('analyze-debug ${response.statusCode}');
      if (response.statusCode != 200) {
        setState(() {
          _serverJsonController.text = 'Error: ${response.statusCode}\n${response.body}';
          _saveStatus = 'Error';
          _saveSuccess = false;
        });
        _labLog('Error: ${response.body}');
        return;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() {
        _serverJsonController.text = pretty;
        _saveStatus = '';
      });
      _labLog('OK: ${decoded['category'] ?? '?'}');
    } catch (e) {
      _labLog('Send error: $e');
      setState(() {
        _serverJsonController.text = 'Exception: $e';
        _saveStatus = 'Error';
        _saveSuccess = false;
      });
    }
  }

  Future<void> _saveToServerDb() async {
    String raw = _serverJsonController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _saveStatus = 'Error: no JSON';
        _saveSuccess = false;
      });
      _labLog('Save: no JSON');
      return;
    }
    // הסרת markdown אם יש
    raw = raw
        .replaceFirst(RegExp(r'^```\w*\n?'), '')
        .replaceFirst(RegExp(r'\n?```\s*$'), '')
        .trim();
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final uri = Uri.parse('$_kBackendBase/api/analyze-debug/save');
      final headers = await AppCheckHttpHelper.getBackendHeaders();
      headers['Content-Type'] = 'application/json';
      _labLog('POST $uri');
      final response = await http
          .post(uri, headers: headers, body: jsonEncode(decoded))
          .timeout(const Duration(seconds: 10));
      _labLog('analyze-debug/save ${response.statusCode}');
      setState(() {
        _saveSuccess = response.statusCode == 200;
        _saveStatus = response.statusCode == 200 ? 'Success' : 'Error: ${response.statusCode}';
      });
      if (response.statusCode != 200) _labLog('Save error: ${response.body}');
    } catch (e) {
      _labLog('Save error: $e');
      setState(() {
        _saveSuccess = false;
        _saveStatus = 'Error: $e';
      });
    }
  }

  void _loadFilePage() {
    try {
      final isar = DatabaseService.instance.isar;
      final q = isar.fileMetadatas.buildQuery<FileMetadata>();
      final all = q.findAll();
      q.close();
      final total = all.length;
      final start = (_page * _pageSize).clamp(0, total);
      final end = (start + _pageSize).clamp(0, total);
      setState(() {
        _fileTotalCount = total;
        _fileList = total == 0 ? [] : all.sublist(start, end);
      });
    } catch (e) {
      _labLog('DB load error: $e');
    }
  }

  void _deleteFile(FileMetadata file) {
    try {
      DatabaseService.instance.deleteFile(file.id);
      _labLog('Deleted file id=${file.id}');
      _loadFilePage();
    } catch (e) {
      _labLog('Delete error: $e');
    }
  }

  void _loadSynonymsStats() {
    _runSynonymsQuery(_dictionarySearchController.text.trim());
  }

  /// מריץ שאילתת synonyms עם סינון אופציונלי (עם debounce מהשדה)
  void _runSynonymsQuery(String query) {
    try {
      final isar = DatabaseService.instance.isar;
      final q = isar.searchSynonyms.buildQuery<SearchSynonym>();
      final all = q.findAll();
      q.close();
      final List<SearchSynonym> list = query.isEmpty
          ? all
          : all
              .where((s) =>
                  s.term.toLowerCase().contains(query.toLowerCase()))
              .toList();
      setState(() {
        _synonymsCount = list.length;
        _synonymsPreview = list.take(50).toList();
      });
    } catch (e) {
      _labLog('Synonyms query error: $e');
    }
  }

  Future<void> _forceSyncFromCloud() async {
    _labLog('Force sync...');
    try {
      await KnowledgeBaseService.instance.syncDictionaryWithServer();
      setState(() {
        _lastSyncTime = DateTime.now();
      });
      _loadSynonymsStats();
      _labLog('Force sync done');
    } catch (e) {
      _labLog('Force sync error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        appBar: AppBar(
          backgroundColor: Colors.grey[850],
          title: const Text('AI Lab Debugger', style: TextStyle(color: Colors.white)),
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.blueAccent,
            tabs: const [
              Tab(text: 'Pipeline'),
              Tab(text: 'Local DB'),
              Tab(text: 'Dictionary'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: SafeArea(
                child: TabBarView(
                  children: [
                    _buildPipelineTab(),
                    _buildLocalDbTab(),
                    _buildDictionaryTab(),
                  ],
                ),
              ),
            ),
            _buildLogConsole(),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStage(
          stageIndex: 1,
          title: 'Local OCR',
          onSettings: () => _showOcrSettings(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: _pickAndRunOcr,
                icon: const Icon(Icons.folder_open, size: 20),
                label: const Text('Pick image & run OCR'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white70,
                  side: const BorderSide(color: Colors.white24),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _ocrFilePath.isEmpty ? 'No file' : _ocrFilePath,
                style: const TextStyle(fontSize: 12, color: Colors.white54),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (_ocrFileSizeBytes > 0 || _ocrExtractedText.isNotEmpty) ...[
                const SizedBox(height: 8),
                Builder(
                  builder: (context) {
                    final density = _textDensityScore(
                      _ocrExtractedText.length,
                      _ocrFileSizeBytes > 0 ? _ocrFileSizeBytes : 1,
                    );
                    final pass = density >= _garbageThreshold;
                    return Text(
                      'Score: ${density.toStringAsFixed(2)}% (Needed: > ${_garbageThreshold.toStringAsFixed(1)}%)',
                      style: TextStyle(
                        fontSize: 13,
                        color: pass ? Colors.greenAccent : Colors.redAccent,
                        fontWeight: FontWeight.w500,
                      ),
                    );
                  },
                ),
              ],
              const SizedBox(height: 8),
              Builder(
                builder: (context) {
                  final pass = !_ocrFailedByThreshold;
                  return Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: pass
                          ? Colors.green.withValues(alpha: 0.15)
                          : Colors.red.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: pass ? Colors.green : Colors.red,
                        width: 1.5,
                      ),
                    ),
                    child: TextField(
                      readOnly: true,
                      maxLines: 6,
                      controller: _ocrDisplayController,
                      style: const TextStyle(color: Colors.white70, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Extracted text…',
                        border: InputBorder.none,
                        isDense: true,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStage(
          stageIndex: 2,
          title: 'Server AI (Gemini)',
          onSettings: () => _showCustomPromptSettings(context),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Admin Badge — האם Custom Prompts פעילים
              Row(
                children: [
                  Icon(
                    _isAdmin ? Icons.shield : Icons.shield_outlined,
                    size: 20,
                    color: _isAdmin ? Colors.green : Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _isAdmin
                        ? 'Admin Access: Granted (Custom Prompts Active)'
                        : 'Standard User (Custom Prompts Ignored)',
                    style: TextStyle(
                      fontSize: 12,
                      color: _isAdmin ? Colors.greenAccent : Colors.white54,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SizedBox(
                height: 140,
                child: TextField(
                  controller: _serverJsonController,
                  readOnly: false,
                  maxLines: null,
                  expands: true,
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'JSON response (editable — fix before Save to DB)…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _sendToServer,
                icon: const Icon(Icons.send, size: 20),
                label: const Text('Send to Server'),
                style: FilledButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildStage(
          stageIndex: 3,
          title: 'Server Database',
          onSettings: null,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _saveToServerDb,
                    icon: const Icon(Icons.save, size: 20),
                    label: const Text('Save to DB'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.green.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_saveStatus.isNotEmpty)
                    Icon(
                      _saveSuccess ? Icons.check_circle : Icons.error,
                      color: _saveSuccess ? Colors.green : Colors.red,
                      size: 24,
                    ),
                  if (_saveStatus.isNotEmpty)
                    Text(
                      _saveStatus,
                      style: TextStyle(
                        color: _saveSuccess ? Colors.green : Colors.red,
                        fontSize: 14,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStage({
    required int stageIndex,
    required String title,
    required VoidCallback? onSettings,
    required Widget child,
  }) {
    final outlineColors = [
      Colors.blueAccent,
      Colors.amberAccent,
      Colors.greenAccent,
    ];
    final color = outlineColors[(stageIndex - 1) % outlineColors.length];
    return Card(
      color: const Color(0xFF161B22),
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: color.withValues(alpha: 0.6), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$stageIndex',
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
                if (onSettings != null)
                  IconButton(
                    icon: const Icon(Icons.settings, color: Colors.white54),
                    onPressed: onSettings,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }

  void _showOcrSettings(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) {
        double value = _garbageThreshold;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF161B22),
              title: const Text('Local OCR', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Needed: > ${value.toStringAsFixed(1)}% (Score = textLength/fileSizeBytes × 100)',
                    style: const TextStyle(color: Colors.white70),
                  ),
                  Slider(
                    value: value.clamp(0.0, 10.0),
                    min: 0,
                    max: 10,
                    divisions: 100,
                    onChanged: (v) {
                      setDialogState(() => value = v);
                    },
                  ),
                  const Text(
                    'If density score < needed, stage is marked fail (red).',
                    style: TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    setState(() => _garbageThreshold = value);
                    Navigator.pop(ctx);
                  },
                  child: const Text('OK'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showCustomPromptSettings(BuildContext context) {
    final controller = TextEditingController(text: _customPrompt);
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Custom System Prompt', style: TextStyle(color: Colors.white)),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            maxLines: 12,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Override server prompt for this request…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              setState(() => _customPrompt = controller.text);
              Navigator.pop(ctx);
            },
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildLocalDbTab() {
    final totalPages = _fileTotalCount == 0 ? 1 : (_fileTotalCount / _pageSize).ceil();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'FileMetadata · ${_fileTotalCount} total · page ${_page + 1} of $totalPages',
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            IconButton(
              onPressed: _page > 0
                  ? () {
                      setState(() {
                        _page--;
                        _loadFilePage();
                      });
                    }
                  : null,
              icon: const Icon(Icons.chevron_left, color: Colors.white54),
            ),
            IconButton(
              onPressed: _page < totalPages - 1
                  ? () {
                      setState(() {
                        _page++;
                        _loadFilePage();
                      });
                    }
                  : null,
              icon: const Icon(Icons.chevron_right, color: Colors.white54),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ..._fileList.map((f) {
          final tagCount = f.tags?.length ?? 0;
          return Card(
            color: const Color(0xFF161B22),
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              title: Text(
                f.name,
                style: const TextStyle(color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                'ID: ${f.id} · ${f.addedAt.toIso8601String().substring(0, 10)} · Tags: $tagCount',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () => _deleteFile(f),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildDictionaryTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          color: const Color(0xFF161B22),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Last Sync: ${_lastSyncTime?.toIso8601String() ?? '—'}',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 4),
                Text(
                  'Total Synonyms: $_synonymsCount',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _forceSyncFromCloud,
                  icon: const Icon(Icons.cloud_download, size: 20),
                  label: const Text('Force Sync from Cloud'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.blue.shade700,
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _dictionarySearchController,
          decoration: InputDecoration(
            hintText: 'Search local dictionary (term contains…)',
            prefixIcon: const Icon(Icons.search, color: Colors.white54),
            border: const OutlineInputBorder(),
            filled: true,
            fillColor: const Color(0xFF0D1117),
          ),
          style: const TextStyle(color: Colors.white70),
        ),
        const SizedBox(height: 12),
        Text(
          _dictionarySearchController.text.trim().isEmpty
              ? 'First 50 Synonyms (preview)'
              : 'Matches (first 50)',
          style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        ..._synonymsPreview.map((s) {
          return Card(
            color: const Color(0xFF161B22),
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              dense: true,
              title: Text(
                s.term,
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
              subtitle: Text(
                '${s.category} · ${s.expansions.take(3).join(', ')}${s.expansions.length > 3 ? '…' : ''}',
                style: const TextStyle(color: Colors.white54, fontSize: 12),
              ),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildLogConsole() {
    return Container(
      height: 120,
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Log',
            style: TextStyle(
              color: Colors.white54,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: _labLogs.length,
              itemBuilder: (_, i) {
                final line = _labLogs[_labLogs.length - 1 - i];
                return Text(
                  line,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 11,
                    fontFamily: 'monospace',
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
