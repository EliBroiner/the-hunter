import 'package:flutter/material.dart';
import '../../../services/localization_service.dart';
import '../subscription_logic.dart';

/// צבעי זהב לעיצוב פרימיום
const Color _goldPrimary = Color(0xFFFFD700);
const Color _goldDark = Color(0xFFB8860B);

/// אייקון כתר מוזהב
class SubscriptionCrownIcon extends StatelessWidget {
  const SubscriptionCrownIcon({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_goldPrimary, _goldDark],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: _goldPrimary.withValues(alpha: 0.4),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: const Icon(
        Icons.workspace_premium,
        color: Color(0xFF1E1E3F),
        size: 50,
      ),
    );
  }
}

/// תגית חיסכון
class SubscriptionSavingsBadge extends StatelessWidget {
  const SubscriptionSavingsBadge({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_goldPrimary, _goldDark]),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.black, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// כרטיס מחיר בודד
class SubscriptionPricingCard extends StatelessWidget {
  const SubscriptionPricingCard({
    super.key,
    required this.package,
    required this.isSelected,
    required this.onTap,
  });

  final PricingPackage package;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surfaceContainerHighest;
    final onSurface = theme.colorScheme.onSurface;
    final onVariant = theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? _goldPrimary.withValues(alpha: 0.1) : surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _goldPrimary : onVariant.withValues(alpha: 0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [BoxShadow(color: _goldPrimary.withValues(alpha: 0.2), blurRadius: 15)] : null,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                if (package.savings != null) SubscriptionSavingsBadge(text: package.savings!) else const SizedBox(height: 22),
                const SizedBox(height: 8),
                Text(
                  package.title,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: isSelected ? _goldPrimary : onSurface),
                ),
                Text(package.titleHe, style: TextStyle(fontSize: 12, color: onVariant)),
                const SizedBox(height: 12),
                Text(
                  package.price,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: isSelected ? _goldPrimary : onSurface),
                ),
                Text(package.period, style: TextStyle(fontSize: 12, color: onVariant)),
              ],
            ),
            if (isSelected) const _PricingCardCheckMark(),
          ],
        ),
      ),
    );
  }
}

class _PricingCardCheckMark extends StatelessWidget {
  const _PricingCardCheckMark();

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      right: 0,
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: const BoxDecoration(color: _goldPrimary, shape: BoxShape.circle),
        child: const Icon(Icons.check, color: Colors.black, size: 14),
      ),
    );
  }
}

/// תגית מצב Mock
class SubscriptionMockBadge extends StatelessWidget {
  const SubscriptionMockBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.developer_mode, color: Colors.orange, size: 14),
          const SizedBox(width: 4),
          Text(
            tr('dev_mode_badge'),
            style: const TextStyle(color: Colors.orange, fontSize: 10, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
