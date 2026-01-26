/// מודל לתוצאת פענוח שאילתה מ-Gemini API
class SearchIntent {
  final List<String> terms;
  final List<String> fileTypes;
  final DateRange? dateRange;

  SearchIntent({
    required this.terms,
    required this.fileTypes,
    this.dateRange,
  });

  /// יצירת אובייקט מ-JSON
  factory SearchIntent.fromJson(Map<String, dynamic> json) {
    return SearchIntent(
      terms: List<String>.from(json['terms'] ?? []),
      fileTypes: List<String>.from(json['fileTypes'] ?? []),
      dateRange: json['dateRange'] != null 
          ? DateRange.fromJson(json['dateRange']) 
          : null,
    );
  }

  /// המרה ל-JSON
  Map<String, dynamic> toJson() => {
    'terms': terms,
    'fileTypes': fileTypes,
    'dateRange': dateRange?.toJson(),
  };

  /// בודק אם יש תוכן משמעותי
  bool get hasContent => terms.isNotEmpty || fileTypes.isNotEmpty || dateRange != null;

  @override
  String toString() => 'SearchIntent(terms: $terms, fileTypes: $fileTypes, dateRange: $dateRange)';
}

/// טווח תאריכים
class DateRange {
  final String? start; // פורמט: yyyy-MM-dd
  final String? end;   // פורמט: yyyy-MM-dd

  DateRange({this.start, this.end});

  factory DateRange.fromJson(Map<String, dynamic> json) {
    return DateRange(
      start: json['start'],
      end: json['end'],
    );
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
  };

  /// ממיר לאובייקט DateTime
  DateTime? get startDate => start != null ? DateTime.tryParse(start!) : null;
  DateTime? get endDate => end != null ? DateTime.tryParse(end!) : null;

  @override
  String toString() => 'DateRange(start: $start, end: $end)';
}
