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
/// בקשת אצווה לניתוח מסמכים.
/// פרומפט: DB (DocAnalysis) או adminPromptOverride אם Admin.
/// </summary>
public class BatchRequest
{
    public string UserId { get; set; } = string.Empty;
    public List<DocumentPayload> Documents { get; set; } = new();

    /// <summary>דריסת פרומפט — משתמש רק אם המשתמש Admin. מבוקש ללוג.</summary>
    public string? AdminPromptOverride { get; set; }
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
/// בקשת ניתוח דיבאג (AI Lab). פרומפט: DB (DocAnalysis) או adminPromptOverride אם Admin.
/// </summary>
public class DebugAnalyzeRequest
{
    public string Text { get; set; } = string.Empty;
    public string? UserId { get; set; }
    public string? AdminPromptOverride { get; set; }
}

/// <summary>
/// דיווח כשלון Meaningful Text Check מהאפליקציה — נשמר ל-scan_failures.
/// </summary>
public class ReportScanFailureRequest
{
    public string DocumentId { get; set; } = "";
    public string Filename { get; set; } = "";
    public string RawText { get; set; } = "";
    public double? GarbageRatioPercent { get; set; }
    public string? UserId { get; set; }
    /// <summary>סיבת העלאה — Local OCR Low Confidence, Manual Admin Request.</summary>
    public string? ReasonForUpload { get; set; }
}

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
