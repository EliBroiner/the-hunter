using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DictionaryController : ControllerBase
{
    private readonly AdminFirestoreService _firestore;
    private readonly IScannerSettingsService _scannerSettings;
    private readonly ILogger<DictionaryController> _logger;

    public DictionaryController(AdminFirestoreService firestore, IScannerSettingsService scannerSettings, ILogger<DictionaryController> logger)
    {
        _firestore = firestore;
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
        _logger.LogInformation("[BACKEND] Dictionary version requested. Returning latest timestamp for incremental sync.");
        var (count, lastModified) = await _firestore.GetDictionaryVersionAsync();
        return Ok(new DictionaryVersionResponse(count.ToString(), lastModified));
    }

    /// <summary>
    /// מחזיר עדכוני מילון. ?since=ISO8601 — רק מונחים שעודכנו אחרי התאריך (סנכרון חכם).
    /// </summary>
    [HttpGet("updates")]
    [ProducesResponseType(typeof(DictionaryUpdatesResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetUpdates([FromQuery] string? since = null)
    {
        DateTime? sinceDt = null;
        if (!string.IsNullOrWhiteSpace(since) && DateTime.TryParse(since, null, System.Globalization.DateTimeStyles.RoundtripKind, out var parsed))
            sinceDt = parsed.ToUniversalTime();
        var terms = await _firestore.GetApprovedTermsForExportAsync(sinceDt);
        var synonyms = terms
            .OrderByDescending(x => x.Frequency)
            .Select(x => new LearnedTermDto(x.Term, x.Category, x.Frequency))
            .ToList();

        var (weights, ok) = await _firestore.GetRankingWeightsAsync();
        var rankingConfig = ok ? weights : new Dictionary<string, double>();

        var scannerConfig = new Dictionary<string, double>
        {
            ["garbageThresholdPercent"] = await _scannerSettings.GetGarbageThresholdPercentAsync(),
            ["minMeaningfulLength"] = await _scannerSettings.GetMinMeaningfulLengthAsync(),
            ["minValidCharRatioPercent"] = await _scannerSettings.GetMinValidCharRatioPercentAsync()
        };

        return Ok(new DictionaryUpdatesResponse(synonyms, rankingConfig, scannerConfig));
    }
}

/// <summary>
/// DTO למונח מאושר — ללא Id ו-IsApproved
/// </summary>
public record LearnedTermDto(string Term, string Category, int Frequency);

/// <summary>
/// תשובת בדיקת גרסה — count + lastModified (ISO8601)
/// </summary>
public record DictionaryVersionResponse(string Version, string? LastModified = null);

/// <summary>
/// תשובת עדכוני מילון — synonyms + rankingConfig + scannerConfig
/// </summary>
public record DictionaryUpdatesResponse(
    IReadOnlyList<LearnedTermDto> Synonyms,
    IReadOnlyDictionary<string, double> RankingConfig,
    IReadOnlyDictionary<string, double>? ScannerConfig = null);
