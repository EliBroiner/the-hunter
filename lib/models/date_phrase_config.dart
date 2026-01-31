/// הגדרת ביטוי תאריך — pattern + type (today/yesterday) או days (מספר ימים אחורה)
class DatePhraseConfig {
  final String pattern;
  final String? type;
  final int? days;

  DatePhraseConfig({required this.pattern, this.type, this.days});

  factory DatePhraseConfig.fromJson(Map<String, dynamic> json) {
    return DatePhraseConfig(
      pattern: json['pattern'] as String? ?? '',
      type: json['type'] as String?,
      days: json['days'] as int?,
    );
  }

  /// מחזיר (dateFrom, dateTo) לפי now
  (DateTime, DateTime) getRange(DateTime now) {
    if (type == 'today') {
      final start = DateTime(now.year, now.month, now.day);
      final end = start.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      return (start, end);
    }
    if (type == 'yesterday') {
      final start = now.subtract(const Duration(days: 1));
      final startOfDay = DateTime(start.year, start.month, start.day);
      final end = startOfDay.add(const Duration(hours: 23, minutes: 59, seconds: 59));
      return (startOfDay, end);
    }
    if (days != null && days! > 0) {
      final end = now;
      final start = now.subtract(Duration(days: days!));
      return (start, end);
    }
    final start = DateTime(now.year, now.month, now.day);
    return (start, start.add(const Duration(hours: 23, minutes: 59, seconds: 59)));
  }
}
