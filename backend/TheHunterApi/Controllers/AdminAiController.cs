using Microsoft.AspNetCore.Mvc;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.Formats.Jpeg;
using SixLabors.ImageSharp.PixelFormats;
using SixLabors.ImageSharp.Processing;
using TheHunterApi.Constants;
using static TheHunterApi.Constants.SystemPromptFeatures;
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
    private readonly OcrService _ocrService;
    private readonly ILogger<AdminAiController> _logger;

    private const int MaxFileSizeBytes = 10 * 1024 * 1024; // 10MB

    // משקלים מתוך RankingConfig — Filename: 200, Content: 120, Path/Metadata: 80
    private const double FilenameWeight = 200;
    private const double ContentWeight = 120;
    private const double MetadataWeight = 80;

    public AdminAiController(GeminiService geminiService, ISystemPromptService systemPromptService, AdminFirestoreService firestore, IScannerSettingsService scannerSettings, OcrService ocrService, ILogger<AdminAiController> logger)
    {
        _geminiService = geminiService;
        _systemPromptService = systemPromptService;
        _firestore = firestore;
        _scannerSettings = scannerSettings;
        _ocrService = ocrService;
        _logger = logger;
    }

    /// <summary>
    /// GET /admin/debug/file-xray/{documentId} — נתוני File X-Ray מלאים (B&W, OCR source, raw/cleaned, tags).
    /// </summary>
    [HttpGet("file-xray/{documentId}")]
    [ProducesResponseType(typeof(FileXRayData), StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status404NotFound)]
    public async Task<IActionResult> GetFileXRay(string documentId)
    {
        var data = await _firestore.GetFileXRayAsync(documentId);
        return data != null ? Ok(data) : NotFound();
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

        var ratio = TextQualityHelper.GetGarbageRatio(text);
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
        if (ValidateFileRequired(file) is { } fileErr)
            return BadRequest(fileErr);

        var ext = Path.GetExtension(file!.FileName).ToLowerInvariant().TrimStart('.');
        var mimeType = OcrConstants.GetMimeTypeForExtension(ext);
        if (string.IsNullOrEmpty(mimeType))
            return BadRequest(new ErrorResponse { Error = "סוג לא נתמך. נתמך: PDF, JPG, PNG, WebP" });

        var bytes = await ReadFileBytesAsync(file);

        var (directText, garbageRatio) = ext == "pdf"
            ? PdfExtractionHelper.TryExtractText(bytes)
            : ("", 1.0);

        var minLength = await _scannerSettings.GetMinMeaningfulLengthAsync();
        var minValidRatio = await _scannerSettings.GetMinValidCharRatioPercentAsync();
        var needsFallback = string.IsNullOrEmpty(directText) || !TextQualityHelper.IsTextMeaningful(directText, minLength, minValidRatio / 100.0);

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
        var rawText = !string.IsNullOrEmpty(fallbackText) ? fallbackText : directText;
        var cleanedText = TextQualityHelper.CleanText(rawText);
        var cleanupRatioPercent = string.IsNullOrEmpty(rawText) ? (double?)null : Math.Round(TextQualityHelper.GetGarbageRatio(rawText) * 100, 2);
        var thresholdPercent = await _scannerSettings.GetGarbageThresholdPercentAsync();

        return Ok(new OcrTestResponse
        {
            Filename = file.FileName,
            FileSizeBytes = (int)file.Length,
            DirectExtractText = directText,
            DirectGarbageRatioPercent = !string.IsNullOrEmpty(directText) ? Math.Round(garbageRatio * 100, 2) : null,
            DirectPassesThreshold = !string.IsNullOrEmpty(directText) && garbageRatio <= (thresholdPercent / 100.0),
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

    /// <summary>
    /// POST /admin/debug/ocr-step-bw — שלב 1→2: המרת תמונה ל-B&W. מחזיר thumbnail + base64 לשלב הבא.
    /// </summary>
    [HttpPost("ocr-step-bw")]
    [RequestSizeLimit(MaxFileSizeBytes)]
    [ProducesResponseType(typeof(OcrStepBwResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> OcrStepBw(IFormFile? file)
    {
        if (ValidateFileRequired(file) is { } fileErr)
            return BadRequest(fileErr);
        if (ValidateImageExtension(file!) is { } imgErr)
            return BadRequest(imgErr);

        var bytes = await ReadFileBytesAsync(file!);
        try
        {
            var (bwBytes, thumbDataUrl) = CreateBwAndThumbnail(bytes);
            if (bwBytes == null)
                return StatusCode(500, new ErrorResponse { Error = "B&W conversion failed" });
            return Ok(new OcrStepBwResponse { BwThumbnailDataUrl = thumbDataUrl, BwBase64 = Convert.ToBase64String(bwBytes) });
        }
        finally
        {
            Array.Clear(bytes, 0, bytes.Length);
        }
    }

    /// <summary>
    /// POST /admin/debug/ocr-step-vision — שלב 2→3: Cloud Vision על תמונת B&W. מחזיר טקסט גולמי.
    /// </summary>
    [HttpPost("ocr-step-vision")]
    [RequestSizeLimit(MaxFileSizeBytes)]
    [ProducesResponseType(typeof(OcrStepVisionResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> OcrStepVision([FromBody] OcrStepVisionRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.ImageBase64))
            return BadRequest(new ErrorResponse { Error = "ImageBase64 נדרש" });

        byte[] bytes;
        try
        {
            bytes = Convert.FromBase64String(request.ImageBase64.Trim());
        }
        catch
        {
            return BadRequest(new ErrorResponse { Error = "Base64 לא תקין" });
        }

        try
        {
            var (text, error) = await _ocrService.TestCloudVisionAsync(bytes);
            if (error != null)
                return StatusCode(500, new ErrorResponse { Error = "Cloud Vision failed", Details = error });
            return Ok(new OcrStepVisionResponse { Text = text ?? "", IsPureImageNoText = string.IsNullOrWhiteSpace(text) });
        }
        finally
        {
            Array.Clear(bytes, 0, bytes.Length);
        }
    }

    /// <summary>
    /// POST /admin/debug/ocr-step-gemini — שלב 3→4: ניתוח טקסט ב-Gemini עם פרומפט מותאם.
    /// </summary>
    [HttpPost("ocr-step-gemini")]
    [ProducesResponseType(typeof(DocumentAnalysisResult), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> OcrStepGemini([FromBody] OcrStepGeminiRequest request)
    {
        if (!_geminiService.IsConfigured)
            return StatusCode(503, new ErrorResponse { Error = "Gemini API not configured" });
        if (request == null)
            return BadRequest(new ErrorResponse { Error = "Request body required" });

        var text = request.Text ?? "";
        var customPrompt = string.IsNullOrWhiteSpace(request.SystemPromptOverride) ? null : request.SystemPromptOverride.Trim();

        var result = await _geminiService.AnalyzeDocumentWithCustomPromptAsync(text, customPrompt);
        return Ok(result);
    }

    /// <summary>ולידציה: קובץ קיים וגודל תקין. null = OK.</summary>
    private static ErrorResponse? ValidateFileRequired(IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return new ErrorResponse { Error = "קובץ נדרש" };
        if (file.Length > MaxFileSizeBytes)
            return new ErrorResponse { Error = $"גודל מקסימלי: {MaxFileSizeBytes / 1024 / 1024}MB" };
        return null;
    }

    /// <summary>ולידציה: סיומת תמונה בלבד (JPG, PNG, WebP). null = OK.</summary>
    private static ErrorResponse? ValidateImageExtension(IFormFile file)
    {
        var ext = Path.GetExtension(file.FileName).ToLowerInvariant().TrimStart('.');
        return OcrConstants.IsImageExtension(ext) ? null : new ErrorResponse { Error = "רק תמונות: JPG, PNG, WebP" };
    }

    /// <summary>קריאת bytes מקובץ — משותף ל-ocr-test ו-ocr-step-bw.</summary>
    private static async Task<byte[]> ReadFileBytesAsync(IFormFile file)
    {
        using var ms = new MemoryStream();
        await file.CopyToAsync(ms);
        return ms.ToArray();
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
            var dbPrompt = await _systemPromptService.GetActivePromptAsync(OcrExtraction);
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
        return OcrConstants.ExtractionPromptFallback;
    }

    private static string Normalize(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        return new string(s.Where(c => char.IsLetterOrDigit(c) || char.IsWhiteSpace(c)).ToArray())
            .ToLowerInvariant()
            .Trim();
    }

}
