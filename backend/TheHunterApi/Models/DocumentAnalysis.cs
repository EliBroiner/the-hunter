namespace TheHunterApi.Models;

/// <summary>
/// תוצאת ניתוח AI למסמך בודד
/// </summary>
public class DocumentAnalysisResult
{
    public string Category { get; set; } = string.Empty;
    public string? Date { get; set; }  // YYYY-MM-DD
    public List<string> Tags { get; set; } = new();
    public string Summary { get; set; } = string.Empty;

    /// <summary>הצעות ייעול Gemini — מילים ו-Regex למילון/חוקים מקומיים.</summary>
    public List<AiSuggestion> Suggestions { get; set; } = new();
}

/// <summary>
/// מטען מסמך לבקשה — טקסט חולץ (OCR) + filename להקשר. לא קובץ מצורף.
/// </summary>
public class DocumentPayload
{
    public string Id { get; set; } = string.Empty;
    /// <summary>שם קובץ להקשר — נשלח מהלקוח לצורכי לוג.</summary>
    public string? Filename { get; set; }
    /// <summary>תוכן טקסט חולץ (OCR) — זה מה שנשלח ל-Gemini.</summary>
    public string Text { get; set; } = string.Empty;
}

/// <summary>
/// בקשת אצווה לניתוח מסמכים
/// </summary>
public class BatchRequest
{
    public string UserId { get; set; } = string.Empty;
    public List<DocumentPayload> Documents { get; set; } = new();

    /// <summary>
    /// דריסת פרומפט לניתוח — רק למשתמשי Admin (מתעלמים אם המשתמש לא Admin).
    /// </summary>
    public string? CustomPromptOverride { get; set; }
}

/// <summary>
/// תוצאת ניתוח מסמך בודד עם מזהה
/// </summary>
public class DocumentAnalysisResponse
{
    public string DocumentId { get; set; } = string.Empty;
    public DocumentAnalysisResult Result { get; set; } = new();
}

/// <summary>
/// בקשת ניתוח דיבאג — טקסט + פרומפט מותאם (AI Lab)
/// </summary>
public class DebugAnalyzeRequest
{
    public string Text { get; set; } = string.Empty;
    public string? CustomPrompt { get; set; }
}
