import 'package:flutter/material.dart';

/// מסך הגדרות
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
            // כותרת
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.primary,
                              theme.colorScheme.secondary,
                            ],
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.settings,
                          color: Colors.white,
                          size: 20,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        'הגדרות האפליקציה',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'התאם את האפליקציה לצרכים שלך',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            
            // הגדרות עתידיות
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
          ],
        ),
      ),
    );
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
