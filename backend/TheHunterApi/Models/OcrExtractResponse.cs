namespace TheHunterApi.Models;

/// <summary>
/// תשובת OCR Fallback — טקסט מחולץ מתמונה (Cloud Vision או Gemini).
/// כשמורץ Gemini Tagging — כולל Result מלא (קטגוריה, תגיות) והחלפת קטגוריה מקומית כושלת.
/// </summary>
public class OcrExtractResponse
{
    public string Text { get; set; } = "";
    public string? Error { get; set; }
    /// <summary>true = Cloud Vision/Gemini החזירו תמונה נקייה מטקסט — למנוע retries.</summary>
    public bool IsPureImageNoText { get; set; }
    /// <summary>מקור OCR — GoogleCloud | Gemini. null אם לא הוחל.</summary>
    public string? OcrSource { get; set; }
    /// <summary>תוצאת Gemini (קטגוריה, תגיות, סיכום) — כשהריצה הושלמה. לדריסת קטגוריה מקומית כושלת.</summary>
    public DocumentAnalysisResult? GeminiResult { get; set; }
    /// <summary>שרשרת עיבוד לדיבאג: [Local OCR -> Failed] -> [Cloud Vision -> Success] -> [Gemini Tagging -> Done]</summary>
    public string? ProcessingChain { get; set; }
}
