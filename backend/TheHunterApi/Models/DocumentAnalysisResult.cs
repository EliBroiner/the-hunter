using System.Text.Json.Serialization;

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
    /// <summary>דגל: true אם הטקסט מקוטע או המבנה שבור — דורש OCR ברזולוציה גבוהה.</summary>
    [JsonPropertyName("requires_high_res_ocr")]
    public bool RequiresHighResOcr { get; set; }
    /// <summary>מטא־דאטה מחולצת — שמות, מזהים, מיקומים (לא ב-tags)</summary>
    public DocumentMetadata? Metadata { get; set; }
}
