namespace TheHunterApi.Models;

/// <summary>
/// פריט מאוחד מ-smart_categories — sourceType: "term" | "rule".
/// </summary>
public class UnifiedDictionaryItem
{
    public string SourceType { get; set; } = ""; // "term" | "rule"
    public string DocumentId { get; set; } = "";

    // term
    public string? Term { get; set; }
    public string? Category { get; set; }
    public int Frequency { get; set; }
    public string? Definition { get; set; }
    public string? UserId { get; set; }
    public DateTime LastModified { get; set; }

    // rule
    public string? Key { get; set; }
    public Dictionary<string, string> DisplayNames { get; set; } = new();
    public List<string> Keywords { get; set; } = new();
    public List<string> RegexPatterns { get; set; } = new();
}
