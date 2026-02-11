using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// מימוש ניהול פרומפטים — שליפה, טיוטה, והחלפת פעיל בטרנזקציה.
/// </summary>
public class SystemPromptService : ISystemPromptService
{
    private readonly AppDbContext _db;
    private readonly ILogger<SystemPromptService> _logger;

    public SystemPromptService(AppDbContext db, ILogger<SystemPromptService> logger)
    {
        _db = db;
        _logger = logger;
    }

    /// <inheritdoc />
    public async Task<SystemPrompt?> GetActivePromptAsync(string feature)
    {
        if (string.IsNullOrWhiteSpace(feature))
            return null;

        return await _db.SystemPrompts
            .Where(p => p.Feature == feature && p.IsActive)
            .FirstOrDefaultAsync();
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
