using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;
using TheHunterApi.Filters;
using TheHunterApi.Models;

namespace TheHunterApi.Controllers;

/// <summary>
/// לוח בקרה לניהול מונחים שנלמדו - אישור/מחיקה
/// </summary>
[Route("admin")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
public class AdminDashboardController : Controller
{
    private readonly IDbContextFactory<AppDbContext> _dbFactory;
    private readonly ILogger<AdminDashboardController> _logger;

    public AdminDashboardController(IDbContextFactory<AppDbContext> dbFactory, ILogger<AdminDashboardController> logger)
    {
        _dbFactory = dbFactory;
        _logger = logger;
    }

    /// <summary>
    /// מציג את כל המונחים שממתינים לאישור + הגדרות דירוג
    /// </summary>
    [HttpGet]
    [Route("")]
    [Route("index")]
    public async Task<IActionResult> Index()
    {
        await using var db = _dbFactory.CreateDbContext();
        var items = await db.LearnedTerms
            .Where(x => !x.IsApproved)
            .OrderByDescending(x => x.Frequency)
            .ThenByDescending(x => x.LastSeen)
            .ToListAsync();
        var rankingSettings = await db.RankingSettings.ToListAsync();
        var rankingWeights = rankingSettings.ToDictionary(r => r.Key, r => r.Value);

        var searchActivities = await db.SearchActivities
            .OrderByDescending(x => x.Count)
            .Take(50)
            .ToListAsync();

        return View(new AdminDashboardViewModel
        {
            PendingTerms = items,
            RankingWeights = rankingWeights,
            SearchActivities = searchActivities
        });
    }

    /// <summary>
    /// מעדכן משקלי דירוג — עובר על המילון ומעדכן ערכים ב-DB
    /// </summary>
    [HttpPost]
    [Route("update-weights")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> UpdateWeights([FromForm] Dictionary<string, double> newWeights)
    {
        if (newWeights == null || newWeights.Count == 0)
        {
            TempData["WeightsMessage"] = "לא התקבלו ערכים לעדכון.";
            TempData["WeightsMessageSuccess"] = false;
            return RedirectToAction(nameof(Index));
        }

        await using var db = _dbFactory.CreateDbContext();
        foreach (var kvp in newWeights)
        {
            var existing = await db.RankingSettings.FindAsync(kvp.Key);
            if (existing != null)
            {
                existing.Value = kvp.Value;
            }
            else
            {
                db.RankingSettings.Add(new RankingSetting { Key = kvp.Key, Value = kvp.Value });
            }
        }
        await db.SaveChangesAsync();
        _logger.LogInformation("משקלי דירוג עודכנו: {Count} מפתחות", newWeights.Count);
        TempData["WeightsMessage"] = "המשקלים עודכנו בהצלחה.";
        TempData["WeightsMessageSuccess"] = true;
        return RedirectToAction(nameof(Index));
    }

    /// <summary>
    /// מאפס משקלי דירוג לברירות המחדל הקשיחות (200, 120, 80, 1.2, 150)
    /// </summary>
    [HttpPost]
    [Route("reset-weights")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> ResetWeights()
    {
        var defaults = new Dictionary<string, double>
        {
            { "filenameWeight", 200.0 },
            { "contentWeight", 120.0 },
            { "pathWeight", 80.0 },
            { "fullMatchMultiplier", 1.2 },
            { "exactPhraseBonus", 150.0 }
        };

        await using var db = _dbFactory.CreateDbContext();
        foreach (var kvp in defaults)
        {
            var existing = await db.RankingSettings.FindAsync(kvp.Key);
            if (existing != null)
                existing.Value = kvp.Value;
            else
                db.RankingSettings.Add(new RankingSetting { Key = kvp.Key, Value = kvp.Value });
        }
        await db.SaveChangesAsync();
        _logger.LogInformation("משקלי דירוג אופסו לברירות מחדל");
        TempData["WeightsMessage"] = "המשקלים אופסו לברירות המחדל.";
        TempData["WeightsMessageSuccess"] = true;
        return RedirectToAction(nameof(Index));
    }

    /// <summary>
    /// מאשר מונח - מעדכן IsApproved = true (אישור ידני ללא תלות בסף תדירות)
    /// </summary>
    [HttpPost]
    [Route("approve/{id:int}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Approve(int id)
    {
        await using var db = _dbFactory.CreateDbContext();
        var term = await db.LearnedTerms.FindAsync(id);
        if (term == null)
            return NotFound();

        term.IsApproved = true;
        term.LastSeen = DateTime.UtcNow;
        await db.SaveChangesAsync();
        _logger.LogInformation("מונח אושר ידנית: {Term} ({Category}) Id={Id}", term.Term, term.Category, id);
        return RedirectToAction(nameof(Index));
    }

    /// <summary>
    /// מוחק מונח מהמערכת
    /// </summary>
    [HttpPost]
    [Route("delete/{id:int}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(int id)
    {
        await using var db = _dbFactory.CreateDbContext();
        var term = await db.LearnedTerms.FindAsync(id);
        if (term == null)
            return NotFound();

        db.LearnedTerms.Remove(term);
        await db.SaveChangesAsync();
        _logger.LogInformation("מונח נמחק: {Term} Id={Id}", term.Term, id);
        return RedirectToAction(nameof(Index));
    }
}
