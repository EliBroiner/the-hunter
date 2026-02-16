namespace TheHunterApi.Models;

/// <summary>פריט מ-learned_knowledge — term, category, source_file. לסקירה ב-Admin ולהזרקה ל-SmartSearch.</summary>
public class LearnedKnowledgeItem
{
    public string FirestoreId { get; set; } = string.Empty;
    public string Term { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public string? SourceFile { get; set; }
    public string Status { get; set; } = "pending_approval"; // pending_approval | approved
    public DateTime CreatedAt { get; set; }
    public string? RegexPattern { get; set; }
}
