import 'package:geocoding/geocoding.dart';

/// שירות העשרת מיקום — גיאוקודינג עם locale אנגלי כדי לשמור "Thailand" וכו' להתאמה למילים נרדפות
class LocationEnrichmentService {
  LocationEnrichmentService._();

  static LocationEnrichmentService? _instance;

  static LocationEnrichmentService get instance {
    _instance ??= LocationEnrichmentService._();
    return _instance!;
  }

  /// מזהה לוקאל לגיאוקודינג — תמיד אנגלית (en_US) כדי שהשמות יתאימו למילים הנרדפות באנגלית
  static const String _localeIdentifier = 'en_US';

  bool _localeSet = false;

  /// מגדיר את הלוקאל ל־en_US לפני גיאוקודינג (קריאה פעם אחת מספיקה)
  Future<void> _ensureLocaleEnUs() async {
    if (_localeSet) return;
    await setLocaleIdentifier(_localeIdentifier);
    _localeSet = true;
  }

  /// Reverse geocoding: קואורדינטות → שם מקום באנגלית (למשל "Thailand").
  /// משתמש ב־localeIdentifier: 'en_US' כדי שהתוצאה תתאים למילים הנרדפות.
  Future<String?> getPlaceNameFromCoordinates(double latitude, double longitude) async {
    try {
      await _ensureLocaleEnUs();
      final placemarks = await placemarkFromCoordinates(latitude, longitude);
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      // עדיפות: מדינה (Thailand) או locality
      if (p.country != null && p.country!.isNotEmpty) return p.country;
      if (p.locality != null && p.locality!.isNotEmpty) return p.locality;
      if (p.administrativeArea != null && p.administrativeArea!.isNotEmpty) return p.administrativeArea;
      return p.name;
    } catch (_) {
      return null;
    }
  }
}
