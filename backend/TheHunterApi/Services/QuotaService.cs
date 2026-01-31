using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;

namespace TheHunterApi.Services;

/// <summary>
/// ניהול מכסת סריקות AI - Free Tier: 50 סריקות לחודש למשתמש
/// </summary>
public class QuotaService
{
    private const int FreeTierLimit = 50;
    private readonly IDbContextFactory<AppDbContext> _dbFactory;

    public QuotaService(IDbContextFactory<AppDbContext> dbFactory)
    {
        _dbFactory = dbFactory;
    }

    /// <summary>
    /// בודק אם למשתמש יש מכסה פנויה (current + requested ≤ 50)
    /// </summary>
    public async Task<bool> CanUserScanAsync(string userId, int requestedAmount)
    {
        var yearMonth = DateTime.UtcNow.ToString("yyyy-MM");
        await using var db = await _dbFactory.CreateDbContextAsync();
        var usage = await db.UserAiUsages
            .Where(x => x.UserId == userId && x.YearMonth == yearMonth)
            .Select(x => x.ScanCount)
            .FirstOrDefaultAsync();
        return usage + requestedAmount <= FreeTierLimit;
    }

    /// <summary>
    /// מעדכן את שימוש המשתמש במכסה
    /// </summary>
    public async Task IncrementUsageAsync(string userId, int amount)
    {
        var yearMonth = DateTime.UtcNow.ToString("yyyy-MM");
        await using var db = await _dbFactory.CreateDbContextAsync();
        var row = await db.UserAiUsages
            .FirstOrDefaultAsync(x => x.UserId == userId && x.YearMonth == yearMonth);

        if (row == null)
        {
            db.UserAiUsages.Add(new UserAiUsage
            {
                UserId = userId,
                YearMonth = yearMonth,
                ScanCount = amount
            });
        }
        else
        {
            row.ScanCount += amount;
        }

        await db.SaveChangesAsync();
    }
}
