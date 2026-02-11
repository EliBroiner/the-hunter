using Microsoft.AspNetCore.Mvc;
using UglyToad.PdfPig;
using TheHunterApi.Filters;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// AI Lab Debugger — endpoints לבדיקת Scoring, Garbage Filter, Playground ו-OCR.
/// מוגן ב-AdminKeyAuthorizationFilter.
/// </summary>
[Route("admin/debug")]
[ServiceFilter(typeof(AdminKeyAuthorizationFilter))]
[ApiController]
public class AdminAiController : ControllerBase
{
    private readonly GeminiService _geminiService;
    private readonly ILogger<AdminAiController> _logger;

    private const int MaxFileSizeBytes = 10 * 1024 * 1024; // 10MB

    // משקלים מתוך RankingConfig — Filename: 200, Content: 120, Path/Metadata: 80
    private const double FilenameWeight = 200;
    private const double ContentWeight = 120;
    private const double MetadataWeight = 80;

    // סף ג'יבריש — 30% (כמו extracted_text_quality.dart)
    private const double GarbageThresholdPercent = 30;

    public AdminAiController(GeminiService geminiService, ILogger<AdminAiController> logger)
    {
        _geminiService = geminiService;
        _logger = logger;
    }

    /// <summary>
    /// POST /admin/debug/score — מחשב ציון רלוונטיות לפי שאילתה ומסמך (filename, content, metadata).
    /// מחזיר פירוט: Filename, Content, Metadata.
    /// </summary>
    [HttpPost("score")]
    [ProducesResponseType(typeof(ScoreDebugResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    public IActionResult Score([FromBody] ScoreDebugRequest request)
    {
        if (request == null || string.IsNullOrWhiteSpace(request.Query))
            return BadRequest(new ErrorResponse { Error = "Query is required" });

        var query = request.Query.Trim();
        var filename = (request.Filename ?? "").Trim();
        var content = (request.Content ?? "").Trim();
        var metadata = (request.Metadata ?? "").Trim();

        // פירוק שאילתה למונחים — split על רווחים, נרמול
        var terms = query.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Select(t => Normalize(t))
            .Where(t => t.Length > 0)
            .Distinct()
            .ToList();

        if (terms.Count == 0)
            return Ok(new ScoreDebugResponse
            {
                Query = query,
                Terms = [],
                FilenameScore = 0,
                ContentScore = 0,
                MetadataScore = 0,
                TotalScore = 0,
                Breakdown = "No terms extracted from query"
            });

        var fnLower = filename.ToLowerInvariant();
        var contentLower = content.ToLowerInvariant();
        var metaLower = metadata.ToLowerInvariant();

        // ספירת התאמות — כל מונח שמתאים בשדה מקבל את המשקל המלא (כמו RelevanceEngine)
        var matchesInFilename = terms.Count(t => fnLower.Contains(t));
        var matchesInContent = terms.Count(t => contentLower.Contains(t));
        var matchesInMetadata = terms.Count(t => metaLower.Contains(t));

        var fnScore = matchesInFilename * FilenameWeight;
        var contentScore = matchesInContent * ContentWeight;
        var metaScore = matchesInMetadata * MetadataWeight;

        var total = fnScore + contentScore + metaScore;
        var breakdown = $"Filename: {fnScore:F0} | Content: {contentScore:F0} | Metadata: {metaScore:F0}";

        return Ok(new ScoreDebugResponse
        {
            Query = query,
            Terms = terms,
            FilenameScore = fnScore,
            ContentScore = contentScore,
            MetadataScore = metaScore,
            TotalScore = total,
            Breakdown = breakdown
        });
    }

    /// <summary>
    /// POST /admin/debug/garbage-filter — מחשב יחס ג'יבריש לפי הלוגיקה של extracted_text_quality.dart.
    /// תווים תקינים: עברית, לטינית, ספרות, רווחים, פיסוק בסיסי. מעל 30% = נכשל.
    /// </summary>
    [HttpPost("garbage-filter")]
    [ProducesResponseType(typeof(GarbageFilterResponse), StatusCodes.Status200OK)]
    public IActionResult GarbageFilter([FromBody] GarbageFilterRequest request)
    {
        var text = request?.Text ?? "";

        if (text.Length == 0)
            return Ok(new GarbageFilterResponse
            {
                TextLength = 0,
                GarbageCount = 0,
                GarbageRatioPercent = 100,
                PassesThreshold = false,
                ThresholdPercent = GarbageThresholdPercent
            });

        var ratio = GetGarbageRatio(text);
        var percent = ratio * 100;
        var passes = ratio <= (GarbageThresholdPercent / 100.0);
        var garbageCount = (int)Math.Round(ratio * text.Length);

        _logger.LogInformation("[Debug] Garbage filter: textLen={Len}, garbage={Garbage}, ratio={Ratio:P1}, passes={Passes}",
            text.Length, garbageCount, ratio, passes);

        return Ok(new GarbageFilterResponse
        {
            TextLength = text.Length,
            GarbageCount = garbageCount,
            GarbageRatioPercent = Math.Round(percent, 2),
            PassesThreshold = passes,
            ThresholdPercent = GarbageThresholdPercent
        });
    }

    /// <summary>
    /// POST /admin/debug/playground — מריץ פרומפט מול Gemini, מחזיר תשובה גולמית (JSON).
    /// משמש ל-Prompt Playground באתר הניהול.
    /// </summary>
    [HttpPost("playground")]
    [ProducesResponseType(typeof(PlaygroundResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> Playground([FromBody] PlaygroundRequest request)
    {
        if (!_geminiService.IsConfigured)
            return StatusCode(503, new ErrorResponse { Error = "Gemini API not configured" });

        var systemPrompt = (request?.SystemPrompt ?? "").Trim();
        var userQuery = (request?.UserQuery ?? "").Trim();

        if (string.IsNullOrEmpty(userQuery))
            return BadRequest(new ErrorResponse { Error = "UserQuery is required" });

        if (string.IsNullOrEmpty(systemPrompt))
            systemPrompt = "You are a helpful assistant. Return JSON when appropriate.";

        var (rawText, success, error) = await _geminiService.GenerateContentRawAsync(systemPrompt, userQuery);

        return Ok(new PlaygroundResponse
        {
            RawJson = rawText,
            Success = success,
            Error = error
        });
    }

    /// <summary>
    /// POST /admin/debug/ocr-test — העלאת PDF/תמונה, חילוץ ישיר + fallback ל-Gemini אם ג'יבריש > 30%.
    /// </summary>
    [HttpPost("ocr-test")]
    [RequestSizeLimit(MaxFileSizeBytes)]
    [ProducesResponseType(typeof(OcrTestResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status503ServiceUnavailable)]
    public async Task<IActionResult> OcrTest(IFormFile? file)
    {
        if (file == null || file.Length == 0)
            return BadRequest(new ErrorResponse { Error = "קובץ נדרש" });

        if (file.Length > MaxFileSizeBytes)
            return BadRequest(new ErrorResponse { Error = $"גודל מקסימלי: {MaxFileSizeBytes / 1024 / 1024}MB" });

        var ext = Path.GetExtension(file.FileName).ToLowerInvariant().TrimStart('.');
        string mimeType = ext switch
        {
            "pdf" => "application/pdf",
            "jpg" or "jpeg" => "image/jpeg",
            "png" => "image/png",
            "webp" => "image/webp",
            _ => ""
        };

        if (string.IsNullOrEmpty(mimeType))
            return BadRequest(new ErrorResponse { Error = "סוג לא נתמך. נתמך: PDF, JPG, PNG, WebP" });

        byte[] bytes;
        using (var ms = new MemoryStream())
        {
            await file.CopyToAsync(ms);
            bytes = ms.ToArray();
        }

        string? directText = null;
        double garbageRatio = 1.0;

        if (ext == "pdf")
        {
            try
            {
                using var doc = PdfDocument.Open(new MemoryStream(bytes));
                directText = string.Join("\n", doc.GetPages().Select(p => p.Text));
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "PdfPig extract failed");
                directText = "";
            }
        }

        if (!string.IsNullOrEmpty(directText))
        {
            garbageRatio = GetGarbageRatio(directText);
        }

        var needsFallback = directText == null || string.IsNullOrEmpty(directText) ||
            garbageRatio > (GarbageThresholdPercent / 100.0);

        string? fallbackText = null;
        string? fallbackError = null;

        if (needsFallback && _geminiService.IsConfigured)
        {
            var prompt = "חלץ את כל הטקסט מהמסמך/התמונה. החזר רק את הטקסט הגולמי, ללא הסברים. שמור על השפה המקורית.";
            var (extracted, success, err) = await _geminiService.ExtractTextFromFileAsync(bytes, mimeType, prompt);
            fallbackText = success ? extracted : null;
            fallbackError = err;
        }

        return Ok(new OcrTestResponse
        {
            Filename = file.FileName,
            FileSizeBytes = (int)file.Length,
            DirectExtractText = directText ?? "",
            DirectGarbageRatioPercent = directText != null ? Math.Round(garbageRatio * 100, 2) : null,
            DirectPassesThreshold = directText != null && garbageRatio <= (GarbageThresholdPercent / 100.0),
            FallbackUsed = needsFallback,
            FallbackText = fallbackText,
            FallbackError = fallbackError,
            ThresholdPercent = GarbageThresholdPercent
        });
    }

    private static string Normalize(string s)
    {
        if (string.IsNullOrEmpty(s)) return "";
        return new string(s.Where(c => char.IsLetterOrDigit(c) || char.IsWhiteSpace(c)).ToArray())
            .ToLowerInvariant()
            .Trim();
    }

    /// <summary>
    /// יחס תווים "זבל" (0.0–1.0) — תואם ל-extracted_text_quality.dart
    /// תווים תקינים: עברית (\u0590-\u05FF), לטינית, ספרות, רווחים, פיסוק בסיסי
    /// </summary>
    private static double GetGarbageRatio(string text)
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

    private static bool IsValidChar(int codePoint)
    {
        if (codePoint <= 0x20 && (codePoint == 0x09 || codePoint == 0x0A || codePoint == 0x0D || codePoint == 0x20))
            return true;
        if (codePoint >= 0x30 && codePoint <= 0x39) return true; // 0-9
        if (codePoint >= 0x41 && codePoint <= 0x5A) return true; // A-Z
        if (codePoint >= 0x61 && codePoint <= 0x7A) return true; // a-z
        if (codePoint >= 0x0590 && codePoint <= 0x05FF) return true; // עברית + ניקוד
        var punct = new[] { 0x2C, 0x2E, 0x3A, 0x3B, 0x21, 0x3F, 0x2D, 0x5F, 0x27, 0x22, 0x28, 0x29 };
        return punct.Contains(codePoint);
    }
}

#region Request/Response DTOs

public class ScoreDebugRequest
{
    public string Query { get; set; } = "";
    public string? Filename { get; set; }
    public string? Content { get; set; }
    public string? Metadata { get; set; }
}

public class ScoreDebugResponse
{
    public string Query { get; set; } = "";
    public List<string> Terms { get; set; } = [];
    public double FilenameScore { get; set; }
    public double ContentScore { get; set; }
    public double MetadataScore { get; set; }
    public double TotalScore { get; set; }
    public string Breakdown { get; set; } = "";
}

public class GarbageFilterRequest
{
    public string? Text { get; set; }
}

public class GarbageFilterResponse
{
    public int TextLength { get; set; }
    public int GarbageCount { get; set; }
    public double GarbageRatioPercent { get; set; }
    public bool PassesThreshold { get; set; }
    public double ThresholdPercent { get; set; }
}

public class PlaygroundRequest
{
    public string? SystemPrompt { get; set; }
    public string? UserQuery { get; set; }
}

public class PlaygroundResponse
{
    public string? RawJson { get; set; }
    public bool Success { get; set; }
    public string? Error { get; set; }
}

public class ErrorResponse
{
    public string Error { get; set; } = "";
    public string? Details { get; set; }
}

public class OcrTestResponse
{
    public string Filename { get; set; } = "";
    public int FileSizeBytes { get; set; }
    public string DirectExtractText { get; set; } = "";
    public double? DirectGarbageRatioPercent { get; set; }
    public bool DirectPassesThreshold { get; set; }
    public bool FallbackUsed { get; set; }
    public string? FallbackText { get; set; }
    public string? FallbackError { get; set; }
    public double ThresholdPercent { get; set; }
}

#endregion
