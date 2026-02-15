using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DictionaryController : ControllerBase
{
    private readonly AdminFirestoreService _firestore;
    private readonly ISmartCategoriesService _smartCategories;
    private readonly IScannerSettingsService _scannerSettings;
    private readonly ILogger<DictionaryController> _logger;

    public DictionaryController(
        AdminFirestoreService firestore,
        ISmartCategoriesService smartCategories,
        IScannerSettingsService scannerSettings,
        ILogger<DictionaryController> logger)
    {
        _firestore = firestore;
        _smartCategories = smartCategories;
        _scannerSettings = scannerSettings;
        _logger = logger;
    }

    /// <summary>
    /// בדיקת גרסה — מחזיר count ו־lastModified (ISO8601). הלקוח משווה ל־lastSyncTimestamp.
    /// </summary>
    [HttpGet("version")]
    [ProducesResponseType(typeof(DictionaryVersionResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetVersion()
    {
        _logger.LogInformation("[BACKEND] Dictionary version requested.");
        var (count, lastModified) = await _firestore.GetDictionaryVersionAsync();
        return Ok(new DictionaryVersionResponse(count.ToString(), lastModified));
    }

    /// <summary>
    /// מחזיר עדכוני מילון מ-smart_categories (כל sourceType). ?since=ISO8601 — סנכרון חכם.
    /// </summary>
    [HttpGet("updates")]
    [ProducesResponseType(typeof(DictionaryUpdatesResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetUpdates([FromQuery] string? since = null)
    {
        DateTime? sinceDt = null;
        if (!string.IsNullOrWhiteSpace(since) && DateTime.TryParse(since, null, System.Globalization.DateTimeStyles.RoundtripKind, out var parsed))
            sinceDt = parsed.ToUniversalTime();

        var all = await _smartCategories.GetAllUnifiedAsync(sinceDt);
        var terms = all.Where(x => x.SourceType == "term" || x.SourceType == "ai_suggestion").ToList();
        var rules = all.Where(x => x.SourceType == "rule").ToList();

        var synonyms = terms
            .OrderByDescending(x => x.Frequency)
            .ThenByDescending(x => x.LastModified)
            .Select(x => new LearnedTermDto(x.Term ?? "", x.Category ?? "general", x.Frequency))
            .ToList();

        var smartCategories = rules.Select(r => new SmartCategoryDto(
            r.Key ?? "",
            r.DisplayNames,
            r.Keywords,
            r.RegexPatterns
        )).ToList();

        var (weights, ok) = await _firestore.GetRankingWeightsAsync();
        var rankingConfig = ok ? weights : new Dictionary<string, double>();

        var scannerConfig = new Dictionary<string, double>
        {
            ["garbageThresholdPercent"] = await _scannerSettings.GetGarbageThresholdPercentAsync(),
            ["minMeaningfulLength"] = await _scannerSettings.GetMinMeaningfulLengthAsync(),
            ["minValidCharRatioPercent"] = await _scannerSettings.GetMinValidCharRatioPercentAsync()
        };

        return Ok(new DictionaryUpdatesResponse(synonyms, rankingConfig, scannerConfig, smartCategories));
    }
}

public record LearnedTermDto(string Term, string Category, int Frequency);

public record DictionaryVersionResponse(string Version, string? LastModified = null);

public record DictionaryUpdatesResponse(
    IReadOnlyList<LearnedTermDto> Synonyms,
    IReadOnlyDictionary<string, double> RankingConfig,
    IReadOnlyDictionary<string, double>? ScannerConfig = null,
    IReadOnlyList<SmartCategoryDto>? SmartCategories = null);
