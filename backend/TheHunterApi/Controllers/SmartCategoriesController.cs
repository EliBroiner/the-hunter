using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// API לקטגוריות חכמות — טעינה והוספת חוק (Regex/Keyword) ל-Firestore.
/// </summary>
[ApiController]
[Route("api/smart-categories")]
public class SmartCategoriesController : ControllerBase
{
    private readonly ISmartCategoriesService _service;

    public SmartCategoriesController(ISmartCategoriesService service)
    {
        _service = service;
    }

    [HttpGet]
    [ProducesResponseType(typeof(IReadOnlyList<SmartCategoryDto>), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetAll(CancellationToken ct)
    {
        var list = await _service.GetAllAsync(ct);
        var dtos = list.Select(d => new SmartCategoryDto(
            d.Key,
            d.DisplayNames,
            d.Keywords,
            d.RegexPatterns
        )).ToList();
        return Ok(dtos);
    }

    /// <summary>type: "regex" | "keyword", value: המחרוזת להוספה.</summary>
    [HttpPost("{categoryId}/rules")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> AddRule(string categoryId, [FromBody] AddRuleRequest body, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(body?.Type) || string.IsNullOrWhiteSpace(body.Value))
            return BadRequest(new { error = "type and value required" });
        var ok = await _service.AddRuleAsync(categoryId, body.Type, body.Value, ct);
        return ok ? Ok(new { ok = true }) : BadRequest(new { error = "AddRule failed" });
    }

    /// <summary>אישור הצעות Admin — מוסיף keywords ו-regex ל-SmartCategory ב-Firestore.</summary>
    [HttpPost("{categoryId}/rules/batch")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    public async Task<IActionResult> AddRulesBatch(string categoryId, [FromBody] AddRulesBatchRequest body, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(categoryId))
            return BadRequest(new { error = "categoryId required" });
        var keywords = body?.Keywords ?? new List<string>();
        var regexPatterns = body?.RegexPatterns ?? new List<string>();
        var count = await _service.AddRulesBatchAsync(categoryId, keywords, regexPatterns, ct);
        return Ok(new { ok = true, added = count });
    }

    /// <summary>
    /// שמירה ידנית מ-Debugger: יוצר/מעדכן מסמך ב-smart_categories (category = document ID).
    /// </summary>
    [HttpPost("save-manual")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    [ProducesResponseType(StatusCodes.Status400BadRequest)]
    [ProducesResponseType(StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> SaveManual([FromBody] SaveManualRequest body, CancellationToken ct)
    {
        if (body == null || string.IsNullOrWhiteSpace(body.Category))
            return BadRequest(new { error = "category required" });
        try
        {
            var tags = body.Tags ?? new List<string>();
            var suggestions = body.Suggestions ?? new List<object>();
            var docId = await _service.SaveManualAsync(body.Category, tags, suggestions, body.Summary, ct);
            return docId != null ? Ok(new { ok = true, category = docId }) : BadRequest(new { error = "Save failed" });
        }
        catch (Exception ex)
        {
            return StatusCode(500, new { error = ex.Message });
        }
    }
}

public record SaveManualRequest(string Category, List<string>? Tags, List<object>? Suggestions, string? Summary);

public record SmartCategoryDto(
    string Key,
    IReadOnlyDictionary<string, string> DisplayNames,
    IReadOnlyList<string> Keywords,
    IReadOnlyList<string> RegexPatterns);

public record AddRuleRequest(string Type, string Value);

public record AddRulesBatchRequest(List<string>? Keywords, List<string>? RegexPatterns);
