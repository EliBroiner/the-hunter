using Microsoft.EntityFrameworkCore;
using TheHunterApi.Models;

namespace TheHunterApi.Data;

/// <summary>
/// DbContext עבור מקור נתונים SQLite — טבלת SystemPrompts.
/// </summary>
public class AppDbContext : DbContext
{
    public AppDbContext(DbContextOptions<AppDbContext> options)
        : base(options)
    {
    }

    public DbSet<SystemPrompt> SystemPrompts { get; set; }

    protected override void OnModelCreating(ModelBuilder modelBuilder)
    {
        // אינדקס לחיפוש לפי feature ופעיל
        modelBuilder.Entity<SystemPrompt>()
            .HasIndex(e => new { e.Feature, e.IsActive });
    }
}
