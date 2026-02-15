using Google.Cloud.Firestore;

namespace TheHunterApi.Services;

/// <summary>
/// מיגרציה חד־פעמית: knowledge_base → smart_categories (sourceType=term), מחיקת knowledge_base.
/// </summary>
public interface IKnowledgeBaseMigrationService
{
    Task<(int Migrated, int Deleted)> MigrateAndDeleteAsync(CancellationToken ct = default);
}

public class KnowledgeBaseMigrationService : IKnowledgeBaseMigrationService
{
    private const string ColKnowledgeBase = "knowledge_base";
    private const string SourceTypeRule = "rule";
    private readonly FirestoreDb _firestore;
    private readonly ISmartCategoriesService _smartCategories;
    private readonly ILogger<KnowledgeBaseMigrationService> _logger;

    public KnowledgeBaseMigrationService(FirestoreDb firestore, ISmartCategoriesService smartCategories, ILogger<KnowledgeBaseMigrationService> logger)
    {
        _firestore = firestore;
        _smartCategories = smartCategories;
        _logger = logger;
    }

    public async Task<(int Migrated, int Deleted)> MigrateAndDeleteAsync(CancellationToken ct = default)
    {
        var scCol = _firestore.Collection(LearningService.CollectionSmartCategories);
        var scSnap = await scCol.GetSnapshotAsync(ct);
        foreach (var doc in scSnap.Documents)
        {
            var data = doc.ToDictionary();
            if (!data.ContainsKey("sourceType"))
            {
                await doc.Reference.UpdateAsync(new Dictionary<string, object> { { "sourceType", SourceTypeRule } });
                _logger.LogDebug("Added sourceType=rule to {DocId}", doc.Id);
            }
        }

        var kbCol = _firestore.Collection(ColKnowledgeBase);
        var migrated = 0;
        var toDelete = new List<DocumentReference>();

        var kbSnap = await kbCol.GetSnapshotAsync(ct);
        foreach (var doc in kbSnap.Documents)
        {
            var data = doc.ToDictionary();
            var isApproved = GetBool(data, "isApproved");
            if (!isApproved) { toDelete.Add(doc.Reference); continue; }

            var term = GetString(data, "term");
            var category = GetString(data, "category") ?? "general";
            if (string.IsNullOrWhiteSpace(term)) { toDelete.Add(doc.Reference); continue; }

            var userId = GetString(data, "userId");
            var definition = GetString(data, "definition");
            await _smartCategories.AddTermAsync(term, category, string.IsNullOrEmpty(definition) ? null : definition, string.IsNullOrEmpty(userId) ? null : userId, ct);
            migrated++;
            toDelete.Add(doc.Reference);
        }

        var deleted = 0;
        foreach (var docRef in toDelete)
        {
            await docRef.DeleteAsync();
            deleted++;
        }

        _logger.LogInformation("[Migration] knowledge_base → smart_categories: migrated {M}, deleted {D}", migrated, deleted);
        return (migrated, deleted);
    }

    private static string GetString(IReadOnlyDictionary<string, object> d, string key) =>
        d.TryGetValue(key, out var v) && v != null ? v.ToString()?.Trim() ?? "" : "";

    private static bool GetBool(IReadOnlyDictionary<string, object> d, string key) =>
        d.TryGetValue(key, out var v) && v is bool b && b;
}
