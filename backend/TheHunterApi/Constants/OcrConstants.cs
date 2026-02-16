namespace TheHunterApi.Constants;

/// <summary>
/// קבועים משותפים ל-OCR — מיפוי MIME. פרומפט חילוץ הועבר ל-SystemPromptFallbacks.OcrExtraction.
/// </summary>
public static class OcrConstants
{
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
