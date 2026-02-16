using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Caching.Memory;
using TheHunterApi.Data;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// מימוש ניהול פרומפטים — שליפה, טיוטה, והחלפת פעיל בטרנזקציה.
/// GetActivePromptAsync — ממומן 5 דקות להפחתת עומס על ה-DB.
/// </summary>
public class SystemPromptService : ISystemPromptService
{
    private readonly AppDbContext _db;
    private readonly IMemoryCache _cache;
    private readonly ILogger<SystemPromptService> _logger;

    private const string CacheKeyPrefix = "SystemPrompt:";
    private static readonly TimeSpan CacheDuration = TimeSpan.FromMinutes(5);

    public SystemPromptService(AppDbContext db, IMemoryCache cache, ILogger<SystemPromptService> logger)
    {
        _db = db;
        _cache = cache;
        _logger = logger;
    }

    /// <inheritdoc />
    public async Task<SystemPrompt?> GetActivePromptAsync(string feature)
    {
        if (string.IsNullOrWhiteSpace(feature))
            return null;

        var cacheKey = $"{CacheKeyPrefix}{feature}";
        return await _cache.GetOrCreateAsync(cacheKey, async entry =>
        {
            entry.AbsoluteExpirationRelativeToNow = CacheDuration;
            var prompt = await _db.SystemPrompts
                .AsNoTracking()
                .Where(p => p.Feature == feature && p.IsActive)
                .FirstOrDefaultAsync();
            _logger.LogDebug("SystemPrompt cache miss: Feature={Feature}, Cached={Cached}", feature, prompt != null);
            return prompt;
        });
    }

    /// <inheritdoc />
    public async Task<SystemPrompt> AddDraftAsync(string feature, string content, string version)
    {
        if (string.IsNullOrWhiteSpace(feature))
            throw new ArgumentException("Feature is required", nameof(feature));
        if (string.IsNullOrWhiteSpace(content))
            throw new ArgumentException("Content is required", nameof(content));
        if (string.IsNullOrWhiteSpace(version))
            throw new ArgumentException("Version is required", nameof(version));

        var prompt = new SystemPrompt
        {
            Content = content,
            Version = version,
            Feature = feature,
            IsActive = false,
            CreatedAt = DateTime.UtcNow
        };

        _db.SystemPrompts.Add(prompt);
        await _db.SaveChangesAsync();

        _logger.LogInformation("SystemPrompt draft added: Feature={Feature}, Version={Version}, Id={Id}",
            feature, version, prompt.Id);

        return prompt;
    }

    /// <inheritdoc />
    public async Task<bool> SetActiveByFeatureVersionAsync(string feature, string version)
    {
        if (string.IsNullOrWhiteSpace(feature) || string.IsNullOrWhiteSpace(version))
            return false;

        var prompt = await _db.SystemPrompts
            .FirstOrDefaultAsync(p => p.Feature == feature && p.Version == version);
        if (prompt == null)
        {
            _logger.LogWarning("SetActiveByFeatureVersion: Prompt not found Feature={Feature}, Version={Version}", feature, version);
            return false;
        }

        return await SetActiveAsync(prompt.Id);
    }

    /// <inheritdoc />
    public async Task<List<SystemPrompt>> GetPromptsForFeatureAsync(string feature)
    {
        if (string.IsNullOrWhiteSpace(feature))
            return [];

        var list = await _db.SystemPrompts
            .AsNoTracking()
            .Where(p => p.Feature == feature)
            .ToListAsync();

        return list.OrderByDescending(p => ParseVersionForSort(p.Version)).ToList();
    }

    /// <summary>ממיר גרסה למספר למיון — 1.2 → 102, 1.10 → 110.</summary>
    private static long ParseVersionForSort(string version)
    {
        var parts = version.Split('.');
        long result = 0;
        for (var i = 0; i < Math.Min(3, parts.Length); i++)
        {
            if (int.TryParse(parts[i], out var n))
                result = result * 1000 + n;
        }
        return result;
    }

    /// <inheritdoc />
    public async Task<bool> SetActiveAsync(int promptId)
    {
        var prompt = await _db.SystemPrompts.FindAsync(promptId);
        if (prompt == null)
        {
            _logger.LogWarning("SetActive: Prompt {Id} not found", promptId);
            return false;
        }

        await using var transaction = await _db.Database.BeginTransactionAsync();
        try
        {
            // ביטול פעילות של כל הפרומפטים באותו feature
            var others = await _db.SystemPrompts
                .Where(p => p.Feature == prompt.Feature && p.Id != promptId)
                .ToListAsync();

            foreach (var p in others)
            {
                p.IsActive = false;
            }

            // הפעלת הפרומפט הנבחר
            prompt.IsActive = true;
            prompt.ActivatedAt = DateTime.UtcNow;

            await _db.SaveChangesAsync();
            await transaction.CommitAsync();

            // ביטול cache — הפרומפט הפעיל השתנה
            _cache.Remove($"{CacheKeyPrefix}{prompt.Feature}");

            _logger.LogInformation("SystemPrompt activated: Id={Id}, Feature={Feature}, Version={Version}",
                prompt.Id, prompt.Feature, prompt.Version);

            return true;
        }
        catch (Exception ex)
        {
            await transaction.RollbackAsync();
            _logger.LogError(ex, "SetActive failed for prompt {Id}", promptId);
            throw;
        }
    }

    /// <inheritdoc />
    public async Task<List<SystemPrompt>> GetListAsync(string? feature = null)
    {
        var query = _db.SystemPrompts.AsNoTracking();
        if (!string.IsNullOrWhiteSpace(feature))
            query = query.Where(p => p.Feature == feature);
        return await query.OrderByDescending(p => p.CreatedAt).ToListAsync();
    }
}
