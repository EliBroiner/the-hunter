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
}

public record SmartCategoryDto(
    string Key,
    IReadOnlyDictionary<string, string> DisplayNames,
    IReadOnlyList<string> Keywords,
    IReadOnlyList<string> RegexPatterns);

public record AddRuleRequest(string Type, string Value);
