using Google.Cloud.Firestore;

using TheHunterApi.Constants;

namespace TheHunterApi.Services;

/// <summary>
/// בודק הרשאות משתמש — Firestore collection users, document id = userId.
/// Auto-bootstrap: יצירת מסמך first access; קידום ל-Admin אם email תואם ל-ADMIN_EMAIL.
/// </summary>
public class UserRoleService
{
    private const string ColUsers = "users";
    private readonly FirestoreDb _firestore;
    private readonly IConfiguration _config;
    private readonly ILogger<UserRoleService> _logger;
    private readonly string? _adminEmail;

    public UserRoleService(FirestoreDb firestore, IConfiguration config, ILogger<UserRoleService> logger)
    {
        _firestore = firestore;
        _config = config;
        _logger = logger;
        _adminEmail = _config["ADMIN_EMAIL"] ?? Environment.GetEnvironmentVariable("ADMIN_EMAIL");
    }

    /// <summary>
    /// בודק אם למשתמש יש את התפקיד המבוקש. יוצר/מעדכן מסמך אוטומטית (lazy + Admin bootstrap).
    /// מיזוג Ghost→Real ו־self-heal של שדה id מתבצעים בטרנזקציה כדי למנוע אובדן נתונים.
    /// </summary>
    public async Task<bool> HasRoleAsync(string userId, string role, string? email = null)
    {
        if (string.IsNullOrWhiteSpace(userId))
            return false;

        var docRef = _firestore.Collection(ColUsers).Document(userId);
        DocumentReference? ghostRef = null;
        IReadOnlyDictionary<string, object>? ghostData = null;

        if (!string.IsNullOrWhiteSpace(email))
        {
            var ghostQuery = await _firestore.Collection(ColUsers)
                .WhereEqualTo("email", email.Trim())
                .Limit(1)
                .GetSnapshotAsync();
            if (ghostQuery.Documents.Count > 0)
            {
                var ghostDoc = ghostQuery.Documents[0];
                if (ghostDoc.Id != userId)
                {
                    ghostRef = ghostDoc.Reference;
                    ghostData = ghostDoc.ToDictionary();
                }
            }
        }

        await _firestore.RunTransactionAsync(async transaction =>
        {
            var realSnap = await transaction.GetSnapshotAsync(docRef);

            if (realSnap.Exists)
            {
                // Real User קיים — עדכון lastLogin + self-heal id אם חסר
                var updates = new Dictionary<string, object>
                {
                    { "lastLogin", FieldValue.ServerTimestamp },
                };
                var current = realSnap.ToDictionary();
                if (!current.TryGetValue("id", out var idVal) || idVal == null || string.IsNullOrWhiteSpace(idVal.ToString()))
                {
                    updates["id"] = userId;
                    _logger.LogInformation("Self-healing: set id={UserId} on existing user doc", userId);
                }
                transaction.Update(docRef, updates);
                return;
            }

            if (ghostRef != null && ghostData != null)
            {
                // Ghost קיים ו-Real לא — מיזוג אטומי: קודם יצירת Real (Merge), אחר כך מחיקת Ghost
                var oldRoles = GetRolesList(ghostData);
                var oldRole = ghostData.TryGetValue("role", out var r) ? r?.ToString() ?? "User" : "User";
                var rolesToSet = oldRoles != null && oldRoles.Count > 0
                    ? oldRoles
                    : new List<object> { oldRole };
                var newData = new Dictionary<string, object>
                {
                    { "id", userId },
                    { "email", email!.Trim() },
                    { "roles", rolesToSet },
                    { "createdAt", Timestamp.FromDateTime(DateTime.UtcNow) },
                    { "updatedAt", Timestamp.FromDateTime(DateTime.UtcNow) },
                };
                transaction.Set(docRef, newData, SetOptions.MergeAll);
                transaction.Delete(ghostRef);
                _logger.LogInformation(
                    "[Auth] Merged ghost user {OldId} into {UserId} (transaction). Preserved Role: {OldRole}.",
                    ghostRef.Id, userId, oldRole);
                return;
            }

            // Fallback: יצירת משתמש חדש
            var initialRoles = new List<object> { "User" };
            if (_IsAdminEmail(email))
                initialRoles.Add(RolesConstants.Admin);
            var data = new Dictionary<string, object>
            {
                { "id", userId },
                { "roles", initialRoles },
                { "createdAt", Timestamp.FromDateTime(DateTime.UtcNow) },
            };
            if (!string.IsNullOrWhiteSpace(email))
                data["email"] = email;
            transaction.Set(docRef, data, SetOptions.MergeAll);
            _logger.LogInformation("Auto-created user {UserId} (Admin: {IsAdmin})", userId, _IsAdminEmail(email));
        });

        // Admin bootstrap (מחוץ לטרנזקציה — עדכון תפקיד לפי ADMIN_EMAIL)
        var snapAfter = await docRef.GetSnapshotAsync();
        if (snapAfter.Exists)
        {
            var dataExisting = snapAfter.ToDictionary();
            var rolesList = GetRolesList(dataExisting);
            if (_IsAdminEmail(email) && rolesList != null && !rolesList.Any(r => string.Equals(r?.ToString(), RolesConstants.Admin, StringComparison.OrdinalIgnoreCase)))
            {
                await docRef.UpdateAsync(new Dictionary<string, object>
                {
                    { "id", userId },
                    { "roles", FieldValue.ArrayUnion(RolesConstants.Admin) },
                    { "updatedAt", Timestamp.FromDateTime(DateTime.UtcNow) },
                });
                if (!string.IsNullOrWhiteSpace(email))
                    await docRef.UpdateAsync(new Dictionary<string, object> { { "email", email } });
                _logger.LogInformation("Self-healing: added Admin to user {UserId}", userId);
                rolesList = new List<object>(rolesList!) { RolesConstants.Admin };
            }
            return CheckHasRoleFromDoc(dataExisting, rolesList, role);
        }

        return false;
    }

    private bool _IsAdminEmail(string? email)
    {
        if (string.IsNullOrWhiteSpace(_adminEmail) || string.IsNullOrWhiteSpace(email))
            return false;
        return string.Equals(email.Trim(), _adminEmail.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private static List<object>? GetRolesList(IReadOnlyDictionary<string, object> data)
    {
        if (data.TryGetValue("roles", out var rolesVal) && rolesVal is IList<object> list)
            return list.ToList();
        if (data.TryGetValue("role", out var single) && single != null)
            return new List<object> { single };
        return null;
    }

    private static bool CheckHasRole(List<object> roles, string role)
    {
        var has = roles.Any(r => string.Equals(r?.ToString(), role, StringComparison.OrdinalIgnoreCase));
        if (has) return true;
        if (role.Equals("DebugAccess", StringComparison.OrdinalIgnoreCase) &&
            roles.Any(r => string.Equals(r?.ToString(), RolesConstants.Admin, StringComparison.OrdinalIgnoreCase)))
            return true;
        return false;
    }

    private bool CheckHasRoleFromDoc(IReadOnlyDictionary<string, object> data, List<object>? rolesList, string role)
    {
        if (rolesList != null)
            return CheckHasRole(rolesList, role);
        var singleRole = data.TryGetValue("role", out var r) ? r?.ToString() ?? "" : "";
        return HasRole(singleRole, role);
    }

    private static bool HasRole(string userRole, string requiredRole)
    {
        if (userRole.Equals(requiredRole, StringComparison.OrdinalIgnoreCase))
            return true;
        if (requiredRole.Equals(RolesConstants.DebugAccess, StringComparison.OrdinalIgnoreCase) &&
            userRole.Equals(RolesConstants.Admin, StringComparison.OrdinalIgnoreCase))
            return true;
        return false;
    }
}
