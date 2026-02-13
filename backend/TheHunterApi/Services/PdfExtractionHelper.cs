using UglyToad.PdfPig;

namespace TheHunterApi.Services;

/// <summary>
/// חילוץ טקסט מ-PDF — שימוש חוזר ב-OcrTest (Admin AI Lab).
/// </summary>
internal static class PdfExtractionHelper
{
    /// <summary>מחלץ טקסט מ-PDF. מחזיר (טקסט, יחס ג'יבריש). כשלון → ("", 1.0).</summary>
    public static (string Text, double GarbageRatio) TryExtractText(byte[] bytes)
    {
        try
        {
            using var doc = PdfDocument.Open(new MemoryStream(bytes));
            var text = string.Join("\n", doc.GetPages().Select(p => p.Text));
            if (string.IsNullOrEmpty(text)) return ("", 1.0);
            var ratio = TextQualityHelper.GetGarbageRatio(text);
            return (text, ratio);
        }
        catch
        {
            return ("", 1.0);
        }
    }
}
