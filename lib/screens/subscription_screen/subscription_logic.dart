import 'package:purchases_flutter/purchases_flutter.dart';
import '../../services/localization_service.dart';

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
  final Package? rcPackage;

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

/// ממפה חבילות אמיתיות מ-RevenueCat
List<PricingPackage> mapRealPackages(List<Package> rcPackages) {
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

  packages.sort((a, b) => a.plan == SubscriptionPlan.monthly ? -1 : 1);
  return packages;
}

/// חבילות Mock לפיתוח
List<PricingPackage> getMockPackages() {
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
