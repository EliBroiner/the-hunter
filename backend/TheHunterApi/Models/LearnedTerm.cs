using System.ComponentModel.DataAnnotations.Schema;

namespace TheHunterApi.Models;

/// <summary>
/// מונח שנלמד מ-AI — תואם למסמכי Firestore ב־knowledge_base.
/// מיפוי שדות: term, definition, category, frequency, isApproved, userId, lastSeen/timestamp.
/// </summary>
public class LearnedTerm
{
    public int Id { get; set; }
    [NotMapped]
    public string? FirestoreId { get; set; }
    /// <summary>Firestore: term</summary>
    public string Term { get; set; } = string.Empty;
    /// <summary>Firestore: definition (אופציונלי)</summary>
    public string? Definition { get; set; }
    /// <summary>Firestore: category</summary>
    public string Category { get; set; } = string.Empty;
    /// <summary>Firestore: frequency</summary>
    public int Frequency { get; set; } = 1;
    /// <summary>Firestore: isApproved</summary>
    public bool IsApproved { get; set; }
    /// <summary>Firestore: userId (אופציונלי)</summary>
    public string? UserId { get; set; }
    /// <summary>Firestore: lastSeen או timestamp</summary>
    public DateTime LastSeen { get; set; }
}
