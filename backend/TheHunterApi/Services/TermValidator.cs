using System.Globalization;
using System.Text.RegularExpressions;

namespace TheHunterApi.Services;

/// <summary>
/// ולידציה וסניטציה למונחים - מניעת Dictionary Stuffing (ספאם, ג'יבריש, הזרקה)
/// </summary>
public static class TermValidator
{
    private const int MaxTermLength = 80;
    private const int MaxCategoryLength = 50;

    // תווים מותרים: אותיות (כולל עברית), ספרות, רווח, מקף, גרש
    private static readonly Regex AllowedTermRegex = new(
        @"^[\p{L}\p{N}\s\-']+$",
        RegexOptions.Compiled | RegexOptions.CultureInvariant,
        TimeSpan.FromMilliseconds(50));

    // דחיית רצף עיצורים ארוך (4+ ברצף) - ג'יבריש באנגלית
    private static readonly Regex ConsecutiveConsonantsRegex = new(
        @"[bcdfghjklmnpqrstvwxzBCDFGHJKLMNPQRSTVWXZ]{4,}",
        RegexOptions.Compiled,
        TimeSpan.FromMilliseconds(20));

    // דחיית תו שחוזר על עצמו 4+ פעמים (לדוגמה: aaaaa)
    private static readonly Regex RepeatedCharRegex = new(
        @"(.)\1{3,}",
        RegexOptions.Compiled,
        TimeSpan.FromMilliseconds(20));

    /// <summary>
    /// בודק אם מונח תקין - אורך, תווים, ג'יבריש
    /// </summary>
    public static bool IsValidTerm(string? term)
    {
        if (string.IsNullOrWhiteSpace(term)) return false;
        var t = term.Trim();
        if (t.Length > MaxTermLength) return false;
        if (t.Length < 2) return false; // מינימום 2 תווים

        // דחיית תווים לא מותרים
        if (!AllowedTermRegex.IsMatch(t)) return false;

        // דחיית ג'יבריש - רצף עיצורים ארוך
        if (ConsecutiveConsonantsRegex.IsMatch(t)) return false;

        // דחיית חזרות
        if (RepeatedCharRegex.IsMatch(t)) return false;

        // דחיית מונח שהוא רק ספרות
        if (t.All(char.IsDigit)) return false;

        return true;
    }

    /// <summary>
    /// בודק אם קטגוריה תקינה
    /// </summary>
    public static bool IsValidCategory(string? category)
    {
        if (string.IsNullOrWhiteSpace(category)) return true; // general יתקבל
        var c = category.Trim();
        if (c.Length > MaxCategoryLength) return false;
        return AllowedTermRegex.IsMatch(c);
    }
}
