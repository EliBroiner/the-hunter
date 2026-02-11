using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Filters;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// ניהול SystemPrompts — היסטוריה, טיוטות, החלפת פעיל.
/// מוגן ב-AdminKeyAuthorizationFilter.
/// </summary>
[Route("admin/prompts")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
[ApiController]
public class AdminSystemPromptsController : ControllerBase
{
    private readonly ISystemPromptService _promptService;
    private readonly ILogger<AdminSystemPromptsController> _logger;

    public AdminSystemPromptsController(ISystemPromptService promptService, ILogger<AdminSystemPromptsController> logger)
    {
        _promptService = promptService;
        _logger = logger;
    }

    /// <summary>
    /// GET /admin/prompts — היסטוריית פרומפטים. אופציונלי: ?feature=Search
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResult<List<SystemPrompt>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetList([FromQuery] string? feature = null)
    {
        var list = await _promptService.GetListAsync(feature);
        return Ok(ApiResult<List<SystemPrompt>>.Ok(list));
    }

    /// <summary>
    /// POST /admin/prompts — שמירת טיוטה חדשה.
    /// </summary>
    [HttpPost]
    [ProducesResponseType(typeof(ApiResult<SystemPrompt>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> SaveDraft([FromBody] SavePromptRequest request)
    {
        if (request == null)
            return BadRequest(new ErrorResponse { Error = "Request body required" });
        if (string.IsNullOrWhiteSpace(request.Feature))
            return BadRequest(new ErrorResponse { Error = "Feature is required" });
        if (string.IsNullOrWhiteSpace(request.Content))
            return BadRequest(new ErrorResponse { Error = "Content is required" });
        if (string.IsNullOrWhiteSpace(request.Version))
            return BadRequest(new ErrorResponse { Error = "Version is required" });

        try
        {
            var prompt = await _promptService.AddDraftAsync(request.Feature, request.Content, request.Version);
            return Ok(ApiResult<SystemPrompt>.Ok(prompt));
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new ErrorResponse { Error = ex.Message });
        }
    }

    /// <summary>
    /// PATCH /admin/prompts/{id}/active — הפעלת פרומפט (מבטל פעילות של השאר באותו feature).
    /// </summary>
    [HttpPatch("{id:int}/active")]
    [ProducesResponseType(typeof(ApiResult<object>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SetActive(int id)
    {
        var ok = await _promptService.SetActiveAsync(id);
        if (!ok)
            return NotFound(new ErrorResponse { Error = "Prompt not found" });

        return Ok(ApiResult<object>.Ok(new { id, activated = true }));
    }
}

/// <summary>
/// DTO לשמירת טיוטת פרומפט.
/// </summary>
public class SavePromptRequest
{
    public string Feature { get; set; } = "";
    public string Content { get; set; } = "";
    public string Version { get; set; } = "";
}
