import 'package:flutter/material.dart';
import '../../models/file_metadata.dart';

/// מחזיר תיאור סטטוס הקובץ בעברית — לתצוגה עדינה בגיליון פרטים
String fileAnalysisStatusLabel(FileMetadata file) {
  if (file.aiStatus == 'unreadable') return 'נסרק — טקסט לא קריא';
  if (file.aiStatus == 'local_match') return 'זוהה במילון';
  if (file.isAiAnalyzed && file.aiStatus == null) return 'נותח ב-AI';
  if (file.aiStatus == 'quotaLimit') return 'ניתוח לא זמין (מכסה)';
  if (file.aiStatus == 'pending_retry') return 'ממתין לניתוח חוזר';
  if (file.aiStatus == 'auth_failed_retry') return 'ממתין לחידוש אימות';
  if (file.aiStatus == 'error') return 'שגיאה בניתוח';
  return 'ממתין לניתוח';
}

/// גיליון פרטי קובץ — סטטוס, ניתוח מחדש והתקדמות בעברית (RTL, Material 3)
class FileDetailsSheet extends StatefulWidget {
  final FileMetadata file;
  /// reportProgress — עדכון הודעת התקדמות; isCanceled — דגל ביטול (לחיצה על ביטול)
  final Future<void> Function(void Function(String) reportProgress, bool Function() isCanceled) onReanalyze;
  final List<Widget>? actionTiles;

  const FileDetailsSheet({
    super.key,
    required this.file,
    required this.onReanalyze,
    this.actionTiles,
  });

  @override
  State<FileDetailsSheet> createState() => _FileDetailsSheetState();
}

class _FileDetailsSheetState extends State<FileDetailsSheet> {
  bool _isReanalyzing = false;
  String _progressMessage = '';
  bool _reanalyzeFailed = false;
  bool _cancelRequested = false;

  Future<void> _runReanalyze() async {
    if (_isReanalyzing) return;
    setState(() {
      _isReanalyzing = true;
      _reanalyzeFailed = false;
      _cancelRequested = false;
      _progressMessage = 'מתחבר לשרת...';
    });
    try {
      await widget.onReanalyze(
        (msg) {
          if (mounted) setState(() => _progressMessage = msg);
        },
        () => _cancelRequested,
      );
      if (mounted && !_cancelRequested) setState(() => _reanalyzeFailed = false);
    } catch (_) {
      if (mounted && !_cancelRequested) setState(() => _reanalyzeFailed = true);
    } finally {
      if (mounted) setState(() {
        _isReanalyzing = false;
        _cancelRequested = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyLarge?.color ??
        (theme.brightness == Brightness.dark ? Colors.white : Colors.black);
    final secondaryColor =
        theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurfaceVariant;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // סטטוס עדין
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Text(
              fileAnalysisStatusLabel(widget.file),
              style: theme.textTheme.bodySmall?.copyWith(
                color: secondaryColor,
                fontStyle: FontStyle.italic,
              ),
              textDirection: TextDirection.rtl,
            ),
          ),
          // ניתוח מחדש
          ListTile(
            leading: Icon(
              Icons.refresh,
              color: _isReanalyzing ? theme.disabledColor : theme.colorScheme.primary,
            ),
            title: Text(
              'ניתוח מחדש',
              style: TextStyle(
                color: _isReanalyzing ? theme.disabledColor : textColor,
              ),
              textDirection: TextDirection.rtl,
            ),
            subtitle: _isReanalyzing
                ? Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        LinearProgressIndicator(
                          backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _progressMessage,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: secondaryColor,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => setState(() => _cancelRequested = true),
                            child: const Text('ביטול'),
                          ),
                        ),
                      ],
                    ),
                  )
                : _reanalyzeFailed
                    ? Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: theme.colorScheme.error,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'הניתוח נכשל - בדוק חיבור או נסה שוב',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.error,
                                ),
                                textDirection: TextDirection.rtl,
                              ),
                            ),
                            FilledButton.tonal(
                              onPressed: _runReanalyze,
                              child: const Text('נסה שוב'),
                            ),
                          ],
                        ),
                      )
                    : null,
            enabled: !_isReanalyzing,
            onTap: _isReanalyzing ? null : _runReanalyze,
          ),
          if (widget.actionTiles != null) ...widget.actionTiles!,
        ],
      ),
    );
  }
}
