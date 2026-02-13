namespace TheHunterApi.Models;

/// <summary>תוצאת ניתוח מסמך בודד עם מזהה</summary>
public class DocumentAnalysisResponse
{
    public string DocumentId { get; set; } = string.Empty;
    public DocumentAnalysisResult Result { get; set; } = new();
}
