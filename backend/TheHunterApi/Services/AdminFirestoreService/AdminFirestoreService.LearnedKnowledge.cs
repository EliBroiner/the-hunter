using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>לולאת למידה סגורה — learned_knowledge. שמירה, אישור, מחיקה, הזרקה ל-SmartSearch.</summary>
public partial class AdminFirestoreService
{
    private const string StatusPendingApproval = "pending_approval";
    private const string StatusApproved = "approved";

    /// <summary>שומר הצעות אנקר (term, rank, reason) ל-learned_knowledge — רק STRONG. Fire-and-forget.</summary>
    public async Task SaveAnchorSuggestionsAsync(IReadOnlyList<DocumentSuggestion> suggestions, string? sourceFile, string? documentCategory, string? userId, CancellationToken ct = default)
    {
        if (suggestions == null || suggestions.Count == 0) return;
        var strong = suggestions.Where(s => string.Equals(s.Rank, "STRONG", StringComparison.OrdinalIgnoreCase)).ToList();
        if (strong.Count == 0) return;
        try
        {
            var col = _db.Collection(ColLearnedKnowledge);
            var cat = string.IsNullOrWhiteSpace(documentCategory) ? "general" : documentCategory;
            foreach (var s in strong)
            {
                var term = (s.Term ?? "").Trim();
                if (term.Length < 2) continue;
                var data = new Dictionary<string, object>
                {
                    ["term"] = term,
                    ["category"] = cat,
                    ["source_file"] = sourceFile ?? "",
                    ["status"] = StatusPendingApproval,
                    ["created_at"] = Timestamp.GetCurrentTimestamp(),
                    ["userId"] = userId ?? "",
                };
                await col.AddAsync(data, ct);
            }
            _logger.LogDebug("Saved {Count} STRONG anchors to learned_knowledge", strong.Count);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SaveAnchorSuggestions failed");
        }
    }

    /// <summary>שומר הצעות מ-AI (פורמט ישן) ל-learned_knowledge — term, category, source_file. status: pending_approval.</summary>
    public async Task SaveLearnedKnowledgeAsync(IReadOnlyList<AiSuggestion> suggestions, string? sourceFile, string? userId, CancellationToken ct = default)
    {
        if (suggestions == null || suggestions.Count == 0) return;
        try
        {
            var col = _db.Collection(ColLearnedKnowledge);
            foreach (var s in suggestions)
            {
                var cat = string.IsNullOrWhiteSpace(s.SuggestedCategory) ? "general" : s.SuggestedCategory;
                foreach (var kw in (s.SuggestedKeywords ?? []).Where(k => !string.IsNullOrWhiteSpace(k)))
                {
                    var term = kw.Trim();
                    if (term.Length < 2) continue;
                    var data = new Dictionary<string, object>
                    {
                        ["term"] = term,
                        ["category"] = cat,
                        ["source_file"] = sourceFile ?? "",
                        ["status"] = StatusPendingApproval,
                        ["created_at"] = Timestamp.GetCurrentTimestamp(),
                        ["userId"] = userId ?? "",
                    };
                    if (!string.IsNullOrWhiteSpace(s.SuggestedRegex)) data["regex_pattern"] = s.SuggestedRegex;
                    await col.AddAsync(data, ct);
                }
            }
            _logger.LogDebug("Saved learned_knowledge from {Count} suggestions", suggestions.Count);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SaveLearnedKnowledge failed");
        }
    }

    /// <summary>מחזיר את כל פריטי learned_knowledge — ממוין לפי תאריך יורד.</summary>
    public async Task<List<LearnedKnowledgeItem>> GetLearnedKnowledgeAsync(string? statusFilter = null, CancellationToken ct = default)
    {
        try
        {
            var col = _db.Collection(ColLearnedKnowledge);
            var query = statusFilter != null
                ? col.WhereEqualTo("status", statusFilter)
                : col;
            var snap = await query.GetSnapshotAsync(ct);
            var list = snap.Documents.Select(d => MapToLearnedKnowledgeItem(d)).Where(x => x != null).Cast<LearnedKnowledgeItem>().ToList();
            return list.OrderByDescending(x => x.CreatedAt).ToList();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetLearnedKnowledge failed");
            return [];
        }
    }

    /// <summary>מחזיר מונחים מאושרים בלבד — להזרקה ל-SmartSearch prompt.</summary>
    public async Task<List<(string Term, string Category)>> GetApprovedLearnedKnowledgeForSearchAsync(CancellationToken ct = default)
    {
        try
        {
            var col = _db.Collection(ColLearnedKnowledge);
            var snap = await col.WhereEqualTo("status", StatusApproved).GetSnapshotAsync(ct);
            return snap.Documents
                .Select(d =>
                {
                    var data = d.ToDictionary();
                    var term = GetField(data, "term")?.ToString() ?? "";
                    var cat = GetField(data, "category")?.ToString() ?? "general";
                    return (term, cat);
                })
                .Where(x => !string.IsNullOrWhiteSpace(x.term))
                .ToList();
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "GetApprovedLearnedKnowledgeForSearch failed");
            return [];
        }
    }

    /// <summary>מאשר פריט — status=approved. כעת יוזרק ל-SmartSearch.</summary>
    public async Task<bool> ApproveLearnedKnowledgeAsync(string documentId, CancellationToken ct = default)
    {
        try
        {
            var ref_ = _db.Collection(ColLearnedKnowledge).Document(documentId);
            var snap = await ref_.GetSnapshotAsync(ct);
            if (!snap.Exists) return false;
            await ref_.UpdateAsync(new Dictionary<string, object> { ["status"] = StatusApproved });
            _logger.LogInformation("LearnedKnowledge approved: {Id}", documentId);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ApproveLearnedKnowledge failed: {Id}", documentId);
            return false;
        }
    }

    /// <summary>מוחק פריט מ-learned_knowledge.</summary>
    public async Task<bool> DeleteLearnedKnowledgeAsync(string documentId, CancellationToken ct = default)
    {
        try
        {
            var ref_ = _db.Collection(ColLearnedKnowledge).Document(documentId);
            var snap = await ref_.GetSnapshotAsync(ct);
            if (!snap.Exists) return false;
            await ref_.DeleteAsync();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "DeleteLearnedKnowledge failed: {Id}", documentId);
            return false;
        }
    }

    private static LearnedKnowledgeItem? MapToLearnedKnowledgeItem(DocumentSnapshot doc)
    {
        if (!doc.Exists) return null;
        var d = doc.ToDictionary();
        var term = GetField(d, "term")?.ToString() ?? "";
        var cat = GetField(d, "category")?.ToString() ?? "general";
        var source = GetField(d, "source_file")?.ToString();
        var status = GetField(d, "status")?.ToString() ?? StatusPendingApproval;
        var regex = GetField(d, "regex_pattern")?.ToString();
        var ts = GetField(d, "created_at");
        var created = ts is Timestamp t ? t.ToDateTime() : DateTime.UtcNow;
        return new LearnedKnowledgeItem
        {
            FirestoreId = doc.Id,
            Term = term,
            Category = cat,
            SourceFile = string.IsNullOrWhiteSpace(source) ? null : source,
            Status = status,
            CreatedAt = created,
            RegexPattern = string.IsNullOrWhiteSpace(regex) ? null : regex
        };
    }
}
