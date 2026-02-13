import 'package:flutter/material.dart';
import '../widgets/ai_lab_stage_card.dart';

/// טאב OCR Testing Lab — צעד אחרי צעד: קובץ → B&W → Cloud Vision → Gemini
class AiLabOcrTestingTab extends StatelessWidget {
  const AiLabOcrTestingTab({
    super.key,
    required this.filePath,
    required this.bwBytes,
    required this.visionText,
    required this.geminiJson,
    required this.visionInProgress,
    required this.geminiInProgress,
    required this.onPickFile,
    required this.onConvertToBw,
    required this.onSendToVision,
    required this.onSendToGemini,
    required this.onShowPromptSettings,
  });

  final String filePath;
  final List<int>? bwBytes;
  final String visionText;
  final String geminiJson;
  final bool visionInProgress;
  final bool geminiInProgress;
  final VoidCallback onPickFile;
  final VoidCallback onConvertToBw;
  final VoidCallback onSendToVision;
  final VoidCallback onSendToGemini;
  final VoidCallback onShowPromptSettings;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildChainVsXrayInfo(),
        const SizedBox(height: 16),
        AiLabStageCard(
          stageIndex: 1,
          title: 'בחר קובץ',
          icon: Icons.folder_open,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: onPickFile,
                icon: const Icon(Icons.add_photo_alternate, size: 20),
                label: const Text('Pick image'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
              ),
              if (filePath.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(filePath, style: const TextStyle(fontSize: 11, color: Colors.white54), maxLines: 2, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AiLabStageCard(
          stageIndex: 2,
          title: 'המר לשחור-לבן',
          icon: Icons.filter_b_and_w,
          child: OutlinedButton.icon(
            onPressed: bwBytes != null ? null : onConvertToBw,
            icon: bwBytes != null ? const Icon(Icons.check_circle, size: 20, color: Colors.green) : const Icon(Icons.filter_b_and_w, size: 20),
            label: Text(bwBytes != null ? 'B&W ready (${(bwBytes!.length / 1024).toStringAsFixed(1)} KB)' : 'Convert to B&W'),
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
          ),
        ),
        const SizedBox(height: 12),
        AiLabStageCard(
          stageIndex: 3,
          title: 'Cloud Vision',
          icon: Icons.cloud,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: bwBytes == null || visionInProgress ? null : onSendToVision,
                icon: visionInProgress
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.cloud_upload, size: 20),
                label: Text(visionInProgress ? 'Sending...' : 'Send to Cloud Vision'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
              ),
              if (visionText.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Text(visionText, style: const TextStyle(fontSize: 12, color: Colors.black87), maxLines: 8, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        AiLabStageCard(
          stageIndex: 4,
          title: 'Gemini (עם Prompt)',
          icon: Icons.psychology,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlinedButton.icon(
                onPressed: (visionText.isEmpty && geminiJson.isEmpty) || geminiInProgress ? null : onSendToGemini,
                icon: geminiInProgress
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send, size: 20),
                label: Text(geminiInProgress ? 'Sending...' : 'Send to Gemini'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
              ),
              if (geminiJson.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFE8E8E8), borderRadius: BorderRadius.circular(8)),
                  child: Text(geminiJson, style: const TextStyle(fontSize: 11, fontFamily: 'monospace'), maxLines: 10, overflow: TextOverflow.ellipsis),
                ),
              TextButton.icon(
                onPressed: onShowPromptSettings,
                icon: const Icon(Icons.tune, size: 18),
                label: const Text('Edit System Prompt'),
                style: TextButton.styleFrom(foregroundColor: Colors.amber),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildChainVsXrayInfo() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blueGrey.shade300, size: 20),
              const SizedBox(width: 8),
              Text('Chain vs File X-Ray', style: TextStyle(color: Colors.blueGrey.shade200, fontWeight: FontWeight.bold, fontSize: 13)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'OCR Testing Lab (כאן): צעד-אחרי-צעד אינטראקטיבי — בוחרים קובץ, ממירים ל-B&W, שולחים ל-Cloud Vision, ואז ל-Gemini עם Prompt מותאם. אין documentId.',
            style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.4),
          ),
          const SizedBox(height: 4),
          Text(
            'File X-Ray (Admin Web): צפייה בנתונים שמורים — מזינים documentId ומקבלים את מה שנשמר ב-Firestore (processing chain, raw/cleaned text, tags). Read-only.',
            style: TextStyle(fontSize: 11, color: Colors.white70, height: 1.4),
          ),
        ],
      ),
    );
  }
}
