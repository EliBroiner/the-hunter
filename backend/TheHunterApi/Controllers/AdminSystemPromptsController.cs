using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Filters;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// ניהול SystemPrompts — Firestore (analysis, search) + SQLite (legacy). מוגן ב-AdminKeyAuthorizationFilter.
/// </summary>
[Route("admin/prompts")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
[ApiController]
public class AdminSystemPromptsController : ControllerBase
{
    private static readonly string[] FirestoreFeatures = ["analysis", "trainer", "search", "ocr_extraction"];

    private readonly ISystemPromptService _promptService;
    private readonly AdminFirestoreService _firestore;
    private readonly ILogger<AdminSystemPromptsController> _logger;

    public AdminSystemPromptsController(
        ISystemPromptService promptService,
        AdminFirestoreService firestore,
        ILogger<AdminSystemPromptsController> logger)
    {
        _promptService = promptService;
        _firestore = firestore;
        _logger = logger;
    }

    private bool UseFirestore(string feature) =>
        !string.IsNullOrWhiteSpace(feature) && FirestoreFeatures.Contains(feature, StringComparer.OrdinalIgnoreCase);

    /// <summary>
    /// GET /admin/prompts — היסטוריית פרומפטים. אופציונלי: ?feature=analysis
    /// </summary>
    [HttpGet]
    [ProducesResponseType(typeof(ApiResult<List<SystemPrompt>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetList([FromQuery] string? feature = null)
    {
        if (feature != null && UseFirestore(feature))
        {
            var list = await _firestore.GetPromptsForFeatureAsync(feature);
            return Ok(ApiResult<List<SystemPrompt>>.Ok(list.Select(ToSystemPrompt).ToList()));
        }
        var sqlList = await _promptService.GetListAsync(feature);
        return Ok(ApiResult<List<SystemPrompt>>.Ok(sqlList));
    }

    /// <summary>
    /// GET /admin/prompts/latest?feature=analysis — הפרומפט הפעיל או fallback מוטבע (להצגה ב-UI).
    /// </summary>
    [HttpGet("latest")]
    [ProducesResponseType(typeof(ApiResult<SystemPromptResult>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetLatest([FromQuery] string feature)
    {
        if (string.IsNullOrWhiteSpace(feature))
            return BadRequest(new ErrorResponse { Error = "feature is required" });
        if (!UseFirestore(feature))
            return BadRequest(new ErrorResponse { Error = "feature must be 'analysis', 'trainer', 'search', or 'ocr_extraction'" });

        var ft = feature switch
        {
            "analysis" => TheHunterApi.Constants.FeatureType.DocumentAnalysis,
            "trainer" => TheHunterApi.Constants.FeatureType.DocumentTrainer,
            "search" => TheHunterApi.Constants.FeatureType.SmartSearch,
            "ocr_extraction" => TheHunterApi.Constants.FeatureType.OcrExtraction,
            _ => TheHunterApi.Constants.FeatureType.DocumentAnalysis
        };
        var result = await _firestore.GetLatestPromptAsync(ft);
        return Ok(ApiResult<SystemPromptResult>.Ok(result));
    }

    /// <summary>
    /// GET /admin/prompts/by-feature?feature=analysis — פרומפטים לפי feature, ממוין לפי גרסה יורד.
    /// </summary>
    [HttpGet("by-feature")]
    [ProducesResponseType(typeof(ApiResult<List<SystemPrompt>>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetByFeature([FromQuery] string feature)
    {
        if (string.IsNullOrWhiteSpace(feature))
            return BadRequest(new ErrorResponse { Error = "feature is required" });

        if (UseFirestore(feature))
        {
            var list = await _firestore.GetPromptsForFeatureAsync(feature);
            return Ok(ApiResult<List<SystemPrompt>>.Ok(list.Select(ToSystemPrompt).ToList()));
        }
        var sqlList = await _promptService.GetPromptsForFeatureAsync(feature);
        return Ok(ApiResult<List<SystemPrompt>>.Ok(sqlList));
    }

    /// <summary>
    /// POST /admin/prompts — שמירת טיוטה. feature=analysis|search → Firestore.
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

        if (UseFirestore(request.Feature))
        {
            var doc = await _firestore.SavePromptAsync(
                request.Feature, request.Version, request.Content, request.SetActive);
            if (doc == null)
                return BadRequest(new ErrorResponse { Error = "Failed to save to Firestore" });
            return Ok(ApiResult<SystemPrompt>.Ok(ToSystemPrompt(doc)));
        }

        try
        {
            var prompt = await _promptService.AddDraftAsync(request.Feature, request.Content, request.Version);
            if (request.SetActive)
            {
                await _promptService.SetActiveAsync(prompt.Id);
                prompt = (await _promptService.GetListAsync(request.Feature))
                    .FirstOrDefault(p => p.Id == prompt.Id) ?? prompt;
            }
            return Ok(ApiResult<SystemPrompt>.Ok(prompt));
        }
        catch (ArgumentException ex)
        {
            return BadRequest(new ErrorResponse { Error = ex.Message });
        }
    }

    /// <summary>
    /// PATCH /admin/prompts/{id}/active — הפעלת פרומפט (SQLite בלבד).
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

    /// <summary>
    /// PATCH /admin/prompts/set-active?feature=analysis&amp;version=1.1 — הפעלת פרומפט לפי feature+version.
    /// </summary>
    [HttpPatch("set-active")]
    [ProducesResponseType(typeof(ApiResult<object>), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status404NotFound)]
    public async Task<IActionResult> SetActiveByFeatureVersion([FromQuery] string feature, [FromQuery] string version)
    {
        if (UseFirestore(feature))
        {
            var ok = await _firestore.SetActiveByFeatureVersionAsync(feature, version);
            if (!ok) return NotFound(new ErrorResponse { Error = "Prompt not found" });
            return Ok(ApiResult<object>.Ok(new { feature, version, activated = true }));
        }
        var sqlOk = await _promptService.SetActiveByFeatureVersionAsync(feature, version);
        if (!sqlOk) return NotFound(new ErrorResponse { Error = "Prompt not found" });
        return Ok(ApiResult<object>.Ok(new { feature, version, activated = true }));
    }

    private static SystemPrompt ToSystemPrompt(SystemPromptFirestoreDoc doc) => new()
    {
        Id = doc.Id.GetHashCode(),
        Content = doc.Text,
        Version = doc.Version,
        IsActive = doc.IsActive,
        Feature = doc.Feature,
        CreatedAt = doc.CreatedAt
    };
}
