using Google.Cloud.Firestore;
using Grpc.Core;

namespace TheHunterApi.Services;

/// <summary>
/// גישה ל-Firestore עבור לוח Admin — smart_categories, suggestions, users, logs, ranking_settings.
/// Project ID: FIRESTORE_PROJECT_ID מ-env/config; fallback: thehunter-485508 (לבדיקות).
/// Collections: smart_categories, suggestions, users, logs, ranking_settings.
/// חובה: Cloud Run Service Account חייב תפקיד Cloud Datastore User (roles/datastore.user).
/// </summary>
public partial class AdminFirestoreService
{
    /// <summary>ברירת מחדל לבדיקות — כאשר FIRESTORE_PROJECT_ID חסר ב-env.</summary>
    private const string DefaultProjectId = "thehunter-485508";
    private const string ColSuggestions = "suggestions";
    /// <summary>הצעות למידה מלאות מ-AI — suggested_keywords, suggested_regex — לסקירה ב-Admin.</summary>
    private const string ColDictionarySuggestions = "dictionary_suggestions";
    /// <summary>לולאת למידה סגורה — term, category, source_file. מונחים מאושרים מוזרקים ל-SmartSearch.</summary>
    private const string ColLearnedKnowledge = "learned_knowledge";
    private const string ColUsers = "users";
    private const string ColLogs = "logs";
    private const string ColRankingSettings = "ranking_settings";
    private const string ColScanFailures = "scan_failures";
    private const string ColScannerSettings = "scanner_settings";
    private const string ColScanStats = "scan_stats";
    /// <summary>לוג בלבד — File X-Ray. אין לוגיקת עסקים או סנכרון Flutter.</summary>
    private const string ColProcessingChains = "processing_chains";
    private const string ColSearchHistory = "search_history";

    private readonly FirestoreDb _db;
    private readonly ILogger<AdminFirestoreService> _logger;
    private readonly ISmartCategoriesService _smartCategories;
    public string EffectiveProjectId { get; }

    public AdminFirestoreService(ILogger<AdminFirestoreService> logger, IConfiguration config, ISmartCategoriesService smartCategories)
    {
        _logger = logger;
        EffectiveProjectId = config["FIRESTORE_PROJECT_ID"]
            ?? Environment.GetEnvironmentVariable("FIRESTORE_PROJECT_ID")
            ?? DefaultProjectId;
        _smartCategories = smartCategories;
        try
        {
            _db = new FirestoreDbBuilder { ProjectId = EffectiveProjectId }.Build();
            _logger.LogInformation(
                "[AdminFirestore] Connected to project {ProjectId}. Collections: smart_categories, suggestions, users, logs, ranking_settings. " +
                "Cloud Run: ודא שה-Service Account יש לו Cloud Datastore User / Firestore permissions.",
                EffectiveProjectId);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "create FirestoreDb");
            _logger.LogError(ex, "[AdminFirestore] Failed to create FirestoreDb for project {ProjectId}", EffectiveProjectId);
            throw;
        }
    }

    /// <summary>לוג לפני כתיבה ל-Firestore — לבדיקת Cloud Run.</summary>
    private void LogWriteAttempt(string collectionName, string operation)
    {
        _logger.LogDebug("[FIRESTORE_ATTEMPT] Writing to collection {CollectionName} in project {ProjectId} (op={Op})",
            collectionName, EffectiveProjectId, operation);
    }

    /// <summary>לוג כשהתוצאה ריקה — לבדיקת Cloud Run.</summary>
    private void LogEmptyCollectionWarning(string collectionName)
    {
        _logger.LogWarning("Firestore returned 0 documents from [{Col}]. ProjectId={ProjectId}. ודא שה-collection קיים והמפתחות נטענו נכון.",
            collectionName, EffectiveProjectId);
    }

    /// <summary>בודק אם השגיאה היא Permission Denied — לוג מפורט לקונסול ולבדיקת Cloud Run logs.</summary>
    private void LogIfPermissionDenied(Exception ex, string operation)
    {
        var inner = ex;
        while (inner != null)
        {
            if (inner is RpcException rpc && rpc.StatusCode == StatusCode.PermissionDenied)
            {
                _logger.LogError(
                    "[FIRESTORE PERMISSION DENIED] {Operation}. ProjectId={ProjectId}. " +
                    "ודא: 1) Cloud Run Service Account יש roles/datastore.user 2) FIRESTORE_PROJECT_ID תואם לפרויקט Firebase. Detail={Detail}",
                    operation, EffectiveProjectId, rpc.Status.Detail);
                return;
            }
            inner = inner.InnerException;
        }
    }

    /// <summary>מוחק את כל המסמכים ב-collection. מחזיר מספר המסמכים שנמחקו.</summary>
    private async Task<int> PurgeCollectionAsync(string collectionName, CancellationToken ct = default)
    {
        var col = _db.Collection(collectionName);
        var snap = await col.GetSnapshotAsync(ct);
        var refs = snap.Documents.Select(d => d.Reference).ToList();
        const int batchSize = 500;
        var deleted = 0;
        for (var i = 0; i < refs.Count; i += batchSize)
        {
            var batch = _db.StartBatch();
            foreach (var docRef in refs.Skip(i).Take(batchSize))
                batch.Delete(docRef);
            await batch.CommitAsync(ct);
            deleted += Math.Min(batchSize, refs.Count - i);
        }
        _logger.LogInformation("PurgeCollection: {Collection} — deleted {Count} documents", collectionName, deleted);
        return deleted;
    }

    /// <summary>מנקה אוספים: suggestions, processing_chains, scan_stats, scan_failures. לא נוגע ב-users, search_history.</summary>
    public async Task<Dictionary<string, int>> PurgeDatabaseCollectionsAsync(CancellationToken ct = default)
    {
        var result = new Dictionary<string, int>(StringComparer.Ordinal);
        foreach (var col in new[] { ColSuggestions, ColProcessingChains, ColScanStats, ColScanFailures })
        {
            try
            {
                result[col] = await PurgeCollectionAsync(col, ct);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "PurgeCollection failed: {Collection}", col);
                result[col] = -1;
            }
        }
        return result;
    }

    /// <summary>מחזיר (count, lastModified ISO8601) לבדיקת גרסה.</summary>
    public async Task<(int Count, string? LastModified)> GetDictionaryVersionAsync()
    {
        var (count, lastMod) = await _smartCategories.GetVersionAsync();
        return (count, lastMod);
    }

    /// <summary>מחזיר ערך מהמסמך — תואם רישית (exact) או lowercase.</summary>
    private static object? GetField(IReadOnlyDictionary<string, object> data, string key)
    {
        if (data.TryGetValue(key, out var v)) return v;
        var lower = key.ToLowerInvariant();
        var match = data.Keys.FirstOrDefault(k => string.Equals(k, lower, StringComparison.OrdinalIgnoreCase));
        return match != null ? data[match] : null;
    }
}
