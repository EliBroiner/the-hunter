using ClosedXML.Excel;
using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Filters;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// לוח בקרה לניהול — נתונים מ-Firestore (knowledge_base, users, logs).
/// </summary>
[Route("admin")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
public class AdminDashboardController : Controller
{
    private readonly AdminFirestoreService _firestore;
    private readonly INotificationService _notification;
    private readonly ILogger<AdminDashboardController> _logger;
    private readonly IConfiguration _config;

    public AdminDashboardController(
        AdminFirestoreService firestore,
        INotificationService notification,
        ILogger<AdminDashboardController> logger,
        IConfiguration config)
    {
        _firestore = firestore;
        _notification = notification;
        _logger = logger;
        _config = config;
    }

    [HttpGet]
    [Route("")]
    [Route("index")]
    public async Task<IActionResult> Index()
    {
        var keyFromCookie = Request.Cookies["admin_session"] != null;
        _logger.LogInformation("DEBUG: API Request received for Admin Index (Terms). Key from cookie: {FromCookie}", keyFromCookie);
        Console.WriteLine($"DEBUG: API Request received for [Admin Index]. Key from cookie: {keyFromCookie}");

        try
        {
            var (terms, termsOk) = await _firestore.GetPendingTermsAsync();
            var (weights, weightsOk) = await _firestore.GetRankingWeightsAsync();
            var (activities, logsOk) = await _firestore.GetLogsAsync(50);

            if (terms.Count == 0)
            {
                _logger.LogWarning("[Admin Index] knowledge_base ריק. ProjectId={ProjectId}. ודא ש-FIRESTORE_PROJECT_ID מוגדר נכון ב-env.", _firestore.EffectiveProjectId);
            }
            if (activities.Count == 0)
            {
                _logger.LogWarning("[Admin Index] logs ריק. ProjectId={ProjectId}. ודא ש-FIRESTORE_PROJECT_ID מוגדר נכון ב-env.", _firestore.EffectiveProjectId);
            }

            var totalUsers = await _firestore.GetUsersCountAsync();
            var pendingCount = await _firestore.GetPendingTermsCountAsync();
            var approvedCount = await _firestore.GetApprovedTermsCountAsync();
            var newTermsPerDay = await _firestore.GetNewTermsPerDayAsync(30);

            await _notification.NotifyIfPendingThresholdAsync(pendingCount, terms.FirstOrDefault());
            var threshold = _config.GetValue("Admin:Notification:PendingThreshold", 10);
            if (pendingCount >= threshold)
                ViewBag.PendingAlert = $"Action Required: {pendingCount} terms are waiting for your approval in The Hunter Admin.";

            _logger.LogInformation("[Admin Index] PendingTerms: {Count}, RankingKeys: {RCount}, SearchActivities: {SCount}",
                terms.Count, weights.Count, activities.Count);

            var dbOk = termsOk && weightsOk && logsOk;
            var geminiOk = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("GEMINI_API_KEY"))
                || !string.IsNullOrEmpty(_config["GEMINI_API_KEY"]);
            var firebaseOk = !string.IsNullOrEmpty(Environment.GetEnvironmentVariable("FIREBASE_PROJECT_NUMBER"));

            return View(new AdminDashboardViewModel
            {
                PendingTerms = terms,
                RankingWeights = weights,
                SearchActivities = activities,
                DatabaseOk = dbOk,
                GeminiOk = geminiOk,
                FirebaseOk = firebaseOk,
                RecentErrors = AdminErrorTracker.RecentErrors,
                TotalUsers = totalUsers,
                PendingTermsCount = pendingCount,
                ApprovedTermsCount = approvedCount,
                NewTermsPerDay = newTermsPerDay
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            Console.WriteLine($"ERROR fetching from Firestore: {ex.Message}");
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
                RecentErrors = AdminErrorTracker.RecentErrors,
                TotalUsers = 0,
                PendingTermsCount = 0,
                ApprovedTermsCount = 0,
                NewTermsPerDay = new Dictionary<string, int>()
            });
        }
    }

    [HttpGet]
    [Route("term/edit/{id}")]
    public async Task<IActionResult> EditTerm(string id)
    {
        if (string.IsNullOrEmpty(id)) return NotFound();
        var term = await _firestore.GetTermByIdAsync(id);
        if (term == null) return NotFound();
        return View(term);
    }

    [HttpPost]
    [Route("term/update")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> UpdateTerm([FromForm] string? FirestoreId, [FromForm] string Term, [FromForm] string? Definition, [FromForm] string Category)
    {
        if (string.IsNullOrEmpty(FirestoreId)) return NotFound();
        var ok = await _firestore.UpdateTermAsync(FirestoreId, Term ?? "", Definition ?? "", Category ?? "");
        if (!ok) return NotFound();
        TempData["WeightsMessage"] = "המונח עודכן בהצלחה.";
        TempData["WeightsMessageSuccess"] = true;
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [Route("clear-errors")]
    [ValidateAntiForgeryToken]
    public IActionResult ClearErrors()
    {
        AdminErrorTracker.ClearErrors();
        return RedirectToAction(nameof(Index));
    }

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
        await _firestore.SetRankingWeightsAsync(newWeights);
        _logger.LogInformation("משקלי דירוג עודכנו: {Count} מפתחות", newWeights.Count);
        TempData["WeightsMessage"] = "המשקלים עודכנו בהצלחה.";
        TempData["WeightsMessageSuccess"] = true;
        return RedirectToAction(nameof(Index));
    }

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
        await _firestore.SetRankingWeightsAsync(defaults);
        _logger.LogInformation("משקלי דירוג אופסו לברירות מחדל");
        TempData["WeightsMessage"] = "המשקלים אופסו לברירות המחדל.";
        TempData["WeightsMessageSuccess"] = true;
        return RedirectToAction(nameof(Index));
    }

    [HttpPost]
    [Route("approve/{id}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Approve(string id)
    {
        if (string.IsNullOrEmpty(id)) return NotFound();
        var ok = await _firestore.ApproveTermAsync(id);
        if (!ok) return NotFound();
        _logger.LogInformation("DEBUG: Term {TermId} was approved by admin.", id);
        Console.WriteLine($"DEBUG: Term {id} was approved by admin.");
        return RedirectToAction(nameof(Index));
    }

    /// <summary>
    /// מאשר מונח (קריאה מ־AJAX) — מחזיר JSON.
    /// </summary>
    [HttpPost]
    [Route("approve-term")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> ApproveTerm([FromForm] string termId)
    {
        if (string.IsNullOrEmpty(termId)) return NotFound();
        var ok = await _firestore.ApproveTermAsync(termId);
        if (!ok) return NotFound();
        _logger.LogInformation("DEBUG: Term {TermId} was approved by admin.", termId);
        Console.WriteLine($"DEBUG: Term {termId} was approved by admin.");
        return Json(new { success = true, termId });
    }

    [HttpPost]
    [Route("delete/{id}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> Delete(string id)
    {
        if (string.IsNullOrEmpty(id)) return NotFound();
        var ok = await _firestore.DeleteTermAsync(id);
        if (!ok) return NotFound();
        _logger.LogInformation("מונח נמחק, doc Id={Id}", id);
        return RedirectToAction(nameof(Index));
    }

    [HttpGet]
    [Route("users")]
    public async Task<IActionResult> Users()
    {
        var keyFromCookie = Request.Cookies["admin_session"] != null;
        _logger.LogInformation("DEBUG: API Request received for Admin Users. Key from cookie: {FromCookie}", keyFromCookie);
        Console.WriteLine($"DEBUG: API Request received for [Admin Users]. Key from cookie: {keyFromCookie}");

        try
        {
            var (users, ok) = await _firestore.GetUsersAsync();
            if (users.Count == 0)
            {
                _logger.LogWarning("[Admin Users] users ריק. ProjectId={ProjectId}. ודא ש-FIRESTORE_PROJECT_ID מוגדר נכון ב-env.", _firestore.EffectiveProjectId);
            }
            _logger.LogInformation("[Admin Users] users count: {Count}", users.Count);
            return View(users);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            Console.WriteLine($"ERROR fetching from Firestore: {ex.Message}");
            return View(new List<AdminUserViewModel>());
        }
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
        var added = await _firestore.AddUserAsync(email.Trim(), userId?.Trim() ?? "", role);
        if (!added)
        {
            TempData["UsersMessage"] = "משתמש עם מייל זה כבר קיים.";
            TempData["UsersMessageSuccess"] = false;
            return RedirectToAction(nameof(Users));
        }
        _logger.LogInformation("משתמש נוסף: {Email} תפקיד {Role}", email.Trim(), role);
        TempData["UsersMessage"] = "המשתמש נוסף בהצלחה.";
        TempData["UsersMessageSuccess"] = true;
        return RedirectToAction(nameof(Users));
    }

    [HttpPost]
    [Route("users/update/{id}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> UpdateUser(string id, [FromForm] string role)
    {
        if (string.IsNullOrEmpty(id)) return NotFound();
        var ok = await _firestore.UpdateUserRoleAsync(id, role);
        if (!ok) return NotFound();
        _logger.LogInformation("משתמש עודכן, doc Id={Id} תפקיד {Role}", id, role);
        TempData["UsersMessage"] = "התפקיד עודכן.";
        TempData["UsersMessageSuccess"] = true;
        return RedirectToAction(nameof(Users));
    }

    [HttpPost]
    [Route("users/delete/{id}")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> DeleteUser(string id)
    {
        if (string.IsNullOrEmpty(id)) return NotFound();
        var ok = await _firestore.DeleteUserAsync(id);
        if (!ok) return NotFound();
        _logger.LogInformation("משתמש נמחק, doc Id={Id}", id);
        TempData["UsersMessage"] = "המשתמש נמחק.";
        TempData["UsersMessageSuccess"] = true;
        return RedirectToAction(nameof(Users));
    }

    /// <summary>API לסטטיסטיקות לרענון ללא reload — JSON.</summary>
    [HttpGet]
    [Route("api/stats")]
    public async Task<IActionResult> GetStats()
    {
        var totalUsers = await _firestore.GetUsersCountAsync();
        var pendingTermsCount = await _firestore.GetPendingTermsCountAsync();
        var approvedTermsCount = await _firestore.GetApprovedTermsCountAsync();
        var lastUpdated = DateTime.UtcNow.ToString("yyyy-MM-ddTHH:mm:ssZ");
        return Json(new { totalUsers, pendingTermsCount, approvedTermsCount, lastUpdated });
    }

    /// <summary>ייצוא מונחים מאושרים ל-Excel — עמודות: ID, Term, Definition, Category, Date Created.</summary>
    [HttpGet]
    [Route("export-approved-terms")]
    public async Task<IActionResult> ExportApprovedTerms()
    {
        var terms = await _firestore.GetApprovedTermsForExportAsync();
        using var wb = new XLWorkbook();
        var ws = wb.Worksheets.Add("Approved Terms");
        ws.Cell(1, 1).Value = "ID";
        ws.Cell(1, 2).Value = "Term";
        ws.Cell(1, 3).Value = "Definition";
        ws.Cell(1, 4).Value = "Category";
        ws.Cell(1, 5).Value = "Date Created";
        int row = 2;
        foreach (var t in terms)
        {
            ws.Cell(row, 1).Value = t.FirestoreId ?? "";
            ws.Cell(row, 2).Value = t.Term ?? "";
            ws.Cell(row, 3).Value = t.Definition ?? "";
            ws.Cell(row, 4).Value = t.Category ?? "";
            ws.Cell(row, 5).Value = t.LastSeen;
            row++;
        }
        using var stream = new MemoryStream();
        wb.SaveAs(stream);
        stream.Position = 0;
        var fileName = $"ApprovedTerms_{DateTime.UtcNow:yyyyMMddHHmmss}.xlsx";
        return File(stream.ToArray(), "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", fileName);
    }

    /// <summary>טריגר ידני לשליחת דוח יומי ל-Telegram.</summary>
    [HttpPost]
    [Route("send-daily-summary")]
    [ValidateAntiForgeryToken]
    public async Task<IActionResult> SendDailySummary()
    {
        var telegram = HttpContext.RequestServices.GetService<ITelegramService>();
        if (telegram == null) return BadRequest("Telegram not configured.");
        await telegram.SendDailySummaryAsync();
        TempData["WeightsMessage"] = "דוח יומי נשלח ל-Telegram.";
        TempData["WeightsMessageSuccess"] = true;
        return RedirectToAction(nameof(Index));
    }
}
