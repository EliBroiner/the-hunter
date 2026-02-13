import 'dart:async';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../../models/search_synonym.dart';
import '../../../services/settings_service.dart';
import '../../../services/app_check_http_helper.dart';
import '../../../services/auth_service.dart';
import '../../../services/database_service.dart';
import '../../../services/knowledge_base_service.dart';
import '../../../services/ocr_service.dart';
import '../../../services/user_roles_service.dart';
import '../../../services/prompt_admin_service.dart';
import 'ai_lab_constants.dart';
import 'tabs/ai_lab_dictionary_tab.dart';
import 'tabs/ai_lab_ocr_testing_tab.dart';
import 'tabs/ai_lab_pipeline_tab.dart';
import 'widgets/ai_lab_log_console.dart';

/// מסך דיבאג — Pipeline, Dictionary, OCR Testing Lab.
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
  String _promptTargetFeature = 'DocAnalysis';
  String _sendStatus = ''; // תוצאת שלב 2 (Send to Server) — Success / Error: ...
  bool _sendSuccess = false;
  bool _saveAsNewVersionInProgress = false;

  // Pipeline: שלב 3 — Save to DB
  String _saveStatus = ''; // Success / Error
  bool _saveSuccess = false;

  bool _sendingInProgress = false;
  bool _savingInProgress = false;
  bool _migrateUsersInProgress = false;

  // OCR Testing Lab — צעד אחרי צעד
  String _ocrLabFilePath = '';
  List<int>? _ocrLabBwBytes;
  String _ocrLabVisionText = '';
  String _ocrLabGeminiJson = '';
  bool _ocrLabVisionInProgress = false;
  bool _ocrLabGeminiInProgress = false;

  // Dictionary
  DateTime? _lastSyncTime;
  int _synonymsCount = 0;
  List<SearchSynonym> _synonymsPreview = [];
  final TextEditingController _dictionarySearchController = TextEditingController();
  final TextEditingController _adminKeyController = TextEditingController();
  Timer? _dictionarySearchDebounce;
  static const Duration _searchDebounceDuration = Duration(milliseconds: 300);

  // לוג קונסול בתחתית המסך
  final List<String> _labLogs = [];
  static const int _maxLabLogs = 200;

  @override
  void initState() {
    super.initState();
    _adminKeyController.text = SettingsService.instance.adminKey ?? '';
    _adminKeyController.addListener(_onAdminKeyChanged);
    _checkAdmin();
    _loadSynonymsStats();
    _dictionarySearchController.addListener(_onDictionarySearchChanged);
  }

  void _onAdminKeyChanged() {
    final t = _adminKeyController.text.trim();
    if (t.isEmpty) {
      SettingsService.instance.setAdminKey(null);
    } else {
      SettingsService.instance.setAdminKey(t);
    }
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
    _adminKeyController.removeListener(_onAdminKeyChanged);
    _adminKeyController.dispose();
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

    final uri = Uri.parse('$kAiLabBackendBase/api/analyze-debug');
    try {
      final userId = AuthService.instance.currentUser?.uid;
      final body = jsonEncode({
        'text': text,
        if (userId != null) 'userId': userId,
        if (_isAdmin && _customPrompt.isNotEmpty) 'adminPromptOverride': _customPrompt,
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
    final uri = Uri.parse('$kAiLabBackendBase/api/smart-categories/save-manual');
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
      length: 3,
      child: Scaffold(
        backgroundColor: Colors.grey[900],
        appBar: AppBar(
          backgroundColor: Colors.grey[850],
          title: const Text('AI Lab Debugger', style: TextStyle(color: Colors.white)),
          actions: [
            if (_isAdmin)
              IconButton(
                icon: const Icon(Icons.psychology, color: Colors.white70),
                tooltip: 'Manage Prompts',
                onPressed: () {
                  PromptAdminService.setAdminKey(SettingsService.instance.adminKey);
                  Navigator.of(context).pushNamed('/prompts');
                },
              ),
          ],
          bottom: TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white54,
            indicatorColor: Colors.blueAccent,
            tabs: const [
              Tab(text: 'Dictionary'),
              Tab(text: 'Pipeline'),
              Tab(text: 'OCR Testing Lab'),
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
                    AiLabDictionaryTab(
                      lastSyncTime: _lastSyncTime,
                      synonymsCount: _synonymsCount,
                      synonymsByCategory: _synonymsByCategory,
                      searchController: _dictionarySearchController,
                      onForceSync: _forceSyncFromCloud,
                    ),
                    AiLabPipelineTab(
                      ocrFilePath: _ocrFilePath,
                      ocrFileSizeBytes: _ocrFileSizeBytes,
                      ocrExtractedText: _ocrExtractedText,
                      garbageThreshold: _garbageThreshold,
                      ocrFailedByThreshold: _ocrFailedByThreshold,
                      ocrDisplayController: _ocrDisplayController,
                      serverJsonController: _serverJsonController,
                      adminKeyController: _adminKeyController,
                      isAdmin: _isAdmin,
                      customPrompt: _customPrompt,
                      sendStatus: _sendStatus,
                      sendSuccess: _sendSuccess,
                      sendingInProgress: _sendingInProgress,
                      saveStatus: _saveStatus,
                      saveSuccess: _saveSuccess,
                      savingInProgress: _savingInProgress,
                      saveAsNewVersionInProgress: _saveAsNewVersionInProgress,
                      migrateUsersInProgress: _migrateUsersInProgress,
                      onPickAndRunOcr: _pickAndRunOcr,
                      onSendToServer: _sendToServer,
                      onSaveToServerDb: _saveToServerDb,
                      onSavePromptAsNewVersion: _savePromptAsNewVersion,
                      onRunMigrateUsers: _runMigrateUsersEnsureId,
                      onShowOcrSettings: _showOcrSettings,
                      onShowCustomPromptSettings: _showCustomPromptSettings,
                      onBypassProChanged: (v) async {
                        await SettingsService.instance.setDebugBypassPro(v);
                        if (mounted) setState(() {});
                      },
                    ),
                    AiLabOcrTestingTab(
                      filePath: _ocrLabFilePath,
                      bwBytes: _ocrLabBwBytes,
                      visionText: _ocrLabVisionText,
                      geminiJson: _ocrLabGeminiJson,
                      visionInProgress: _ocrLabVisionInProgress,
                      geminiInProgress: _ocrLabGeminiInProgress,
                      onPickFile: _ocrLabPickFile,
                      onConvertToBw: _ocrLabConvertToBw,
                      onSendToVision: _ocrLabSendToVision,
                      onSendToGemini: _ocrLabSendToGemini,
                      onShowPromptSettings: () => _showCustomPromptSettings(context),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 1,
              child: AiLabLogConsole(logs: _labLogs),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _runMigrateUsersEnsureId() async {
    setState(() => _migrateUsersInProgress = true);
    _labLog('Migration: POST api/users/migrate-ensure-id');
    try {
      final uri = Uri.parse('$kAiLabBackendBase/api/users/migrate-ensure-id');
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
    var feature = _promptTargetFeature;
    showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: const Text('Custom System Prompt', style: TextStyle(color: Colors.white)),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    value: feature,
                    dropdownColor: const Color(0xFF161B22),
                    decoration: const InputDecoration(
                      labelText: 'Target Feature',
                      filled: true,
                      fillColor: Color(0xFFE8E8E8),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'DocAnalysis', child: Text('DocAnalysis')),
                      DropdownMenuItem(value: 'Search', child: Text('Search')),
                      DropdownMenuItem(value: 'OcrExtraction', child: Text('OcrExtraction')),
                    ],
                    onChanged: (v) => setDialogState(() => feature = v ?? feature),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: controller,
                    maxLines: 10,
                    style: const TextStyle(color: Colors.black87, fontSize: 12),
                    decoration: const InputDecoration(
                      hintText: 'Sent as adminPromptOverride when Admin. Empty = use versioned prompt from DB.',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                      filled: true,
                      fillColor: Color(0xFFE8E8E8),
                    ),
                  ),
                ],
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
                setState(() {
                  _customPrompt = controller.text;
                  _promptTargetFeature = feature;
                });
                Navigator.pop(ctx);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePromptAsNewVersion() async {
    if (_customPrompt.trim().isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('System Prompt is empty. Add text in Custom System Prompt (gear) first.'),
          backgroundColor: Colors.amber,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final version = await _showSaveVersionDialog();
    if (version == null || version.isEmpty) return;
    setState(() => _saveAsNewVersionInProgress = true);
    try {
      PromptAdminService.setAdminKey(SettingsService.instance.adminKey);
      final created = await PromptAdminService.instance.savePrompt(
        feature: _promptTargetFeature,
        content: _customPrompt.trim(),
        version: version.trim(),
      );
      if (!mounted) return;
      if (created != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Prompt saved as ${created.version} (${created.targetFeature})'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            action: SnackBarAction(
              label: 'View',
              textColor: Colors.white,
              onPressed: () {
                Navigator.of(context).pushNamed('/prompts');
              },
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Save failed. Check Admin Key in Pipeline tab.'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saveAsNewVersionInProgress = false);
    }
  }

  Future<String?> _showSaveVersionDialog() async {
    final controller = TextEditingController(text: '1.0');
    String? result;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF161B22),
        title: const Text('Save as New Version', style: TextStyle(color: Colors.white)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Feature: $_promptTargetFeature',
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Version',
                hintText: '1.0',
                filled: true,
                fillColor: Color(0xFFE8E8E8),
              ),
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
              result = controller.text.trim();
              Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    return result;
  }

  /// קיבוץ לפי קטגוריה — לתצוגת Dictionary (לאחר סינון חיפוש)
  Map<String, List<SearchSynonym>> get _synonymsByCategory {
    final map = <String, List<SearchSynonym>>{};
    for (final s in _synonymsPreview) {
      map.putIfAbsent(s.category, () => []).add(s);
    }
    return map;
  }

  Future<void> _ocrLabPickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, allowMultiple: false);
    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null || path.isEmpty) return;
    if (!OCRService.isSupportedImage(path.split('.').last)) {
      _labLog('OCR Lab: unsupported image type');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unsupported image type'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() {
      _ocrLabFilePath = path;
      _ocrLabBwBytes = null;
      _ocrLabVisionText = '';
      _ocrLabGeminiJson = '';
    });
    _labLog('OCR Lab: picked $path');
  }

  Future<void> _ocrLabConvertToBw() async {
    if (_ocrLabFilePath.isEmpty) return;
    _labLog('OCR Lab: converting to B&W...');
    try {
      final result = await OCRService.instance.getCompressedBwImageForUpload(_ocrLabFilePath);
      if (result.bytes.isEmpty) {
        _labLog('OCR Lab: B&W conversion failed');
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('B&W conversion failed'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
        return;
      }
      setState(() => _ocrLabBwBytes = result.bytes);
      _labLog('OCR Lab: B&W ready ${result.bytes.length} bytes');
    } catch (e) {
      _labLog('OCR Lab B&W error: $e');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
    }
  }

  Future<void> _ocrLabSendToVision() async {
    if (_ocrLabBwBytes == null) return;
    setState(() => _ocrLabVisionInProgress = true);
    _labLog('OCR Lab: sending to Cloud Vision...');
    try {
      final uri = Uri.parse('$kAiLabBackendBase/api/debug/ocr-vision-only');
      final request = http.MultipartRequest('POST', uri);
      request.files.add(http.MultipartFile.fromBytes('file', _ocrLabBwBytes!, filename: 'bw.jpg'));
      request.headers.addAll(await AppCheckHttpHelper.getBackendHeaders());
      final streamed = await request.send();
      final response = await http.Response.fromStream(streamed);
      if (!mounted) return;
      if (response.statusCode != 200) {
        _labLog('OCR Lab Vision error: ${response.statusCode} ${response.body}');
        setState(() {
          _ocrLabVisionText = 'Error: ${response.statusCode}\n${response.body.length > 200 ? '${response.body.substring(0, 200)}...' : response.body}';
          _ocrLabVisionInProgress = false;
        });
        return;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final text = decoded['text']?.toString() ?? '';
      setState(() {
        _ocrLabVisionText = text.isEmpty ? '(no text in image)' : text;
        _ocrLabVisionInProgress = false;
      });
      _labLog('OCR Lab: Vision done, text length=${text.length}');
    } catch (e, st) {
      _labLog('OCR Lab Vision error: $e');
      if (mounted) {
        setState(() {
          _ocrLabVisionText = 'Exception: $e';
          _ocrLabVisionInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
      debugPrint('_ocrLabSendToVision: $e\n$st');
    }
  }

  Future<void> _ocrLabSendToGemini() async {
    final text = _ocrLabVisionText;
    if (text.isEmpty || text.startsWith('Error') || text.startsWith('Exception') || text == '(no text in image)') {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Run Cloud Vision first or enter text'), backgroundColor: Colors.amber, behavior: SnackBarBehavior.floating));
      return;
    }
    setState(() => _ocrLabGeminiInProgress = true);
    _labLog('OCR Lab: sending to Gemini...');
    try {
      final uri = Uri.parse('$kAiLabBackendBase/api/analyze-debug');
      final userId = AuthService.instance.currentUser?.uid;
      final body = jsonEncode({
        'text': text,
        if (userId != null) 'userId': userId,
        if (_isAdmin && _customPrompt.isNotEmpty) 'adminPromptOverride': _customPrompt,
      });
      final headers = await AppCheckHttpHelper.getBackendHeaders();
      headers['Content-Type'] = 'application/json';
      final response = await http.post(uri, headers: headers, body: body).timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (response.statusCode != 200) {
        setState(() {
          _ocrLabGeminiJson = 'Error: ${response.statusCode}\n${response.body}';
          _ocrLabGeminiInProgress = false;
        });
        return;
      }
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final pretty = const JsonEncoder.withIndent('  ').convert(decoded);
      setState(() {
        _ocrLabGeminiJson = pretty;
        _ocrLabGeminiInProgress = false;
      });
      _labLog('OCR Lab: Gemini done');
    } catch (e, st) {
      _labLog('OCR Lab Gemini error: $e');
      if (mounted) {
        setState(() {
          _ocrLabGeminiJson = 'Exception: $e';
          _ocrLabGeminiInProgress = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$e'), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating));
      }
      debugPrint('_ocrLabSendToGemini: $e\n$st');
    }
  }

}
