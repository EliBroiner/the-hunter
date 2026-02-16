import 'package:flutter/material.dart';

/// קונסול לוג בתחתית AI Lab — ניתן לסגור/לפתוח
class AiLabLogConsole extends StatelessWidget {
  const AiLabLogConsole({
    super.key,
    required this.logs,
    required this.expanded,
    required this.onToggle,
  });

  final List<String> logs;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.keyboard_arrow_down : Icons.keyboard_arrow_up,
                    color: Colors.white54,
                    size: 20,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Log',
                    style: TextStyle(
                      color: Colors.white54,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '(${logs.length})',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const Spacer(),
                  if (logs.isEmpty)
                    Text(
                      'No logs yet — run Pipeline or OCR to see output',
                      style: TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                ],
              ),
            ),
          ),
          if (expanded)
            Expanded(
              child: logs.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        'No logs yet. Run OCR, Send to Server, or Force Sync to see output.',
                        style: TextStyle(color: Colors.white24, fontSize: 11),
                      ),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      itemCount: logs.length,
                      itemBuilder: (_, i) {
                        final line = logs[logs.length - 1 - i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 1),
                          child: Text(
                            line,
                            style: const TextStyle(
                              color: Colors.white38,
                              fontSize: 11,
                              fontFamily: 'monospace',
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      },
                    ),
            ),
        ],
      ),
    );
  }
}
