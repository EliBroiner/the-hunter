using Microsoft.AspNetCore.Mvc;
using UglyToad.PdfPig;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using TheHunterApi.Filters;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// AI Lab Debugger — endpoints לבדיקת Scoring, Garbage Filter, Playground ו-OCR.
/// מוגן ב-AdminKeyAuthorizationFilter.
/// </summary>
[Route("admin/debug")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
[ApiController]
public class AdminAiController : ControllerBase
{
    private readonly GeminiService _geminiService;
    private readonly ISystemPromptService _systemPromptService;
    private readonly AdminFirestoreService _firestore;
    private readonly IScannerSettingsService _scannerSettings;
    private readonly ILogger<AdminAiController> _logger;

    private const int MaxFileSizeBytes = 10 * 1024 * 1024; // 10MB

    // משקלים מתוך RankingConfig — Filename: 200, Content: 120, Path/Metadata: 80
    private const double FilenameWeight = 200;
    private const double ContentWeight = 120;
    private const double MetadataWeight = 80;

    private const string OcrExtractionFallback = "חלץ את כל הטקסט מהמסמך/התמונה. החזר רק את הטקסט הגולמי, ללא הסברים. שמור על השפה המקורית.";

    public AdminAiController(GeminiService geminiService, ISystemPromptService systemPromptService, AdminFirestoreService firestore, IScannerSettingsService scannerSettings, ILogger<AdminAiController> logger)
    {
        _geminiService = geminiService;
        _systemPromptService = systemPromptService;
        _firestore = firestore;
        _scannerSettings = scannerSettings;
        _logger = logger;
    }

    /// <summary>
    /// GET /admin/debug/processing-chain/{documentId} — שרשרת עיבוד למסמך (Cloud Vision + Gemini).
    /// </summary>
    [HttpGet("processing-chain/{documentId}")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetProcessingChain(string documentId)
    {
        var chain = await _firestore.GetProcessingChainAsync(documentId);
        if (chain == null) return NotFound();
        return Ok(new { documentId, chain });
    }

    /// <summary>
    /// GET /admin/debug/scan-stats — סטטיסטיקות סריקה (תמונות שדולגו, חיסכון).
    /// </summary>
    [HttpGet("scan-stats")]
    [ProducesResponseType(typeof(ScanStatsResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetScanStats()
    {
        var imagesSkippedNoText = await _firestore.GetImagesSkippedNoTextCountAsync();
        return Ok(new ScanStatsResponse { ImagesSkippedNoText = imagesSkippedNoText });
    }

    /// <summary>
    /// GET /admin/debug/scan-failure/{id} — מחזיר כשלון ל-Debug ב-AI Lab (Manual Override).
    /// </summary>
    [HttpGet("scan-failure/{id}")]
    [ProducesResponseType(typeof(ScanFailure), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetScanFailure(string id)
    {
        var failure = await _firestore.GetScanFailureByIdAsync(id);
        return failure != null ? Ok(failure) : NotFound();
    }

    /// <summary>
    /// POST /admin/debug/score — מחשב ציון רלוונטיות לפי שאילתה ומסמך (filename, content, metadata).
    /// מחזיר פירוט: Filename, Content, Metadata.
    /// </summary>
    [HttpPost("score")]
    [ProducesResponseType(typeof(ScoreDebugResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public IActionResult Score([FromBody] ScoreDebugRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Query))
            return BadRequest(new ErrorResponse { Error = "Query is required" });

        var query = request.Query.Trim();
        var filename = (request.Filename ?? "").Trim();
        var content = (request.Content ?? "").Trim();
        var metadata = (request.Metadata ?? "").Trim();

        // פירוק שאילתה למונחים — split על רווחים, נרמול
        var terms = query.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(t => Normalize(t))
            .Where(t => t.Length > 0)
            .Distinct()
            .ToList();

        if (terms.Count == 0)
            return Ok(new ScoreDebugResponse
            {
                Query = query,
                Terms = [],
                FilenameScore = 0,
                ContentScore = 0,
                MetadataScore = 0,
                TotalScore = 0,
                Breakdown = "No terms extracted from query"
            });

        var fnLower = filename.ToLowerInvariant();
        var contentLower = content.ToLowerInvariant();
        var metaLower = metadata.ToLowerInvariant();

        // ספירת התאמות — כל מונח שמתאים בשדה מקבל את המשקל המלא (כמו RelevanceEngine)
        var matchesInFilename = terms.Count(t => fnLower.Contains(t));
        var matchesInContent = terms.Count(t => contentLower.Contains(t));
        var matchesInMetadata = terms.Count(t => metaLower.Contains(t));

        var fnScore = matchesInFilename * FilenameWeight;
        var contentScore = matchesInContent * ContentWeight;
        var metaScore = matchesInMetadata * MetadataWeight;

        var total = fnScore + contentScore + metaScore;
        var breakdown = $"Filename: {fnScore:F0} | Content: {contentScore:F0} | Metadata: {metaScore:F0}";

        return Ok(new ScoreDebugResponse
        {
            Query = query,
            Terms = terms,
            FilenameScore = fnScore,
            ContentScore = contentScore,
            MetadataScore = metaScore,
            TotalScore = total,
            Breakdown = breakdown
        });
    }

    /// <summary>
    /// POST /admin/debug/garbage-filter — מחשב יחס ג'יבריש לפי הלוגיקה של extracted_text_quality.dart.
    /// סף ג'יבריש — מ-scanner_settings (garbageThresholdPercent).
    /// </summary>
    [HttpPost("garbage-filter")]
    [ProducesResponseType(typeof(GarbageFilterResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GarbageFilter([FromBody] GarbageFilterRequest request)
    {
        var text = request?.Text ?? "";
        var thresholdPercent = await _scannerSettings.GetGarbageThresholdPercentAsync();

        if (text.Length == 0)
            return Ok(new GarbageFilterResponse
            {
                TextLength = 0,
                GarbageCount = 0,
                GarbageRatioPercent = 100,
                PassesThreshold = false,
                ThresholdPercent = thresholdPercent
            });

        var ratio = GetGarbageRatio(text);
        var percent = ratio * 100;
        var passes = ratio <= (thresholdPercent / 100.0);
        var garbageCount = (int)Math.Round(ratio * text.Length);

        _logger.LogInformation("[Debug] Garbage filter: textLen={Len}, garbage={Garbage}, ratio={Ratio:P1}, passes={Passes}, threshold={Threshold}%",
            text.Length, garbageCount, ratio, passes, thresholdPercent);

        return Ok(new GarbageFilterResponse
        {
            TextLength = text.Length,
            GarbageCount = garbageCount,
            GarbageRatioPercent = Math.Round(percent, 2),
            PassesThreshold = passes,
            ThresholdPercent = thresholdPercent
        });
    }

    /// <summary>
    /// POST /admin/debug/playground — מריץ פרומפט מול Gemini, מחזיר תשובה גולמית (JSON).
    /// משמש ל-Prompt Playground באתר הניהול.
    /// </summary>
    [HttpPost("playground")]
    [ProducesResponseType(typeof(PlaygroundResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> Playground([FromBody] PlaygroundRequest request)
    {
        if (!_geminiService.IsConfigured)
            return StatusCode(503, new ErrorResponse { Error = "Gemini API not configured" });

        var systemPrompt = (request?.SystemPrompt ?? "").Trim();
        var userQuery = (request?.UserQuery ?? "").Trim();

        if (string.IsNullOrEmpty(userQuery))
            return BadRequest(new ErrorResponse { Error = "UserQuery is required" });

        if (string.IsNullOrEmpty(systemPrompt))
            systemPrompt = "You are a helpful assistant. Return JSON when appropriate.";

        var (rawText, success, error) = await _geminiService.GenerateContentRawAsync(systemPrompt, userQuery);

        return Ok(new PlaygroundResponse
        {
            RawJson = rawText,
            Success = success,
            Error = error
        });
    }

    /// <summary>
    /// POST /admin/debug/ocr-test — העלאת PDF/תמונה, חילוץ ישיר + fallback ל-Gemini אם ג'יבריש > 30%.
    /// </summary>
    [HttpPost("ocr-test")]
    [RequestSizeLimit(MaxFileSizeBytes)]
    [ProducesResponseType(typeof(OcrTestResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> OcrTest(IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new ErrorResponse { Error = "קובץ נדרש" });

        if (file.Length > MaxFileSizeBytes)
            return BadRequest(new ErrorResponse { Error = $"גודל מקסימלי: {MaxFileSizeBytes / 1024 / 1024}MB" });

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant().TrimStart('.');
        string mimeType = ext switch
        {
            "pdf" => "application/pdf",
            "jpg" or "jpeg" => "image/jpeg",
            "png" => "image/png",
            "webp" => "image/webp",
            _ => ""
        };

        if (string.IsNullOrEmpty(mimeType))
            return BadRequest(new ErrorResponse { Error = "סוג לא נתמך. נתמך: PDF, JPG, PNG, WebP" });

        byte[] bytes;
        using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms);
            bytes = ms.ToArray();
        }

        string? directText = null;
        double garbageRatio = 1.0;

        if (ext == "pdf")
        {
            try
            {
                using var doc = PdfDocument.Open(new MemoryStream(bytes));
                directText = string.Join("\n", doc.GetPages().Select(p => p.Text));
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "PdfPig extract failed");
                directText = "";
            }
        }

        if (!string.IsNullOrEmpty(directText))
        {
            garbageRatio = GetGarbageRatio(directText);
        }

        var minLength = await _scannerSettings.GetMinMeaningfulLengthAsync();
        var minValidRatio = await _scannerSettings.GetMinValidCharRatioPercentAsync();
        var needsFallback = directText == null || !IsTextMeaningful(directText ?? "", minLength, minValidRatio / 100.0);

        string? fallbackText = null;
        string? fallbackError = null;
        string? bwThumbnailDataUrl = null;
        byte[] bytesForGemini = bytes;

        // לתמונות — עיבוד B&W כמו באפליקציה, ויצירת thumbnail
        var isImage = ext is "jpg" or "jpeg" or "png" or "webp";
        if (isImage)
        {
            try
            {
                var (bwBytes, thumbDataUrl) = CreateBwAndThumbnail(bytes);
                if (bwBytes != null)
                {
                    bytesForGemini = bwBytes;
                    bwThumbnailDataUrl = thumbDataUrl;
                }
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "B&W processing failed, using original");
            }
        }

        if (needsFallback && _geminiService.IsConfigured)
        {
            var prompt = await GetOcrExtractionPromptAsync();
            var (extracted, success, err) = await _geminiService.ExtractTextFromFileAsync(bytesForGemini, mimeType, prompt);
            fallbackText = success ? extracted : null;
            fallbackError = err;
        }

        // Raw = מקור ראשי (Direct או Fallback). Cleaned = אחרי TextCleaner
        var rawText = !string.IsNullOrEmpty(fallbackText) ? fallbackText : (directText ?? "");
        if (string.IsNullOrEmpty(rawText) && directText != null)
            rawText = directText;
        var cleanedText = CleanText(rawText);
        var cleanupRatioPercent = string.IsNullOrEmpty(rawText) ? (double?)null : Math.Round(GetGarbageRatio(rawText) * 100, 2);
        var thresholdPercent = await _scannerSettings.GetGarbageThresholdPercentAsync();

        return Ok(new OcrTestResponse
        {
            Filename = file.FileName,
            FileSizeBytes = (int)file.Length,
            DirectExtractText = directText ?? "",
            DirectGarbageRatioPercent = directText != null ? Math.Round(garbageRatio * 100, 2) : null,
            DirectPassesThreshold = directText != null && garbageRatio <= (thresholdPercent / 100.0),
            FallbackUsed = needsFallback,
            FallbackText = fallbackText,
            FallbackError = fallbackError,
            ThresholdPercent = thresholdPercent,
            RawExtractText = rawText,
            CleanedExtractText = cleanedText,
            CleanupRatioPercent = cleanupRatioPercent,
            ReasonForUpload = "Manual Admin Request",
            BwThumbnailDataUrl = bwThumbnailDataUrl
        });
    }

    /// <summary>עיבוד B&W + thumbnail — כמו Flutter OCRService. מחזיר (bytes לשליחה, data URL ל-thumbnail).</summary>
    private static (byte[]? BwBytes, string? ThumbnailDataUrl) CreateBwAndThumbnail(byte[] input)
    {
        using var image = Image.Load<Rgb24>(input);
        image.Mutate(x =>
        {
            x.Grayscale();
            x.BinaryThreshold(128f);
        });
        var encoder = new JpegEncoder { Quality = 70 };
        var bwBytes = new MemoryStream();
        image.SaveAsJpeg(bwBytes, encoder);
        bwBytes.Position = 0;

        // thumbnail — max 200px
        const int maxThumb = 200;
        using var thumb = image.Clone(x =>
        {
            if (image.Width > maxThumb || image.Height > maxThumb)
                x.Resize(new ResizeOptions { Size = new Size(maxThumb, maxThumb), Mode = ResizeMode.Max });
        });
        var thumbMs = new MemoryStream();
        thumb.SaveAsJpeg(thumbMs, new JpegEncoder { Quality = 75 });
        var base64 = Convert.ToBase64String(thumbMs.ToArray());
        return (bwBytes.ToArray(), "data:image/jpeg;base64," + base64);
    }

    private async Task<string> GetOcrExtractionPromptAsync()
    {
        try
        {
            var dbPrompt = await _systemPromptService.GetActivePromptAsync("OcrExtraction");
            if (dbPrompt != null && !string.IsNullOrWhiteSpace(dbPrompt.Content))
            {
                _logger.LogDebug("OCR prompt: using DB (Version={Version})", dbPrompt.Version);
                return dbPrompt.Content;
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "Failed to get OcrExtraction prompt from DB, using fallback");
        }
        return OcrExtractionFallback;
    }

    private static string Normalize(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        return new string(s.Where(c => char.IsLetterOrDigit(c) || char.IsWhiteSpace(c)).ToArray())
            .ToLowerInvariant()
            .Trim();
    }

    /// <summary>
    /// יחס תווים "זבל" (0.0–1.0) — תואם ל-extracted_text_quality.dart
    /// תווים תקינים: עברית (\u0590-\u05FF), לטינית, ספרות, רווחים, פיסוק בסיסי
    /// </summary>
    private static double GetGarbageRatio(string text)
    {
        if (string.IsNullOrEmpty(text)) return 1.0;
        int total = 0, garbage = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            total++;
            if (!IsValidChar(rune.Value)) garbage++;
        }
        return total == 0 ? 1.0 : (double)garbage / total;
    }

    private static bool IsValidChar(int codePoint)
    {
        if (codePoint <= 0x20 && (codePoint == 0x09 || codePoint == 0x0A || codePoint == 0x0D || codePoint == 0x20))
            return true;
        if (codePoint >= 0x30 && codePoint <= 0x39) return true; // 0-9
        if (codePoint >= 0x41 && codePoint <= 0x5A) return true; // A-Z
        if (codePoint >= 0x61 && codePoint <= 0x7A) return true; // a-z
        if (codePoint >= 0x0590 && codePoint <= 0x05FF) return true; // עברית + ניקוד
        var punct = new[] { 0x2C, 0x2E, 0x3A, 0x3B, 0x21, 0x3F, 0x2D, 0x5F, 0x27, 0x22, 0x28, 0x29 };
        return punct.Contains(codePoint);
    }

    /// <summary>
    /// בודק אם הטקסט משמעותי — minValidRatio תווים תקינים ואורך מינימלי minLength.
    /// </summary>
    private static bool IsTextMeaningful(string text, int minLength, double minValidRatio)
    {
        if (string.IsNullOrEmpty(text) || text.Length < minLength) return false;
        var validRatio = 1.0 - GetGarbageRatio(text);
        return validRatio >= minValidRatio;
    }

    /// <summary>
    /// TextCleaner — ניקוי טקסט: רווחים, תווים לא רצויים (תואם ל-Flutter _cleanupText).
    /// </summary>
    private static string CleanText(string text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var cleaned = System.Text.RegularExpressions.Regex.Replace(text, @"\n{3,}", "\n\n");
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[ \t]+", " ");
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[\x00-\x08\x0B\x0C\x0E-\x1F]", "");
        return cleaned.Trim();
    }
}

#region Request/Response DTOs

public class ScoreDebugRequest
{
    public string Query { get; set; } = "";
    public string? Filename { get; set; }
    public string? Content { get; set; }
    public string? Metadata { get; set; }
}

public class ScoreDebugResponse
{
    public string Query { get; set; } = "";
    public List<string> Terms { get; set; } = [];
    public double FilenameScore { get; set; }
    public double ContentScore { get; set; }
    public double MetadataScore { get; set; }
    public double TotalScore { get; set; }
    public string Breakdown { get; set; } = "";
}

public class GarbageFilterRequest
{
    public string? Text { get; set; }
}

public class GarbageFilterResponse
{
    public int TextLength { get; set; }
    public int GarbageCount { get; set; }
    public double GarbageRatioPercent { get; set; }
    public bool PassesThreshold { get; set; }
    public double ThresholdPercent { get; set; }
}

public class PlaygroundRequest
{
    public string? SystemPrompt { get; set; }
    public string? UserQuery { get; set; }
}

public class PlaygroundResponse
{
    public string? RawJson { get; set; }
    public bool Success { get; set; }
    public string? Error { get; set; }
}

public class ErrorResponse
{
    public string Error { get; set; } = "";
    public string? Details { get; set; }
}

public class ScanStatsResponse
{
    public long ImagesSkippedNoText { get; set; }
}

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

#endregion
