using Microsoft.AspNetCore.Mvc;
using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;
using TheHunterApi.Filters;
using TheHunterApi.Models;
using TheHunterApi.Services;

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
    private readonly IConfiguration _config;

    public AdminDashboardController(
        IDbContextFactory<AppDbContext> dbFactory,
        ILogger<AdminDashboardController> logger,
        IConfiguration config)
    {
        _dbFactory = dbFactory;
        _logger = logger;
        _config = config;
    }

    /// <summary>
    /// מציג את כל המונחים שממתינים לאישור + הגדרות דירוג
    /// </summary>
    [HttpGet]
    [Route("")]
    [Route("index")]
    public async Task<IActionResult> Index()
    {
        var dbOk = false;
        try
        {
            await using var db = _dbFactory.CreateDbContext();
            dbOk = await db.Database.CanConnectAsync();
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

            var geminiOk = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GEMINI_API_KEY"))
                || !string.IsNullOrEmpty(_config["GEMINI_API_KEY"]);
            var firebaseOk = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("FIREBASE_PROJECT_NUMBER"));

            return View(new AdminDashboardViewModel
            {
                PendingTerms = items,
                RankingWeights = rankingWeights,
                SearchActivities = searchActivities,
                DatabaseOk = dbOk,
                GeminiOk = geminiOk,
                FirebaseOk = firebaseOk,
                RecentErrors = AdminErrorTracker.RecentErrors
            });
        }
        catch (Exception ex)
        {
            AdminErrorTracker.AddError(ex.Message);
            return View(new AdminDashboardViewModel
            {
                PendingTerms = new List<LearnedTerm>(),
                RankingWeights = new Dictionary<string, double>(),
                SearchActivities = new List<SearchActivity>(),
                DatabaseOk = false,
                GeminiOk = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GEMINI_API_KEY"))
                    || !string.IsNullOrEmpty(_config["GEMINI_API_KEY"]),
                FirebaseOk = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("FIREBASE_PROJECT_NUMBER")),
                RecentErrors = AdminErrorTracker.RecentErrors
            });
        }
    }

    /// <summary>
    /// מנקה את רשימת שגיאות השרת ומחזיר ל-Index
    /// </summary>
    [HttpPost]
    [Route("clear-errors")]
    [ValidateAntiForgeryToken]
    public IActionResult ClearErrors()
    {
        AdminErrorTracker.ClearErrors();
        return RedirectToAction(nameof(Index));
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

    /// <summary>
    /// עמוד ניהול משתמשים — Admin, DebugAccess, User
    /// </summary>
    [HttpGet]
    [Route("users")]
    public async Task<IActionResult> Users()
    {
        await using var db = _dbFactory.CreateDbContext();
        var users = await db.AppManagedUsers.OrderBy(u => u.Email).ToListAsync();
        return View(users);
    }

    [HttpPost]
    [Route("users/add")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> AddUser([FromForm] string email, [FromForm] string role, [FromForm] string? userId)
    {
        if (string.IsNullOrWhiteSpace(email))
        {
            TempData["UsersMessage"] = "נא להזין מייל.";
            TempData["UsersMessageSuccess"] = false;
            return RedirectToAction(nameof(Users));
        }

        await using var db = _dbFactory.CreateDbContext();
        var normalizedEmail = email.Trim();
        if (await db.AppManagedUsers.AnyAsync(u => u.Email.Equals(normalizedEmail, StringComparison.OrdinalIgnoreCase)))
        {
            TempData["UsersMessage"] = "משתמש עם מייל זה כבר קיים.";
            TempData["UsersMessageSuccess"] = false;
            return RedirectToAction(nameof(Users));
        }

        var now = DateTime.UtcNow;
        db.AppManagedUsers.Add(new AppManagedUser
        {
            Email = normalizedEmail,
            UserId = string.IsNullOrWhiteSpace(userId) ? "" : userId.Trim(),
            Role = role is "Admin" or "DebugAccess" ? role : "User",
            CreatedAt = now,
            UpdatedAt = now,
        });
        await db.SaveChangesAsync();
        _logger.LogInformation("משתמש נוסף: {Email} תפקיד {Role}", normalizedEmail, role);
        TempData["UsersMessage"] = "המשתמש נוסף בהצלחה.";
        TempData["UsersMessageSuccess"] = true;
        return RedirectToAction(nameof(Users));
    }

    [HttpPost]
    [Route("users/update/{id:int}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> UpdateUser(int id, [FromForm] string role)
    {
        await using var db = _dbFactory.CreateDbContext();
        var user = await db.AppManagedUsers.FindAsync(id);
        if (user == null) return NotFound();

        user.Role = role is "Admin" or "DebugAccess" ? role : "User";
        user.UpdatedAt = DateTime.UtcNow;
        await db.SaveChangesAsync();
        _logger.LogInformation("משתמש עודכן: {Email} תפקיד {Role}", user.Email, user.Role);
        TempData["UsersMessage"] = "התפקיד עודכן.";
        TempData["UsersMessageSuccess"] = true;
        return RedirectToAction(nameof(Users));
    }

    [HttpPost]
    [Route("users/delete/{id:int}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteUser(int id)
    {
        await using var db = _dbFactory.CreateDbContext();
        var user = await db.AppManagedUsers.FindAsync(id);
        if (user == null) return NotFound();

        db.AppManagedUsers.Remove(user);
        await db.SaveChangesAsync();
        _logger.LogInformation("משתמש נמחק: {Email}", user.Email);
        TempData["UsersMessage"] = "המשתמש נמחק.";
        TempData["UsersMessageSuccess"] = true;
        return RedirectToAction(nameof(Users));
    }
}
