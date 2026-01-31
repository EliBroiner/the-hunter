using Microsoft.EntityFrameworkCore;

namespace TheHunterApi.Data;

/// <summary>
/// DbContext ראשי - SQLite לצורכי מכסת AI
/// </summary>
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options) : base(options) { }

    public DbSet<UserAiUsage> UserAiUsages => Set<UserAiUsage>();

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        modelBuilder.Entity<UserAiUsage>(e =>
        {
            e.HasKey(x => new { x.UserId, x.YearMonth });
            e.HasIndex(x => new { x.UserId, x.YearMonth });
        });
    }
}
