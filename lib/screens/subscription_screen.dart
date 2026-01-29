import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../services/settings_service.dart';
import '../services/localization_service.dart';

/// סוג מנוי
enum SubscriptionPlan { monthly, yearly }

/// חבילה (אמיתית או Mock)
class PricingPackage {
  final String id;
  final String title;
  final String titleHe;
  final String price;
  final String period;
  final String? savings;
  final SubscriptionPlan plan;
  final Package? rcPackage; // null אם mock

  PricingPackage({
    required this.id,
    required this.title,
    required this.titleHe,
    required this.price,
    required this.period,
    this.savings,
    required this.plan,
    this.rcPackage,
  });
}

/// מסך מנויים - Hunter Pro
class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  // צבעי זהב לעיצוב פרימיום
  static const Color _goldPrimary = Color(0xFFFFD700);
  static const Color _goldDark = Color(0xFFB8860B);
  static const Color _goldLight = Color(0xFFFFF8DC);

  // מצב
  bool _isLoading = true;
  bool _isMockMode = false;
  bool _isPurchasing = false;
  String? _errorMessage;
  
  // חבילות
  List<PricingPackage> _packages = [];
  PricingPackage? _selectedPackage;
  
  // מונה לחיצות לbackdoor
  int _titleTapCount = 0;
  DateTime? _lastTapTime;

  @override
  void initState() {
    super.initState();
    _fetchOfferings();
  }

  /// שליפת חבילות מ-RevenueCat
  Future<void> _fetchOfferings() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final offerings = await Purchases.getOfferings();
      
      if (offerings.current != null && offerings.current!.availablePackages.isNotEmpty) {
        // יש חבילות אמיתיות מ-RevenueCat
        _packages = _mapRealPackages(offerings.current!.availablePackages);
        _isMockMode = false;
        print('RevenueCat: Loaded ${_packages.length} real packages');
      } else {
        // אין חבילות - מצב פיתוח (Mock)
        _packages = _getMockPackages();
        _isMockMode = true;
        print('RevenueCat: No offerings found, using MOCK mode');
      }
      
      // בחירת ברירת מחדל - שנתי
      _selectedPackage = _packages.firstWhere(
        (p) => p.plan == SubscriptionPlan.yearly,
        orElse: () => _packages.first,
      );
      
    } catch (e) {
      print('RevenueCat Error: $e');
      // במקרה של שגיאה - מצב Mock
      _packages = _getMockPackages();
      _isMockMode = true;
      _selectedPackage = _packages.last;
      _errorMessage = tr('dev_mode_active');
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  /// ממפה חבילות אמיתיות מ-RevenueCat
  List<PricingPackage> _mapRealPackages(List<Package> rcPackages) {
    final packages = <PricingPackage>[];
    
    for (final pkg in rcPackages) {
      final isMonthly = pkg.packageType == PackageType.monthly;
      final isYearly = pkg.packageType == PackageType.annual;
      
      if (isMonthly || isYearly) {
        packages.add(PricingPackage(
          id: pkg.identifier,
          title: isMonthly ? tr('plan_monthly') : tr('plan_yearly'),
          titleHe: isMonthly ? tr('plan_monthly_he') : tr('plan_yearly_he'),
          price: pkg.storeProduct.priceString,
          period: isMonthly ? '/month' : '/year',
          savings: isYearly ? 'Save 37%' : null,
          plan: isMonthly ? SubscriptionPlan.monthly : SubscriptionPlan.yearly,
          rcPackage: pkg,
        ));
      }
    }
    
    // מיון - חודשי קודם
    packages.sort((a, b) => a.plan == SubscriptionPlan.monthly ? -1 : 1);
    
    return packages;
  }

  /// חבילות Mock לפיתוח
  List<PricingPackage> _getMockPackages() {
    return [
      PricingPackage(
        id: 'mock_monthly',
        title: 'Monthly (Dev)',
        titleHe: 'חודשי (פיתוח)',
        price: '\$4.99',
        period: '/month',
        plan: SubscriptionPlan.monthly,
      ),
      PricingPackage(
        id: 'mock_yearly',
        title: 'Yearly (Dev)',
        titleHe: 'שנתי (פיתוח)',
        price: '\$29.99',
        period: '/year',
        savings: 'Save 50%',
        plan: SubscriptionPlan.yearly,
      ),
    ];
  }

  /// לחיצה על כותרת (backdoor)
  void _onTitleTap() {
    final now = DateTime.now();
    
    // איפוס אם עבר יותר משנייה מהלחיצה האחרונה
    if (_lastTapTime != null && now.difference(_lastTapTime!).inMilliseconds > 1000) {
      _titleTapCount = 0;
    }
    
    _titleTapCount++;
    _lastTapTime = now;
    
    if (_titleTapCount >= 3) {
      _titleTapCount = 0;
      _activateProBackdoor();
    }
  }

  /// Backdoor - הפעלת Pro ישירות
  Future<void> _activateProBackdoor() async {
    await SettingsService.instance.setIsPremium(true);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Row(
            children: [
              Icon(Icons.developer_mode, color: Colors.white),
              SizedBox(width: 8),
              Text('🔓 Dev Backdoor: Pro Activated!'),
            ],
          ),
          backgroundColor: Colors.purple,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
      
      // סגירת המסך
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  /// לחיצה על כפתור הרשמה
  Future<void> _onSubscribePressed() async {
    if (_selectedPackage == null) return;
    
    // בדיקה אם המשתמש הוא אורח
    if (AuthService.instance.isGuest) {
      final shouldLink = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('נדרש חשבון Google'),
          content: Text(tr('google_account_required_desc')),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(tr('cancel')),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(tr('link_account')),
            ),
          ],
        ),
      );

      if (shouldLink != true) return;

      setState(() => _isPurchasing = true);
      
      final result = await AuthService.instance.upgradeAnonymousToGoogle();
      
      setState(() => _isPurchasing = false);

      if (!result.success) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? tr('link_account_error')),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      
      // אם הצליח - ממשיכים לרכישה
    }
    
    setState(() => _isPurchasing = true);

    try {
      if (_isMockMode) {
        // מצב Mock - סימולציה של רכישה
        await Future.delayed(const Duration(seconds: 1));
        
        // בדיקה אם כבר יש מנוי (במצב Mock אנחנו מדמים שאין, אבל אם היה שרת אמיתי היינו בודקים)
        // במצב Mock, אם המשתמש כבר "רכש", ה-SettingsService כבר מעודכן.
        // אבל כאן אנחנו רוצים לדמות מצב שבו המשתמש לוחץ על רכישה למרות שיש לו מנוי.
        // במערכת אמיתית, RevenueCat יחזיר שגיאה או יגיד שהרכישה שוחזרה.
        
        // נבדוק אם כבר פרימיום
        if (SettingsService.instance.isPremium) {
           if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.info, color: Colors.white),
                    SizedBox(width: 8),
                    Text('You already have an active subscription!'),
                  ],
                ),
                backgroundColor: Colors.blue,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
            setState(() => _isPurchasing = false);
            return;
           }
        }

        await SettingsService.instance.setIsPremium(true);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 8),
                  Text('✨ Mock Purchase Successful! Pro Activated'),
                ],
              ),
              backgroundColor: Colors.green,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
          
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) Navigator.of(context).pop();
          });
        }
      } else {
        // רכישה אמיתית דרך RevenueCat
        
        // בדיקה מקדימה אם כבר יש מנוי פעיל
        final customerInfo = await Purchases.getCustomerInfo();
        if (customerInfo.entitlements.active.containsKey('pro') ||
            customerInfo.entitlements.active.containsKey('premium')) {
            
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Row(
                    children: [
                      Icon(Icons.info, color: Colors.white),
                      SizedBox(width: 8),
                      Text('You already have an active subscription!'),
                    ],
                  ),
                  backgroundColor: Colors.blue,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              );
              setState(() => _isPurchasing = false);
              return;
            }
        }

        final purchaseInfo = await Purchases.purchasePackage(_selectedPackage!.rcPackage!);
        
        // בדיקה אם יש entitlement פעיל
        final isPro = purchaseInfo.entitlements.active.containsKey('pro') ||
                      purchaseInfo.entitlements.active.containsKey('premium');
        
        if (isPro) {
          await SettingsService.instance.setIsPremium(true);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(tr('purchase_success')),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
            
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) Navigator.of(context).pop();
            });
          }
        }
      }
    } on PurchasesErrorCode catch (e) {
      print('Purchase Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('purchase_error').replaceFirst('\$error', e.toString()))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      print('Purchase Error: $e');
      // User cancelled - ignore
    }

    if (mounted) {
      setState(() => _isPurchasing = false);
    }
  }

  /// שחזור רכישות
  Future<void> _onRestorePurchases() async {
    setState(() => _isPurchasing = true);

    try {
      if (_isMockMode) {
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white),
                  SizedBox(width: 8),
                  Text('Mock Mode: No purchases to restore'),
                ],
              ),
              backgroundColor: Colors.blueGrey,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        final customerInfo = await Purchases.restorePurchases();
        
        final isPro = customerInfo.entitlements.active.containsKey('pro') ||
                      customerInfo.entitlements.active.containsKey('premium');
        
        if (isPro) {
          await SettingsService.instance.setIsPremium(true);
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.check_circle, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(tr('restore_subscription_success')),
                  ],
                ),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
            
            Future.delayed(const Duration(milliseconds: 500), () {
              if (mounted) Navigator.of(context).pop();
            });
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Row(
                  children: [
                    const Icon(Icons.info_outline, color: Colors.white),
                    const SizedBox(width: 8),
                    Text(tr('no_subscription_found')),
                  ],
                ),
                backgroundColor: Colors.blueGrey,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        }
      }
    } catch (e) {
      print('Restore Error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.white),
                const SizedBox(width: 8),
                Expanded(child: Text(tr('restore_error_with_details').replaceFirst('\$error', e.toString()))),
              ],
            ),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    }

    if (mounted) {
      setState(() => _isPurchasing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0F0F23),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator(color: _goldPrimary))
            : SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      // כפתור סגירה + תג Mock
                      Row(
                        children: [
                          IconButton(
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(Icons.close, color: Colors.white54),
                          ),
                          const Spacer(),
                          if (_isMockMode)
                            Container(
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
                                    style: const TextStyle(
                                      color: Colors.orange,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      // אייקון הכתר
                      _buildCrownIcon(),
                      const SizedBox(height: 24),

                      // כותרת (עם backdoor)
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
                      const SizedBox(height: 8),
                      // ניהול / ביטול מנוי (פותח את Play Store)
                      _buildManageSubscription(),
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

  /// כותרת ותיאור - עם backdoor על triple tap
  Widget _buildTitle() {
    return GestureDetector(
      onTap: _onTitleTap,
      child: Column(
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [_goldLight, _goldPrimary, _goldDark],
            ).createShader(bounds),
            child: Text(
              tr('subscription_title'),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: Colors.white,
                letterSpacing: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            tr('subscription_subtitle'),
            style: TextStyle(
              fontSize: 16,
              color: Colors.grey.shade400,
            ),
          ),
        ],
      ),
    );
  }

  /// רשימת יתרונות
  Widget _buildBenefitsList() {
    final benefits = [
      (tr('benefit_smart_search'), tr('benefit_smart_search_desc')),
      (tr('benefit_voice_search'), tr('benefit_voice_search_desc')),
      (tr('benefit_history'), tr('benefit_history_desc')),
      (tr('benefit_support'), tr('benefit_support_desc')),
      (tr('benefit_no_ads'), tr('benefit_no_ads_desc')),
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
    if (_packages.isEmpty) {
      return const Center(
        child: Text('No packages available', style: TextStyle(color: Colors.grey)),
      );
    }

    return Row(
      children: _packages.map((pkg) {
        final isFirst = _packages.indexOf(pkg) == 0;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(left: isFirst ? 0 : 6, right: isFirst ? 6 : 0),
            child: _buildPricingCard(pkg),
          ),
        );
      }).toList(),
    );
  }

  /// כרטיס מחיר בודד
  Widget _buildPricingCard(PricingPackage package) {
    final isSelected = _selectedPackage?.id == package.id;

    return GestureDetector(
      onTap: () => setState(() => _selectedPackage = package),
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
                // תג חסכון / Mock
                if (package.savings != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_goldPrimary, _goldDark],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      package.savings!,
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
                  package.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? _goldPrimary : Colors.white,
                  ),
                ),
                Text(
                  package.titleHe,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade500,
                  ),
                ),
                const SizedBox(height: 12),

                // מחיר
                Text(
                  package.price,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? _goldPrimary : Colors.white,
                  ),
                ),
                Text(
                  package.period,
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
        onPressed: _isPurchasing ? null : _onSubscribePressed,
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
            child: _isPurchasing
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      color: Colors.black,
                      strokeWidth: 2,
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.star, color: Colors.black, size: 22),
                      const SizedBox(width: 10),
                      Text(
                        tr('subscribe_now'),
                        style: const TextStyle(
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

  /// שחזור רכישות
  Widget _buildRestorePurchases() {
    return TextButton(
      onPressed: _isPurchasing ? null : _onRestorePurchases,
      child: Text(
        tr('restore_purchases'),
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 14,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  /// ניהול / ביטול מנוי – פותח את דף המנויים ב-Play Store
  Widget _buildManageSubscription() {
    return TextButton.icon(
      onPressed: _isPurchasing ? null : _openManageSubscription,
      icon: Icon(Icons.settings, size: 16, color: Colors.grey.shade500),
      label: Text(
        tr('manage_subscription'),
        style: TextStyle(
          color: Colors.grey.shade500,
          fontSize: 14,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }

  Future<void> _openManageSubscription() async {
    // Android: דף המנויים של המשתמש ב-Play Store
    final uri = Uri.parse('https://play.google.com/store/account/subscriptions');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  /// הערות משפטיות
  Widget _buildDisclaimer() {
    return Text(
      _isMockMode
          ? tr('dev_mode_desc')
          : tr('subscription_disclaimer'),
      textAlign: TextAlign.center,
      style: TextStyle(
        color: _isMockMode ? Colors.orange.shade300 : Colors.grey.shade600,
        fontSize: 11,
        height: 1.4,
      ),
    );
  }
}
