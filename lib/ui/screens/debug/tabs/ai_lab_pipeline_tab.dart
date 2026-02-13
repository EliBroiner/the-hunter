import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../../../services/settings_service.dart';
import '../widgets/ai_lab_stage_card.dart';
import '../ai_lab_constants.dart';

/// טאב Pipeline — Local OCR → Server AI → Save to DB + Users migration
class AiLabPipelineTab extends StatelessWidget {
  const AiLabPipelineTab({
    super.key,
    required this.ocrFilePath,
    required this.ocrFileSizeBytes,
    required this.ocrExtractedText,
    required this.garbageThreshold,
    required this.ocrFailedByThreshold,
    required this.ocrDisplayController,
    required this.serverJsonController,
    required this.adminKeyController,
    required this.isAdmin,
    required this.customPrompt,
    required this.sendStatus,
    required this.sendSuccess,
    required this.sendingInProgress,
    required this.saveStatus,
    required this.saveSuccess,
    required this.savingInProgress,
    required this.saveAsNewVersionInProgress,
    required this.migrateUsersInProgress,
    required this.onPickAndRunOcr,
    required this.onSendToServer,
    required this.onSaveToServerDb,
    required this.onSavePromptAsNewVersion,
    required this.onRunMigrateUsers,
    required this.onShowOcrSettings,
    required this.onShowCustomPromptSettings,
    required this.onBypassProChanged,
  });

  final String ocrFilePath;
  final int ocrFileSizeBytes;
  final String ocrExtractedText;
  final double garbageThreshold;
  final bool ocrFailedByThreshold;
  final TextEditingController ocrDisplayController;
  final TextEditingController serverJsonController;
  final TextEditingController adminKeyController;
  final bool isAdmin;
  final String customPrompt;
  final String sendStatus;
  final bool sendSuccess;
  final bool sendingInProgress;
  final String saveStatus;
  final bool saveSuccess;
  final bool savingInProgress;
  final bool saveAsNewVersionInProgress;
  final bool migrateUsersInProgress;
  final VoidCallback onPickAndRunOcr;
  final VoidCallback onSendToServer;
  final VoidCallback onSaveToServerDb;
  final VoidCallback onSavePromptAsNewVersion;
  final VoidCallback onRunMigrateUsers;
  final void Function(BuildContext) onShowOcrSettings;
  final void Function(BuildContext) onShowCustomPromptSettings;
  final void Function(bool) onBypassProChanged;

  static double textDensityScore(int textLength, int fileSizeBytes) {
    if (fileSizeBytes <= 0) return 0;
    return (textLength / fileSizeBytes) * 100;
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildServerInfo(),
        if (kDebugMode) ...[
          const SizedBox(height: 12),
          _buildBypassProSwitch(),
          const SizedBox(height: 12),
          _buildAdminKeyField(),
        ],
        const SizedBox(height: 16),
        AiLabStageCard(
          stageIndex: 1,
          title: 'Local OCR',
          onSettings: () => onShowOcrSettings(context),
          child: _buildOcrStageContent(context),
        ),
        const SizedBox(height: 16),
        AiLabStageCard(
          stageIndex: 2,
          title: 'Server AI (Gemini)',
          onSettings: () => onShowCustomPromptSettings(context),
          child: _buildServerAiContent(),
        ),
        const SizedBox(height: 16),
        AiLabStageCard(
          stageIndex: 3,
          title: 'Server Database',
          child: _buildSaveToDbContent(),
        ),
        const SizedBox(height: 16),
        const SizedBox(height: 16),
        _buildMigrateUsersCard(),
      ],
    );
  }

  Widget _buildServerInfo() {
    return Container(
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
              style: const TextStyle(fontSize: 12, color: Colors.white70, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBypassProSwitch() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.amber),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Bypass PRO (דיבאג): מאפשר לחלץ Secure Folder, Tags ללא מנוי',
              style: TextStyle(fontSize: 12, color: Colors.amber[200]),
            ),
          ),
          Switch(
            value: SettingsService.instance.debugBypassPro,
            onChanged: onBypassProChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildAdminKeyField() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.blueGrey.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey),
      ),
      child: Row(
        children: [
          const Icon(Icons.key, color: Colors.white70, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: adminKeyController,
              obscureText: true,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
              decoration: const InputDecoration(
                hintText: 'Admin Key (X-Admin-Key)',
                hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                isDense: true,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOcrStageContent(BuildContext context) {
    final density = textDensityScore(ocrExtractedText.length, ocrFileSizeBytes > 0 ? ocrFileSizeBytes : 1);
    final pass = density >= garbageThreshold;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlinedButton.icon(
          onPressed: onPickAndRunOcr,
          icon: const Icon(Icons.folder_open, size: 20),
          label: const Text('Pick image & run OCR'),
          style: OutlinedButton.styleFrom(foregroundColor: Colors.white70, side: const BorderSide(color: Colors.white24)),
        ),
        const SizedBox(height: 8),
        Text(
          ocrFilePath.isEmpty ? 'No file' : ocrFilePath,
          style: const TextStyle(fontSize: 12, color: Colors.white54),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        if (ocrFileSizeBytes > 0 || ocrExtractedText.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            'Score: ${density.toStringAsFixed(2)}% (Needed: > ${garbageThreshold.toStringAsFixed(1)}%)',
            style: TextStyle(fontSize: 13, color: pass ? Colors.greenAccent : Colors.redAccent, fontWeight: FontWeight.w500),
          ),
        ],
        const SizedBox(height: 8),
        Builder(
          builder: (_) {
            final passBox = !ocrFailedByThreshold;
            return Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: passBox ? Colors.green.withValues(alpha: 0.15) : Colors.red.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: passBox ? Colors.green : Colors.red, width: 1.5),
              ),
              child: TextField(
                readOnly: true,
                maxLines: 6,
                controller: ocrDisplayController,
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
    );
  }

  Widget _buildServerAiContent() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(isAdmin ? Icons.shield : Icons.shield_outlined, size: 20, color: isAdmin ? Colors.green : Colors.grey),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                isAdmin ? 'Admin Access: Granted (Custom Prompts Active)' : 'Standard User (Custom Prompts Ignored)',
                style: TextStyle(fontSize: 12, color: isAdmin ? Colors.greenAccent : Colors.white54),
              ),
            ),
            if (isAdmin && customPrompt.trim().isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber, width: 1),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.science, size: 14, color: Colors.amber[700]),
                    const SizedBox(width: 4),
                    Text('Live Testing', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber[700])),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 140,
          child: TextField(
            controller: serverJsonController,
            readOnly: false,
            maxLines: null,
            expands: true,
            style: const TextStyle(color: Colors.black87, fontSize: 12, fontFamily: 'monospace'),
            decoration: InputDecoration(
              hintText: 'JSON response (editable — fix before Save to DB)…',
              alignLabelWithHint: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              contentPadding: const EdgeInsets.all(12),
              filled: true,
              fillColor: const Color(0xFFE8E8E8),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            FilledButton.icon(
              onPressed: sendingInProgress ? null : onSendToServer,
              icon: sendingInProgress
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 20),
              label: Text(sendingInProgress ? 'Sending...' : 'Send to Server'),
              style: FilledButton.styleFrom(backgroundColor: Colors.blue.shade700, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 8),
            if (isAdmin)
              FilledButton.icon(
                onPressed: saveAsNewVersionInProgress ? null : onSavePromptAsNewVersion,
                icon: saveAsNewVersionInProgress
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.save_as, size: 18),
                label: Text(saveAsNewVersionInProgress ? 'Saving...' : 'Save as New Version'),
                style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
              ),
            const SizedBox(width: 16),
            if (sendStatus.isNotEmpty)
              Icon(sendSuccess ? Icons.check_circle : Icons.error, color: sendSuccess ? Colors.green : Colors.red, size: 24),
            if (sendStatus.isNotEmpty)
              Flexible(
                child: Text(sendStatus, style: TextStyle(color: sendSuccess ? Colors.green : Colors.red, fontSize: 14), overflow: TextOverflow.ellipsis),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildSaveToDbContent() {
    return Column(
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
              onPressed: savingInProgress ? null : onSaveToServerDb,
              icon: savingInProgress
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save, size: 20),
              label: Text(savingInProgress ? 'Saving...' : 'Save to DB'),
              style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
            ),
            const SizedBox(width: 16),
            if (saveStatus.isNotEmpty)
              Icon(saveSuccess ? Icons.check_circle : Icons.error, color: saveSuccess ? Colors.green : Colors.red, size: 24),
            if (saveStatus.isNotEmpty)
              Text(saveStatus, style: TextStyle(color: saveSuccess ? Colors.green : Colors.red, fontSize: 14)),
          ],
        ),
      ],
    );
  }

  Widget _buildMigrateUsersCard() {
    return Card(
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
              onPressed: migrateUsersInProgress ? null : onRunMigrateUsers,
              icon: migrateUsersInProgress
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.people_outline, size: 18),
              label: Text(migrateUsersInProgress ? 'Running...' : 'Ensure user docs have id field'),
              style: FilledButton.styleFrom(backgroundColor: Colors.orange.shade700, foregroundColor: Colors.white),
            ),
          ],
        ),
      ),
    );
  }
}
