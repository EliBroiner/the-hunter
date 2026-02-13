namespace TheHunterApi.Models;

/// <summary>בקשת ניתוח דיבאג (AI Lab). פרומפט: DB (DocAnalysis) או adminPromptOverride אם Admin.</summary>
public class DebugAnalyzeRequest
{
    public string Text { get; set; } = string.Empty;
    public string? UserId { get; set; }
    public string? AdminPromptOverride { get; set; }
}
