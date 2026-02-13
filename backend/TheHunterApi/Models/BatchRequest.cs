namespace TheHunterApi.Models;

/// <summary>בקשת אצווה לניתוח מסמכים. פרומפט: DB (DocAnalysis) או adminPromptOverride אם Admin.</summary>
public class BatchRequest
{
    public string UserId { get; set; } = string.Empty;
    public List<DocumentPayload> Documents { get; set; } = new();
    /// <summary>דריסת פרומפט — משתמש רק אם המשתמש Admin. מבוקש ללוג.</summary>
    public string? AdminPromptOverride { get; set; }
}
