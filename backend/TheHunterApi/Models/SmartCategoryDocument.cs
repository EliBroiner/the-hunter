namespace TheHunterApi.Models;

/// <summary>
/// מודל למסמך ב-Firestore collection smart_categories — קטגוריה עם מילים ו-Regex.
/// המבנה תואם לשמירה/קריאה מ-Firestore (כולל מהלקוח).
/// </summary>
public class SmartCategoryDocument
{
    /// <summary>מפתח פנימי (למשל bank_transfer).</summary>
    public string Key { get; set; } = string.Empty;

    /// <summary>שמות לתצוגה: "en" -> "Bank Transfer", "he" -> "העברה בנקאית".</summary>
    public Dictionary<string, string> DisplayNames { get; set; } = new();

    /// <summary>מילים לזיהוי (מילון).</summary>
    public List<string> Keywords { get; set; } = new();

    /// <summary>תבניות Regex (חוקים חכמים).</summary>
    public List<string> RegexPatterns { get; set; } = new();

    /// <summary>דירוג לכל keyword — "Boarding Pass"→Strong, "Payment"→Weak. ברירת מחדל: Medium.</summary>
    public Dictionary<string, string> KeywordRanks { get; set; } = new();

    /// <summary>Firestore: last_updated — לסנכרון חכם.</summary>
    public DateTime LastUpdated { get; set; } = DateTime.MinValue;
}
