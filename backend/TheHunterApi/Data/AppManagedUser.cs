using System.ComponentModel.DataAnnotations;

namespace TheHunterApi.Data;

/// <summary>
/// משתמש מנוהל — תפקידים והרשאות (Admin, DebugAccess, User)
/// </summary>
public class AppManagedUser
{
    public int Id { get; set; }

    [MaxLength(256)]
    public string UserId { get; set; } = string.Empty;

    [MaxLength(256)]
    public string Email { get; set; } = string.Empty;

    [MaxLength(256)]
    public string? DisplayName { get; set; }

    [MaxLength(64)]
    public string Role { get; set; } = "User";

    public DateTime CreatedAt { get; set; }
    public DateTime UpdatedAt { get; set; }
}
