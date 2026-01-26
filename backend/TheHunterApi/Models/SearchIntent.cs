namespace TheHunterApi.Models;

/// <summary>
/// תוצאת הפענוח של שאילתת חיפוש בשפה טבעית
/// </summary>
public class SearchIntent
{
    /// <summary>
    /// מילות מפתח לחיפוש - כולל תרגומים ומילים נרדפות
    /// </summary>
    public List<string> Terms { get; set; } = new();
    
    /// <summary>
    /// סיומות קבצים לסינון (pdf, jpg, docx וכו')
    /// </summary>
    public List<string> FileTypes { get; set; } = new();
    
    /// <summary>
    /// טווח תאריכים לסינון - null אם לא צוין
    /// </summary>
    public DateRange? DateRange { get; set; }
}

/// <summary>
/// טווח תאריכים בפורמט ISO 8601
/// </summary>
public class DateRange
{
    /// <summary>
    /// תאריך התחלה בפורמט yyyy-MM-dd
    /// </summary>
    public string? Start { get; set; }
    
    /// <summary>
    /// תאריך סיום בפורמט yyyy-MM-dd
    /// </summary>
    public string? End { get; set; }
}

/// <summary>
/// בקשת חיפוש מהלקוח
/// </summary>
public class SearchRequest
{
    /// <summary>
    /// שאילתת החיפוש בשפה טבעית
    /// </summary>
    public string Query { get; set; } = string.Empty;
}

/// <summary>
/// תשובת שגיאה
/// </summary>
public class ErrorResponse
{
    public string Error { get; set; } = string.Empty;
    public string? Details { get; set; }
}
