namespace TheHunterApi.Models;

/// <summary>בקשת חיפוש מהלקוח. פרומפט: DB (Search) או adminPromptOverride אם Admin.</summary>
public class SearchRequest
{
    public string Query { get; set; } = string.Empty;
    public string? UserId { get; set; }
    public string? AdminPromptOverride { get; set; }
}
