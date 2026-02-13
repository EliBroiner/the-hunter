namespace TheHunterApi.Models;

public class OcrTestResponse
{
    public string Filename { get; set; } = "";
    public int FileSizeBytes { get; set; }
    public string DirectExtractText { get; set; } = "";
    public double? DirectGarbageRatioPercent { get; set; }
    public bool DirectPassesThreshold { get; set; }
    public bool FallbackUsed { get; set; }
    public string? FallbackText { get; set; }
    public string? FallbackError { get; set; }
    public double ThresholdPercent { get; set; }
    /// <summary>טקסט גולמי לפני TextCleaner (מקור ראשי: Direct או Fallback)</summary>
    public string RawExtractText { get; set; } = "";
    /// <summary>טקסט אחרי TextCleaner</summary>
    public string CleanedExtractText { get; set; } = "";
    /// <summary>אחוז רעש שהוסר (ג'יבריש)</summary>
    public double? CleanupRatioPercent { get; set; }
    /// <summary>סיבת העלאה — Manual Admin Request, Local OCR Low Confidence</summary>
    public string ReasonForUpload { get; set; } = "Manual Admin Request";
    /// <summary>תמונת B&W שנשלחה לשרת (base64 data URL) — לתמונות בלבד</summary>
    public string? BwThumbnailDataUrl { get; set; }
}
