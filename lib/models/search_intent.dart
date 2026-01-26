/// מודל intent לחיפוש חכם - מגיע מהבקאנד
class SearchIntent {
  final List<String> terms;
  final List<String> fileTypes;
  final DateRange? dateRange;

  SearchIntent({
    required this.terms,
    required this.fileTypes,
    this.dateRange,
  });

  factory SearchIntent.fromJson(Map<String, dynamic> json) {
    return SearchIntent(
      terms: (json['terms'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      fileTypes: (json['fileTypes'] as List<dynamic>?)
          ?.map((e) => e.toString())
          .toList() ?? [],
      dateRange: json['dateRange'] != null
          ? DateRange.fromJson(json['dateRange'] as Map<String, dynamic>)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'terms': terms,
    'fileTypes': fileTypes,
    'dateRange': dateRange?.toJson(),
  };

  /// האם יש תוכן לחיפוש
  bool get hasContent => terms.isNotEmpty || fileTypes.isNotEmpty || dateRange != null;

  @override
  String toString() => 'SearchIntent(terms: $terms, fileTypes: $fileTypes, dateRange: $dateRange)';
}

/// טווח תאריכים
class DateRange {
  final String? start; // Format: yyyy-MM-dd
  final String? end;   // Format: yyyy-MM-dd

  DateRange({this.start, this.end});

  factory DateRange.fromJson(Map<String, dynamic> json) {
    return DateRange(
      start: json['start'] as String?,
      end: json['end'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'start': start,
    'end': end,
  };

  DateTime? get startDate => start != null ? DateTime.tryParse(start!) : null;
  DateTime? get endDate => end != null ? DateTime.tryParse(end!) : null;

  @override
  String toString() => 'DateRange($start to $end)';
}
