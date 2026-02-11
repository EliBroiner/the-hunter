using System.ComponentModel.DataAnnotations;

namespace TheHunterApi.Models;

/// <summary>
/// ניהול פרומפטים למערכת — Search, Summary, Tags. רק פרומפט אחד פעיל לכל feature.
/// </summary>
public class SystemPrompt
{
    [Key]
    public int Id { get; set; }

    [Required]
    public string Content { get; set; } = string.Empty;

    /// <summary>מזהה גרסה — מחרוזת או auto-increment. להבחנה בין גרסאות.</summary>
    [Required]
    [MaxLength(50)]
    public string Version { get; set; } = string.Empty;

    /// <summary>רק פרומפט אחד לכל feature יכול להיות פעיל.</summary>
    public bool IsActive { get; set; }

    /// <summary>הבחנה בין features: Search, Summary, Tags, DocAnalysis וכו'.</summary>
    [Required]
    [MaxLength(50)]
    public string Feature { get; set; } = string.Empty;

    public DateTime CreatedAt { get; set; }

    /// <summary>תאריך הפעלה — כשנעשה IsActive = true.</summary>
    public DateTime? ActivatedAt { get; set; }
}
