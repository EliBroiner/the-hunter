using System.Text.Json;
using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// קריאה/כתיבה ל-Firestore collection smart_categories — מקור אמת יחיד.
/// sourceType: "ai_suggestion" (מונח מאושר מ-AI) | "rule" (keywords/regex) | "term" (legacy).
/// </summary>
public interface ISmartCategoriesService
{
    Task<int> GetCountAsync(CancellationToken ct = default);
    Task<(int Count, string? LastModified)> GetVersionAsync(CancellationToken ct = default);
    Task<IReadOnlyList<SmartCategoryDocument>> GetRulesAsync(DateTime? since = null, CancellationToken ct = default);
    Task<IReadOnlyList<UnifiedDictionaryItem>> GetAllUnifiedAsync(DateTime? since = null, CancellationToken ct = default);
    /// <summary>מונח מאושר מ-suggestions — נשמר עם sourceType: "ai_suggestion".</summary>
    Task<string?> AddAiSuggestionAsync(string term, string category, string? definition, string? userId, CancellationToken ct = default);
    Task<string?> AddTermAsync(string term, string category, string? definition, string? userId, CancellationToken ct = default);
    Task<bool> AddRuleAsync(string categoryId, string type, string value, CancellationToken ct = default);
    Task<int> AddRulesBatchAsync(string categoryId, IReadOnlyList<string> keywords, IReadOnlyList<string> regexPatterns, CancellationToken ct = default);
    Task<string?> SaveManualAsync(string categoryKey, IReadOnlyList<string> tags, IReadOnlyList<object> suggestions, string? summary, CancellationToken ct = default);
    Task<bool> DeleteTermAsync(string documentId, CancellationToken ct = default);
    Task<LearnedTerm?> GetTermByIdAsync(string documentId, CancellationToken ct = default);
    Task<bool> UpdateTermAsync(string documentId, string term, string definition, string category, CancellationToken ct = default);
}

public class SmartCategoriesService : ISmartCategoriesService
{
    private const string SourceTypeTerm = "term";
    private const string SourceTypeAiSuggestion = "ai_suggestion";
    private const string SourceTypeRule = "rule";

    private static string SanitizeDocId(string categoryKey) =>
        string.IsNullOrWhiteSpace(categoryKey) ? "" : categoryKey.Trim().Replace("/", "|");

    private readonly FirestoreDb _firestore;
    private readonly ILogger<SmartCategoriesService> _logger;

    public SmartCategoriesService(FirestoreDb firestore, ILogger<SmartCategoriesService> logger)
    {
        _firestore = firestore;
        _logger = logger;
    }

    private string Col => LearningService.CollectionSmartCategories;

    public async Task<int> GetCountAsync(CancellationToken ct = default)
    {
        var snap = await _firestore.Collection(Col).GetSnapshotAsync(ct);
        return snap.Documents.Count;
    }

    public async Task<(int Count, string? LastModified)> GetVersionAsync(CancellationToken ct = default)
    {
        var all = await GetAllUnifiedAsync(null, ct);
        if (all.Count == 0) return (0, null);
        var max = all.Max(x => x.LastModified);
        return (all.Count, max.ToUniversalTime().ToString("o"));
    }

    public async Task<IReadOnlyList<SmartCategoryDocument>> GetRulesAsync(DateTime? since = null, CancellationToken ct = default)
    {
        var all = await GetAllUnifiedAsync(since, ct);
        return all.Where(x => x.SourceType == SourceTypeRule).Select(ToRuleDoc).ToList();
    }

    public async Task<IReadOnlyList<UnifiedDictionaryItem>> GetAllUnifiedAsync(DateTime? since = null, CancellationToken ct = default)
    {
        var snap = await _firestore.Collection(Col).GetSnapshotAsync(ct);
        var list = new List<UnifiedDictionaryItem>();
        foreach (var doc in snap.Documents)
        {
            var data = doc.ToDictionary();
            var item = FromDoc(doc.Id, data);
            if (item == null) continue;
            if (since.HasValue && item.LastModified < since.Value) continue;
            list.Add(item);
        }
        return list;
    }

    public async Task<string?> AddAiSuggestionAsync(string term, string category, string? definition, string? userId, CancellationToken ct = default)
    {
        return await AddTermInternalAsync(term, category, definition, userId, SourceTypeAiSuggestion, ct);
    }

    public async Task<string?> AddTermAsync(string term, string category, string? definition, string? userId, CancellationToken ct = default)
    {
        return await AddTermInternalAsync(term, category, definition, userId, SourceTypeTerm, ct);
    }

    private async Task<string?> AddTermInternalAsync(string term, string category, string? definition, string? userId, string sourceType, CancellationToken ct)
    {
        if (string.IsNullOrWhiteSpace(term)) return null;
        var col = _firestore.Collection(Col);
        var data = new Dictionary<string, object>
        {
            { "sourceType", sourceType },
            { "term", term.Trim() },
            { "category", (category ?? "general").Trim() },
            { "frequency", 1 },
            { "lastModified", FieldValue.ServerTimestamp },
        };
        if (!string.IsNullOrWhiteSpace(definition)) data["definition"] = definition.Trim();
        if (!string.IsNullOrWhiteSpace(userId)) data["userId"] = userId.Trim();
        var docRef = await col.AddAsync(data, ct);
        return docRef.Id;
    }

    public async Task<bool> AddRuleAsync(string categoryId, string type, string value, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(categoryId) || string.IsNullOrWhiteSpace(value)) return false;
        var trimmed = value.Trim();
        if (trimmed.Length == 0) return false;

        var docId = SanitizeDocId(categoryId);
        if (string.IsNullOrWhiteSpace(docId)) return false;
        var docRef = _firestore.Collection(Col).Document(docId);

        var snap = await docRef.GetSnapshotAsync(ct);
        if (!snap.Exists)
        {
            var init = new Dictionary<string, object>
            {
                { "sourceType", SourceTypeRule },
                { "key", categoryId.Trim() },
                { "display_names", new Dictionary<string, string>() },
                { "keywords", new List<string>() },
                { "regex_patterns", new List<string>() },
                { "last_updated", FieldValue.ServerTimestamp },
            };
            await docRef.SetAsync(init, SetOptions.MergeAll);
        }
        else
        {
            var data = snap.ToDictionary();
            if (GetString(data, "sourceType") != SourceTypeRule)
                await docRef.UpdateAsync(new Dictionary<string, object> { { "sourceType", SourceTypeRule } });
        }

        var field = string.Equals(type, "regex", StringComparison.OrdinalIgnoreCase) ? "regex_patterns" : "keywords";
        await docRef.UpdateAsync(new Dictionary<string, object>
        {
            { field, FieldValue.ArrayUnion(trimmed) },
            { "last_updated", FieldValue.ServerTimestamp }
        });
        _logger.LogInformation("Added rule to {CategoryId}: {Type} = {Value}", categoryId, type, trimmed);
        return true;
    }

    public async Task<int> AddRulesBatchAsync(string categoryId, IReadOnlyList<string> keywords, IReadOnlyList<string> regexPatterns, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(categoryId)) return 0;
        var kw = keywords?.Where(k => !string.IsNullOrWhiteSpace(k)).Select(k => k!.Trim()).Distinct().ToList() ?? new List<string>();
        var rx = regexPatterns?.Where(r => !string.IsNullOrWhiteSpace(r)).Select(r => r!.Trim()).Distinct().ToList() ?? new List<string>();
        if (kw.Count == 0 && rx.Count == 0) return 0;

        var added = 0;
        foreach (var k in kw) { if (await AddRuleAsync(categoryId, "keyword", k, ct)) added++; }
        foreach (var r in rx) { if (await AddRuleAsync(categoryId, "regex", r, ct)) added++; }
        if (added > 0) _logger.LogInformation("AddRulesBatch: {CategoryId} — +{Count} rules", categoryId, added);
        return added;
    }

    public async Task<string?> SaveManualAsync(string categoryKey, IReadOnlyList<string> tags, IReadOnlyList<object> suggestions, string? summary, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(categoryKey)) return null;

        var key = categoryKey.Trim();
        var keywords = tags?.Where(t => !string.IsNullOrWhiteSpace(t)).Select(t => t!.Trim()).ToList() ?? new List<string>();
        var regexStrings = new List<string>();
        if (suggestions != null)
        {
            foreach (var s in suggestions)
            {
                if (s == null) continue;
                if (s is JsonElement je)
                {
                    var regex = je.TryGetProperty("suggested_regex", out var r) ? r.GetString()
                        : je.TryGetProperty("suggestedRegex", out var r2) ? r2.GetString() : null;
                    if (!string.IsNullOrWhiteSpace(regex)) regexStrings.Add(regex.Trim());
                    else if (!string.IsNullOrWhiteSpace(je.GetRawText())) regexStrings.Add(je.GetRawText().Trim());
                }
                else if (s is string str && !string.IsNullOrWhiteSpace(str)) regexStrings.Add(str.Trim());
                else if (!string.IsNullOrWhiteSpace(s.ToString())) regexStrings.Add(s.ToString()!.Trim());
            }
        }

        var docId = SanitizeDocId(key);
        if (string.IsNullOrWhiteSpace(docId)) return null;
        var data = new Dictionary<string, object>
        {
            { "sourceType", SourceTypeRule },
            { "key", key },
            { "keywords", keywords },
            { "regex_patterns", regexStrings },
            { "display_names", new Dictionary<string, object> { { "he", summary ?? "" } } },
            { "last_updated", FieldValue.ServerTimestamp },
        };
        await _firestore.Collection(Col).Document(docId).SetAsync(data, SetOptions.MergeAll);
        _logger.LogInformation("[Server] smart_categories: saved '{Key}'. Keywords: {Kc}, Regex: {Rc}", key, keywords.Count, regexStrings.Count);
        return key;
    }

    public async Task<bool> DeleteTermAsync(string documentId, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(documentId)) return false;
        var docRef = _firestore.Collection(Col).Document(documentId);
        var snap = await docRef.GetSnapshotAsync(ct);
        if (!snap.Exists) return false;
        var data = snap.ToDictionary();
        var st = GetString(data, "sourceType");
        if (st != SourceTypeTerm && st != SourceTypeAiSuggestion) return false;
        await docRef.DeleteAsync();
        return true;
    }

    public async Task<LearnedTerm?> GetTermByIdAsync(string documentId, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(documentId)) return null;
        var docRef = _firestore.Collection(Col).Document(documentId);
        var snap = await docRef.GetSnapshotAsync(ct);
        if (!snap.Exists) return null;
        var data = snap.ToDictionary();
        var st = GetString(data, "sourceType");
        if (st != SourceTypeTerm && st != SourceTypeAiSuggestion) return null;
        var item = FromDoc(documentId, data);
        if (item == null) return null;
        return new LearnedTerm
        {
            FirestoreId = documentId,
            Term = item.Term ?? "",
            Definition = item.Definition,
            Category = item.Category ?? "general",
            Frequency = item.Frequency,
            IsApproved = true,
            UserId = item.UserId,
            LastSeen = item.LastModified,
        };
    }

    public async Task<bool> UpdateTermAsync(string documentId, string term, string definition, string category, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(documentId)) return false;
        var docRef = _firestore.Collection(Col).Document(documentId);
        var snap = await docRef.GetSnapshotAsync(ct);
        if (!snap.Exists) return false;
        var data = snap.ToDictionary();
        var st = GetString(data, "sourceType");
        if (st != SourceTypeTerm && st != SourceTypeAiSuggestion) return false;
        var updates = new Dictionary<string, object>
        {
            { "term", term ?? "" },
            { "category", category ?? "" },
            { "lastModified", FieldValue.ServerTimestamp },
        };
        if (!string.IsNullOrEmpty(definition)) updates["definition"] = definition;
        await docRef.UpdateAsync(updates);
        return true;
    }

    private static UnifiedDictionaryItem? FromDoc(string docId, IReadOnlyDictionary<string, object> data)
    {
        var sourceType = GetString(data, "sourceType");
        if (sourceType == SourceTypeTerm || sourceType == SourceTypeAiSuggestion)
        {
            return new UnifiedDictionaryItem
            {
                SourceType = sourceType,
                DocumentId = docId,
                Term = GetString(data, "term"),
                Category = GetString(data, "category"),
                Frequency = GetInt(data, "frequency"),
                Definition = GetString(data, "definition"),
                UserId = GetString(data, "userId"),
                LastModified = GetTimestamp(data, "lastModified") ?? DateTime.UtcNow,
            };
        }
        if (sourceType == SourceTypeRule || string.IsNullOrEmpty(sourceType))
        {
            var key = GetString(data, "key");
            if (string.IsNullOrEmpty(key)) key = docId;
            var displayNames = new Dictionary<string, string>();
            if (data.TryGetValue("display_names", out var dn) && dn is IDictionary<string, object> dnMap)
                foreach (var e in dnMap) displayNames[e.Key] = e.Value?.ToString() ?? "";
            return new UnifiedDictionaryItem
            {
                SourceType = SourceTypeRule,
                DocumentId = docId,
                Key = key,
                DisplayNames = displayNames,
                Keywords = GetStringList(data, "keywords"),
                RegexPatterns = GetStringList(data, "regex_patterns"),
                LastModified = GetTimestamp(data, "last_updated") ?? DateTime.UtcNow,
            };
        }
        return null;
    }

    private static SmartCategoryDocument ToRuleDoc(UnifiedDictionaryItem item) => new()
    {
        Key = item.Key ?? "",
        DisplayNames = item.DisplayNames,
        Keywords = item.Keywords,
        RegexPatterns = item.RegexPatterns,
        LastUpdated = item.LastModified,
    };

    private static string GetString(IReadOnlyDictionary<string, object> d, string key) =>
        d.TryGetValue(key, out var v) && v != null ? v.ToString()?.Trim() ?? "" : "";

    private static int GetInt(IReadOnlyDictionary<string, object> d, string key)
    {
        var v = d.TryGetValue(key, out var val) ? val : null;
        if (v is long l) return (int)l;
        if (v is int i) return i;
        return 1;
    }

    private static DateTime? GetTimestamp(IReadOnlyDictionary<string, object> d, string key)
    {
        var v = d.TryGetValue(key, out var val) ? val : null;
        return v is Timestamp ts ? ts.ToDateTime() : null;
    }

    private static List<string> GetStringList(IReadOnlyDictionary<string, object> data, string field)
    {
        var list = new List<string>();
        if (!data.TryGetValue(field, out var v)) return list;
        if (v is IEnumerable<object> en)
            foreach (var item in en)
                if (item != null && !string.IsNullOrWhiteSpace(item.ToString()))
                    list.Add(item.ToString()!.Trim());
        return list;
    }
}
