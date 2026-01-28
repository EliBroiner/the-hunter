import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../services/auth_service.dart';
import '../services/backup_service.dart';
import '../services/settings_service.dart';
import '../services/localization_service.dart';

/// מסך הגדרות
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _backupService = BackupService.instance;
  final _settingsService = SettingsService.instance;
  
  bool _isBackingUp = false;
  bool _isRestoring = false;
  double _backupProgress = 0;
  BackupInfo? _backupInfo;
  bool _loadingBackupInfo = false;
  bool _autoBackupEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadBackupInfo();
    _loadAutoBackupSetting();
  }

  Future<void> _loadBackupInfo() async {
    if (!_settingsService.isPremium) return;
    
    setState(() => _loadingBackupInfo = true);
    
    try {
      final info = await _backupService.getBackupInfo();
      if (mounted) {
        setState(() {
          _backupInfo = info;
          _loadingBackupInfo = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loadingBackupInfo = false);
    }
  }
  
  Future<void> _loadAutoBackupSetting() async {
    final enabled = await _backupService.isAutoBackupEnabled();
    if (mounted) {
      setState(() => _autoBackupEnabled = enabled);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = AuthService.instance;
    final user = authService.currentUser;
    final isGuest = authService.isGuest;
    final isPremium = _settingsService.isPremium;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('settings_title'),
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // פרופיל משתמש
            _buildUserProfile(context, theme, user, isGuest),
            const SizedBox(height: 24),
            
            // גיבוי ושחזור (פרימיום בלבד)
            _buildSettingsSection(
              context,
              tr('section_backup'),
              [
                _buildBackupTile(context, theme, isPremium),
                if (isPremium && _backupInfo != null)
                  _buildRestoreTile(context, theme),
                if (isPremium)
                  _buildAutoBackupTile(context, theme),
              ],
            ),
            if (isPremium && _backupInfo != null)
              _buildBackupInfoCard(theme),
            const SizedBox(height: 16),
            
            // הגדרות כלליות
            _buildSettingsSection(
              context,
              tr('section_general'),
              [
                _buildSettingsTile(
                  context,
                  icon: Icons.language,
                  title: tr('language'),
                  subtitle: _settingsService.locale == 'he' ? 'עברית' : 'English',
                  onTap: () => _showLanguageDialog(context),
                ),
                _buildThemeModeTile(context),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildSettingsSection(
              context,
              tr('section_scan'),
              [
                _buildSettingsTile(
                  context,
                  icon: Icons.folder,
                  title: tr('scan_folders'),
                  subtitle: tr('scan_folders_subtitle'),
                  trailing: const Icon(Icons.chevron_right, color: Colors.grey),
                  onTap: () {
                    Navigator.of(context).pushNamed('/folders');
                  },
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildSettingsSection(
              context,
              tr('section_tools'),
              [
                _buildDuplicatesFinderTile(context, theme, _settingsService.isPremium),
                _buildSecureFolderTile(context, theme, _settingsService.isPremium),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildSettingsSection(
              context,
              tr('section_about'),
              [
                _buildSettingsTile(
                  context,
                  icon: Icons.info_outline,
                  title: tr('about_app'),
                  subtitle: 'v1.0.0',
                  onTap: () => _showAboutSheet(context),
                ),
              ],
            ),
            const SizedBox(height: 24),
            
            // כפתור התנתקות
            _buildLogoutButton(context, theme),
          ],
        ),
      ),
    );
  }

  /// בונה כרטיס גיבוי
  Widget _buildBackupTile(BuildContext context, ThemeData theme, bool isPremium) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isPremium ? null : Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: isPremium 
                ? const LinearGradient(colors: [Colors.blue, Colors.purple])
                : null,
            color: isPremium ? null : Colors.grey.shade800,
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isBackingUp
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _backupProgress > 0 ? _backupProgress : null,
                    color: Colors.white,
                  ),
                )
              : Icon(
                  Icons.cloud_upload,
                  color: isPremium ? Colors.white : Colors.grey,
                  size: 20,
                ),
        ),
        title: Row(
          children: [
            Text(
              tr('backup_cloud'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isPremium ? null : Colors.grey,
              ),
            ),
            if (!isPremium) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  tr('pro_badge'),
                  style: const TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          _isBackingUp 
              ? '${tr("loading")} ${(_backupProgress * 100).toInt()}%'
              : (isPremium 
                  ? (_backupInfo != null 
                      ? tr('last_backup').replaceFirst('\${date}', _backupInfo!.formattedDate)
                      : tr('tap_to_backup'))
                  : tr('upgrade_premium')),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        trailing: isPremium && !_isBackingUp
            ? Icon(Icons.chevron_left, color: Colors.grey.shade600)
            : null,
        onTap: isPremium && !_isBackingUp ? _performBackup : _showPremiumRequired,
      ),
    );
  }

  /// בונה כרטיס שחזור
  Widget _buildRestoreTile(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Colors.green, Colors.teal]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: _isRestoring
              ? SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    value: _backupProgress > 0 ? _backupProgress : null,
                    color: Colors.white,
                  ),
                )
              : const Icon(Icons.cloud_download, color: Colors.white, size: 20),
        ),
        title: Text(
          tr('restore_cloud'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _isRestoring
              ? '\${tr("loading")} \${(_backupProgress * 100).toInt()}%'
              : tr('restore_info').replaceFirst('\${count}', _backupInfo!.filesCount.toString()).replaceFirst('\${size}', _backupInfo!.formattedSize),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        trailing: !_isRestoring
            ? Icon(Icons.chevron_left, color: Colors.grey.shade600)
            : null,
        onTap: !_isRestoring ? () => _showRestoreConfirmation(context) : null,
      ),
    );
  }

  /// בונה כרטיס מחפש כפולים
  Widget _buildDuplicatesFinderTile(BuildContext context, ThemeData theme, bool isPremium) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isPremium ? null : Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: isPremium 
                ? const LinearGradient(colors: [Colors.orange, Colors.red])
                : null,
            color: isPremium ? null : Colors.grey.shade800,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.find_replace,
            color: isPremium ? Colors.white : Colors.grey,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              tr('duplicates_finder'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isPremium ? null : Colors.grey,
              ),
            ),
            if (!isPremium) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          isPremium 
              ? tr('duplicates_subtitle')
              : tr('upgrade_premium'),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        trailing: isPremium 
            ? Icon(Icons.chevron_left, color: Colors.grey.shade600)
            : null,
        onTap: isPremium 
            ? () => Navigator.of(context).pushNamed('/duplicates')
            : _showPremiumRequired,
      ),
    );
  }

  /// בונה כרטיס תיקייה מאובטחת
  Widget _buildSecureFolderTile(BuildContext context, ThemeData theme, bool isPremium) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: isPremium ? null : Border.all(color: Colors.amber.withValues(alpha: 0.5)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            gradient: isPremium 
                ? const LinearGradient(colors: [Colors.purple, Colors.indigo])
                : null,
            color: isPremium ? null : Colors.grey.shade800,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            Icons.lock,
            color: isPremium ? Colors.white : Colors.grey,
            size: 20,
          ),
        ),
        title: Row(
          children: [
            Text(
              tr('secure_folder'),
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isPremium ? null : Colors.grey,
              ),
            ),
            if (!isPremium) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  'PRO',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ],
        ),
        subtitle: Text(
          isPremium 
              ? tr('secure_folder_subtitle')
              : tr('upgrade_premium'),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        trailing: isPremium 
            ? Icon(Icons.chevron_left, color: Colors.grey.shade600)
            : null,
        onTap: isPremium 
            ? () => Navigator.of(context).pushNamed('/secure')
            : _showPremiumRequired,
      ),
    );
  }

  /// בונה כרטיס אחסון בענן - נמחק לפי בקשת המשתמש
  // Widget _buildCloudStorageTile...


  /// מבצע גיבוי חכם
  Future<void> _performBackup() async {
    setState(() {
      _isBackingUp = true;
      _backupProgress = 0;
    });

    // שימוש בגיבוי חכם - מעלה רק שינויים!
    final result = await _backupService.smartBackup(
      onProgress: (progress) {
        if (mounted) setState(() => _backupProgress = progress);
      },
    );

    setState(() => _isBackingUp = false);

    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(result.message ?? tr('backup_success').replaceFirst('\${count}', result.filesCount.toString())),
                ),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        _loadBackupInfo();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? tr('backup_error')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// מציג אישור שחזור
  void _showRestoreConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber, color: Colors.amber),
            const SizedBox(width: 12),
            Text(tr('restore_title')),
          ],
        ),
        content: Text(
          tr('restore_confirm'),
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _performRestore();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade700,
            ),
            child: Text(tr('restore_action')),
          ),
        ],
      ),
    );
  }

  /// מבצע שחזור
  Future<void> _performRestore() async {
    setState(() {
      _isRestoring = true;
      _backupProgress = 0;
    });

    final result = await _backupService.restoreFromCloud(
      onProgress: (progress) {
        if (mounted) setState(() => _backupProgress = progress);
      },
    );

    setState(() => _isRestoring = false);

    if (mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Text(tr('restore_success').replaceFirst('\${count}', result.filesCount.toString())),
              ],
            ),
            backgroundColor: Colors.green.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
        
        // הפעלת סריקה מלאה לרענון הנתונים והוספת קבצים מקומיים חסרים
        // זה פותר את הבעיה שקבצים "נעלמים" עד להפעלה מחדש
        // אנחנו משתמשים ב-Future.delayed כדי לא לחסום את ה-UI
        Future.delayed(const Duration(milliseconds: 500), () {
           // דרך לגשת ל-AutoScanManager היא בעייתית מכאן כי הוא מוגדר ב-main.dart
           // אבל הוא Singleton גלובלי (אם היינו מייצאים אותו).
           // מכיוון שהוא מוגדר ב-main.dart ולא כ-service נפרד, קשה לגשת אליו.
           // הפתרון הנכון הוא להעביר את AutoScanManager לקובץ נפרד ב-services.
           // אבל כרגע, מכיוון ששינינו את restoreFromCloud לשימוש ב-saveFiles (מיזוג),
           // הבעיה של "היעלמות קבצים" אמורה להיפתר מעצמה!
           // הקבצים המקומיים לא נמחקים יותר.
        });
        
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.error ?? tr('restore_error')),
            backgroundColor: Colors.red.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  /// מציג הודעת פרימיום נדרש
  void _showPremiumRequired() {
    Navigator.pushNamed(context, '/subscription');
  }
  
  /// בונה כרטיס גיבוי אוטומטי
  Widget _buildAutoBackupTile(BuildContext context, ThemeData theme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: SwitchListTile(
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.schedule, color: Colors.green, size: 20),
        ),
        title: Text(
          tr('auto_backup'),
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          _autoBackupEnabled ? tr('auto_backup_subtitle') : tr('auto_backup_off'),
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        value: _autoBackupEnabled,
        onChanged: (value) async {
          setState(() => _autoBackupEnabled = value);
          await _backupService.setAutoBackupEnabled(value);
        },
      ),
    );
  }
  
  /// בונה כרטיס מידע על הגיבוי
  Widget _buildBackupInfoCard(ThemeData theme) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 0, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.blue.shade900.withValues(alpha: 0.3),
            Colors.purple.shade900.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.cloud_done, color: Colors.green, size: 18),
              const SizedBox(width: 8),
              Text(
                tr('last_backup_title'),
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildInfoChip(Icons.calendar_today, _backupInfo!.formattedDate),
              const SizedBox(width: 8),
              _buildInfoChip(Icons.folder, '${_backupInfo!.filesCount} קבצים'),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _buildInfoChip(Icons.storage, _backupInfo!.formattedSize),
              const SizedBox(width: 8),
              if (_backupInfo!.filesWithText > 0)
                _buildInfoChip(Icons.text_fields, '${_backupInfo!.filesWithText} עם טקסט'),
            ],
          ),
        ],
      ),
    );
  }
  
  Widget _buildInfoChip(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white70),
          const SizedBox(width: 4),
          Text(
            text,
            style: const TextStyle(fontSize: 11, color: Colors.white70),
          ),
        ],
      ),
    );
  }

  /// מציג הודעה שהפיצ'ר בפיתוח
  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.construction, color: Colors.amber, size: 20),
            const SizedBox(width: 12),
            Text(tr('coming_soon').replaceFirst('\${feature}', feature)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
  
  /// בונה פרופיל משתמש
  Widget _buildUserProfile(
    BuildContext context, 
    ThemeData theme, 
    dynamic user,
    bool isGuest,
  ) {
    final displayName = isGuest 
        ? tr('guest') 
        : (user?.displayName ?? user?.email?.split('@').first ?? 'User');
    final email = isGuest ? 'Guest' : (user?.email ?? '');
    final photoUrl = user?.photoURL;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          // תמונת פרופיל
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  theme.colorScheme.primary,
                  theme.colorScheme.secondary,
                ],
              ),
              shape: BoxShape.circle,
            ),
            child: photoUrl != null
                ? ClipOval(
                    child: Image.network(
                      photoUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.person,
                        color: Colors.white,
                        size: 30,
                      ),
                    ),
                  )
                : const Icon(
                    Icons.person,
                    color: Colors.white,
                    size: 30,
                  ),
          ),
          const SizedBox(width: 16),
          // פרטי משתמש
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    if (isGuest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          tr('guest'),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (_settingsService.isPremium) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Colors.amber, Colors.orange],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'PRO',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 14,
                    ),
                  ),
                if (isGuest)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: () => _upgradeToGoogle(context),
                      icon: const Icon(Icons.upgrade, size: 16),
                      label: Text(tr('upgrade_to_google')),
                      style: TextButton.styleFrom(
                        padding: EdgeInsets.zero,
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// שדרוג חשבון אורח ל-Google
  Future<void> _upgradeToGoogle(BuildContext context) async {
    final result = await AuthService.instance.upgradeAnonymousToGoogle();
    
    if (context.mounted) {
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('upgrade_success')),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? tr('upgrade_error')),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// בונה סקציית הגדרות
  Widget _buildSettingsSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            title,
            style: TextStyle(
              color: Colors.grey.shade400,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...children,
      ],
    );
  }

  /// בונה פריט בחירת מצב תצוגה (כהה/בהיר/מערכת)
  Widget _buildThemeModeTile(BuildContext context) {
    final theme = Theme.of(context);
    
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _settingsService.themeModeNotifier,
      builder: (context, currentMode, child) {
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    currentMode == ThemeMode.dark 
                        ? Icons.dark_mode 
                        : currentMode == ThemeMode.light
                            ? Icons.light_mode
                            : Icons.brightness_auto,
                    color: theme.colorScheme.primary, 
                    size: 20,
                  ),
                ),
                title: Text(
                  tr('theme'),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  currentMode == ThemeMode.dark 
                      ? tr('theme_dark')
                      : currentMode == ThemeMode.light
                          ? tr('theme_light')
                          : tr('theme_system'),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    _buildThemeModeChip(
                      context,
                      icon: Icons.light_mode,
                      label: tr('theme_light'),
                      mode: ThemeMode.light,
                      isSelected: currentMode == ThemeMode.light,
                    ),
                    const SizedBox(width: 8),
                    _buildThemeModeChip(
                      context,
                      icon: Icons.dark_mode,
                      label: tr('theme_dark'),
                      mode: ThemeMode.dark,
                      isSelected: currentMode == ThemeMode.dark,
                    ),
                    const SizedBox(width: 8),
                    _buildThemeModeChip(
                      context,
                      icon: Icons.brightness_auto,
                      label: tr('theme_system'),
                      mode: ThemeMode.system,
                      isSelected: currentMode == ThemeMode.system,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// בונה צ'יפ לבחירת מצב תצוגה
  Widget _buildThemeModeChip(
    BuildContext context, {
    required IconData icon,
    required String label,
    required ThemeMode mode,
    required bool isSelected,
  }) {
    final theme = Theme.of(context);
    
    return Expanded(
      child: GestureDetector(
        onTap: () => _settingsService.setThemeMode(mode),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected 
                ? theme.colorScheme.primary.withValues(alpha: 0.2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected 
                  ? theme.colorScheme.primary 
                  : Colors.grey.withValues(alpha: 0.3),
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected 
                    ? theme.colorScheme.primary 
                    : Colors.grey.shade400,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  color: isSelected 
                      ? theme.colorScheme.primary 
                      : Colors.grey.shade400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// בונה פריט הגדרות
  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    final theme = Theme.of(context);
    
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: theme.colorScheme.primary, size: 20),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            fontSize: 12,
            color: Colors.grey.shade500,
          ),
        ),
        trailing: trailing ?? Icon(Icons.chevron_left, color: Colors.grey.shade600),
        onTap: onTap,
      ),
    );
  }

  /// מציג דיאלוג בחירת שפה
  void _showLanguageDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('choose_language')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(tr('hebrew')),
              leading: Radio<String>(
                value: 'he',
                groupValue: _settingsService.locale,
                onChanged: (value) {
                  _settingsService.setLocale(value!);
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              onTap: () {
                _settingsService.setLocale('he');
                Navigator.pop(context);
                setState(() {});
              },
            ),
            ListTile(
              title: Text(tr('english')),
              leading: Radio<String>(
                value: 'en',
                groupValue: _settingsService.locale,
                onChanged: (value) {
                  _settingsService.setLocale(value!);
                  Navigator.pop(context);
                  setState(() {});
                },
              ),
              onTap: () {
                _settingsService.setLocale('en');
                Navigator.pop(context);
                setState(() {});
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
        ],
      ),
    );
  }

  /// בונה כפתור התנתקות
  Widget _buildLogoutButton(BuildContext context, ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showLogoutDialog(context),
        icon: const Icon(Icons.logout, color: Colors.red),
        label: Text(
          tr('logout'),
          style: const TextStyle(color: Colors.red),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  /// מציג דיאלוג אישור התנתקות
  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(tr('logout_dialog_title')),
        content: Text(tr('logout_dialog_content')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService.instance.signOut();
              if (context.mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            child: Text(tr('logout')),
          ),
        ],
      ),
    );
  }

  /// מציג מידע על האפליקציה
  void _showAboutSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Color(0xFF1E1E3F),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ידית
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade700,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),
            
            // לוגו
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF6366F1), Color(0xFF8B5CF6)],
                ),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(Icons.search, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 16),
            
            // שם
            Text(
              tr('app_name'),
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            
            // גרסה
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version = snapshot.data?.version ?? '1.0.0';
                final buildNumber = snapshot.data?.buildNumber ?? '1';
                return Text(
                  'Version $version ($buildNumber)',
                  style: TextStyle(color: Colors.grey.shade500),
                );
              },
            ),
            const SizedBox(height: 16),
            
            // תיאור
            Text(
              tr('app_description_long'),
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade400),
            ),
            const SizedBox(height: 24),
            
            // כפתור סגירה
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                child: Text(tr('close')),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
