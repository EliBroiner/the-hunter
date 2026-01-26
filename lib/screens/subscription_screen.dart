import 'package:flutter/material.dart';

/// סוג מנוי
enum SubscriptionPlan { monthly, yearly }

/// מסך מנויים - Hunter Pro
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  SubscriptionPlan _selectedPlan = SubscriptionPlan.yearly;

  // צבעי זהב לעיצוב פרימיום
  static const Color _goldPrimary = Color(0xFFFFD700);
  static const Color _goldDark = Color(0xFFB8860B);
  static const Color _goldLight = Color(0xFFFFF8DC);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                // כפתור סגירה
                Align(
                  alignment: Alignment.topLeft,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, color: Colors.white54),
                  ),
                ),

                // אייקון הכתר
                _buildCrownIcon(),
                const SizedBox(height: 24),

                // כותרת
                _buildTitle(),
                const SizedBox(height: 32),

                // רשימת יתרונות
                _buildBenefitsList(),
                const SizedBox(height: 32),

                // כרטיסי מחיר
                _buildPricingCards(),
                const SizedBox(height: 32),

                // כפתור הרשמה
                _buildSubscribeButton(),
                const SizedBox(height: 16),

                // שחזור רכישות
                _buildRestorePurchases(),
                const SizedBox(height: 24),

                // הערות קטנות
                _buildDisclaimer(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// אייקון כתר מוזהב
  Widget _buildCrownIcon() {
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

  /// כותרת ותיאור
  Widget _buildTitle() {
    return Column(
      children: [
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [_goldLight, _goldPrimary, _goldDark],
          ).createShader(bounds),
          child: const Text(
            'Hunter Pro',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Upgrade to unlock all features',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey.shade400,
          ),
        ),
      ],
    );
  }

  /// רשימת יתרונות
  Widget _buildBenefitsList() {
    final benefits = [
      ('Smart AI Search', 'חיפוש חכם עם בינה מלאכותית'),
      ('Voice Search', 'חיפוש קולי בעברית ואנגלית'),
      ('Unlimited History', 'היסטוריית חיפושים ללא הגבלה'),
      ('Priority Support', 'תמיכה מועדפת 24/7'),
      ('No Ads', 'ללא פרסומות'),
    ];

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1E1E3F),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: _goldPrimary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: benefits.map((benefit) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: _goldPrimary.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: _goldPrimary,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        benefit.$1,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        benefit.$2,
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  /// כרטיסי מחירים
  Widget _buildPricingCards() {
    return Row(
      children: [
        Expanded(
          child: _buildPricingCard(
            plan: SubscriptionPlan.monthly,
            title: 'Monthly',
            titleHe: 'חודשי',
            price: '₪19.99',
            period: '/month',
            savings: null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildPricingCard(
            plan: SubscriptionPlan.yearly,
            title: 'Yearly',
            titleHe: 'שנתי',
            price: '₪149.99',
            period: '/year',
            savings: 'Save 37%',
          ),
        ),
      ],
    );
  }

  /// כרטיס מחיר בודד
  Widget _buildPricingCard({
    required SubscriptionPlan plan,
    required String title,
    required String titleHe,
    required String price,
    required String period,
    String? savings,
  }) {
    final isSelected = _selectedPlan == plan;

    return GestureDetector(
      onTap: () => setState(() => _selectedPlan = plan),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected 
              ? _goldPrimary.withValues(alpha: 0.1) 
              : const Color(0xFF1E1E3F),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? _goldPrimary : Colors.grey.shade800,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: _goldPrimary.withValues(alpha: 0.2),
                    blurRadius: 15,
                  ),
                ]
              : null,
        ),
        child: Stack(
          children: [
            Column(
              children: [
                // תג חסכון
                if (savings != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_goldPrimary, _goldDark],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      savings,
                      style: const TextStyle(
                        color: Colors.black,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  )
                else
                  const SizedBox(height: 22),
                const SizedBox(height: 8),

                // כותרת
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? _goldPrimary : Colors.white,
                  ),
                ),
                Text(
                  titleHe,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 12),

                // מחיר
                Text(
                  price,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? _goldPrimary : Colors.white,
                  ),
                ),
                Text(
                  period,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ),

            // אינדיקטור בחירה
            if (isSelected)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                    color: _goldPrimary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.black,
                    size: 14,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// כפתור הרשמה
  Widget _buildSubscribeButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _onSubscribePressed,
        style: ElevatedButton.styleFrom(
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: 8,
          shadowColor: _goldPrimary.withValues(alpha: 0.5),
        ),
        child: Ink(
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_goldPrimary, _goldDark],
            ),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Container(
            alignment: Alignment.center,
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.star, color: Colors.black, size: 22),
                SizedBox(width: 10),
                Text(
                  'Subscribe Now',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// לחיצה על כפתור הרשמה
  void _onSubscribePressed() {
    final planName = _selectedPlan == SubscriptionPlan.monthly 
        ? 'Monthly' 
        : 'Yearly';
    print('Subscribe clicked - Plan: $planName');
    
    // TODO: לוגיקת תשלום תיווסף בהמשך
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.white),
            const SizedBox(width: 8),
            Text('Selected plan: $planName (Payment coming soon)'),
          ],
        ),
        backgroundColor: _goldDark,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// שחזור רכישות
  Widget _buildRestorePurchases() {
    return TextButton(
      onPressed: _onRestorePurchases,
      child: Text(
        'Restore Purchases',
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 14,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  /// לחיצה על שחזור רכישות
  void _onRestorePurchases() {
    print('Restore purchases clicked');
    
    // TODO: לוגיקת שחזור רכישות תיווסף בהמשך
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Row(
          children: [
            Icon(Icons.restore, color: Colors.white),
            SizedBox(width: 8),
            Text('Checking for previous purchases...'),
          ],
        ),
        backgroundColor: Colors.blueGrey,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// הערות משפטיות
  Widget _buildDisclaimer() {
    return Text(
      'Payment will be charged to your Google Play account. '
      'Subscription automatically renews unless canceled at least '
      '24 hours before the end of the current period.',
      textAlign: TextAlign.center,
      style: TextStyle(
        color: Colors.grey.shade600,
        fontSize: 11,
        height: 1.4,
      ),
    );
  }
}
