using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>חלק partial — מונחים (suggestions), אישורים, ייצוא.</summary>
public partial class AdminFirestoreService
{
    /// <summary>שומר הצעות למידה מלאות מ-AI ל-dictionary_suggestions — לסקירת Admin (keywords + regex).</summary>
    public async Task SaveDictionarySuggestionsAsync(IReadOnlyList<AiSuggestion> suggestions, string? sourceDocumentId, string? userId, CancellationToken ct = default)
    {
        if (suggestions == null || suggestions.Count == 0) return;
        try
        {
            var col = _db.Collection(ColDictionarySuggestions);
            foreach (var s in suggestions)
            {
                if (string.IsNullOrWhiteSpace(s.SuggestedCategory) && (s.SuggestedKeywords == null || s.SuggestedKeywords.Count == 0)) continue;
                var data = new Dictionary<string, object>
                {
                    ["suggested_category"] = s.SuggestedCategory ?? "",
                    ["suggested_keywords"] = s.SuggestedKeywords ?? new List<string>(),
                    ["suggested_regex"] = s.SuggestedRegex ?? "",
                    ["confidence"] = Math.Clamp(s.Confidence, 0, 1),
                    ["created_at"] = Timestamp.GetCurrentTimestamp(),
                    ["userId"] = userId ?? "",
                };
                if (!string.IsNullOrWhiteSpace(sourceDocumentId)) data["sourceDocumentId"] = sourceDocumentId;
                await col.AddAsync(data, ct);
            }
            _logger.LogDebug("Saved {Count} dictionary suggestions to Firestore", suggestions.Count);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "SaveDictionarySuggestions failed — continuing");
        }
    }

    /// <summary>מונחים שממתינים לאישור — קורא מ-suggestions (status=pending_approval).</summary>
    public async Task<(List<LearnedTerm> Terms, bool Ok)> GetPendingTermsAsync()
    {
        try
        {
            var col = _db.Collection(ColSuggestions);
            var query = col.WhereEqualTo("status", "pending_approval");
            var snapshot = await query.GetSnapshotAsync();
            var list = new List<LearnedTerm>();
            foreach (var doc in snapshot.Documents)
            {
                var term = MapSuggestionDocToLearnedTerm(doc.Id, doc.ToDictionary());
                if (term != null) list.Add(term);
            }
            list = list.OrderByDescending(x => x.LastSeen).ToList();
            if (list.Count == 0) LogEmptyCollectionWarning(ColSuggestions);
            return (list, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetPendingTerms");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            return (new List<LearnedTerm>(), false);
        }
    }

    private static LearnedTerm? MapSuggestionDocToLearnedTerm(string docId, IReadOnlyDictionary<string, object> data)
    {
        try
        {
            var term = GetField(data, "term")?.ToString() ?? "";
            var category = GetField(data, "category")?.ToString() ?? "";
            var userId = GetField(data, "userId")?.ToString();
            var snippet = GetField(data, "original_text_snippet")?.ToString();
            var confVal = GetField(data, "confidence_score");
            var conf = confVal is double d ? d : (confVal is long l ? (double)l : 1.0);
            var lastSeen = DateTime.UtcNow;
            var tsVal = GetField(data, "created_at") ?? GetField(data, "lastSeen") ?? GetField(data, "timestamp");
            if (tsVal is Timestamp ts) lastSeen = ts.ToDateTime();
            return new LearnedTerm
            {
                Id = 0, Term = term, Definition = null, Category = category, Frequency = 1, IsApproved = false,
                UserId = userId, LastSeen = lastSeen, FirestoreId = docId,
                OriginalTextSnippet = string.IsNullOrWhiteSpace(snippet) ? null : snippet,
                ConfidenceScore = Math.Clamp(conf, 0, 1),
            };
        }
        catch { return null; }
    }

    /// <summary>מאשר מונח — מעתיק ל-smart_categories ומחק מ-suggestions.</summary>
    public async Task<bool> ApproveTermAsync(string documentId)
    {
        try
        {
            var suggRef = _db.Collection(ColSuggestions).Document(documentId);
            var suggSnap = await suggRef.GetSnapshotAsync();
            if (!suggSnap.Exists) return false;
            var data = suggSnap.ToDictionary();
            var term = GetField(data, "term")?.ToString() ?? "";
            var category = GetField(data, "category")?.ToString() ?? "general";
            var definition = GetField(data, "definition")?.ToString();
            var userId = GetField(data, "userId")?.ToString();
            await _smartCategories.AddAiSuggestionAsync(term, category, definition, userId);
            _logger.LogInformation("[DATA-INTEGRITY] Verified suggestion. term={Term}, category={Category}", term, category);
            LogWriteAttempt(ColSuggestions, "Delete");
            await suggRef.DeleteAsync();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR approving Firestore term: {Message}", ex.Message);
            return false;
        }
    }

    /// <summary>מאשר את כל המונחים הממתינים.</summary>
    public async Task<int> ApproveAllPendingTermsAsync()
    {
        var (terms, _) = await GetPendingTermsAsync();
        var count = 0;
        foreach (var t in terms.Where(x => !string.IsNullOrEmpty(x.FirestoreId)))
        {
            if (await ApproveTermAsync(t.FirestoreId!)) count++;
        }
        return count;
    }

    /// <summary>מנקה הצעות באיכות נמוכה — snippet ריק או מונח תו/ספרה בודד.</summary>
    public async Task<int> CleanupLowQualitySuggestionsAsync()
    {
        var deleted = 0;
        try
        {
            var snap = await _db.Collection(ColSuggestions).GetSnapshotAsync();
            var toDelete = new List<DocumentReference>();
            foreach (var doc in snap.Documents)
            {
                var data = doc.ToDictionary();
                var term = GetField(data, "term")?.ToString() ?? "";
                var snippet = GetField(data, "original_text_snippet")?.ToString() ?? "";
                if (string.IsNullOrWhiteSpace(snippet) || term.Length == 1) toDelete.Add(doc.Reference);
            }
            const int batchSize = 500;
            for (var i = 0; i < toDelete.Count; i += batchSize)
            {
                var batch = _db.StartBatch();
                foreach (var docRef in toDelete.Skip(i).Take(batchSize)) batch.Delete(docRef);
                await batch.CommitAsync();
                deleted += Math.Min(batchSize, toDelete.Count - i);
            }
            _logger.LogInformation("CleanupLowQualitySuggestions: deleted {Count} documents", deleted);
        }
        catch (Exception ex) { _logger.LogError(ex, "CleanupLowQualitySuggestions failed"); }
        return deleted;
    }

    /// <summary>מוחק מונח — suggestions או smart_categories.</summary>
    public async Task<bool> DeleteTermAsync(string documentId)
    {
        try
        {
            var suggRef = _db.Collection(ColSuggestions).Document(documentId);
            if ((await suggRef.GetSnapshotAsync()).Exists)
            {
                LogWriteAttempt(ColSuggestions, "Delete");
                await suggRef.DeleteAsync();
                return true;
            }
            return await _smartCategories.DeleteTermAsync(documentId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR deleting Firestore term: {Message}", ex.Message);
            return false;
        }
    }

    /// <summary>מחזיר מונח בודד — suggestions או smart_categories.</summary>
    public async Task<LearnedTerm?> GetTermByIdAsync(string documentId)
    {
        try
        {
            var suggSnap = await _db.Collection(ColSuggestions).Document(documentId).GetSnapshotAsync();
            if (suggSnap.Exists) return MapSuggestionDocToLearnedTerm(documentId, suggSnap.ToDictionary());
            return await _smartCategories.GetTermByIdAsync(documentId);
        }
        catch { return null; }
    }

    /// <summary>מעדכן term, definition, category — suggestions או smart_categories.</summary>
    public async Task<bool> UpdateTermAsync(string documentId, string term, string definition, string category)
    {
        try
        {
            var suggRef = _db.Collection(ColSuggestions).Document(documentId);
            if ((await suggRef.GetSnapshotAsync()).Exists)
            {
                LogWriteAttempt(ColSuggestions, "Update");
                var updates = new Dictionary<string, object> { { "term", term ?? "" }, { "category", category ?? "" } };
                if (!string.IsNullOrEmpty(definition)) updates["definition"] = definition;
                await suggRef.UpdateAsync(updates);
                return true;
            }
            return await _smartCategories.UpdateTermAsync(documentId, term, definition, category);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "UpdateTerm");
            _logger.LogError(ex, "ERROR updating term in Firestore: {Message}", ex.Message);
            return false;
        }
    }

    public async Task<int> GetApprovedTermsCountAsync()
    {
        try
        {
            var all = await _smartCategories.GetAllUnifiedAsync(null);
            return all.Count(x => x.SourceType == "term" || x.SourceType == "ai_suggestion");
        }
        catch { return 0; }
    }

    /// <summary>מונחים שאושרו היום.</summary>
    public async Task<int> GetApprovedTermsCountTodayAsync()
    {
        try
        {
            var list = await GetApprovedTermsForExportAsync(null);
            var today = DateTime.UtcNow.Date;
            return list.Count(t => t.LastSeen.Date == today);
        }
        catch { return 0; }
    }

    public async Task<int> GetPendingTermsCountAsync()
    {
        var (count, _, _) = await GetPendingTermsStatsAsync();
        return count;
    }

    /// <summary>מחזיר (ספירה, קבצים ייחודיים, מונח ראשון) — ממתינים ב-7 ימים.</summary>
    public async Task<(int Count, int UniqueFiles, LearnedTerm? FirstTerm)> GetPendingTermsStatsAsync()
    {
        try
        {
            var sevenDaysAgo = Timestamp.FromDateTime(DateTime.UtcNow.AddDays(-7));
            var query = _db.Collection(ColSuggestions)
                .WhereEqualTo("status", "pending_approval")
                .WhereGreaterThanOrEqualTo("created_at", sevenDaysAgo);
            var snap = await query.GetSnapshotAsync();
            var fileIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            LearnedTerm? firstTerm = null;
            var firstDoc = snap.Documents.OrderBy(d => d.CreateTime).FirstOrDefault();
            foreach (var doc in snap.Documents)
            {
                var data = doc.ToDictionary();
                var sid = GetField(data, "sourceDocumentId")?.ToString();
                if (!string.IsNullOrWhiteSpace(sid)) fileIds.Add(sid.Trim());
            }
            if (firstDoc != null) firstTerm = MapSuggestionDocToLearnedTerm(firstDoc.Id, firstDoc.ToDictionary());
            return (snap.Count, fileIds.Count, firstTerm);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "GetPendingTermsStatsAsync failed");
            return (0, 0, null);
        }
    }

    /// <summary>כל המונחים שאושרו — מ-smart_categories.</summary>
    public async Task<List<LearnedTerm>> GetApprovedTermsForExportAsync(DateTime? since)
    {
        var all = await _smartCategories.GetAllUnifiedAsync(since);
        return all
            .Where(x => x.SourceType == "term" || x.SourceType == "ai_suggestion")
            .Select(x => new LearnedTerm
            {
                FirestoreId = x.DocumentId, Term = x.Term ?? "", Definition = x.Definition, Category = x.Category ?? "general",
                Frequency = x.Frequency, IsApproved = true, UserId = x.UserId, LastSeen = x.LastModified,
            })
            .OrderByDescending(t => t.Frequency).ThenByDescending(t => t.LastSeen)
            .ToList();
    }

    /// <summary>מונחים חדשים לפי יום — עד 30 יום.</summary>
    public async Task<Dictionary<string, int>> GetNewTermsPerDayAsync(int lastDays = 30)
    {
        var result = new Dictionary<string, int>(StringComparer.Ordinal);
        var cutoff = DateTime.UtcNow.Date.AddDays(-lastDays);
        try
        {
            var all = await _smartCategories.GetAllUnifiedAsync(null);
            foreach (var x in all.Where(x => x.SourceType == "term" || x.SourceType == "ai_suggestion"))
            {
                if (x.LastModified < cutoff) continue;
                var key = x.LastModified.Date.ToString("yyyy-MM-dd");
                result.TryGetValue(key, out var c);
                result[key] = c + 1;
            }
        }
        catch { }
        return result;
    }
}
