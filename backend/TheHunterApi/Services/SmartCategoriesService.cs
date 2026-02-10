using System.Text.Json;
using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// קריאה/כתיבה ל-Firestore collection smart_categories — למוח ההעשרה בלקוח.
/// </summary>
public interface ISmartCategoriesService
{
    Task<IReadOnlyList<SmartCategoryDocument>> GetAllAsync(CancellationToken ct = default);
    Task<bool> AddRuleAsync(string categoryId, string type, string value, CancellationToken ct = default);
    /// <summary>יוצר/מעדכן מסמך ב-smart_categories מנתוני Debugger (Manual JSON Save).</summary>
    Task<string?> SaveManualAsync(string categoryKey, IReadOnlyList<string> tags, IReadOnlyList<object> suggestions, string? summary, CancellationToken ct = default);
}

public class SmartCategoriesService : ISmartCategoriesService
{
    private readonly FirestoreDb _firestore;
    private readonly ILogger<SmartCategoriesService> _logger;

    public SmartCategoriesService(FirestoreDb firestore, ILogger<SmartCategoriesService> logger)
    {
        _firestore = firestore;
        _logger = logger;
    }

    public async Task<IReadOnlyList<SmartCategoryDocument>> GetAllAsync(CancellationToken ct = default)
    {
        try
        {
            var col = _firestore.Collection(LearningService.CollectionSmartCategories);
            var snapshot = await col.GetSnapshotAsync(ct);
            var list = new List<SmartCategoryDocument>();
            foreach (var doc in snapshot.Documents)
            {
                var data = doc.ToDictionary();
                list.Add(FromFirestoreDoc(doc.Id, data));
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
            var docRef = _firestore
                .Collection(LearningService.CollectionSmartCategories)
                .Document(categoryId);

            var snap = await docRef.GetSnapshotAsync(ct);
            if (!snap.Exists)
            {
                // יוצר מסמך עם שדות ברירת מחדל ואז מעדכן
                var init = new Dictionary<string, object>
                {
                    { "key", categoryId },
                    { "display_names", new Dictionary<string, string>() },
                    { "keywords", new List<string>() },
                    { "regex_patterns", new List<string>() },
                };
                await docRef.SetAsync(init, SetOptions.MergeAll, ct);
            }

            var field = string.Equals(type, "regex", StringComparison.OrdinalIgnoreCase) ? "regex_patterns" : "keywords";
            await docRef.UpdateAsync(new Dictionary<string, object> { { field, FieldValue.ArrayUnion(trimmed) } });

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
            var docRef = col.Document(key);
            var data = new Dictionary<string, object>
            {
                { "key", key },
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
        return new SmartCategoryDocument
        {
            Key = key,
            DisplayNames = displayNames,
            Keywords = keywords,
            RegexPatterns = regexPatterns,
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
