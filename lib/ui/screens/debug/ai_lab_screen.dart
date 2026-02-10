import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../models/search_synonym.dart';
import '../../../services/app_check_http_helper.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/ocr_service.dart';
import '../../../services/user_roles_service.dart';

/// בסיס כתובת הבקאנד — AI Lab (חשוף ל־UI לצורכי Deep Network Tracing)
const String _kBackendBase = 'https://the-hunter-105628026575.me-west1.run.app';

/// כתובת הבסיס הנוכחית — לתצוגה ובדיקת חיבור אמיתי
String get currentBaseUrl => _kBackendBase;

/// מסך דיבאג — Pipeline, Dictionary. מוגבל למשתמש Admin.
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
  String _sendStatus = ''; // תוצאת שלב 2 (Send to Server) — Success / Error: ...
  bool _sendSuccess = false;

  // Pipeline: שלב 3 — Save to DB
  String _saveStatus = ''; // Success / Error
  bool _saveSuccess = false;

  bool _sendingInProgress = false;
  bool _savingInProgress = false;
  bool _migrateUsersInProgress = false;

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

  /// Send to Server — קורא ל-analyze-debug, מציג את ה-JSON הגולמי בתיבה לעריכה ואז Save to DB.
  Future<void> _sendToServer() async {
    final text = _ocrExtractedText.isEmpty
        ? _serverJsonController.text.trim()
        : _ocrExtractedText;
    if (text.isEmpty) {
      _labLog('Send: no text');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Enter text or pick an image for OCR first'),
            backgroundColor: Colors.amber,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    setState(() {
      _serverJsonController.text = '...';
      _sendStatus = '';
      _sendSuccess = false;
      _saveStatus = '';
      _saveSuccess = false;
      _sendingInProgress = true;
    });

    final uri = Uri.parse('$_kBackendBase/api/analyze-debug');
    try {
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
      if (!mounted) return;
      if (response.statusCode != 200) {
        final errMsg = response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body;
        setState(() {
          _serverJsonController.text = 'Error: ${response.statusCode}\n${response.body}';
          _sendStatus = 'Error: $errMsg';
          _sendSuccess = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Send to Server failed: ${response.statusCode} $errMsg'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      } else {
        final rawBody = response.body;
        try {
          final decoded = jsonDecode(rawBody) as Map<String, dynamic>;
          final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
          setState(() {
            _serverJsonController.text = pretty;
            _sendStatus = 'Success';
            _sendSuccess = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('JSON loaded. Edit if needed, then tap Save to DB.'),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
            ),
          );
        } catch (e) {
          setState(() {
            _serverJsonController.text = rawBody.isEmpty ? '(empty response)' : rawBody;
            _sendStatus = 'Success (raw)';
            _sendSuccess = true;
          });
        }
      }
    } catch (e, st) {
      _labLog('Send error: $e');
      if (mounted) {
        final errMsg = e.toString();
        setState(() {
          _serverJsonController.text = 'Exception: $errMsg';
          _sendStatus = 'Error: $errMsg';
          _sendSuccess = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      debugPrint('_sendToServer exception: $e\n$st');
    } finally {
      if (mounted) setState(() => _sendingInProgress = false);
    }
  }

  /// Save to DB — שומר ל-Firestore collection smart_categories (document ID = category).
  Future<void> _saveToServerDb() async {
    String raw = _serverJsonController.text.trim();
    if (raw.isEmpty) {
      setState(() {
        _saveStatus = 'Error: no JSON';
        _saveSuccess = false;
      });
      _labLog('Save: no JSON');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No JSON to save. Use Send to Server first.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }
    raw = raw
        .replaceFirst(RegExp(r'^```\w*\n?'), '')
        .replaceFirst(RegExp(r'\n?```\s*$'), '')
        .trim();

    // ולידציה ופרסור — זורק אם JSON לא תקין
    final dynamic parsedData;
    try {
      parsedData = jsonDecode(raw);
    } catch (e) {
      _labLog('Save: invalid JSON — $e');
      if (mounted) {
        setState(() {
          _saveStatus = 'Error: invalid JSON';
          _saveSuccess = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Invalid JSON: $e'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      return;
    }

    if (parsedData is! Map<String, dynamic>) {
      _labLog('Save: body must be a JSON object');
      if (mounted) {
        setState(() {
          _saveStatus = 'Error: not an object';
          _saveSuccess = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('JSON must be an object with "category"'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final decoded = parsedData;
    final category = decoded['category']?.toString().trim() ?? '';
    if (category.isEmpty) {
      if (mounted) {
        setState(() {
          _saveStatus = 'Error: missing category';
          _saveSuccess = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('JSON must contain a "category" field'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _savingInProgress = true);
    final uri = Uri.parse('$_kBackendBase/api/smart-categories/save-manual');
    try {
      // כותרת חובה — מונע מהשרת לפרש body כמחרוזת
      final headers = await AppCheckHttpHelper.getBackendHeaders(
        existing: {'Content-Type': 'application/json'},
      );
      // שליחה כאובייקט מקודד (לא מחרוזת גולמית) כדי שה־model binder יקבל Object
      final body = jsonEncode(decoded);
      _labLog('POST $uri');
      final response = await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 10));
      _labLog('save-manual ${response.statusCode}');
      if (!mounted) return;
      final success = response.statusCode == 200;
      setState(() {
        _saveSuccess = success;
        _saveStatus = success ? 'Success' : 'Error: ${response.statusCode}';
      });
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Category '$category' updated/created!"),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final errBody = response.body.isEmpty ? 'no body' : (response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save to DB failed: ${response.statusCode} $errBody'),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
    } catch (e, st) {
      _labLog('Save error: $e');
      if (mounted) {
        final errMsg = e.toString();
        setState(() {
          _saveSuccess = false;
          _saveStatus = 'Error: $errMsg';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errMsg),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 6),
          ),
        );
      }
      debugPrint('_saveToServerDb exception: $e\n$st');
    } finally {
      if (mounted) setState(() => _savingInProgress = false);
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
        _synonymsPreview = list;
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
      length: 2,
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
              Tab(text: 'Dictionary'),
              Tab(text: 'Pipeline'),
            ],
          ),
        ),
        body: Column(
          children: [
            Expanded(
              flex: 2,
              child: SafeArea(
                child: TabBarView(
                  children: [
                    _buildDictionaryTab(),
                    _buildPipelineTab(),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: _buildLogConsole(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPipelineTab() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Deep Network Tracing — הצגת כתובת היעד
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.blueGrey.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.blueGrey),
          ),
          child: Row(
            children: [
              const Icon(Icons.dns, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Target Server: $currentBaseUrl',
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white70,
                    fontFamily: 'monospace',
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
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
                      style: const TextStyle(color: Colors.black87, fontSize: 13),
                      decoration: const InputDecoration(
                        hintText: 'Extracted text…',
                        border: InputBorder.none,
                        isDense: true,
                        filled: true,
                        fillColor: Color(0xFFE8E8E8),
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
                    color: Colors.black87,
                    fontSize: 12,
                    fontFamily: 'monospace',
                  ),
                  decoration: const InputDecoration(
                    hintText: 'JSON response (editable — fix before Save to DB)…',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.all(8),
                    filled: true,
                    fillColor: Color(0xFFE8E8E8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _sendingInProgress ? null : _sendToServer,
                    icon: _sendingInProgress
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.send, size: 20),
                    label: Text(_sendingInProgress ? 'Sending...' : 'Send to Server'),
                    style: FilledButton.styleFrom(
                      backgroundColor: Colors.blue.shade700,
                      foregroundColor: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 16),
                  if (_sendStatus.isNotEmpty)
                    Icon(
                      _sendSuccess ? Icons.check_circle : Icons.error,
                      color: _sendSuccess ? Colors.green : Colors.red,
                      size: 24,
                    ),
                  if (_sendStatus.isNotEmpty)
                    Flexible(
                      child: Text(
                        _sendStatus,
                        style: TextStyle(
                          color: _sendSuccess ? Colors.green : Colors.red,
                          fontSize: 14,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
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
              Text(
                'שומר ב־DB של השרת (LearnedTerms) — לא ב־DB המקומי של הקבצים.',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade400),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton.icon(
                    onPressed: _savingInProgress ? null : _saveToServerDb,
                    icon: _savingInProgress
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save, size: 20),
                    label: Text(_savingInProgress ? 'Saving...' : 'Save to DB'),
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
        const SizedBox(height: 16),
        // מיגרציה חד-פעמית: הוספת שדה id לכל מסמך users
        Card(
          color: const Color(0xFF161B22),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orangeAccent.withValues(alpha: 0.5)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Users migration',
                  style: TextStyle(color: Colors.orangeAccent, fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  'מוסיף שדה id (תואם Document ID) לכל מסמך ב-users שחסר.',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade400),
                ),
                const SizedBox(height: 8),
                FilledButton.icon(
                  onPressed: _migrateUsersInProgress ? null : _runMigrateUsersEnsureId,
                  icon: _migrateUsersInProgress
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.people_outline, size: 18),
                  label: Text(_migrateUsersInProgress ? 'Running...' : 'Ensure user docs have id field'),
                  style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _runMigrateUsersEnsureId() async {
    setState(() => _migrateUsersInProgress = true);
    _labLog('Migration: POST api/users/migrate-ensure-id');
    try {
      final uri = Uri.parse('$_kBackendBase/api/users/migrate-ensure-id');
      final headers = await AppCheckHttpHelper.getBackendHeaders();
      headers['Content-Type'] = 'application/json';
      final response = await http.post(uri, headers: headers).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode == 200) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final total = decoded['total'] as int? ?? 0;
        final updated = decoded['updated'] as int? ?? 0;
        _labLog('Migration: total=$total, updated=$updated');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Users: $total total, $updated updated with id field.'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        _labLog('Migration error: ${response.statusCode} ${response.body}');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Migration failed: ${response.statusCode} ${response.body}'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      _labLog('Migration error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Migration failed: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating),
        );
      }
    } finally {
      if (mounted) setState(() => _migrateUsersInProgress = false);
    }
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
            style: const TextStyle(color: Colors.black87, fontSize: 12),
            decoration: const InputDecoration(
              hintText: 'Override server prompt for this request…',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
              filled: true,
              fillColor: Color(0xFFE8E8E8),
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

  /// קיבוץ לפי קטגוריה — לתצוגת Dictionary (לאחר סינון חיפוש)
  Map<String, List<SearchSynonym>> get _synonymsByCategory {
    final map = <String, List<SearchSynonym>>{};
    for (final s in _synonymsPreview) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  Widget _buildDictionaryTab() {
    final grouped = _synonymsByCategory;
    final categoryKeys = grouped.keys.toList()..sort((a, b) => a.compareTo(b));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Card(
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
                    'Total Synonyms: $_synonymsCount · ${grouped.length} categories',
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
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
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
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            itemCount: categoryKeys.length,
            itemBuilder: (_, index) {
              final category = categoryKeys[index];
              final synonyms = grouped[category]!;
              final categoryColor = _categoryColor(category.hashCode);
              return Card(
                color: const Color(0xFF161B22),
                margin: const EdgeInsets.only(bottom: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: categoryColor.withValues(alpha: 0.5)),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        category,
                        style: TextStyle(
                          color: categoryColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: synonyms.map((s) {
                          final label = s.expansions.isEmpty
                              ? s.term
                              : '${s.term} (${s.expansions.take(2).join(', ')}${s.expansions.length > 2 ? '…' : ''})';
                          return Chip(
                            label: Text(
                              label,
                              style: const TextStyle(fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            backgroundColor: categoryColor.withValues(alpha: 0.15),
                            side: BorderSide(color: categoryColor.withValues(alpha: 0.4)),
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  static Color _categoryColor(int hash) {
    final colors = [
      Colors.blueAccent,
      Colors.amberAccent,
      Colors.greenAccent,
      Colors.purpleAccent,
      Colors.cyanAccent,
      Colors.orangeAccent,
    ];
    return colors[hash.abs() % colors.length];
  }

  Widget _buildLogConsole() {
    return Container(
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
