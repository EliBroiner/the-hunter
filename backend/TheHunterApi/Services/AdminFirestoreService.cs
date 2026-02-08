using Google.Cloud.Firestore;
using Grpc.Core;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// גישה ל-Firestore עבור לוח Admin — knowledge_base, users, logs, ranking_settings.
/// Project ID: FIRESTORE_PROJECT_ID מ-env/config; fallback: thehunter-485508 (לבדיקות).
/// Collections: knowledge_base, users, logs, ranking_settings (תואם ל-Flutter/firestore.rules).
/// חובה: Cloud Run Service Account חייב תפקיד Cloud Datastore User (roles/datastore.user).
/// </summary>
public class AdminFirestoreService
{
    /// <summary>ברירת מחדל לבדיקות — כאשר FIRESTORE_PROJECT_ID חסר ב-env.</summary>
    private const string DefaultProjectId = "thehunter-485508";
    private const string ColKnowledgeBase = "knowledge_base";
    private const string ColUsers = "users";
    private const string ColLogs = "logs";
    private const string ColRankingSettings = "ranking_settings";

    private readonly FirestoreDb _db;
    private readonly ILogger<AdminFirestoreService> _logger;
    public string EffectiveProjectId { get; }

    public AdminFirestoreService(ILogger<AdminFirestoreService> logger, IConfiguration config)
    {
        _logger = logger;
        // Fallback: אם FIRESTORE_PROJECT_ID חסר — משתמשים ב-thehunter-485508 לבדיקות
        EffectiveProjectId = config["FIRESTORE_PROJECT_ID"]
            ?? Environment.GetEnvironmentVariable("FIRESTORE_PROJECT_ID")
            ?? DefaultProjectId;
        try
        {
            _db = new FirestoreDbBuilder { ProjectId = EffectiveProjectId }.Build();
            _logger.LogInformation(
                "[AdminFirestore] Connected to project {ProjectId}. Collections: {Cols}. " +
                "Cloud Run: ודא שה-Service Account יש לו Cloud Datastore User / Firestore permissions.",
                EffectiveProjectId,
                string.Join(", ", ColKnowledgeBase, ColUsers, ColLogs, ColRankingSettings));
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
        Console.WriteLine($"[FIRESTORE_ATTEMPT] Writing to collection {collectionName} in project {EffectiveProjectId}");
    }

    /// <summary>בודק אם השגיאה היא Permission Denied — לוג מפורט לקונסול ולבדיקת Cloud Run logs.</summary>
    private void LogIfPermissionDenied(Exception ex, string operation)
    {
        var inner = ex;
        while (inner != null)
        {
            if (inner is RpcException rpc && rpc.StatusCode == StatusCode.PermissionDenied)
            {
                Console.WriteLine($"[FIRESTORE PERMISSION DENIED] operation={operation}, ProjectId={EffectiveProjectId}, Detail={rpc.Status.Detail}");
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
    /// מונחים שממתינים לאישור (isApproved == false). שדות ב-Firestore: term, category, frequency, isApproved, lastSeen.
    /// </summary>
    public async Task<(List<LearnedTerm> Terms, bool Ok)> GetPendingTermsAsync()
    {
        try
        {
            var col = _db.Collection(ColKnowledgeBase);
            var query = col.WhereEqualTo("isApproved", false);
            var snapshot = await query.GetSnapshotAsync();
            var list = new List<LearnedTerm>();
            foreach (var doc in snapshot.Documents)
            {
                var data = doc.ToDictionary();
                var term = MapDocToLearnedTerm(doc.Id, data);
                if (term != null)
                    list.Add(term);
            }
            list = list.OrderByDescending(x => x.Frequency).ThenByDescending(x => x.LastSeen).ToList();
            if (list.Count == 0)
            {
                _logger.LogWarning("Firestore returned 0 documents from [{Col}]. ProjectId={ProjectId}. ודא שה-collection קיים והמפתחות נטענו נכון.", ColKnowledgeBase, EffectiveProjectId);
            }
            return (list, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetPendingTerms");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            return (new List<LearnedTerm>(), false);
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
            if (list.Count == 0)
            {
                _logger.LogWarning("Firestore returned 0 documents from [{Col}]. ProjectId={ProjectId}. ודא שה-collection קיים והמפתחות נטענו נכון.", ColUsers, EffectiveProjectId);
            }
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
            if (list.Count == 0)
            {
                _logger.LogWarning("Firestore returned 0 documents from [{Col}]. ProjectId={ProjectId}. ודא שה-collection קיים והמפתחות נטענו נכון.", ColLogs, EffectiveProjectId);
            }
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
            if (dict.Count == 0)
                _logger.LogWarning("Firestore returned 0 documents from [{Col}]. ProjectId={ProjectId}. ודא שה-collection קיים והמפתחות נטענו נכון.", ColRankingSettings, EffectiveProjectId);
            return (dict, true);
        }
        catch (Exception ex)
        {
            LogIfPermissionDenied(ex, "GetRankingWeights");
            _logger.LogError(ex, "ERROR fetching from Firestore: {Message}", ex.Message);
            Console.WriteLine($"ERROR fetching from Firestore: {ex.Message}");
            return (new Dictionary<string, double>(), false);
        }
    }

    public async Task<bool> ApproveTermAsync(string documentId)
    {
        try
        {
            LogWriteAttempt(ColKnowledgeBase, "Update");
            var ref_ = _db.Collection(ColKnowledgeBase).Document(documentId);
            await ref_.UpdateAsync(new Dictionary<string, object>
            {
                { "isApproved", true },
                { "lastSeen", Timestamp.FromDateTime(DateTime.UtcNow) },
            });
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ERROR updating Firestore term: {Message}", ex.Message);
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
                    { "isBanned", isBanned },
                    { "updatedAt", Timestamp.FromDateTime(DateTime.UtcNow) },
                });
                return true;
            }
            var query = await _db.Collection(ColUsers).WhereEqualTo("userId", userDocIdOrFirebaseUserId).Limit(1).GetSnapshotAsync();
            if (query.Documents.Count == 0) return false;
            await query.Documents[0].Reference.UpdateAsync(new Dictionary<string, object>
            {
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

    public async Task<bool> DeleteTermAsync(string documentId)
    {
        try
        {
            LogWriteAttempt(ColKnowledgeBase, "Delete");
            await _db.Collection(ColKnowledgeBase).Document(documentId).DeleteAsync();
            return true;
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
            var data = new Dictionary<string, object>
            {
                { "email", email.Trim() },
                { "userId", userId ?? "" },
                { "role", role is "Admin" or "DebugAccess" ? role : "User" },
                { "createdAt", now },
                { "updatedAt", now },
            };
            await col.AddAsync(data);
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
                { "role", role is "Admin" or "DebugAccess" ? role : "User" },
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

    /// <summary>מחזיר מונח בודד לפי מזהה מסמך.</summary>
    public async Task<LearnedTerm?> GetTermByIdAsync(string documentId)
    {
        try
        {
            var snap = await _db.Collection(ColKnowledgeBase).Document(documentId).GetSnapshotAsync();
            if (!snap.Exists) return null;
            return MapDocToLearnedTerm(documentId, snap.ToDictionary());
        }
        catch
        {
            return null;
        }
    }

    /// <summary>מעדכן שדות term, definition, category במסמך knowledge_base.</summary>
    public async Task<bool> UpdateTermAsync(string documentId, string term, string definition, string category)
    {
        try
        {
            LogWriteAttempt(ColKnowledgeBase, "Update");
            await _db.Collection(ColKnowledgeBase).Document(documentId).UpdateAsync(new Dictionary<string, object>
            {
                { "term", term ?? "" },
                { "definition", definition ?? "" },
                { "category", category ?? "" },
            });
            return true;
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
            var list = await GetApprovedTermsForExportAsync();
            var today = DateTime.UtcNow.Date;
            return list.Count(t => t.LastSeen.Date == today);
        }
        catch { return 0; }
    }

    public async Task<int> GetPendingTermsCountAsync()
    {
        try
        {
            var snap = await _db.Collection(ColKnowledgeBase).WhereEqualTo("isApproved", false).GetSnapshotAsync();
            return snap.Count;
        }
        catch { return 0; }
    }

    public async Task<int> GetApprovedTermsCountAsync()
    {
        try
        {
            var snap = await _db.Collection(ColKnowledgeBase).WhereEqualTo("isApproved", true).GetSnapshotAsync();
            return snap.Count;
        }
        catch { return 0; }
    }

    /// <summary>כל המונחים שאושרו — לייצוא Excel.</summary>
    public async Task<List<LearnedTerm>> GetApprovedTermsForExportAsync()
    {
        var list = new List<LearnedTerm>();
        try
        {
            var snap = await _db.Collection(ColKnowledgeBase).WhereEqualTo("isApproved", true).GetSnapshotAsync();
            foreach (var doc in snap.Documents)
            {
                var t = MapDocToLearnedTerm(doc.Id, doc.ToDictionary());
                if (t != null) list.Add(t);
            }
        }
        catch { }
        return list;
    }

    /// <summary>מונחים חדשים לפי יום (לפי timestamp או lastSeen) — עד 30 יום אחרונים.</summary>
    public async Task<Dictionary<string, int>> GetNewTermsPerDayAsync(int lastDays = 30)
    {
        var result = new Dictionary<string, int>(StringComparer.Ordinal);
        try
        {
            var snap = await _db.Collection(ColKnowledgeBase).GetSnapshotAsync();
            var cutoff = DateTime.UtcNow.Date.AddDays(-lastDays);
            foreach (var doc in snap.Documents)
            {
                var data = doc.ToDictionary();
                var tsVal = GetField(data, "timestamp") ?? GetField(data, "lastSeen") ?? GetField(data, "createdAt");
                DateTime? dt = null;
                if (tsVal is Timestamp ts) dt = ts.ToDateTime();
                if (!dt.HasValue || dt.Value < cutoff) continue;
                var key = dt.Value.Date.ToString("yyyy-MM-dd");
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
            var tsVal = GetField(data, "lastSeen") ?? GetField(data, "timestamp");
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
