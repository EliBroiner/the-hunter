using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SearchController : ControllerBase
{
    private readonly GeminiService _geminiService;
    private readonly ILogger<SearchController> _logger;

    public SearchController(
        GeminiService geminiService,
        ILogger<SearchController> logger)
    {
        _geminiService = geminiService;
        _logger = logger;
    }

    /// <summary>
    /// מנתח שאילתת חיפוש בשפה טבעית ומחזיר intent מובנה
    /// </summary>
    /// <param name="request">בקשת חיפוש עם שאילתה בשפה טבעית</param>
    /// <returns>SearchIntent עם terms, fileTypes ו-dateRange</returns>
    [HttpPost("intent")]
    [ProducesResponseType(typeof(SearchIntent), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> ParseSearchIntent([FromBody] SearchRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Query))
        {
            return BadRequest(new ErrorResponse { Error = "Query cannot be empty" });
        }

        if (!_geminiService.IsConfigured)
        {
            return StatusCode(503, new ErrorResponse 
            { 
                Error = "AI service not configured",
                Details = "GEMINI_API_KEY environment variable is not set"
            });
        }

        _logger.LogInformation("Received search intent request: {Query}", request.Query);

        var result = await _geminiService.ParseSearchIntentAsync(request.Query);

        if (!result.IsSuccess)
        {
            _logger.LogError("Failed to parse search intent: {Error}", result.Error);
            return StatusCode(500, new ErrorResponse 
            { 
                Error = "Failed to parse search intent",
                Details = result.Error
            });
        }

        return Ok(result.Data);
    }

    /// <summary>
    /// בודק את סטטוס השירות
    /// </summary>
    [HttpGet("status")]
    [ProducesResponseType(typeof(object), StatusCodes.Status200OK)]
    public IActionResult GetStatus()
    {
        return Ok(new
        {
            service = "SearchController",
            geminiConfigured = _geminiService.IsConfigured,
            timestamp = DateTime.UtcNow
        });
    }
}
