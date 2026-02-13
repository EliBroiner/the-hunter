import 'package:flutter/material.dart';

/// קונסול לוג בתחתית AI Lab
class AiLabLogConsole extends StatelessWidget {
  const AiLabLogConsole({super.key, required this.logs});

  final List<String> logs;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.all(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Log',
            style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              itemCount: logs.length,
              itemBuilder: (_, i) {
                final line = logs[logs.length - 1 - i];
                return Text(
                  line,
                  style: const TextStyle(color: Colors.white38, fontSize: 11, fontFamily: 'monospace'),
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
