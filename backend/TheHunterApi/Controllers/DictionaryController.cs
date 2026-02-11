using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DictionaryController : ControllerBase
{
    private readonly AdminFirestoreService _firestore;
    private readonly IScannerSettingsService _scannerSettings;

    public DictionaryController(AdminFirestoreService firestore, IScannerSettingsService scannerSettings)
    {
        _firestore = firestore;
        _scannerSettings = scannerSettings;
    }

    /// <summary>
    /// מחזיר עדכוני מילון: synonyms, rankingConfig, scannerConfig (הגדרות סריקה דינמיות).
    /// </summary>
    [HttpGet("updates")]
    [ProducesResponseType(typeof(DictionaryUpdatesResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetUpdates()
    {
        var terms = await _firestore.GetApprovedTermsForExportAsync();
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
/// תשובת עדכוני מילון — synonyms + rankingConfig + scannerConfig
/// </summary>
public record DictionaryUpdatesResponse(
    IReadOnlyList<LearnedTermDto> Synonyms,
    IReadOnlyDictionary<string, double> RankingConfig,
    IReadOnlyDictionary<string, double>? ScannerConfig = null);
