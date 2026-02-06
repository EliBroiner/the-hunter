using Microsoft.EntityFrameworkCore;
using TheHunterApi.Models;

namespace TheHunterApi.Data;

/// <summary>
/// DbContext ראשי - SQLite לצורכי מכסת AI
/// </summary>
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<UserAiUsage> UserAiUsages => Set<UserAiUsage>();
    public DbSet<LearnedTerm> LearnedTerms => Set<LearnedTerm>();
    public DbSet<UserLearningQuota> UserLearningQuotas => Set<UserLearningQuota>();
    public DbSet<RankingSetting> RankingSettings => Set<RankingSetting>();
    public DbSet<SearchActivity> SearchActivities => Set<SearchActivity>();
    public DbSet<AppManagedUser> AppManagedUsers => Set<AppManagedUser>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<UserAiUsage>(e =>
        {
            e.HasKey(x => new { x.UserId, x.YearMonth });
            e.HasIndex(x => new { x.UserId, x.YearMonth });
        });

        // טבלת מונחים שנלמדו - לולאת למידה
        modelBuilder.Entity<LearnedTerm>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Term);
            e.HasIndex(x => new { x.Term, x.Category }).IsUnique();
        });

        // מכסת הצעות מונחים ליום למשתמש - מניעת Dictionary Stuffing
        modelBuilder.Entity<UserLearningQuota>(e =>
        {
            e.HasKey(x => new { x.UserId, x.DateKey });
            e.HasIndex(x => new { x.UserId, x.DateKey });
        });

        // משקלי דירוג דינמיים — seed בהתאם ל-config הקיים (200, 120, 80, 1.2, 150)
        modelBuilder.Entity<RankingSetting>(e =>
        {
            e.HasKey(x => x.Key);
        });
        modelBuilder.Entity<RankingSetting>().HasData(
            new RankingSetting { Key = "filenameWeight", Value = 200.0 },
            new RankingSetting { Key = "contentWeight", Value = 120.0 },
            new RankingSetting { Key = "pathWeight", Value = 80.0 },
            new RankingSetting { Key = "fullMatchMultiplier", Value = 1.2 },
            new RankingSetting { Key = "exactPhraseBonus", Value = 150.0 }
        );

        // סטטיסטיקת חיפושים — מונחים נפוצים לסיוע בבחירת synonyms
        modelBuilder.Entity<SearchActivity>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.Term).IsUnique();
        });

        // ניהול משתמשים ותפקידים — Admin, DebugAccess, User
        modelBuilder.Entity<AppManagedUser>(e =>
        {
            e.HasKey(x => x.Id);
            e.HasIndex(x => x.UserId).IsUnique();
            e.HasIndex(x => x.Email);
        });
    }
}
