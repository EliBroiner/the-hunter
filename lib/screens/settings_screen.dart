import 'package:flutter/material.dart';
import '../services/auth_service.dart';

/// מסך הגדרות
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final authService = AuthService.instance;
    final user = authService.currentUser;
    final isGuest = authService.isGuest;

    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'הגדרות',
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
            
            // הגדרות כלליות
            _buildSettingsSection(
              context,
              'כללי',
              [
                _buildSettingsTile(
                  context,
                  icon: Icons.language,
                  title: 'שפה',
                  subtitle: 'עברית',
                  onTap: () {},
                ),
                _buildSettingsTile(
                  context,
                  icon: Icons.dark_mode,
                  title: 'מצב כהה',
                  subtitle: 'פעיל',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildSettingsSection(
              context,
              'סריקה',
              [
                _buildSettingsTile(
                  context,
                  icon: Icons.folder,
                  title: 'תיקיות לסריקה',
                  subtitle: 'בחר תיקיות',
                  onTap: () {},
                ),
                _buildSettingsTile(
                  context,
                  icon: Icons.text_fields,
                  title: 'חילוץ טקסט (OCR)',
                  subtitle: 'פעיל',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: 16),
            
            _buildSettingsSection(
              context,
              'אודות',
              [
                _buildSettingsTile(
                  context,
                  icon: Icons.info_outline,
                  title: 'גרסה',
                  subtitle: '1.0.0',
                  onTap: () {},
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
  
  /// בונה פרופיל משתמש
  Widget _buildUserProfile(
    BuildContext context, 
    ThemeData theme, 
    dynamic user,
    bool isGuest,
  ) {
    final displayName = isGuest 
        ? 'אורח' 
        : (user?.displayName ?? user?.email?.split('@').first ?? 'משתמש');
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
                : Icon(
                    isGuest ? Icons.person_outline : Icons.person,
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
                    Flexible(
                      child: Text(
                        displayName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isGuest) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'אורח',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.orange,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  email,
                  style: TextStyle(
                    color: Colors.grey.shade500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          
          // כפתור שדרוג לאורחים
          if (isGuest)
            TextButton.icon(
              onPressed: () => _upgradeToGoogle(context),
              icon: const Icon(Icons.upgrade, size: 18),
              label: const Text('שדרג'),
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
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
            content: const Text('החשבון שודרג בהצלחה!'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
        Navigator.of(context).pop(); // חזרה למסך הקודם
      } else if (result.errorMessage != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.errorMessage!),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }
  }
  
  /// בונה כפתור התנתקות
  Widget _buildLogoutButton(BuildContext context, ThemeData theme) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showLogoutDialog(context),
        icon: const Icon(Icons.logout, color: Colors.red),
        label: const Text(
          'התנתק',
          style: TextStyle(color: Colors.red),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Colors.red),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
  
  /// מציג דיאלוג אישור התנתקות
  Future<void> _showLogoutDialog(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('התנתקות'),
        content: const Text('האם אתה בטוח שברצונך להתנתק?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('ביטול'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text('התנתק'),
          ),
        ],
      ),
    );
    
    if (confirmed == true && context.mounted) {
      await AuthService.instance.signOut();
      if (context.mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    }
  }

  /// בונה סקשן הגדרות
  Widget _buildSettingsSection(
    BuildContext context,
    String title,
    List<Widget> children,
  ) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(children: children),
        ),
      ],
    );
  }

  /// בונה פריט הגדרה בודד
  Widget _buildSettingsTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: theme.colorScheme.primary, size: 20),
      ),
      title: Text(title),
      subtitle: Text(
        subtitle,
        style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_left,
        color: Colors.grey.shade500,
      ),
      onTap: onTap,
    );
  }
}
