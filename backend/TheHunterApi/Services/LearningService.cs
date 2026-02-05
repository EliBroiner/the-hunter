using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שירות לולאת למידה - עדכון מונחים שנלמדו מ-AI עם הגנה מפני Dictionary Stuffing
/// </summary>
public interface ILearningService
{
    /// <summary>
    /// מעבד תוצאה מ-AI: מוסיף מונח חדש או מעלה תדירות אם קיים
    /// </summary>
    /// <param name="userId">מזהה משתמש לאימות מכסת הצעות יומית (null = אין אכיפה)</param>
    Task ProcessAiResultAsync(string term, string category, string? userId = null);
}

public class LearningService : ILearningService
{
    private const int ApprovalFrequencyThreshold = 5; // IsApproved = true רק כשהתדירות >= ערך זה
    private const int MaxSuggestionsPerUserPerDay = 30;

    private readonly IDbContextFactory<AppDbContext> _dbFactory;
    private readonly ILogger<LearningService> _logger;

    public LearningService(IDbContextFactory<AppDbContext> dbFactory, ILogger<LearningService> logger)
    {
        _dbFactory = dbFactory;
        _logger = logger;
    }

    public async Task ProcessAiResultAsync(string term, string category, string? userId = null)
    {
        // סניטציה - דחיית מונחים לא תקינים
        if (!TermValidator.IsValidTerm(term))
        {
            _logger.LogDebug("מונח נדחה - לא עבר ולידציה: {Term}", term.Length > 50 ? term[..50] + "…" : term);
            return;
        }
        if (!TermValidator.IsValidCategory(category))
        {
            _logger.LogDebug("קטגוריה נדחתה: {Category}", category);
            return;
        }

        var cat = string.IsNullOrWhiteSpace(category) ? "general" : category.Trim();
        var t = term.Trim();

        await using var db = _dbFactory.CreateDbContext();

        var existing = await db.LearnedTerms
            .FirstOrDefaultAsync(x => x.Term == t && x.Category == cat);

        if (existing != null)
        {
            // מונח קיים - עדכון תדירות בלבד (אין מכסת משתמש)
            existing.Frequency++;
            existing.LastSeen = DateTime.UtcNow;
            // העלאה ל-IsApproved כשהתדירות מגיעה לסף
            if (!existing.IsApproved && existing.Frequency >= ApprovalFrequencyThreshold)
            {
                existing.IsApproved = true;
                _logger.LogInformation("מונח אושר אוטומטית: {Term} ({Category}) תדירות={Freq}", t, cat, existing.Frequency);
            }
        }
        else
        {
            // מונח חדש - בדיקת מכסת משתמש
            if (!string.IsNullOrWhiteSpace(userId) && !await CanUserSuggestAsync(db, userId))
            {
                _logger.LogWarning("משתמש {UserId} חרג ממכסת ההצעות היומית", userId);
                return;
            }

            db.LearnedTerms.Add(new LearnedTerm
            {
                Term = t,
                Category = cat,
                Frequency = 1,
                IsApproved = false,
                LastSeen = DateTime.UtcNow
            });

            // עדכון מכסת משתמש
            if (!string.IsNullOrWhiteSpace(userId))
                await IncrementUserSuggestionCountAsync(db, userId);
        }

        await db.SaveChangesAsync();
    }

    /// <summary>
    /// בודק אם למשתמש נשארה מכסה יומית
    /// </summary>
    private static async Task<bool> CanUserSuggestAsync(AppDbContext db, string userId)
    {
        var dateKey = DateTime.UtcNow.ToString("yyyy-MM-dd");
        var quota = await db.UserLearningQuotas
            .Where(x => x.UserId == userId && x.DateKey == dateKey)
            .Select(x => x.SuggestionCount)
            .FirstOrDefaultAsync();
        return quota < MaxSuggestionsPerUserPerDay;
    }

    /// <summary>
    /// מעלה את מונה ההצעות היומי של המשתמש
    /// </summary>
    private static async Task IncrementUserSuggestionCountAsync(AppDbContext db, string userId)
    {
        var dateKey = DateTime.UtcNow.ToString("yyyy-MM-dd");
        var row = await db.UserLearningQuotas
            .FirstOrDefaultAsync(x => x.UserId == userId && x.DateKey == dateKey);

        if (row == null)
        {
            db.UserLearningQuotas.Add(new UserLearningQuota
            {
                UserId = userId,
                DateKey = dateKey,
                SuggestionCount = 1
            });
        }
        else
        {
            row.SuggestionCount++;
        }
    }
}
