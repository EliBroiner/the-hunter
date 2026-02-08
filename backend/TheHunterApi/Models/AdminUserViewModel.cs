namespace TheHunterApi.Models;

/// <summary>
/// משתמש Admin — מזהה הוא Firestore document id.
/// שדות מ-Firestore: email, userId, role, createdAt/registrationDate, updatedAt, lastSeen (Timestamp → DateTime).
/// </summary>
public class AdminUserViewModel
{
    public string Id { get; set; } = string.Empty;
    public string Email { get; set; } = string.Empty;
    public string UserId { get; set; } = string.Empty;
    public string Role { get; set; } = "User";
    /// <summary>Firestore: createdAt או registrationDate (Timestamp)</summary>
    public DateTime? RegistrationDate { get; set; }
    /// <summary>Firestore: updatedAt (Timestamp)</summary>
    public DateTime UpdatedAt { get; set; }
    /// <summary>Firestore: lastSeen (Timestamp)</summary>
    public DateTime? LastSeen { get; set; }
}
