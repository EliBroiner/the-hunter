using System.Text.Json.Serialization;

namespace TheHunterApi.Models;

/// <summary>
/// הצעת למידה מ-Gemini — מילים או Regex לזיהוי מקומי עתידי.
/// שמות השדות תואמים לפלט JSON מהפרומפט (snake_case).
/// </summary>
public class AiSuggestion
{
    [JsonPropertyName("suggested_category")]
    public string SuggestedCategory { get; set; } = string.Empty;

    [JsonPropertyName("suggested_keywords")]
    public List<string> SuggestedKeywords { get; set; } = new();

    [JsonPropertyName("suggested_regex")]
    public string? SuggestedRegex { get; set; }

    [JsonPropertyName("confidence")]
    public double Confidence { get; set; }
}
