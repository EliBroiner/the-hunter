using Google.Cloud.Vision.V1;
using Grpc.Core;
using SixLabors.ImageSharp;
using SixLabors.ImageSharp.PixelFormats;

namespace TheHunterApi.Services;

/// <summary>
/// חילוץ טקסט מתמונות דרך Google Cloud Vision. משמש כ-fallback כש־ML Kit נכשל.
/// </summary>
public class OcrService
{
    private readonly ILogger<OcrService> _logger;
    private ImageAnnotatorClient? _client;

    public OcrService(ILogger<OcrService> logger) => _logger = logger;

    /// <summary>יוצר לקוח Cloud Vision (עם Application Default Credentials).</summary>
    private ImageAnnotatorClient GetClient()
    {
        if (_client == null)
        {
            try
            {
                _client = ImageAnnotatorClient.Create();
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Failed to create Cloud Vision client");
                throw;
            }
        }
        return _client;
    }

    /// <summary>
    /// חילוץ טקסט מתמונה דרך Cloud Vision.
    /// מחזיר (text, success, isPureImageNoText) — isPureImageNoText=true כשהתמונה נקייה מטקסט (למנוע retries).
    /// </summary>
    public async Task<(string Text, bool Success, bool IsPureImageNoText)> ExtractTextFromImageAsync(byte[] imageBytes)
    {
        try
        {
            var image = Google.Cloud.Vision.V1.Image.FromBytes(imageBytes);
            var response = await GetClient().DetectDocumentTextAsync(image);

            var fullText = response?.Text?.Trim() ?? "";
            var isPureImageNoText = string.IsNullOrEmpty(fullText);

            if (isPureImageNoText)
            {
                _logger.LogInformation("Pure Image - No Text Found: Cloud Vision returned no text. Avoid future retries.");
            }

            return (fullText, true, isPureImageNoText);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Cloud Vision OCR failed");
            return ("", false, false);
        }
    }

    /// <summary>בדיקה זמנית — שולח תמונה ל-Cloud Vision, מחזיר טקסט או הודעת שגיאה מדויקת.</summary>
    public async Task<(string? Text, string? Error)> TestCloudVisionAsync(byte[] imageBytes)
    {
        try
        {
            var image = Google.Cloud.Vision.V1.Image.FromBytes(imageBytes);
            var response = await GetClient().DetectDocumentTextAsync(image);
            var text = response?.Text?.Trim() ?? "";
            return (string.IsNullOrEmpty(text) ? "(no text in image)" : text, null);
        }
        catch (Exception ex)
        {
            var msg = ex.Message;
            if (ex.InnerException != null)
                msg += " | Inner: " + ex.InnerException.Message;
            if (ex is RpcException rpc)
                msg = $"{rpc.StatusCode} {rpc.Status.Detail}";
            return (null, msg);
        }
    }

    /// <summary>
    /// בודק אם התמונה נראית מעובדת (גווני אפור/B&W) — R≈G≈B לרוב הפיקסלים.
    /// דוגמית ~100 פיקסלים. מחזיר true אם &gt;90% פיקסלים grayscale.
    /// </summary>
    public static bool AppearsPreprocessedBw(byte[] imageBytes)
    {
        try
        {
            using var image = SixLabors.ImageSharp.Image.Load<Rgb24>(imageBytes);
            var w = image.Width;
            var h = image.Height;
            if (w == 0 || h == 0) return false;

            const int sampleSize = 100;
            const int tolerance = 12; // R,G,B within 12 = grayscale
            var step = Math.Max(1, (w * h) / sampleSize);
            var grayscaleCount = 0;
            var total = 0;

            for (var i = 0; i < w * h && total < sampleSize; i += step)
            {
                var x = i % w;
                var y = i / w;
                if (y >= h) break;

                var p = image[x, y];
                var isGray = Math.Abs(p.R - p.G) <= tolerance && Math.Abs(p.G - p.B) <= tolerance;
                if (isGray) grayscaleCount++;
                total++;
            }

            return total > 0 && (double)grayscaleCount / total >= 0.9;
        }
        catch
        {
            return false;
        }
    }
}
