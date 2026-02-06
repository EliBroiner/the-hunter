using System.Collections.Concurrent;
using Microsoft.EntityFrameworkCore;
using Serilog;
using TheHunterApi.Data;

namespace TheHunterApi.Services;

/// <summary>
/// ניהול מכסת סריקות AI — בשלב בדיקות: 1000 סריקות לחודש
/// </summary>
public class QuotaService
{
    private const int FreeTierLimit = 1000;
    private readonly IDbContextFactory<AppDbContext> _dbFactory;

    // מפתח לכל userId — מניעת race על UNIQUE(UserId, YearMonth)
    private static readonly ConcurrentDictionary<string, SemaphoreSlim> PerUserLocks = new();

    public QuotaService(IDbContextFactory<AppDbContext> dbFactory)
    {
        _dbFactory = dbFactory;
    }

    private static SemaphoreSlim GetLockForUser(string userId) =>
        PerUserLocks.GetOrAdd(userId, _ => new SemaphoreSlim(1, 1));

    /// <summary>
    /// בודק אם למשתמש יש מכסה פנויה — אם אין רשומה ב-DB נחשב 0 ומוענק שימוש
    /// </summary>
    public async Task<bool> CanUserScanAsync(string userId, int requestedAmount)
    {
        var yearMonth = DateTime.UtcNow.ToString("yyyy-MM");
        await using var db = _dbFactory.CreateDbContext();
        var row = await db.UserAiUsages
            .FirstOrDefaultAsync(x => x.UserId == userId && x.YearMonth == yearMonth);
        var current = row?.ScanCount ?? 0;
        var allowed = current + requestedAmount <= FreeTierLimit;
        Log.Information("User {UserId} quota: {Current}/{Max} (requested {Requested}) → {Result}",
            userId, current, FreeTierLimit, requestedAmount, allowed ? "ALLOWED" : "BLOCKED");
        return allowed;
    }

    /// <summary>
    /// Upsert: אם קיים — מעלה Count; אם לא — יוצר רשומה. Retry אם race עם thread אחר.
    /// </summary>
    public async Task IncrementUsageAsync(string userId, int amount)
    {
        var yearMonth = DateTime.UtcNow.ToString("yyyy-MM");
        Log.Information("[Quota] Incrementing usage for user {UserId} for month {YearMonth}", userId, yearMonth);

        var sem = GetLockForUser(userId);
        await sem.WaitAsync();
        try
        {
            const int maxRetries = 3;
            for (var attempt = 0; attempt < maxRetries; attempt++)
            {
                try
                {
                    await using var db = _dbFactory.CreateDbContext();
                    var row = await db.UserAiUsages
                        .FirstOrDefaultAsync(x => x.UserId == userId && x.YearMonth == yearMonth);

                    if (row != null)
                    {
                        row.ScanCount += amount;
                    }
                    else
                    {
                        db.UserAiUsages.Add(new UserAiUsage
                        {
                            UserId = userId,
                            YearMonth = yearMonth,
                            ScanCount = amount
                        });
                    }

                    await db.SaveChangesAsync();
                    return;
                }
                catch (DbUpdateException ex) when (attempt < maxRetries - 1)
                {
                    // UNIQUE(UserId,YearMonth) — thread אחר יצר את הרשומה, ננסה שוב עם Increment
                    Log.Warning(ex, "[Quota] Unique constraint on user {UserId} month {YearMonth}, retry {Attempt}", userId, yearMonth, attempt + 1);
                }
            }
        }
        finally
        {
            sem.Release();
        }
    }
}
