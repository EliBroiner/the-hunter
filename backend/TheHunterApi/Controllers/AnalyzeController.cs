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
    private readonly ILogger<AnalyzeController> _logger;

    public AnalyzeController(
        GeminiService geminiService,
        QuotaService quotaService,
        ILearningService learningService,
        UserRoleService userRoleService,
        ILogger<AnalyzeController> logger)
    {
        _geminiService = geminiService;
        _quotaService = quotaService;
        _learningService = learningService;
        _userRoleService = userRoleService;
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

            if (!await _quotaService.CanUserScanAsync(userId, count))
            {
                _logger.LogWarning("Quota exceeded for user {UserId}", userId);
                return StatusCode(403, new ErrorResponse { Error = "Quota Exceeded", Details = "Free tier limit: 1000 scans/month" });
            }

            // דריסת פרומפט — זמנית: תמיד מאפשרים (לבדיקות בלי הגדרת Admin ב-DB). להחזיר בדיקת Admin כשמוכן.
            string? customPromptOverride = null;
            if (!string.IsNullOrWhiteSpace(request.CustomPromptOverride))
            {
                customPromptOverride = request.CustomPromptOverride!.Trim();
                // if (await _userRoleService.HasRoleAsync(userId, "Admin"))
                //     customPromptOverride = request.CustomPromptOverride!.Trim();
                // else
                //     customPromptOverride = null;
            }

            var results = await _geminiService.AnalyzeDocumentsBatchAsync(request.Documents, userId, customPromptOverride);
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

        var result = await _geminiService.ParseSearchIntentAsync(request.Query);
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

        var result = await _geminiService.AnalyzeDocumentWithCustomPromptAsync(request.Text ?? "", request.CustomPrompt);
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
