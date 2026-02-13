import 'package:flutter/material.dart';
import '../ai_lab_constants.dart';

/// כרטיס stage ממוספר — משותף ל־Pipeline ו־OCR Testing Lab
class AiLabStageCard extends StatelessWidget {
  const AiLabStageCard({
    super.key,
    required this.stageIndex,
    required this.title,
    this.icon,
    this.onSettings,
    required this.child,
  });

  final int stageIndex;
  final String title;
  final IconData? icon;
  final VoidCallback? onSettings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final color = kStageColors[(stageIndex - 1) % kStageColors.length];
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
                    style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
                const SizedBox(width: 10),
                if (icon != null) ...[
                  Icon(icon, color: color, size: 20),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
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
}
