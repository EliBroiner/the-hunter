using System.ComponentModel.DataAnnotations;
using System.ComponentModel.DataAnnotations.Schema;

namespace TheHunterApi.Data;

/// <summary>
/// מעקב שימוש AI למשתמש לפי חודש - לצורך הגבלת מכסה (Free Tier)
/// </summary>
public class UserAiUsage
{
    [Key]
    [Column(Order = 0)]
    [MaxLength(256)]
    public string UserId { get; set; } = string.Empty;

    [Key]
    [Column(Order = 1)]
    [MaxLength(7)]  // "2026-01"
    public string YearMonth { get; set; } = string.Empty;

    public int ScanCount { get; set; }
}
