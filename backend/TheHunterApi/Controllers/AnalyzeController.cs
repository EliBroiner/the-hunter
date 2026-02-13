using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api")]
public class AnalyzeController : ControllerBase
{
    private readonly GeminiService _geminiService;
    private readonly QuotaService _quotaService;
    private readonly ILearningService _learningService;
    private readonly UserRoleService _userRoleService;
    private readonly AdminFirestoreService _firestore;
    private readonly OcrService _ocrService;
    private readonly IScannerSettingsService _scannerSettings;
    private readonly ILogger<AnalyzeController> _logger;

    public AnalyzeController(
        GeminiService geminiService,
        QuotaService quotaService,
        ILearningService learningService,
        UserRoleService userRoleService,
        AdminFirestoreService firestore,
        OcrService ocrService,
        IScannerSettingsService scannerSettings,
        ILogger<AnalyzeController> logger)
    {
        _geminiService = geminiService;
        _quotaService = quotaService;
        _learningService = learningService;
        _userRoleService = userRoleService;
        _firestore = firestore;
        _ocrService = ocrService;
        _scannerSettings = scannerSettings;
        _logger = logger;
    }

    /// <summary>
    /// ניתוח אצווה של מסמכים ב-AI - כולל בדיקת מכסה
    /// </summary>
    [HttpPost("analyze-batch")]
    [ProducesResponseType(typeof(List<DocumentAnalysisResponse>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status403Forbidden)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> AnalyzeBatch([FromBody] BatchRequest request)
    {
        _logger.LogInformation("📥 [Server] Received request from client.");
        try
        {
            if (request.Documents == null || request.Documents.Count == 0)
                return BadRequest(new ErrorResponse { Error = "Documents cannot be empty" });

            var userId = string.IsNullOrEmpty(request.UserId) ? "anonymous" : request.UserId;
            var count = request.Documents.Count;
            var isAdmin = await _userRoleService.HasRoleAsync(userId, "Admin");
            if (isAdmin)
                _logger.LogInformation("👑 [Quota] User {UserId} is Admin — skipping quota check and usage increment.", userId);

            // Admin — לא מוגבל במכסה
            if (!isAdmin && !await _quotaService.CanUserScanAsync(userId, count))
            {
                _logger.LogWarning("Quota exceeded for user {UserId}", userId);
                return StatusCode(403, new ErrorResponse { Error = "Quota Exceeded", Details = "Free tier limit: 1000 scans/day (stored in Firestore collection 'quotas')" });
            }

            // Trace: מה הגיע מהלקוח
            for (var i = 0; i < request.Documents.Count; i++)
            {
                var d = request.Documents[i];
                _logger.LogInformation("➡️ [SERVER_IN] Received Batch Item. ID: {Id}, Filename: {Filename}, Text Length: {TextLength}",
                    d.Id ?? "(null)", d.Filename ?? "(null)", d.Text?.Length ?? 0);
            }

            string? customPromptOverride = null;
            if (!string.IsNullOrWhiteSpace(request.AdminPromptOverride) && isAdmin)
            {
                customPromptOverride = request.AdminPromptOverride.Trim();
                _logger.LogWarning("[AUDIT] AdminPromptOverride used for analyze-batch | UserId={UserId} | PromptLength={Len}", userId, customPromptOverride.Length);
            }

            var results = await _geminiService.AnalyzeDocumentsBatchAsync(request.Documents, userId, customPromptOverride);
            // Admin — לא מעדכנים מכסה
            if (!isAdmin)
                await _quotaService.IncrementUsageAsync(userId, count);

            _logger.LogInformation("✅ [Server] Successfully processed batch. Returning 200 OK.");
            return Ok(results);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "❌ [Server] Error in processing: {Message}", ex.Message);
            throw;
        }
    }

    /// <summary>
    /// המרת שאילתה בשפה טבעית למונחי חיפוש (מילים נרדפות, תאריכים)
    /// </summary>
    [HttpPost("semantic-search")]
    [ProducesResponseType(typeof(SemanticSearchResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> SemanticSearch([FromBody] SearchRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Query))
            return BadRequest(new ErrorResponse { Error = "Query cannot be empty" });

        if (!_geminiService.IsConfigured)
            return StatusCode(503, new ErrorResponse { Error = "AI service not configured" });

        string? promptOverride = null;
        var userId = request.UserId?.Trim();
        if (!string.IsNullOrWhiteSpace(request.AdminPromptOverride) && !string.IsNullOrWhiteSpace(userId))
        {
            var isAdmin = await _userRoleService.HasRoleAsync(userId, "Admin");
            if (isAdmin)
            {
                promptOverride = request.AdminPromptOverride.Trim();
                _logger.LogWarning("[AUDIT] AdminPromptOverride used for semantic-search | UserId={UserId} | PromptLength={Len}", userId, promptOverride.Length);
            }
        }

        var result = await _geminiService.ParseSearchIntentAsync(request.Query, promptOverride);
        if (!result.IsSuccess)
            return StatusCode(500, new ErrorResponse { Error = "Search parsing failed", Details = result.Error });

        var intent = result.Data!;
        return Ok(new SemanticSearchResponse
        {
            Terms = intent.Terms,
            DateFrom = intent.DateRange?.Start,
            DateTo = intent.DateRange?.End,
            FileTypes = intent.FileTypes
        });
    }

    /// <summary>
    /// ניתוח דיבאג — טקסט + פרומפט מותאם (AI Lab). מחזיר JSON ללא שמירה ל-Learning.
    /// </summary>
    [HttpPost("analyze-debug")]
    [ProducesResponseType(typeof(DocumentAnalysisResult), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> AnalyzeDebug([FromBody] DebugAnalyzeRequest request)
    {
        if (request == null)
            return BadRequest(new ErrorResponse { Error = "Request body required" });
        if (!_geminiService.IsConfigured)
            return StatusCode(503, new ErrorResponse { Error = "AI service not configured" });

        string? customPrompt = null;
        var userId = request.UserId?.Trim();
        if (!string.IsNullOrWhiteSpace(request.AdminPromptOverride) && !string.IsNullOrWhiteSpace(userId))
        {
            var isAdmin = await _userRoleService.HasRoleAsync(userId, "Admin");
            if (isAdmin)
            {
                customPrompt = request.AdminPromptOverride.Trim();
                _logger.LogWarning("[AUDIT] AdminPromptOverride used for analyze-debug | UserId={UserId} | PromptLength={Len}", userId, customPrompt.Length);
            }
        }

        var result = await _geminiService.AnalyzeDocumentWithCustomPromptAsync(request.Text ?? "", customPrompt);
        return Ok(result);
    }

    /// <summary>
    /// שמירת תוצאת ניתוח ל-Learning (AI Lab — שלב 3).
    /// </summary>
    [HttpPost("analyze-debug/save")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> SaveAnalyzeResult([FromBody] DocumentAnalysisResult result)
    {
        if (result == null)
            return BadRequest(new ErrorResponse { Error = "Result body required" });

        var category = result.Category ?? "—";
        var tagCount = result.Tags?.Count ?? 0;
        _logger.LogInformation("[Server] Gemini response received. Category: {Category}, Tags: {TagCount}. Attempting to save to DB (collection: suggestions)...",
            category, tagCount);

        try
        {
            var userId = (string?)null;
            if (!string.IsNullOrWhiteSpace(result.Category))
                await _learningService.ProcessAiResultAsync(result.Category, "category", userId);
            foreach (var tag in result.Tags ?? [])
            {
                if (string.IsNullOrWhiteSpace(tag)) continue;
                await _learningService.ProcessAiResultAsync(tag, result.Category ?? "general", userId);
            }
            _logger.LogInformation("[Server] analyze-debug/save OK — Category={Category}, Tags={TagCount}", result.Category, tagCount);
            return Ok();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Server] CRITICAL: Failed to save analyze-debug/save to DB. Error: {Message}", ex.Message);
            return StatusCode(500, new ErrorResponse { Error = "Save to DB failed", Details = ex.Message });
        }
    }

    /// <summary>
    /// OCR Fallback — העלאת תמונה מקומפוסת (B&W) לחילוץ טקסט. משמש כשמ-ML Kit נכשל.
    /// Cloud Vision → Gemini Tagging (קטגוריה, תגיות) — דריסת קטגוריה מקומית כושלת.
    /// </summary>
    [HttpPost("ocr-extract")]
    [RequestSizeLimit(5 * 1024 * 1024)] // 5MB
    [ProducesResponseType(typeof(OcrExtractResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> OcrExtract(IFormFile? file, [FromForm] string? documentId, [FromForm] string? filename, [FromForm] string? userId)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new ErrorResponse { Error = "Image file required for OCR" });

        byte[] bytes;
        using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms);
            bytes = ms.ToArray();
        }

        try
        {
            var docId = documentId ?? "(unknown)";
            var fn = filename ?? file.FileName ?? "image.jpg";

            if (!OcrService.AppearsPreprocessedBw(bytes))
            {
                _logger.LogWarning("OCR-extract: Image may not be preprocessed (Grayscale/B&W). DocumentId={DocumentId}, Filename={Filename}",
                    docId, fn);
            }

            var googleCloudVisionEnabled = await _scannerSettings.GetCloudVisionFallbackEnabledAsync();
            string text;
            bool isPureImageNoText;
            string? ocrSource = null;
            DocumentAnalysisResult? geminiResult = null;
            string? processingChain = null;

            if (googleCloudVisionEnabled)
            {
                _logger.LogInformation("Processing B&W image via Google Cloud Vision for Document {DocumentId}", docId);
                var (t, success, pure) = await _ocrService.ExtractTextFromImageAsync(bytes);
                if (!success)
                {
                _logger.LogWarning("OCR-extract Cloud Vision failed for DocumentId={DocumentId}, falling back to Gemini", docId);
                (text, isPureImageNoText) = await _extractViaGeminiAsync(bytes, file.FileName ?? fn);
                    ocrSource = "Gemini";
                }
                else
                {
                    text = t;
                    isPureImageNoText = pure;
                    ocrSource = "GoogleCloud";
                }

                // Phase B: שליחת הטקסט החדש ל-Gemini — חילוץ קטגוריה, תגיות, תאריך. דריסת קטגוריה מקומית כושלת.
                if (!isPureImageNoText && !string.IsNullOrWhiteSpace(text) && text.Trim().Length >= 5 && _geminiService.IsConfigured)
                {
                    _logger.LogInformation("OCR-extract: Triggering Gemini tagging for Document {DocumentId} (Cloud Vision text length={Len})", docId, text.Length);
                    var geminiResponse = await _geminiService.AnalyzeOcrTextAsync(docId, fn, text.Trim(), userId?.Trim());
                    geminiResult = geminiResponse.Result;
                    processingChain = "[Local OCR -> Failed] -> [Cloud Vision -> Success] -> [Gemini Tagging -> Done]";
                    await _firestore.SaveProcessingChainAsync(docId, processingChain, fn,
                        rawText: text, cleanedText: CleanTextForXRay(text), ocrSource, geminiResult?.Tags, geminiResult?.Category);
                }
            }
            else
            {
                if (!_geminiService.IsConfigured)
                {
                    _logger.LogWarning("OCR-extract: Cloud Vision disabled and Gemini not configured");
                    return StatusCode(503, new ErrorResponse { Error = "Cloud Vision Fallback is disabled. Enable in Admin Portal, or configure Gemini API." });
                }
                _logger.LogDebug("Cloud Vision Fallback disabled, using Gemini");
                (text, isPureImageNoText) = await _extractViaGeminiAsync(bytes, file.FileName ?? fn);
                ocrSource = "Gemini";
                // Gemini-only path — שליחת טקסט ל-Gemini tagging ושמירה ל-FileXRay
                if (!isPureImageNoText && !string.IsNullOrWhiteSpace(text) && text.Trim().Length >= 5)
                {
                    var geminiResponse = await _geminiService.AnalyzeOcrTextAsync(docId, fn, text.Trim(), userId?.Trim());
                    geminiResult = geminiResponse.Result;
                    processingChain = "[Local OCR -> Failed] -> [Gemini OCR + Tagging -> Done]";
                    await _firestore.SaveProcessingChainAsync(docId, processingChain, fn,
                        rawText: text, cleanedText: CleanTextForXRay(text), ocrSource, geminiResult?.Tags, geminiResult?.Category);
                }
            }

            return Ok(new OcrExtractResponse
            {
                Text = text,
                IsPureImageNoText = isPureImageNoText,
                OcrSource = ocrSource,
                GeminiResult = geminiResult,
                ProcessingChain = processingChain
            });
        }
        finally
        {
            Array.Clear(bytes, 0, bytes.Length);
            _logger.LogInformation("Temporary OCR buffer cleared successfully");
        }
    }

    /// <summary>ניקוי טקסט ל-FileXRay — תואם ל-TextCleaner ב-AdminAiController.</summary>
    private static string CleanTextForXRay(string text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var cleaned = System.Text.RegularExpressions.Regex.Replace(text, @"\n{3,}", "\n\n");
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[ \t]+", " ");
        cleaned = System.Text.RegularExpressions.Regex.Replace(cleaned, @"[\x00-\x08\x0B\x0C\x0E-\x1F]", "");
        return cleaned.Trim();
    }

    private async Task<(string Text, bool IsPureImageNoText)> _extractViaGeminiAsync(byte[] bytes, string fileName)
    {
        var ext = Path.GetExtension(fileName).ToLowerInvariant().TrimStart('.');
        var mimeType = ext switch { "png" => "image/png", "webp" => "image/webp", _ => "image/jpeg" };
        const string prompt = "חלץ את כל הטקסט מהמסמך/התמונה. החזר רק את הטקסט הגולמי, ללא הסברים. שמור על השפה המקורית.";
        var (extracted, success, _) = await _geminiService.ExtractTextFromFileAsync(bytes, mimeType, prompt);
        var text = success ? (extracted ?? "") : "";
        return (text, string.IsNullOrWhiteSpace(text));
    }

    /// <summary>
    /// דיווח כשלון Meaningful Text Check מהאפליקציה — נשמר ל-scan_failures לדיבאג ב-AI Lab.
    /// </summary>
    [HttpPost("report-scan-failure")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> ReportScanFailure([FromBody] ReportScanFailureRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Filename))
            return BadRequest(new ErrorResponse { Error = "Filename required" });

        var docId = await _firestore.AddScanFailureAsync(
            request.DocumentId ?? "",
            request.Filename.Trim(),
            request.RawText ?? "",
            request.GarbageRatioPercent,
            request.UserId?.Trim(),
            request.ReasonForUpload?.Trim());

        return docId != null
            ? Ok(new { success = true, id = docId })
            : StatusCode(500, new ErrorResponse { Error = "Failed to save scan failure" });
    }

    /// <summary>
    /// דיווח תמונה שדולגה — No Text Detected (ML Kit / Gemini). מגדיל מונה ב-scan_stats לסטטיסטיקת חיסכון.
    /// </summary>
    [HttpPost("report-no-text-detected")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ReportNoTextDetected()
    {
        await _firestore.IncrementImagesSkippedNoTextAsync();
        return Ok(new { success = true });
    }

    /// <summary>
    /// OCR Testing Lab — חילוץ טקסט מתמונה דרך Cloud Vision בלבד (ללא Gemini).
    /// מקבל תמונה B&W, מחזיר טקסט גולמי.
    /// </summary>
    [HttpPost("debug/ocr-vision-only")]
    [RequestSizeLimit(5 * 1024 * 1024)]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> OcrVisionOnly(IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new ErrorResponse { Error = "Image file required" });

        byte[] bytes;
        using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms);
            bytes = ms.ToArray();
        }

        try
        {
            var (text, error) = await _ocrService.TestCloudVisionAsync(bytes);
            if (error != null)
                return StatusCode(500, new ErrorResponse { Error = "Cloud Vision failed", Details = error });
            return Ok(new { text = text ?? "", isPureImageNoText = string.IsNullOrWhiteSpace(text) });
        }
        finally
        {
            Array.Clear(bytes, 0, bytes.Length);
        }
    }

    /// <summary>
    /// בדיקה זמנית — שולח תמונה מינימלית ל-Cloud Vision. מחזיר 200 עם טקסט בהצלחה, או הודעת שגיאה מדויקת (403, API not enabled וכו').
    /// </summary>
    [HttpGet("debug/test-cloud-vision")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> TestCloudVision()
    {
        // תמונה מינימלית 1x1 PNG (base64) — מספיקה לבדיקת חיבור ל-API
        var base64 = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==";
        var bytes = Convert.FromBase64String(base64);
        var (text, error) = await _ocrService.TestCloudVisionAsync(bytes);
        if (error != null)
            return StatusCode(500, error);
        return Ok(new { success = true, text });
    }

    /// <summary>
    /// Database Doctor — בודק כתיבה ל-Firestore (collection: suggestions). GET לבדיקה בדפדפן.
    /// </summary>
    [HttpGet("test-db-write")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> TestDbWrite()
    {
        var (docId, error) = await _learningService.TryWriteTestDocumentAsync();
        if (docId != null)
            return Ok($"Write Successful. ID: {docId}");
        return StatusCode(500, $"Write Failed. Exception: {error}");
    }
}
