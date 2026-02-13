using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using Serilog;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// עזר קריאות HTTP ל-Gemini API — retry על 429, חילוץ טקסט, ניקוי JSON.
/// </summary>
internal static class GeminiHttpHelper
{
    private const int MaxRetriesOn429 = 2;
    private const int DefaultRetryAfterSeconds = 45;

    /// <summary>שולח POST עם retry אוטומטי על 429. מחזיר (response, body) — null אם נכשל סופית.</summary>
    public static async Task<(HttpResponseMessage? Response, string ResponseBody)> PostWith429RetryAsync(
        HttpClient client,
        string url,
        string jsonContent,
        Microsoft.Extensions.Logging.ILogger logger,
        string contextForLog = "")
    {
        HttpResponseMessage? response = null;
        string responseBody = "";
        for (var attempt = 0; attempt <= MaxRetriesOn429; attempt++)
        {
            var httpContent = new StringContent(jsonContent, Encoding.UTF8, "application/json");
            response = await client.PostAsync(url, httpContent);
            responseBody = await response.Content.ReadAsStringAsync();

            logger.LogDebug("GEMINI_RESPONSE {Context} | Status={Status} | Body length={Len}",
                contextForLog, (int)response.StatusCode, responseBody.Length);

            if ((int)response.StatusCode == 429 && attempt < MaxRetriesOn429)
            {
                var waitSec = TryParseRetryAfterSeconds(responseBody);
                logger.LogWarning("[GEMINI_429] {Context} — retry {Attempt}/{Max} after {Sec}s.",
                    contextForLog, attempt + 1, MaxRetriesOn429, waitSec);
                await Task.Delay(TimeSpan.FromSeconds(waitSec));
                continue;
            }
            break;
        }
        return (response, responseBody);
    }

    /// <summary>מחלץ טקסט גולמי מתשובת Gemini (מ-Candidates[0].Content.Parts).</summary>
    public static string ExtractRawTextFromResponse(string responseBody, JsonSerializerOptions jsonOptions)
    {
        var gemini = JsonSerializer.Deserialize<GeminiResponse>(responseBody, jsonOptions);
        var parts = gemini?.Candidates?.FirstOrDefault()?.Content?.Parts ?? [];
        return parts.FirstOrDefault(p => !string.IsNullOrEmpty(p?.Text))?.Text ?? "";
    }

    /// <summary>מחלץ מ-Gemini 429 body את "Please retry in Xs" — מחזיר שניות להמתנה.</summary>
    public static int TryParseRetryAfterSeconds(string responseBody)
    {
        var match = Regex.Match(responseBody, @"retry\s+in\s+([\d.]+)\s*s", RegexOptions.IgnoreCase);
        if (match.Success && double.TryParse(match.Groups[1].Value, System.Globalization.NumberStyles.Any,
                System.Globalization.CultureInfo.InvariantCulture, out var sec))
            return (int)Math.Ceiling(Math.Clamp(sec, 5, 120));
        return DefaultRetryAfterSeconds;
    }

    /// <summary>מנקה תשובת Gemini — מסיר markdown, מחלץ JSON בין סוגריים.</summary>
    public static string SanitizeJsonResponse(string responseText)
    {
        Log.Debug("🧹 SANITIZE_START | Input Length: {Length}", responseText?.Length ?? 0);
        if (string.IsNullOrWhiteSpace(responseText))
        {
            Log.Warning("⚠️ SANITIZE: Empty input, returning empty object");
            return "{}";
        }
        responseText = responseText.Replace("```json", "").Replace("```JSON", "").Replace("```", "").Trim();
        Log.Debug("🧹 AFTER_MARKDOWN_REMOVAL | Length: {Length}", responseText.Length);
        var firstBrace = responseText.IndexOf('{');
        var lastBrace = responseText.LastIndexOf('}');
        Log.Debug("🧹 BRACE_POSITIONS | FirstBrace: {First} | LastBrace: {Last}", firstBrace, lastBrace);
        if (firstBrace >= 0 && lastBrace > firstBrace)
        {
            responseText = responseText.Substring(firstBrace, lastBrace - firstBrace + 1);
            Log.Debug("🧹 JSON_EXTRACTED | Length: {Length}", responseText.Length);
        }
        else
            Log.Warning("⚠️ Could not find valid JSON braces. Attempting to parse raw text. Length: {Length}", responseText.Length);
        responseText = responseText.Replace("\r\n", "\n").Replace("\r", "").Replace("\t", " ");
        var result = responseText.Trim();
        Log.Debug("🧹 SANITIZE_COMPLETE | Final Length: {Length}", result.Length);
        return result;
    }
}
