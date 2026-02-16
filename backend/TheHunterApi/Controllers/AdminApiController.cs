using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Filters;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>API לפעולות Admin — reset-dictionary וכו'.</summary>
[ApiController]
[Route("api/admin")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
public class AdminApiController : ControllerBase
{
    private readonly AdminFirestoreService _firestore;
    private readonly ILogger<AdminApiController> _logger;

    public AdminApiController(AdminFirestoreService firestore, ILogger<AdminApiController> logger)
    {
        _firestore = firestore;
        _logger = logger;
    }

    /// <summary>מנקה smart_categories ומזריע מחדש — דוחף את לוגיקת ה-seed ל-Firestore.</summary>
    [HttpPost("reset-dictionary")]
    [ProducesResponseType(StatusCodes.Status200OK)]
    public async Task<IActionResult> ResetDictionary(CancellationToken ct = default)
    {
        var deleted = await _firestore.PurgeSmartCategoriesAsync(ct);
        var seedCount = await _firestore.SeedSmartCategoriesAsync(ct);
        _logger.LogInformation("[SYNC] reset-dictionary: purged {Deleted}, seeded {SeedCount}", deleted, seedCount);
        return Ok(new { ok = true, purged = deleted, seeded = seedCount });
    }
}
