using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace TheHunterApi.Data;

/// <summary>
/// מכסת הצעות מונחים ללולאת למידה - per user per day (מניעת Dictionary Stuffing)
/// </summary>
public class UserLearningQuota
{
    [Key]
    [Column(Order = 0)]
    [MaxLength(256)]
    public string UserId { get; set; } = string.Empty;

    [Key]
    [Column(Order = 1)]
    [MaxLength(10)] // "2026-02-05"
    public string DateKey { get; set; } = string.Empty;

    public int SuggestionCount { get; set; }
}
