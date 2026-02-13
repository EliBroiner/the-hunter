namespace TheHunterApi.Models;

/// <summary>דיווח כשלון Meaningful Text Check מהאפליקציה — נשמר ל-scan_failures.</summary>
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
