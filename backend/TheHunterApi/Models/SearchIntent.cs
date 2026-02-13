namespace TheHunterApi.Models;

/// <summary>תוצאת הפענוח של שאילתת חיפוש בשפה טבעית</summary>
public class SearchIntent
{
    public List<string> Terms { get; set; } = new();
    public List<string> FileTypes { get; set; } = new();
    public DateRange? DateRange { get; set; }
}
