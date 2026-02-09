using Google.Cloud.Firestore;

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
    /// </summary>
    public async Task<bool> HasRoleAsync(string userId, string role, string? email = null)
    {
        if (string.IsNullOrWhiteSpace(userId))
            return false;

        var docRef = _firestore.Collection(ColUsers).Document(userId);
        var snap = await docRef.GetSnapshotAsync();

        // שלב ב: יצירה או קידום
        if (!snap.Exists)
        {
            var initialRoles = new List<object> { "User" };
            var isAdmin = _IsAdminEmail(email);
            if (isAdmin)
                initialRoles.Add("Admin");
            var data = new Dictionary<string, object>
            {
                { "roles", initialRoles },
                { "createdAt", Timestamp.FromDateTime(DateTime.UtcNow) },
            };
            if (!string.IsNullOrWhiteSpace(email))
                data["email"] = email;
            await docRef.SetAsync(data);
            _logger.LogInformation("Auto-created user {UserId} (Admin: {IsAdmin})", userId, isAdmin);
            return CheckHasRole(initialRoles, role);
        }

        var dataExisting = snap.ToDictionary();
        var rolesList = GetRolesList(dataExisting);

        // Self-healing: email תואם ADMIN_EMAIL אבל אין Admin ב-roles
        if (_IsAdminEmail(email) && rolesList != null && !rolesList.Any(r => string.Equals(r?.ToString(), "Admin", StringComparison.OrdinalIgnoreCase)))
        {
            await docRef.UpdateAsync(new Dictionary<string, object>
            {
                { "roles", FieldValue.ArrayUnion("Admin") },
                { "updatedAt", Timestamp.FromDateTime(DateTime.UtcNow) },
            });
            if (!string.IsNullOrWhiteSpace(email))
                await docRef.UpdateAsync(new Dictionary<string, object> { { "email", email } });
            _logger.LogInformation("Self-healing: added Admin to user {UserId}", userId);
            rolesList = new List<object>(rolesList!) { "Admin" };
        }

        return CheckHasRoleFromDoc(dataExisting, rolesList, role);
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
            roles.Any(r => string.Equals(r?.ToString(), "Admin", StringComparison.OrdinalIgnoreCase)))
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

    /// <summary>
    /// מוסיף תפקיד למשתמש. יוצר מסמך אם לא קיים (MergeAll).
    /// </summary>
    public async Task AddRoleAsync(string userId, string role)
    {
        if (string.IsNullOrWhiteSpace(userId) || string.IsNullOrWhiteSpace(role))
            return;
        var ref_ = _firestore.Collection(ColUsers).Document(userId);
        await ref_.SetAsync(new Dictionary<string, object>
        {
            { "roles", FieldValue.ArrayUnion(role) }
        }, SetOptions.MergeAll);
    }

    private static bool HasRole(string userRole, string requiredRole)
    {
        if (userRole.Equals(requiredRole, StringComparison.OrdinalIgnoreCase))
            return true;
        if (requiredRole.Equals("DebugAccess", StringComparison.OrdinalIgnoreCase) &&
            userRole.Equals("Admin", StringComparison.OrdinalIgnoreCase))
            return true;
        return false;
    }
}
