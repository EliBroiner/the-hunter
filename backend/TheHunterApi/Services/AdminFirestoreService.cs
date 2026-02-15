using Google.Cloud.Firestore;
using Grpc.Core;
using TheHunterApi.Constants;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// גישה ל-Firestore עבור לוח Admin — smart_categories, suggestions, users, logs, ranking_settings.
/// Project ID: FIRESTORE_PROJECT_ID מ-env/config; fallback: thehunter-485508 (לבדיקות).
/// Collections: smart_categories, suggestions, users, logs, ranking_settings.
/// חובה: Cloud Run Service Account חייב תפקיד Cloud Datastore User (roles/datastore.user).
/// </summary>
public class AdminFirestoreService
{
    /// <summary>ברירת מחדל לבדיקות — כאשר FIRESTORE_PROJECT_ID חסר ב-env.</summary>
    private const string DefaultProjectId = "thehunter-485508";
    private const string ColSuggestions = "suggestions";
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

    /// <summary>
    /// מונחים שממתינים לאישור — קורא מ-suggestions (status=pending_approval) — אותה collection ש-LearningService כותב אליה.
    /// </summary>
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
                if (term != null)
                    list.Add(term);
            }
            list = list.OrderByDescending(x => x.LastSeen).ToList(); // created_at DESC — החדשים ראשון
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
            if (tsVal is Timestamp ts)
                lastSeen = ts.ToDateTime();
            return new LearnedTerm
            {
                Id = 0,
                Term = term,
                Definition = null,
                Category = category,
                Frequency = 1,
                IsApproved = false,
                UserId = userId,
                LastSeen = lastSeen,
                FirestoreId = docId,
                OriginalTextSnippet = string.IsNullOrWhiteSpace(snippet) ? null : snippet,
                ConfidenceScore = Math.Clamp(conf, 0, 1),
            };
        }
        catch
        {
            return null;
        }
    }

    /// <summary>
    /// משתמשים מנוהלים — collection 'users'. שדות: email, userId, role, createdAt, updatedAt.
    /// </summary>
    public async Task<(List<AdminUserViewModel> Users, bool Ok)> GetUsersAsync()
    {
        try
        {
            var snapshot = await _db.Collection(ColUsers).OrderBy("email").GetSnapshotAsync();
            var list = new List<AdminUserViewModel>();
            foreach (var doc in snapshot.Documents)
            {
                var u = MapDocToAdminUser(doc.Id, doc.ToDictionary());
                if (u != null)
                    list.Add(u);
            }
            if (list.Count == 0) LogEmptyCollectionWarning(ColUsers);
            return (list, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetUsers");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            return (new List<AdminUserViewModel>(), false);
        }
    }

    /// <summary>
    /// לוגים/פעילות חיפוש — collection 'logs'. שדות: term, count, lastSearch.
    /// </summary>
    public async Task<(List<SearchActivity> Activities, bool Ok)> GetLogsAsync(int limit = 50)
    {
        try
        {
            var query = _db.Collection(ColLogs).OrderByDescending("count").Limit(limit);
            var snapshot = await query.GetSnapshotAsync();
            var list = new List<SearchActivity>();
            int id = 1;
            foreach (var doc in snapshot.Documents)
            {
                var a = MapDocToSearchActivity(doc.Id, doc.ToDictionary(), id++);
                if (a != null)
                    list.Add(a);
            }
            if (list.Count == 0) LogEmptyCollectionWarning(ColLogs);
            return (list, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetLogs");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            return (new List<SearchActivity>(), false);
        }
    }

    /// <summary>
    /// משקלי דירוג — collection 'ranking_settings', document id = key, שדה value.
    /// </summary>
    public async Task<(Dictionary<string, double> Weights, bool Ok)> GetRankingWeightsAsync()
    {
        try
        {
            var snapshot = await _db.Collection(ColRankingSettings).GetSnapshotAsync();
            var dict = new Dictionary<string, double>();
            foreach (var doc in snapshot.Documents)
            {
                var v = doc.GetValue<double?>("value");
                if (v.HasValue)
                    dict[doc.Id] = v.Value;
            }
            if (dict.Count == 0) LogEmptyCollectionWarning(ColRankingSettings);
            return (dict, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetRankingWeights");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            return (new Dictionary<string, double>(), false);
        }
    }

    /// <summary>
    /// כשלונות Meaningful Text Check — אחרונים 10. לקריאה ב-Scanning Health.
    /// </summary>
    public async Task<(List<ScanFailure> Failures, bool Ok)> GetScanFailuresAsync(int limit = 10)
    {
        try
        {
            var query = _db.Collection(ColScanFailures)
                .OrderByDescending("timestamp")
                .Limit(limit);
            var snapshot = await query.GetSnapshotAsync();
            var list = new List<ScanFailure>();
            foreach (var doc in snapshot.Documents)
            {
                var f = MapDocToScanFailure(doc.Id, doc.ToDictionary());
                if (f != null) list.Add(f);
            }
            return (list, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetScanFailures");
            _logger.LogError(ex, "ERROR fetching scan_failures: {Message}", ex.Message);
            return (new List<ScanFailure>(), false);
        }
    }

    /// <summary>מחזיר כשלון בודד לפי Id — ל-Debug ב-AI Lab.</summary>
    public async Task<ScanFailure?> GetScanFailureByIdAsync(string id)
    {
        try
        {
            var snap = await _db.Collection(ColScanFailures).Document(id).GetSnapshotAsync();
            if (!snap.Exists) return null;
            return MapDocToScanFailure(snap.Id, snap.ToDictionary());
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetScanFailureById {Id}: {Message}", id, ex.Message);
            return null;
        }
    }

    /// <summary>דיווח כשלון מהאפליקציה — נכתב ל-scan_failures.</summary>
    public async Task<string?> AddScanFailureAsync(string documentId, string filename, string rawText, double? garbageRatioPercent, string? userId, string? reasonForUpload = null)
    {
        try
        {
            LogWriteAttempt(ColScanFailures, "Add");
            var col = _db.Collection(ColScanFailures);
            var data = new Dictionary<string, object>
            {
                { "documentId", documentId ?? "" },
                { "filename", filename ?? "" },
                { "rawText", (rawText ?? "").Length > 50000 ? (rawText ?? "").Substring(0, 50000) + "…" : (rawText ?? "") },
                { "timestamp", Timestamp.FromDateTime(DateTime.UtcNow) },
                { "userId", userId ?? "" }
            };
            if (garbageRatioPercent.HasValue)
                data["garbageRatioPercent"] = garbageRatioPercent.Value;
            if (!string.IsNullOrWhiteSpace(reasonForUpload))
                data["reasonForUpload"] = reasonForUpload.Trim();
            var docRef = await col.AddAsync(data);
            _logger.LogInformation("[ScanFailure] Reported: docId={DocId}, filename={Fn}", documentId, filename);
            return docRef.Id;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AddScanFailure failed: {Message}", ex.Message);
            return null;
        }
    }

    private static ScanFailure? MapDocToScanFailure(string id, IReadOnlyDictionary<string, object> data)
    {
        try
        {
            DateTime dt = DateTime.UtcNow;
            if (data.TryGetValue("timestamp", out var ts) && ts is Timestamp t)
                dt = t.ToDateTime().ToUniversalTime();
            return new ScanFailure
            {
                Id = id,
                DocumentId = data.TryGetValue("documentId", out var di) ? (di?.ToString() ?? "") : "",
                Filename = data.TryGetValue("filename", out var fn) ? (fn?.ToString() ?? "") : "",
                RawText = data.TryGetValue("rawText", out var rt) ? (rt?.ToString() ?? "") : "",
                GarbageRatioPercent = data.TryGetValue("garbageRatioPercent", out var gr) && gr is double d ? d : null,
                UserId = data.TryGetValue("userId", out var uid) ? uid?.ToString() : null,
                Timestamp = dt,
                ReasonForUpload = data.TryGetValue("reasonForUpload", out var rfu) ? rfu?.ToString() : null
            };
        }
        catch { return null; }
    }

    /// <summary>מאשר מונח — אם ב-suggestions: מעתיק ל-smart_categories (sourceType=ai_suggestion) ומחק מ-suggestions.</summary>
    public async Task<bool> ApproveTermAsync(string documentId)
    {
        try
        {
            var suggRef = _db.Collection(ColSuggestions).Document(documentId);
            var suggSnap = await suggRef.GetSnapshotAsync();
            if (suggSnap.Exists)
            {
                var data = suggSnap.ToDictionary();
                var term = GetField(data, "term")?.ToString() ?? "";
                var category = GetField(data, "category")?.ToString() ?? "general";
                var definition = GetField(data, "definition")?.ToString();
                var userId = GetField(data, "userId")?.ToString();
                await _smartCategories.AddAiSuggestionAsync(term, category, definition, userId);
                _logger.LogInformation("[DATA-INTEGRITY] Verified suggestion format and smart_categories mapping. term={Term}, category={Category}, userId={UserId}",
                    term, category, userId ?? "(null)");
                LogWriteAttempt(ColSuggestions, "Delete");
                await suggRef.DeleteAsync();
                return true;
            }
            return false;
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

    /// <summary>מגדיר isBanned במסמך users — לפי doc id או לפי שדה userId.</summary>
    public async Task<bool> SetUserBannedAsync(string userDocIdOrFirebaseUserId, bool isBanned = true)
    {
        try
        {
            LogWriteAttempt(ColUsers, "Update");
            var docRef = _db.Collection(ColUsers).Document(userDocIdOrFirebaseUserId);
            var snap = await docRef.GetSnapshotAsync();
            if (snap.Exists)
            {
                await docRef.UpdateAsync(new Dictionary<string, object>
                {
                    { "id", userDocIdOrFirebaseUserId },
                    { "isBanned", isBanned },
                    { "updatedAt", Timestamp.FromDateTime(DateTime.UtcNow) },
                });
                return true;
            }
            var query = await _db.Collection(ColUsers).WhereEqualTo("userId", userDocIdOrFirebaseUserId).Limit(1).GetSnapshotAsync();
            if (query.Documents.Count == 0) return false;
            var docRef2 = query.Documents[0].Reference;
            await docRef2.UpdateAsync(new Dictionary<string, object>
            {
                { "id", docRef2.Id },
                { "isBanned", isBanned },
                { "updatedAt", Timestamp.FromDateTime(DateTime.UtcNow) },
            });
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR setting isBanned in Firestore: {Message}", ex.Message);
            return false;
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

    /// <summary>מנקה smart_categories ומחזיר מספר המסמכים שנמחקו.</summary>
    public async Task<int> PurgeSmartCategoriesAsync(CancellationToken ct = default)
    {
        return await PurgeCollectionAsync(LearningService.CollectionSmartCategories, ct);
    }

    /// <summary>מזריע חוקי בסיס ל-smart_categories אחרי TRUNCATE. כולל דירוגים (Strong/Weak).</summary>
    public async Task<int> SeedSmartCategoriesAsync(CancellationToken ct = default)
    {
        var count = 0;
        var seedRules = new Dictionary<string, string[]>
        {
            ["general"] = ["document", "doc", "מסמך", "קובץ", "file", "scan", "סריקה"],
            ["receipt"] = ["invoice", "receipt", "קבלה", "חשבונית", "bill", "inv", "payment", "transfer", "bit", "date"],
            ["id"] = ["id", "identity", "תעודת זהות", "ת.ז", "דרכון", "passport", "teudat zehut"],
            ["flight"] = ["boarding pass", "flight", "טיסה", "כרטיס טיסה"],
            ["salary"] = ["form 106", "106", "טופס 106", "משכורת", "תלוש", "payslip"],
        };
        foreach (var kv in seedRules)
        {
            var added = await _smartCategories.AddRulesBatchAsync(kv.Key, kv.Value, [], ct);
            count += added;
        }
        // דירוגים: Strong דורס Weak, רק Weak → ambiguous (שליחה ל-AI)
        await _smartCategories.SetKeywordRanksAsync("flight", new Dictionary<string, string> { ["boarding pass"] = "strong", ["flight"] = "strong" }, ct);
        await _smartCategories.SetKeywordRanksAsync("id", new Dictionary<string, string> { ["teudat zehut"] = "strong", ["תעודת זהות"] = "strong" }, ct);
        await _smartCategories.SetKeywordRanksAsync("salary", new Dictionary<string, string> { ["form 106"] = "strong", ["טופס 106"] = "strong", ["106"] = "strong" }, ct);
        await _smartCategories.SetKeywordRanksAsync("receipt", new Dictionary<string, string> { ["payment"] = "weak", ["transfer"] = "weak", ["bit"] = "weak", ["invoice"] = "weak", ["receipt"] = "weak", ["date"] = "weak", ["העברה"] = "weak", ["ביט"] = "weak" }, ct);
        _logger.LogInformation("SeedSmartCategories: added {Count} rules with ranks", count);
        return count;
    }

    /// <summary>מנקה הצעות באיכות נמוכה — snippet ריק או מונח תו/ספרה בודד. להרצה חד־פעמית.</summary>
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
                var snippetEmpty = string.IsNullOrWhiteSpace(snippet);
                var termSingleCharOrDigit = term.Length == 1;
                if (snippetEmpty || termSingleCharOrDigit)
                    toDelete.Add(doc.Reference);
            }
            const int batchSize = 500;
            for (var i = 0; i < toDelete.Count; i += batchSize)
            {
                var batch = _db.StartBatch();
                foreach (var docRef in toDelete.Skip(i).Take(batchSize))
                    batch.Delete(docRef);
                await batch.CommitAsync();
                deleted += Math.Min(batchSize, toDelete.Count - i);
            }
            _logger.LogInformation("CleanupLowQualitySuggestions: deleted {Count} documents", deleted);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "CleanupLowQualitySuggestions failed");
        }
        return deleted;
    }

    /// <summary>מוחק מונח — מנסה suggestions, אחר כך smart_categories (sourceType=term).</summary>
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

    public async Task<bool> AddUserAsync(string email, string userId, string role)
    {
        try
        {
            LogWriteAttempt(ColUsers, "Add");
            var col = _db.Collection(ColUsers);
            var existing = await col.WhereEqualTo("email", email.Trim()).GetSnapshotAsync();
            if (existing.Count > 0)
                return false;
            var now = Timestamp.FromDateTime(DateTime.UtcNow);
            DocumentReference docRef;
            string docId;
            if (!string.IsNullOrWhiteSpace(userId))
            {
                docId = userId.Trim();
                docRef = col.Document(docId);
            }
            else
            {
                docRef = col.Document();
                docId = docRef.Id;
            }
            var data = new Dictionary<string, object>
            {
                { "id", docId },
                { "email", email.Trim() },
                { "userId", userId ?? "" },
                { "role", role is RolesConstants.Admin or RolesConstants.DebugAccess ? role : RolesConstants.User },
                { "createdAt", now },
                { "updatedAt", now },
            };
            await docRef.SetAsync(data);
            return true;
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "AddUser");
            _logger.LogError(ex, "ERROR adding Firestore user: {Message}", ex.Message);
            return false;
        }
    }

    public async Task<bool> UpdateUserRoleAsync(string documentId, string role)
    {
        try
        {
            LogWriteAttempt(ColUsers, "Update");
            await _db.Collection(ColUsers).Document(documentId).UpdateAsync(new Dictionary<string, object>
            {
                { "id", documentId },
                { "role", role is RolesConstants.Admin or RolesConstants.DebugAccess ? role : RolesConstants.User },
                { "updatedAt", Timestamp.FromDateTime(DateTime.UtcNow) },
            });
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR updating Firestore user: {Message}", ex.Message);
            return false;
        }
    }

    public async Task<bool> DeleteUserAsync(string documentId)
    {
        try
        {
            LogWriteAttempt(ColUsers, "Delete");
            await _db.Collection(ColUsers).Document(documentId).DeleteAsync();
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR deleting Firestore user: {Message}", ex.Message);
            return false;
        }
    }

    /// <summary>
    /// מיגרציה חד-פעמית: מעדכן כל מסמך ב-users שאין בו שדה id — מוסיף id = Document ID.
    /// </summary>
    /// <returns>(total, updatedCount)</returns>
    public async Task<(int Total, int Updated)> MigrateUsersEnsureIdFieldAsync()
    {
        try
        {
            LogWriteAttempt(ColUsers, "Migrate");
            var snapshot = await _db.Collection(ColUsers).GetSnapshotAsync();
            var total = snapshot.Documents.Count;
            var updated = 0;
            foreach (var doc in snapshot.Documents)
            {
                var data = doc.ToDictionary();
                var existingId = GetField(data, "id")?.ToString()?.Trim();
                if (string.IsNullOrEmpty(existingId))
                {
                    await doc.Reference.UpdateAsync(new Dictionary<string, object> { { "id", doc.Id } });
                    updated++;
                    _logger.LogInformation("Users migration: set id={DocId} on document {DocId}", doc.Id, doc.Id);
                }
            }
            _logger.LogInformation("Users migration complete: total={Total}, updated={Updated}", total, updated);
            return (total, updated);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Users migration failed: {Message}", ex.Message);
            throw;
        }
    }

    public async Task SetRankingWeightsAsync(Dictionary<string, double> weights)
    {
        if (weights.Count == 0) return;
        LogWriteAttempt(ColRankingSettings, "Set");
        var col = _db.Collection(ColRankingSettings);
        foreach (var kvp in weights)
        {
            await col.Document(kvp.Key).SetAsync(new Dictionary<string, object> { { "value", kvp.Value } }, SetOptions.MergeAll);
        }
    }

    /// <summary>
    /// הגדרות סריקה — garbageThresholdPercent, minMeaningfulLength, minValidCharRatioPercent.
    /// מפתח = key, שדה value. ברירת מחדל אם חסר.
    /// </summary>
    public async Task<Dictionary<string, double>> GetScannerSettingsAsync()
    {
        try
        {
            var snapshot = await _db.Collection(ColScannerSettings).GetSnapshotAsync();
            var dict = new Dictionary<string, double>();
            foreach (var doc in snapshot.Documents)
            {
                try
                {
                    var field = doc.GetValue<object>("value");
                    double? v = field switch
                    {
                        double d => d,
                        int i => i,
                        long l => l,
                        float f => f,
                        _ => field != null && double.TryParse(field.ToString(), out var parsed) ? parsed : null
                    };
                    if (v.HasValue)
                        dict[doc.Id] = v.Value;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "Skip scanner_settings doc {DocId}: invalid value", doc.Id);
                }
            }
            return dict;
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetScannerSettings");
            _logger.LogError(ex, "GetScannerSettings: {Message}", ex.Message);
            return new Dictionary<string, double>();
        }
    }

    public async Task SetScannerSettingAsync(string key, double value)
    {
        try
        {
            LogWriteAttempt(ColScannerSettings, "Set");
            await _db.Collection(ColScannerSettings).Document(key).SetAsync(
                new Dictionary<string, object> { { "value", value } }, SetOptions.MergeAll);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SetScannerSetting {Key}: {Message}", key, ex.Message);
            throw;
        }
    }

    /// <summary>מגדיל מונה תמונות שדולגו (No Text Detected) — חוסך קריאות ל-Cloud/Gemini.</summary>
    public async Task IncrementImagesSkippedNoTextAsync()
    {
        try
        {
            var docRef = _db.Collection(ColScanStats).Document("counters");
            await _db.RunTransactionAsync(async transaction =>
            {
                var snap = await transaction.GetSnapshotAsync(docRef);
                if (!snap.Exists)
                {
                    transaction.Set(docRef, new Dictionary<string, object>
                    {
                        { "imagesSkippedNoText", 1L },
                        { "lastUpdated", Timestamp.FromDateTime(DateTime.UtcNow) }
                    });
                }
                else
                {
                    transaction.Update(docRef, new Dictionary<string, object>
                    {
                        { "imagesSkippedNoText", FieldValue.Increment(1) },
                        { "lastUpdated", Timestamp.FromDateTime(DateTime.UtcNow) }
                    });
                }
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "IncrementImagesSkippedNoText failed");
        }
    }

    /// <summary>מחזיר כמות תמונות שדולגו (No Text Detected) — כסף שנחסך.</summary>
    public async Task<long> GetImagesSkippedNoTextCountAsync()
    {
        try
        {
            var snap = await _db.Collection(ColScanStats).Document("counters").GetSnapshotAsync();
            if (!snap.Exists) return 0;
            var data = snap.ToDictionary();
            if (!data.TryGetValue("imagesSkippedNoText", out var val) || val == null) return 0;
            return Convert.ToInt64(val);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetImagesSkippedNoTextCount failed");
            return 0;
        }
    }

    /// <summary>שומר שרשרת עיבוד למסמך — [Local OCR -> Failed] -> [Cloud Vision -> Success] -> [Gemini Tagging -> Done].</summary>
    public async Task SaveProcessingChainAsync(string documentId, string chain, string? filename = null,
        string? rawText = null, string? cleanedText = null, string? ocrSource = null,
        IReadOnlyList<string>? tags = null, string? category = null)
    {
        try
        {
            var data = new Dictionary<string, object>
            {
                { "chain", chain },
                { "filename", filename ?? "" },
                { "timestamp", Timestamp.FromDateTime(DateTime.UtcNow) }
            };
            if (!string.IsNullOrEmpty(rawText))
                data["rawText"] = rawText.Length > 50000 ? rawText.Substring(0, 50000) + "…" : rawText;
            if (!string.IsNullOrEmpty(cleanedText))
                data["cleanedText"] = cleanedText.Length > 50000 ? cleanedText.Substring(0, 50000) + "…" : cleanedText;
            if (!string.IsNullOrEmpty(ocrSource))
                data["ocrSource"] = ocrSource;
            if (tags != null && tags.Count > 0)
                data["tags"] = tags.ToArray();
            if (!string.IsNullOrEmpty(category))
                data["category"] = category;
            await _db.Collection(ColProcessingChains).Document(documentId).SetAsync(data, SetOptions.MergeAll);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "SaveProcessingChain failed for doc {DocId}", documentId);
        }
    }

    /// <summary>מוחק לוגי processing_chains ישנים מ-30 יום — מונע צמיחה אינסופית.</summary>
    public async Task<int> CleanupOldProcessingChainsAsync(int maxAgeDays = 30)
    {
        try
        {
            var cutoff = Timestamp.FromDateTime(DateTime.UtcNow.AddDays(-maxAgeDays));
            var snap = await _db.Collection(ColProcessingChains)
                .WhereLessThan("timestamp", cutoff)
                .GetSnapshotAsync();
            var count = 0;
            foreach (var doc in snap.Documents)
            {
                await doc.Reference.DeleteAsync();
                count++;
            }
            if (count > 0)
                _logger.LogInformation("[processing_chains] Deleted {Count} old logs (older than {Days} days)", count, maxAgeDays);
            return count;
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "CleanupOldProcessingChains failed");
            return 0;
        }
    }

    /// <summary>מחזיר שרשרת עיבוד לפי documentId.</summary>
    public async Task<string?> GetProcessingChainAsync(string documentId)
    {
        try
        {
            var snap = await _db.Collection(ColProcessingChains).Document(documentId).GetSnapshotAsync();
            if (!snap.Exists) return null;
            return snap.GetValue<string>("chain");
        }
        catch
        {
            return null;
        }
    }

    /// <summary>מחזיר נתוני File X-Ray לפי documentId — processing_chains + scan_failures.</summary>
    public async Task<FileXRayData?> GetFileXRayAsync(string documentId)
    {
        try
        {
            var chainSnap = await _db.Collection(ColProcessingChains).Document(documentId).GetSnapshotAsync();
            if (!chainSnap.Exists)
            {
                var failure = await GetScanFailureByDocumentIdAsync(documentId);
                return failure != null ? new FileXRayData
                {
                    DocumentId = documentId,
                    Filename = failure.Filename,
                    RawText = failure.RawText,
                    OcrSource = "Local (Failed)",
                    ProcessingChain = null
                } : null;
            }
            var d = chainSnap.ToDictionary();
            var tags = new List<string>();
            if (d.TryGetValue("tags", out var tVal) && tVal is System.Collections.IEnumerable en)
            {
                foreach (var item in en)
                    tags.Add(item?.ToString() ?? "");
            }
            return new FileXRayData
            {
                DocumentId = documentId,
                Filename = GetString(d, "filename"),
                ProcessingChain = GetString(d, "chain"),
                RawText = GetString(d, "rawText"),
                CleanedText = GetString(d, "cleanedText"),
                OcrSource = GetString(d, "ocrSource"),
                Tags = tags,
                Category = GetString(d, "category")
            };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GetFileXRay failed for doc {DocId}", documentId);
            return null;
        }
    }

    /// <summary>מחזיר כשלון סריקה לפי documentId.</summary>
    public async Task<ScanFailure?> GetScanFailureByDocumentIdAsync(string documentId)
    {
        try
        {
            var snapshot = await _db.Collection(ColScanFailures)
                .WhereEqualTo("documentId", documentId)
                .OrderByDescending("timestamp")
                .Limit(1)
                .GetSnapshotAsync();
            var doc = snapshot.Documents.FirstOrDefault();
            return doc != null ? MapDocToScanFailure(doc.Id, doc.ToDictionary()) : null;
        }
        catch
        {
            return null;
        }
    }

    private static string GetString(IReadOnlyDictionary<string, object> d, string key) =>
        d.TryGetValue(key, out var v) && v != null ? v.ToString() ?? "" : "";

    /// <summary>מחזיר מונח בודד לפי מזהה מסמך — בודק suggestions, smart_categories.</summary>
    public async Task<LearnedTerm?> GetTermByIdAsync(string documentId)
    {
        try
        {
            var suggSnap = await _db.Collection(ColSuggestions).Document(documentId).GetSnapshotAsync();
            if (suggSnap.Exists)
                return MapSuggestionDocToLearnedTerm(documentId, suggSnap.ToDictionary());
            return await _smartCategories.GetTermByIdAsync(documentId);
        }
        catch
        {
            return null;
        }
    }

    /// <summary>מעדכן שדות term, definition, category — בודק suggestions, smart_categories.</summary>
    public async Task<bool> UpdateTermAsync(string documentId, string term, string definition, string category)
    {
        try
        {
            var suggRef = _db.Collection(ColSuggestions).Document(documentId);
            if ((await suggRef.GetSnapshotAsync()).Exists)
            {
                LogWriteAttempt(ColSuggestions, "Update");
                var updates = new Dictionary<string, object>
                {
                    { "term", term ?? "" },
                    { "category", category ?? "" },
                };
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

    public async Task<int> GetUsersCountAsync()
    {
        try
        {
            var snap = await _db.Collection(ColUsers).GetSnapshotAsync();
            return snap.Count;
        }
        catch { return 0; }
    }

    /// <summary>משתמשים שנוספו ב-24 השעות האחרונות (לפי createdAt/registrationDate).</summary>
    public async Task<int> GetNewUsersCountLast24hAsync()
    {
        try
        {
            var (users, _) = await GetUsersAsync();
            var cutoff = DateTime.UtcNow.AddHours(-24);
            return users.Count(u => u.RegistrationDate.HasValue && u.RegistrationDate.Value >= cutoff);
        }
        catch { return 0; }
    }

    /// <summary>מונחים שאושרו היום (לפי lastSeen של מאושרים).</summary>
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

    /// <summary>ספירת מונחים ממתינים — רק status=pending_approval ו-created_at ב-7 הימים האחרונים.</summary>
    public async Task<int> GetPendingTermsCountAsync()
    {
        var (count, _, _) = await GetPendingTermsStatsAsync();
        return count;
    }

    /// <summary>מחזיר (ספירה, מספר קבצים ייחודיים, מונח ראשון) — מונחים ממתינים ב-7 הימים האחרונים.</summary>
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
                if (!string.IsNullOrWhiteSpace(sid))
                    fileIds.Add(sid.Trim());
            }
            if (firstDoc != null)
                firstTerm = MapSuggestionDocToLearnedTerm(firstDoc.Id, firstDoc.ToDictionary());
            return (snap.Count, fileIds.Count, firstTerm);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "GetPendingTermsStatsAsync failed");
            return (0, 0, null);
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

    /// <summary>מחזיר (count, lastModified ISO8601) לבדיקת גרסה.</summary>
    public async Task<(int Count, string? LastModified)> GetDictionaryVersionAsync()
    {
        var (count, lastMod) = await _smartCategories.GetVersionAsync();
        return (count, lastMod);
    }

    /// <summary>כל המונחים שאושרו — מ-smart_categories (sourceType=term).</summary>
    public async Task<List<LearnedTerm>> GetApprovedTermsForExportAsync(DateTime? since)
    {
        var all = await _smartCategories.GetAllUnifiedAsync(since);
        return all
            .Where(x => x.SourceType == "term" || x.SourceType == "ai_suggestion")
            .Select(x => new LearnedTerm
            {
                FirestoreId = x.DocumentId,
                Term = x.Term ?? "",
                Definition = x.Definition,
                Category = x.Category ?? "general",
                Frequency = x.Frequency,
                IsApproved = true,
                UserId = x.UserId,
                LastSeen = x.LastModified,
            })
            .OrderByDescending(t => t.Frequency).ThenByDescending(t => t.LastSeen)
            .ToList();
    }

    /// <summary>מונחים חדשים לפי יום — עד 30 יום אחרונים (sourceType=term).</summary>
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

    /// <summary>מחזיר ערך מהמסמך — תואם רישית (exact) או lowercase.</summary>
    private static object? GetField(IReadOnlyDictionary<string, object> data, string key)
    {
        if (data.TryGetValue(key, out var v)) return v;
        var lower = key.ToLowerInvariant();
        var match = data.Keys.FirstOrDefault(k => string.Equals(k, lower, StringComparison.OrdinalIgnoreCase));
        return match != null ? data[match] : null;
    }

    private static LearnedTerm? MapDocToLearnedTerm(string docId, IReadOnlyDictionary<string, object> data)
    {
        try
        {
            var term = GetField(data, "term")?.ToString() ?? "";
            var definition = GetField(data, "definition")?.ToString();
            var category = GetField(data, "category")?.ToString() ?? "";
            var frequency = 0;
            var f = GetField(data, "frequency");
            if (f is long l) frequency = (int)l;
            else if (f is int i) frequency = i;
            var isApproved = GetField(data, "isApproved") is bool b && b;
            var userId = GetField(data, "userId")?.ToString();
            var lastSeen = DateTime.UtcNow;
            var tsVal = GetField(data, "lastModified") ?? GetField(data, "lastSeen") ?? GetField(data, "timestamp");
            if (tsVal is Timestamp ts)
                lastSeen = ts.ToDateTime();
            return new LearnedTerm
            {
                Id = 0,
                Term = term,
                Definition = definition,
                Category = category,
                Frequency = frequency,
                IsApproved = isApproved,
                UserId = userId,
                LastSeen = lastSeen,
                FirestoreId = docId,
            };
        }
        catch
        {
            return null;
        }
    }

    private static DateTime? TimestampToDateTime(object? val)
    {
        if (val is Timestamp ts) return ts.ToDateTime();
        return null;
    }

    private static AdminUserViewModel? MapDocToAdminUser(string docId, IReadOnlyDictionary<string, object> data)
    {
        try
        {
            var email = GetField(data, "email")?.ToString() ?? "";
            var userId = GetField(data, "userId")?.ToString() ?? "";
            var role = GetField(data, "role")?.ToString() ?? "User";
            var updatedAt = DateTime.UtcNow;
            var ua = GetField(data, "updatedAt");
            if (ua is Timestamp uats) updatedAt = uats.ToDateTime();
            var registrationDate = TimestampToDateTime(GetField(data, "createdAt")) ?? TimestampToDateTime(GetField(data, "registrationDate"));
            var lastSeen = TimestampToDateTime(GetField(data, "lastSeen"));
            return new AdminUserViewModel
            {
                Id = docId,
                Email = email,
                UserId = userId ?? "",
                Role = role ?? "User",
                RegistrationDate = registrationDate,
                UpdatedAt = updatedAt,
                LastSeen = lastSeen,
            };
        }
        catch
        {
            return null;
        }
    }

    private static SearchActivity? MapDocToSearchActivity(string docId, IReadOnlyDictionary<string, object> data, int id)
    {
        try
        {
            var term = GetField(data, "term")?.ToString() ?? docId;
            var count = 0;
            var c = GetField(data, "count");
            if (c is long l) count = (int)l;
            else if (c is int i) count = i;
            var lastSearch = DateTime.UtcNow;
            if (GetField(data, "lastSearch") is Timestamp ts)
                lastSearch = ts.ToDateTime();
            return new SearchActivity { Id = id, Term = term, Count = count, LastSearch = lastSearch };
        }
        catch
        {
            return null;
        }
    }
}
