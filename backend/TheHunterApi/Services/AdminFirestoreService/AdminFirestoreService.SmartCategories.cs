using TheHunterApi.Config;

namespace TheHunterApi.Services;

/// <summary>חלק partial — smart_categories, seed.</summary>
public partial class AdminFirestoreService
{
    /// <summary>מנקה smart_categories ומחזיר מספר המסמכים שנמחקו.</summary>
    public async Task<int> PurgeSmartCategoriesAsync(CancellationToken ct = default)
    {
        return await PurgeCollectionAsync(LearningService.CollectionSmartCategories, ct);
    }

    /// <summary>מזריע חוקי בסיס ל-smart_categories אחרי TRUNCATE.</summary>
    public async Task<int> SeedSmartCategoriesAsync(CancellationToken ct = default)
    {
        var count = await _applySeedRules(ct);
        await _applySeedRanks(ct);
        _logger.LogInformation("[SYNC] Updated Seed and Local Assets with Ranked Dictionary Logic. Added {Count} rules.", count);
        return count;
    }

    async Task<int> _applySeedRules(CancellationToken ct)
    {
        var count = 0;
        foreach (var kv in SmartCategoriesSeedData.GetRules())
            count += await _smartCategories.AddRulesBatchAsync(kv.Key, kv.Value, [], ct);
        return count;
    }

    async Task _applySeedRanks(CancellationToken ct)
    {
        foreach (var kv in SmartCategoriesSeedData.GetStrongRanks())
            await _smartCategories.SetKeywordRanksAsync(kv.Key, kv.Value, ct);
        foreach (var kv in SmartCategoriesSeedData.GetWeakRanks())
            await _smartCategories.SetKeywordRanksAsync(kv.Key, kv.Value, ct);
    }
}
