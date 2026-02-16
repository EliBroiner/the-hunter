using Google.Cloud.Firestore;
using TheHunterApi.Constants;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>חלק partial — משתמשים (users).</summary>
public partial class AdminFirestoreService
{
    /// <summary>משתמשים מנוהלים — collection 'users'.</summary>
    public async Task<(List<AdminUserViewModel> Users, bool Ok)> GetUsersAsync()
    {
        try
        {
            var snapshot = await _db.Collection(ColUsers).OrderBy("email").GetSnapshotAsync();
            var list = new List<AdminUserViewModel>();
            foreach (var doc in snapshot.Documents)
            {
                var u = MapDocToAdminUser(doc.Id, doc.ToDictionary());
                if (u != null) list.Add(u);
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

    /// <summary>מגדיר isBanned — לפי doc id או userId.</summary>
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

    public async Task<bool> AddUserAsync(string email, string userId, string role)
    {
        try
        {
            LogWriteAttempt(ColUsers, "Add");
            var col = _db.Collection(ColUsers);
            var existing = await col.WhereEqualTo("email", email.Trim()).GetSnapshotAsync();
            if (existing.Count > 0) return false;
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

    /// <summary>מיגרציה: מוסיף id = Document ID למסמכים חסרים.</summary>
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
                    _logger.LogInformation("Users migration: set id={DocId}", doc.Id);
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

    public async Task<int> GetUsersCountAsync()
    {
        try
        {
            var snap = await _db.Collection(ColUsers).GetSnapshotAsync();
            return snap.Count;
        }
        catch { return 0; }
    }

    /// <summary>משתמשים שנוספו ב-24 השעות האחרונות.</summary>
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
                Id = docId, Email = email, UserId = userId ?? "", Role = role ?? "User",
                RegistrationDate = registrationDate, UpdatedAt = updatedAt, LastSeen = lastSeen,
            };
        }
        catch { return null; }
    }
}
