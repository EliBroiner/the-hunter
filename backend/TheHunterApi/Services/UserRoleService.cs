using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;

namespace TheHunterApi.Services;

/// <summary>
/// בודק הרשאות משתמש — Admin, DebugAccess, User
/// Admin כולל אוטומטית DebugAccess
/// </summary>
public class UserRoleService
{
    private readonly IDbContextFactory<AppDbContext> _dbFactory;

    public UserRoleService(IDbContextFactory<AppDbContext> dbFactory)
    {
        _dbFactory = dbFactory;
    }

    /// <summary>
    /// בודק אם למשתמש יש את התפקיד המבוקש.
    /// תומך בחיפוש לפי UserId או Email (למקרה של bootstrap — רישום ראשון עם email)
    /// </summary>
    public async Task<bool> HasRoleAsync(string userId, string role, string? email = null)
    {
        if (string.IsNullOrWhiteSpace(userId) && string.IsNullOrWhiteSpace(email))
            return false;

        await using var db = _dbFactory.CreateDbContext();

        var user = await db.AppManagedUsers
            .FirstOrDefaultAsync(u =>
                (!string.IsNullOrEmpty(userId) && u.UserId == userId) ||
                (!string.IsNullOrEmpty(email) && u.Email.Equals(email, StringComparison.OrdinalIgnoreCase)));

        if (user == null)
            return false;

        // קישור: אם מצאנו לפי email ו־UserId ריק — מעדכן ל־UserId הנוכחי
        if (string.IsNullOrEmpty(user.UserId) && !string.IsNullOrEmpty(userId))
        {
            user.UserId = userId;
            user.UpdatedAt = DateTime.UtcNow;
            await db.SaveChangesAsync();
        }

        return HasRole(user.Role, role);
    }

    /// <summary>
    /// Admin כולל אוטומטית DebugAccess
    /// </summary>
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
