namespace TheHunterApi.Models;

/// <summary>בקשת ניתוח דיבאג (AI Lab). פרומפט: DocumentAnalysis (default), DocumentTrainer (useTrainerPrompt=true), או adminPromptOverride.</summary>
public class DebugAnalyzeRequest
{
    public string Text { get; set; } = string.Empty;
    public string? UserId { get; set; }
    public string? AdminPromptOverride { get; set; }
    /// <summary>true = השתמש ב-DocumentTrainer (doc_analysis_learning) — למידה והצעות keywords/regex.</summary>
    public bool UseTrainerPrompt { get; set; }
}
