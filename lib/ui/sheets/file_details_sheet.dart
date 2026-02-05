import 'package:flutter/material.dart';
import '../../models/file_metadata.dart';

/// מחזיר תיאור סטטוס הקובץ בעברית — לתצוגה עדינה בגיליון פרטים
String fileAnalysisStatusLabel(FileMetadata file) {
  if (file.aiStatus == 'unreadable') return 'נסרק — טקסט לא קריא';
  if (file.aiStatus == 'local_match') return 'זוהה במילון';
  if (file.isAiAnalyzed && file.aiStatus == null) return 'נותח ב-AI';
  if (file.aiStatus == 'quotaLimit') return 'ניתוח לא זמין (מכסה)';
  if (file.aiStatus == 'error') return 'שגיאה בניתוח';
  return 'ממתין לניתוח';
}

/// גיליון פרטי קובץ — סטטוס, ניתוח מחדש והתקדמות בעברית (RTL, Material 3)
class FileDetailsSheet extends StatefulWidget {
  final FileMetadata file;
  final Future<void> Function(void Function(String) reportProgress) onReanalyze;
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

  Future<void> _runReanalyze() async {
    if (_isReanalyzing) return;
    setState(() {
      _isReanalyzing = true;
      _progressMessage = 'שלב 1: מחלץ טקסט...';
    });
    try {
      await widget.onReanalyze((msg) {
        if (mounted) setState(() => _progressMessage = msg);
      });
    } finally {
      if (mounted) setState(() => _isReanalyzing = false);
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
