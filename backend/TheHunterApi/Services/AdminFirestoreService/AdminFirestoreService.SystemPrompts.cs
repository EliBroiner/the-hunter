using Google.Cloud.Firestore;
using TheHunterApi.Constants;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

public partial class AdminFirestoreService
{
    private const string ColSystemPrompts = "system_prompts";

    /// <summary>ממפה FeatureType ל־feature string ב-Firestore. analysis, trainer, search.</summary>
    private static string ToFirestoreFeature(FeatureType feature) =>
        feature switch
        {
            FeatureType.DocumentAnalysis => "analysis",
            FeatureType.DocumentTrainer => "trainer",
            FeatureType.SmartSearch => "search",
            FeatureType.OcrExtraction => "ocr_extraction",
            _ => "analysis"
        };

    /// <summary>מביא את הפרומפט הפעיל מ-Firestore. אם ריק — מחזיר fallback מוטבע עם גרסה "0.0 (Hardcoded Fallback)".</summary>
    public async Task<SystemPromptResult> GetLatestPromptAsync(FeatureType feature, CancellationToken ct = default)
    {
        var featureStr = ToFirestoreFeature(feature);
        try
        {
            var col = _db.Collection(ColSystemPrompts);
            var snap = await col
                .WhereEqualTo("feature", featureStr)
                .WhereEqualTo("is_active", true)
                .Limit(1)
                .GetSnapshotAsync(ct);

            if (snap.Count > 0)
            {
                var doc = snap.Documents[0];
                var data = doc.ToDictionary();
                var text = GetField(data, "text")?.ToString() ?? "";
                var version = GetField(data, "version")?.ToString() ?? "?";
                if (!string.IsNullOrWhiteSpace(text))
                {
                    _logger.LogDebug("SystemPrompt {Feature}: Firestore (Version={Version})", featureStr, version);
                    return new SystemPromptResult { Text = text, Version = version, IsFallback = false };
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "כשלון בשליפת פרומפט {Feature} מ-Firestore — משתמש ב-fallback", featureStr);
        }

        var fallbackText = feature switch
        {
            FeatureType.DocumentAnalysis => SystemPromptFallbacks.DocumentAnalysis,
            FeatureType.DocumentTrainer => SystemPromptFallbacks.DocumentTrainer,
            FeatureType.SmartSearch => SystemPromptFallbacks.SmartSearch,
            FeatureType.OcrExtraction => SystemPromptFallbacks.OcrExtraction,
            _ => SystemPromptFallbacks.DocumentAnalysis
        };

        _logger.LogDebug("SystemPrompt {Feature}: fallback מוטבע (Version={Version})", featureStr, SystemPromptFallbacks.FallbackVersion);
        return new SystemPromptResult
        {
            Text = fallbackText,
            Version = SystemPromptFallbacks.FallbackVersion,
            IsFallback = true
        };
    }

    /// <summary>מביא פרומפטים לפי feature — ממוין לפי גרסה יורד.</summary>
    public async Task<List<SystemPromptFirestoreDoc>> GetPromptsForFeatureAsync(string feature, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(feature)) return [];
        try
        {
            var col = _db.Collection(ColSystemPrompts);
            var snap = await col.WhereEqualTo("feature", feature).GetSnapshotAsync(ct);

            var list = snap.Documents
                .Select(d => MapToSystemPromptDoc(d))
                .Where(p => p != null)
                .Cast<SystemPromptFirestoreDoc>()
                .ToList();

            return list.OrderByDescending(p => ParseVersionForSort(p.Version)).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetPromptsForFeature failed: {Feature}", feature);
            return [];
        }
    }

    /// <summary>שומר פרומפט חדש ל-Firestore.</summary>
    public async Task<SystemPromptFirestoreDoc?> SavePromptAsync(string feature, string version, string text, bool setActive = false, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(feature) || string.IsNullOrWhiteSpace(version) || string.IsNullOrWhiteSpace(text))
            return null;

        try
        {
            var col = _db.Collection(ColSystemPrompts);
            var data = new Dictionary<string, object>
            {
                ["feature"] = feature,
                ["version"] = version,
                ["text"] = text,
                ["is_active"] = setActive,
                ["created_at"] = Timestamp.GetCurrentTimestamp()
            };

            var docRef = await col.AddAsync(data, ct);
            var doc = await docRef.GetSnapshotAsync(ct);

            if (setActive)
                await SetActiveByFeatureVersionAsync(feature, version, ct);

            return MapToSystemPromptDoc(doc);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SavePrompt failed: {Feature} v{Version}", feature, version);
            return null;
        }
    }

    /// <summary>מפעיל פרומפט — is_active=true למסמך, false לשאר באותו feature.</summary>
    public async Task<bool> SetActiveByFeatureVersionAsync(string feature, string version, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(feature) || string.IsNullOrWhiteSpace(version)) return false;

        try
        {
            var col = _db.Collection(ColSystemPrompts);
            var allSnap = await col.WhereEqualTo("feature", feature).GetSnapshotAsync(ct);

            var batch = _db.StartBatch();
            DocumentReference? targetRef = null;

            foreach (var doc in allSnap.Documents)
            {
                var v = doc.GetValue<string>("version");
                if (v == version)
                    targetRef = doc.Reference;
                else
                    batch.Update(doc.Reference, "is_active", false);
            }

            if (targetRef == null)
            {
                _logger.LogWarning("SetActive: Prompt not found feature={Feature} version={Version}", feature, version);
                return false;
            }

            batch.Update(targetRef, "is_active", true);
            await batch.CommitAsync(ct);
            _logger.LogInformation("SystemPrompt activated: feature={Feature} version={Version}", feature, version);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SetActiveByFeatureVersion failed: {Feature} v{Version}", feature, version);
            return false;
        }
    }

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

    private static SystemPromptFirestoreDoc? MapToSystemPromptDoc(DocumentSnapshot doc)
    {
        if (!doc.Exists) return null;
        var d = doc.ToDictionary();
        return new SystemPromptFirestoreDoc
        {
            Id = doc.Id,
            Feature = GetField(d, "feature")?.ToString() ?? "",
            Version = GetField(d, "version")?.ToString() ?? "",
            Text = GetField(d, "text")?.ToString() ?? "",
            IsActive = GetField(d, "is_active") is bool b && b,
            CreatedAt = GetField(d, "created_at") is Timestamp ts ? ts.ToDateTime() : DateTime.UtcNow
        };
    }
}
