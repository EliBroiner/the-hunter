import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';

/// סקציית הגדרות — כותרת + רשימת פריטים
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
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
}

/// פריט הגדרות — אייקון, כותרת, תת־כותרת, onTap
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.titleColor,
    this.iconColor,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final Color? titleColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveColor = iconColor ?? titleColor ?? theme.colorScheme.primary;

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
            color: effectiveColor.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: effectiveColor, size: 20),
        ),
        title: Text(
          title,
          style: TextStyle(fontWeight: FontWeight.w600, color: titleColor),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
        ),
        trailing: trailing ?? Icon(Icons.chevron_left, color: Colors.grey.shade600),
        onTap: onTap,
      ),
    );
  }
}

/// צ'יפ מידע — אייקון + טקסט
class SettingsInfoChip extends StatelessWidget {
  const SettingsInfoChip({
    super.key,
    required this.theme,
    required this.icon,
    required this.text,
    required this.chipColor,
  });

  final ThemeData theme;
  final IconData icon;
  final String text;
  final Color chipColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: chipColor.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: chipColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: chipColor),
          const SizedBox(width: 6),
          Text(
            text,
            style: TextStyle(fontSize: 12, color: chipColor),
          ),
        ],
      ),
    );
  }
}

/// שכבת התקדמות — מציגה הודעה + CircularProgressIndicator
class SettingsProgressOverlay extends StatelessWidget {
  const SettingsProgressOverlay({
    super.key,
    required this.theme,
    required this.message,
  });

  final ThemeData theme;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: theme.scaffoldBackgroundColor.withValues(alpha: 0.95),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(color: theme.colorScheme.primary),
              ),
              const SizedBox(height: 16),
              Text(message, style: theme.textTheme.titleMedium),
            ],
          ),
        ),
      ),
    );
  }
}

/// כרטיס פרופיל משתמש
class SettingsUserProfileCard extends StatelessWidget {
  const SettingsUserProfileCard({
    super.key,
    required this.theme,
    required this.displayName,
    required this.email,
    this.photoUrl,
    required this.isGuest,
    required this.isPremium,
    this.onUpgrade,
  });

  final ThemeData theme;
  final String displayName;
  final String email;
  final String? photoUrl;
  final bool isGuest;
  final bool isPremium;
  final VoidCallback? onUpgrade;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          _buildAvatar(
            photoUrl: photoUrl,
            primary: theme.colorScheme.primary,
            secondary: theme.colorScheme.secondary,
          ),
          const SizedBox(width: 16),
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
                      _buildBadge(tr('guest'), Colors.orange),
                    ],
                    if (isPremium) ...[
                      const SizedBox(width: 8),
                      _buildProBadge(),
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
                if (isGuest && onUpgrade != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: TextButton.icon(
                      onPressed: onUpgrade,
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

  Widget _buildAvatar({
    required String? photoUrl,
    required Color primary,
    required Color secondary,
  }) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [primary, secondary]),
        shape: BoxShape.circle,
      ),
      child: photoUrl != null
          ? ClipOval(
              child: Image.network(
                photoUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(Icons.person, color: Colors.white, size: 30),
              ),
            )
          : const Icon(Icons.person, color: Colors.white, size: 30),
    );
  }

  Widget _buildBadge(String text, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildProBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [Colors.amber, Colors.orange]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: const Text(
        'PRO',
        style: TextStyle(fontSize: 10, color: Colors.black, fontWeight: FontWeight.bold),
      ),
    );
  }
}
