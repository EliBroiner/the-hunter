using System.Text.RegularExpressions;

namespace TheHunterApi.Services;

/// <summary>
/// עזר איכות טקסט — ג'יבריש, ניקוי, משמעותיות.
/// תואם ל-extracted_text_quality.dart ב-Flutter.
/// </summary>
public static class TextQualityHelper
{
    /// <summary>
    /// יחס תווים "זבל" (0.0–1.0).
    /// תווים תקינים: עברית (\u0590-\u05FF), לטינית, ספרות, רווחים, פיסוק בסיסי.
    /// </summary>
    public static double GetGarbageRatio(string text)
    {
        if (string.IsNullOrEmpty(text)) return 1.0;
        int total = 0, garbage = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            total++;
            if (!IsValidChar(rune.Value)) garbage++;
        }
        return total == 0 ? 1.0 : (double)garbage / total;
    }

    /// <summary>תווים תקינים: טאב, שורה חדשה, רווח, ספרות, A-Z, a-z, עברית, פיסוק בסיסי.</summary>
    public static bool IsValidChar(int codePoint)
    {
        if (codePoint <= 0x20 && (codePoint == 0x09 || codePoint == 0x0A || codePoint == 0x0D || codePoint == 0x20))
            return true;
        if (codePoint >= 0x30 && codePoint <= 0x39) return true; // 0-9
        if (codePoint >= 0x41 && codePoint <= 0x5A) return true; // A-Z
        if (codePoint >= 0x61 && codePoint <= 0x7A) return true; // a-z
        if (codePoint >= 0x0590 && codePoint <= 0x05FF) return true; // עברית + ניקוד
        int[] punct = [0x2C, 0x2E, 0x3A, 0x3B, 0x21, 0x3F, 0x2D, 0x5F, 0x27, 0x22, 0x28, 0x29];
        return punct.Contains(codePoint);
    }

    /// <summary>בודק אם הטקסט משמעותי — minValidRatio תווים תקינים ואורך מינימלי minLength.</summary>
    public static bool IsTextMeaningful(string text, int minLength, double minValidRatio)
    {
        if (string.IsNullOrEmpty(text) || text.Length < minLength) return false;
        var validRatio = 1.0 - GetGarbageRatio(text);
        return validRatio >= minValidRatio;
    }

    /// <summary>TextCleaner — ניקוי טקסט: רווחים, תווים לא רצויים (תואם ל-Flutter _cleanupText).</summary>
    public static string CleanText(string text)
    {
        if (string.IsNullOrEmpty(text)) return "";
        var cleaned = Regex.Replace(text, @"\n{3,}", "\n\n");
        cleaned = Regex.Replace(cleaned, @"[ \t]+", " ");
        cleaned = Regex.Replace(cleaned, @"[\x00-\x08\x0B\x0C\x0E-\x1F]", "");
        return cleaned.Trim();
    }
}
