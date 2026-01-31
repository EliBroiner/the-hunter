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
    private readonly ILogger<AnalyzeController> _logger;

    public AnalyzeController(
        GeminiService geminiService,
        QuotaService quotaService,
        ILogger<AnalyzeController> logger)
    {
        _geminiService = geminiService;
        _quotaService = quotaService;
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
        if (request.Documents == null || request.Documents.Count == 0)
            return BadRequest(new ErrorResponse { Error = "Documents cannot be empty" });

        var userId = string.IsNullOrEmpty(request.UserId) ? "anonymous" : request.UserId;
        var count = request.Documents.Count;

        if (!await _quotaService.CanUserScanAsync(userId, count))
        {
            _logger.LogWarning("Quota exceeded for user {UserId}", userId);
            return StatusCode(403, new ErrorResponse { Error = "Quota Exceeded", Details = "Free tier limit: 50 scans/month" });
        }

        var results = await _geminiService.AnalyzeDocumentsBatchAsync(request.Documents);
        await _quotaService.IncrementUsageAsync(userId, count);

        return Ok(results);
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
}
