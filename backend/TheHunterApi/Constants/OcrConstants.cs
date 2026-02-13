namespace TheHunterApi.Constants;

/// <summary>
/// קבועים משותפים ל-OCR — פרומפט חילוץ טקסט, מיפוי MIME.
/// </summary>
public static class OcrConstants
{
    /// <summary>פרומפט ברירת מחדל לחילוץ טקסט — AdminAiController, AnalyzeController.</summary>
    public const string ExtractionPromptFallback =
        "חלץ את כל הטקסט מהמסמך/התמונה. החזר רק את הטקסט הגולמי, ללא הסברים. שמור על השפה המקורית.";

    /// <summary>מיפוי סיומת → MIME. מחזיר "" לסיומת לא נתמכת. defaultForImage = image/jpeg כשמקור התמונה.</summary>
    public static string GetMimeTypeForExtension(string ext, string? defaultForImage = null) =>
        ext.ToLowerInvariant().TrimStart('.') switch
        {
            "pdf" => "application/pdf",
            "jpg" or "jpeg" => "image/jpeg",
            "png" => "image/png",
            "webp" => "image/webp",
            _ => defaultForImage ?? ""
        };

    /// <summary>בודק אם הסיומת תמונה נתמכת (JPG, PNG, WebP) — לולידציה.</summary>
    public static bool IsImageExtension(string ext) =>
        GetMimeTypeForExtension(ext) is "image/jpeg" or "image/png" or "image/webp";
}
