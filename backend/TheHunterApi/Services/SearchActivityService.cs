using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// מעקב סטטיסטיקת חיפושים — מונחים שחיפשו המשתמשים (להחלטות על synonyms)
/// </summary>
public interface ISearchActivityService
{
    Task RecordSearchTermsAsync(IEnumerable<string> terms);
}

public class SearchActivityService : ISearchActivityService
{
    private readonly IDbContextFactory<AppDbContext> _dbFactory;

    public SearchActivityService(IDbContextFactory<AppDbContext> dbFactory)
    {
        _dbFactory = dbFactory;
    }

    /// <summary>
    /// מעלה מונה לכל מונח שחיפשו — אם חדש יוצר רשומה
    /// </summary>
    public async Task RecordSearchTermsAsync(IEnumerable<string> terms)
    {
        var list = terms.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t.Trim()).Distinct().ToList();
        if (list.Count == 0) return;

        await using var db = _dbFactory.CreateDbContext();
        var now = DateTime.UtcNow;

        foreach (var term in list)
        {
            var existing = await db.SearchActivities.FirstOrDefaultAsync(x => x.Term == term);
            if (existing != null)
            {
                existing.Count++;
                existing.LastSearch = now;
            }
            else
            {
                db.SearchActivities.Add(new SearchActivity
                {
                    Term = term,
                    Count = 1,
                    LastSearch = now
                });
            }
        }

        await db.SaveChangesAsync();
    }
}
