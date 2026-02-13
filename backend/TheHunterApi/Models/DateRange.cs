namespace TheHunterApi.Models;

/// <summary>טווח תאריכים בפורמט ISO 8601</summary>
public class DateRange
{
    /// <summary>תאריך התחלה בפורמט yyyy-MM-dd</summary>
    public string? Start { get; set; }
    /// <summary>תאריך סיום בפורמט yyyy-MM-dd</summary>
    public string? End { get; set; }
}
