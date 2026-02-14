using System.Text.Json;
using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// קריאה/כתיבה ל-Firestore collection smart_categories — למוח ההעשרה בלקוח.
/// </summary>
public interface ISmartCategoriesService
{
    Task<int> GetCountAsync(CancellationToken ct = default);
    Task<(int Count, string? LastModified)> GetVersionAsync(CancellationToken ct = default);
    Task<IReadOnlyList<SmartCategoryDocument>> GetAllAsync(DateTime? since = null, CancellationToken ct = default);
    Task<bool> AddRuleAsync(string categoryId, string type, string value, CancellationToken ct = default);
    /// <summary>מוסיף חוקים מרובים (keywords + regex) — לשימוש באישור הצעות Admin.</summary>
    Task<int> AddRulesBatchAsync(string categoryId, IReadOnlyList<string> keywords, IReadOnlyList<string> regexPatterns, CancellationToken ct = default);
    /// <summary>יוצר/מעדכן מסמך ב-smart_categories מנתוני Debugger (Manual JSON Save).</summary>
    Task<string?> SaveManualAsync(string categoryKey, IReadOnlyList<string> tags, IReadOnlyList<object> suggestions, string? summary, CancellationToken ct = default);
}

public class SmartCategoriesService : ISmartCategoriesService
{
    /// <summary>Firestore אוסר "/" ב-document ID — מחליף ל-"|" לפורמט רב־לשוני (Invoice / חשבונית)</summary>
    private static string SanitizeDocId(string categoryKey) =>
        string.IsNullOrWhiteSpace(categoryKey) ? "" : categoryKey.Trim().Replace("/", "|");

    private readonly FirestoreDb _firestore;
    private readonly ILogger<SmartCategoriesService> _logger;

    public SmartCategoriesService(FirestoreDb firestore, ILogger<SmartCategoriesService> logger)
    {
        _firestore = firestore;
        _logger = logger;
    }

    public async Task<int> GetCountAsync(CancellationToken ct = default)
    {
        var col = _firestore.Collection(LearningService.CollectionSmartCategories);
        var snapshot = await col.GetSnapshotAsync(ct);
        return snapshot.Documents.Count;
    }

    public async Task<(int Count, string? LastModified)> GetVersionAsync(CancellationToken ct = default)
    {
        var list = await GetAllAsync(null, ct);
        var withDate = list.Where(d => d.LastUpdated > DateTime.MinValue).ToList();
        if (withDate.Count == 0) return (list.Count, null);
        var max = withDate.Max(d => d.LastUpdated);
        return (list.Count, max.ToUniversalTime().ToString("o"));
    }

    public async Task<IReadOnlyList<SmartCategoryDocument>> GetAllAsync(DateTime? since = null, CancellationToken ct = default)
    {
        try
        {
            var col = _firestore.Collection(LearningService.CollectionSmartCategories);
            if (since.HasValue)
            {
                try
                {
                    var ts = Timestamp.FromDateTime(since.Value.ToUniversalTime());
                    var query = col.WhereGreaterThan("last_updated", ts);
                    var snapshot = await query.GetSnapshotAsync(ct);
                    return snapshot.Documents.Select(d => FromFirestoreDoc(d.Id, d.ToDictionary())).ToList();
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Firestore query with since failed. Fallback to in-memory filter.");
                }
            }
            var snap = await col.GetSnapshotAsync(ct);
            var list = new List<SmartCategoryDocument>();
            foreach (var doc in snap.Documents)
            {
                var item = FromFirestoreDoc(doc.Id, doc.ToDictionary());
                if (!since.HasValue || item.LastUpdated > since.Value) list.Add(item);
            }
            return list;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to read smart_categories");
            return Array.Empty<SmartCategoryDocument>();
        }
    }

    /// <summary>type: "regex" | "keyword" — מוסיף ל-regex_patterns או keywords.</summary>
    public async Task<bool> AddRuleAsync(string categoryId, string type, string value, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(categoryId) || string.IsNullOrWhiteSpace(value))
            return false;
        var trimmed = value.Trim();
        if (trimmed.Length == 0) return false;

        try
        {
            var docId = SanitizeDocId(categoryId);
            if (string.IsNullOrWhiteSpace(docId)) return false;
            var docRef = _firestore
                .Collection(LearningService.CollectionSmartCategories)
                .Document(docId);

            var snap = await docRef.GetSnapshotAsync(ct);
            if (!snap.Exists)
            {
                // יוצר מסמך עם שדות ברירת מחדל — key שומר את השם המקורי (כולל /)
                var init = new Dictionary<string, object>
                {
                    { "key", categoryId.Trim() },
                    { "display_names", new Dictionary<string, string>() },
                    { "keywords", new List<string>() },
                    { "regex_patterns", new List<string>() },
                    { "last_updated", FieldValue.ServerTimestamp },
                };
                await docRef.SetAsync(init, SetOptions.MergeAll, ct);
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
        catch (Exception ex)
        {
            _logger.LogError(ex, "AddRule failed for {CategoryId}", categoryId);
            return false;
        }
    }

    /// <inheritdoc />
    public async Task<int> AddRulesBatchAsync(string categoryId, IReadOnlyList<string> keywords, IReadOnlyList<string> regexPatterns, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(categoryId)) return 0;
        var kw = keywords?.Where(k => !string.IsNullOrWhiteSpace(k)).Select(k => k!.Trim()).Distinct().ToList() ?? new List<string>();
        var rx = regexPatterns?.Where(r => !string.IsNullOrWhiteSpace(r)).Select(r => r!.Trim()).Distinct().ToList() ?? new List<string>();
        if (kw.Count == 0 && rx.Count == 0) return 0;

        var added = 0;
        foreach (var k in kw)
        {
            if (await AddRuleAsync(categoryId, "keyword", k, ct)) added++;
        }
        foreach (var r in rx)
        {
            if (await AddRuleAsync(categoryId, "regex", r, ct)) added++;
        }
        if (added > 0)
            _logger.LogInformation("AddRulesBatch: {CategoryId} — +{Count} rules (keywords: {Kc}, regex: {Rc})", categoryId, added, kw.Count, rx.Count);
        return added;
    }

    /// <inheritdoc />
    public async Task<string?> SaveManualAsync(string categoryKey, IReadOnlyList<string> tags, IReadOnlyList<object> suggestions, string? summary, CancellationToken ct = default)
    {
        if (string.IsNullOrWhiteSpace(categoryKey))
        {
            _logger.LogWarning("SaveManual: categoryKey empty");
            return null;
        }

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
                else if (s is IDictionary<string, object> dict && dict.TryGetValue("suggested_regex", out var r) && r != null && !string.IsNullOrWhiteSpace(r.ToString()))
                    regexStrings.Add(r.ToString()!.Trim());
                else if (s is string str && !string.IsNullOrWhiteSpace(str))
                    regexStrings.Add(str.Trim());
                else if (!string.IsNullOrWhiteSpace(s.ToString()))
                    regexStrings.Add(s.ToString()!.Trim());
            }
        }

        try
        {
            var col = _firestore.Collection(LearningService.CollectionSmartCategories);
            var docId = SanitizeDocId(key);
            if (string.IsNullOrWhiteSpace(docId))
            {
                _logger.LogWarning("SaveManual: categoryKey invalid after sanitization");
                return null;
            }
            var docRef = col.Document(docId);
            var data = new Dictionary<string, object>
            {
                { "key", key.Trim() },
                { "keywords", keywords },
                { "regex_patterns", regexStrings },
                { "display_names", new Dictionary<string, object> { { "he", summary ?? "" } } },
                { "last_updated", FieldValue.ServerTimestamp },
            };
            await docRef.SetAsync(data, SetOptions.MergeAll, ct);
            _logger.LogInformation("[Server] smart_categories: saved document '{Key}'. Keywords: {Kc}, Regex: {Rc}", key, keywords.Count, regexStrings.Count);
            return key;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Server] CRITICAL: SaveManual to smart_categories failed. Error: {Message}", ex.Message);
            throw;
        }
    }

    private static SmartCategoryDocument FromFirestoreDoc(string docId, IReadOnlyDictionary<string, object> data)
    {
        var key = data.TryGetValue("key", out var k) ? k?.ToString() ?? docId : docId;
        var displayNames = new Dictionary<string, string>();
        if (data.TryGetValue("display_names", out var dn) && dn is IDictionary<string, object> dnMap)
        {
            foreach (var e in dnMap)
                displayNames[e.Key] = e.Value?.ToString() ?? "";
        }
        var keywords = GetStringList(data, "keywords");
        var regexPatterns = GetStringList(data, "regex_patterns");
        var lastUpdated = DateTime.MinValue;
        if (data.TryGetValue("last_updated", out var lu) && lu is Timestamp ts)
            lastUpdated = ts.ToDateTime();
        return new SmartCategoryDocument
        {
            Key = key,
            DisplayNames = displayNames,
            Keywords = keywords,
            RegexPatterns = regexPatterns,
            LastUpdated = lastUpdated,
        };
    }

    private static List<string> GetStringList(IReadOnlyDictionary<string, object> data, string field)
    {
        var list = new List<string>();
        if (!data.TryGetValue(field, out var v)) return list;
        if (v is IEnumerable<object> en)
        {
            foreach (var item in en)
                if (item != null && !string.IsNullOrWhiteSpace(item.ToString()))
                    list.Add(item.ToString()!.Trim());
        }
        return list;
    }
}
