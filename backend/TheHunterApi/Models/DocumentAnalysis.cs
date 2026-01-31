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
}

/// <summary>
/// מטען מסמך לבקשה
/// </summary>
public class DocumentPayload
{
    public string Id { get; set; } = string.Empty;
    public string Text { get; set; } = string.Empty;
}

/// <summary>
/// בקשת אצווה לניתוח מסמכים
/// </summary>
public class BatchRequest
{
    public string UserId { get; set; } = string.Empty;
    public List<DocumentPayload> Documents { get; set; } = new();
}

/// <summary>
/// תוצאת ניתוח מסמך בודד עם מזהה
/// </summary>
public class DocumentAnalysisResponse
{
    public string DocumentId { get; set; } = string.Empty;
    public DocumentAnalysisResult Result { get; set; } = new();
}
