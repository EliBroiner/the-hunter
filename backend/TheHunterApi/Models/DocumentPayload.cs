namespace TheHunterApi.Models;

/// <summary>מטען מסמך לבקשה — טקסט חולץ (OCR) + filename להקשר. לא קובץ מצורף.</summary>
public class DocumentPayload
{
    public string Id { get; set; } = string.Empty;
    /// <summary>שם קובץ להקשר — נשלח מהלקוח לצורכי לוג.</summary>
    public string? Filename { get; set; }
    /// <summary>תוכן טקסט חולץ (OCR) — זה מה שנשלח ל-Gemini.</summary>
    public string Text { get; set; } = string.Empty;
}
