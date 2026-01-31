namespace TheHunterApi.Models;

/// <summary>
/// תשובת חיפוש סמנטי - מונחים ותאריכים
/// </summary>
public class SemanticSearchResponse
{
    public List<string> Terms { get; set; } = new();
    public string? DateFrom { get; set; }
    public string? DateTo { get; set; }
    public List<string> FileTypes { get; set; } = new();
}
