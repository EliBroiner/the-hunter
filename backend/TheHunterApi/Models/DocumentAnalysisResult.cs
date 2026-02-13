namespace TheHunterApi.Models;

/// <summary>תוצאת ניתוח AI למסמך בודד</summary>
public class DocumentAnalysisResult
{
    public string Category { get; set; } = string.Empty;
    public string? Date { get; set; }  // YYYY-MM-DD
    public List<string> Tags { get; set; } = new();
    public string Summary { get; set; } = string.Empty;
    /// <summary>הצעות ייעול Gemini — מילים ו-Regex למילון/חוקים מקומיים.</summary>
    public List<AiSuggestion> Suggestions { get; set; } = new();
}
