using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class DictionaryController : ControllerBase
{
    private readonly IDbContextFactory<AppDbContext> _dbFactory;

    public DictionaryController(IDbContextFactory<AppDbContext> dbFactory)
    {
        _dbFactory = dbFactory;
    }

    /// <summary>
    /// מחזיר עדכוני מילון: synonyms (מונחים מאושרים) + rankingConfig (משקלי דירוג דינמיים)
    /// </summary>
    [HttpGet("updates")]
    [ProducesResponseType(typeof(DictionaryUpdatesResponse), StatusCodes.Status200OK)]
    public async Task<IActionResult> GetUpdates()
    {
        await using var db = _dbFactory.CreateDbContext();

        var synonyms = await db.LearnedTerms
            .Where(x => x.IsApproved)
            .OrderByDescending(x => x.Frequency)
            .Select(x => new LearnedTermDto(x.Term, x.Category, x.Frequency))
            .ToListAsync();

        var rankingSettings = await db.RankingSettings.ToListAsync();
        var rankingConfig = rankingSettings.ToDictionary(r => r.Key, r => r.Value);

        return Ok(new DictionaryUpdatesResponse(synonyms, rankingConfig));
    }
}

/// <summary>
/// DTO למונח מאושר - ללא Id ו-IsApproved
/// </summary>
public record LearnedTermDto(string Term, string Category, int Frequency);

/// <summary>
/// תשובת עדכוני מילון — synonyms + rankingConfig
/// </summary>
public record DictionaryUpdatesResponse(
    IReadOnlyList<LearnedTermDto> Synonyms,
    IReadOnlyDictionary<string, double> RankingConfig);
