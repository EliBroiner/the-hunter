using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DictionaryController : ControllerBase
{
    private readonly AdminFirestoreService _firestore;

    public DictionaryController(AdminFirestoreService firestore)
    {
        _firestore = firestore;
    }

    /// <summary>
    /// מחזיר עדכוני מילון: synonyms ממונחים מאושרים ב-Firestore knowledge_base + rankingConfig מ-ranking_settings.
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

        return Ok(new DictionaryUpdatesResponse(synonyms, rankingConfig));
    }
}

/// <summary>
/// DTO למונח מאושר — ללא Id ו-IsApproved
/// </summary>
public record LearnedTermDto(string Term, string Category, int Frequency);

/// <summary>
/// תשובת עדכוני מילון — synonyms + rankingConfig
/// </summary>
public record DictionaryUpdatesResponse(
    IReadOnlyList<LearnedTermDto> Synonyms,
    IReadOnlyDictionary<string, double> RankingConfig);
