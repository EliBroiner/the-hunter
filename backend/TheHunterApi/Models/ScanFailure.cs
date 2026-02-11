namespace TheHunterApi.Models;

/// <summary>
/// מסמך שנכשל בבדיקת Meaningful Text (ג'יבריש / אורך מינימלי).
/// נשמר ב-Firestore scan_failures לדיבאג ב-AI Lab.
/// </summary>
public class ScanFailure
{
    public string Id { get; set; } = "";
    public string DocumentId { get; set; } = "";
    public string Filename { get; set; } = "";
    public string RawText { get; set; } = "";
    public double? GarbageRatioPercent { get; set; }
    public string? UserId { get; set; }
    public DateTime Timestamp { get; set; }
    /// <summary>סיבת העלאה לדיבאג — Local OCR Low Confidence, Manual Admin Request.</summary>
    public string? ReasonForUpload { get; set; }
}
