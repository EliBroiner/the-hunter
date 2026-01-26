using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Mvc;

namespace TheHunterApi.Controllers;

[ApiController]
[Route("api/[controller]")]
public class SearchController : ControllerBase
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly GeminiConfig _geminiConfig;
    private readonly ILogger<SearchController> _logger;

    private const string SystemPrompt = """
        You are The Hunter, a file search assistant. 
        The user asks in natural language what file they are looking for.
        You must analyze their intent and output ONLY a valid JSON object with no markdown formatting, no code blocks, no extra text.
        
        Output format:
        {
            "terms": ["keyword1", "keyword2"],
            "fileTypes": ["pdf", "jpg"],
            "dateRange": {
                "start": "2024-01-01",
                "end": "2024-12-31"
            }
        }
        
        Rules:
        - "terms": Extract search keywords from the query. Include synonyms if relevant.
        - "fileTypes": If user mentions documents, use ["pdf", "doc", "docx"]. For images: ["jpg", "jpeg", "png"]. For receipts: ["pdf", "jpg", "png"]. Leave empty [] if not specified.
        - "dateRange": If user says "last week", calculate actual dates. If "yesterday", use that date. If no time mentioned, set to null.
        - Output ONLY the JSON. No explanations, no markdown, no code fences.
        """;

    public SearchController(
        IHttpClientFactory httpClientFactory,
        GeminiConfig geminiConfig,
        ILogger<SearchController> logger)
    {
        _httpClientFactory = httpClientFactory;
        _geminiConfig = geminiConfig;
        _logger = logger;
    }

    /// <summary>
    /// מנתח שאילתת חיפוש בשפה טבעית ומחזיר intent מובנה
    /// </summary>
    /// <param name="request">שאילתת החיפוש</param>
    /// <returns>JSON עם terms, fileTypes, dateRange</returns>
    [HttpPost("intent")]
    [ProducesResponseType(typeof(SearchIntentResponse), StatusCodes.Status200OK)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status400BadRequest)]
    [ProducesResponseType(typeof(ErrorResponse), StatusCodes.Status500InternalServerError)]
    public async Task<IActionResult> ParseSearchIntent([FromBody] SearchRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Query))
        {
            return BadRequest(new ErrorResponse { Error = "Query cannot be empty" });
        }

        if (string.IsNullOrEmpty(_geminiConfig.ApiKey))
        {
            return StatusCode(503, new ErrorResponse 
            { 
                Error = "AI service not configured",
                Details = "GEMINI_API_KEY environment variable is not set"
            });
        }

        _logger.LogInformation("Processing search intent for query: {Query}", request.Query);

        try
        {
            var client = _httpClientFactory.CreateClient("GeminiApi");
            var url = $"v1beta/models/gemini-1.5-flash:generateContent?key={_geminiConfig.ApiKey}";

            var geminiRequest = new GeminiRequest
            {
                Contents = new List<GeminiContent>
                {
                    new GeminiContent
                    {
                        Parts = new List<GeminiPart>
                        {
                            new GeminiPart { Text = SystemPrompt },
                            new GeminiPart { Text = $"User query: {request.Query}" }
                        }
                    }
                },
                GenerationConfig = new GenerationConfig
                {
                    Temperature = 0.1,
                    MaxOutputTokens = 500
                }
            };

            var jsonOptions = new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
            };

            var jsonContent = JsonSerializer.Serialize(geminiRequest, jsonOptions);
            var httpContent = new StringContent(jsonContent, Encoding.UTF8, "application/json");

            var response = await client.PostAsync(url, httpContent);
            var responseBody = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Gemini API error: {StatusCode} - {Body}", response.StatusCode, responseBody);
                return StatusCode(500, new ErrorResponse 
                { 
                    Error = "AI service error",
                    Details = response.StatusCode.ToString()
                });
            }

            // פענוח התשובה מ-Gemini
            var geminiResponse = JsonSerializer.Deserialize<GeminiResponse>(responseBody, jsonOptions);
            var generatedText = geminiResponse?.Candidates?.FirstOrDefault()?.Content?.Parts?.FirstOrDefault()?.Text;

            if (string.IsNullOrEmpty(generatedText))
            {
                _logger.LogWarning("Empty response from Gemini for query: {Query}", request.Query);
                return StatusCode(500, new ErrorResponse { Error = "Empty response from AI" });
            }

            // ניקוי התשובה - הסרת markdown code blocks אם קיימים
            var cleanJson = CleanJsonResponse(generatedText);

            _logger.LogInformation("Generated intent: {Intent}", cleanJson);

            // ניסיון לפרסר את ה-JSON כדי לוודא שהוא תקין
            try
            {
                var intent = JsonSerializer.Deserialize<SearchIntentResponse>(cleanJson, jsonOptions);
                return Ok(intent);
            }
            catch (JsonException)
            {
                // אם הפרסור נכשל, מחזירים את ה-JSON הגולמי
                return Content(cleanJson, "application/json");
            }
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Network error calling Gemini API");
            return StatusCode(500, new ErrorResponse 
            { 
                Error = "Network error",
                Details = ex.Message 
            });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error processing search intent");
            return StatusCode(500, new ErrorResponse 
            { 
                Error = "Unexpected error",
                Details = ex.Message 
            });
        }
    }

    /// <summary>
    /// מנקה את תשובת ה-JSON מ-markdown formatting
    /// </summary>
    private static string CleanJsonResponse(string text)
    {
        var cleaned = text.Trim();
        
        // הסרת ```json ו-``` אם קיימים
        if (cleaned.StartsWith("```json"))
        {
            cleaned = cleaned[7..];
        }
        else if (cleaned.StartsWith("```"))
        {
            cleaned = cleaned[3..];
        }

        if (cleaned.EndsWith("```"))
        {
            cleaned = cleaned[..^3];
        }

        return cleaned.Trim();
    }
}

#region Request/Response Models

/// <summary>
/// בקשת חיפוש מהלקוח
/// </summary>
public class SearchRequest
{
    public string Query { get; set; } = string.Empty;
}

/// <summary>
/// תשובת intent מפורסרת
/// </summary>
public class SearchIntentResponse
{
    public List<string> Terms { get; set; } = new();
    public List<string> FileTypes { get; set; } = new();
    public DateRangeDto? DateRange { get; set; }
}

public class DateRangeDto
{
    public string? Start { get; set; }
    public string? End { get; set; }
}

/// <summary>
/// תשובת שגיאה
/// </summary>
public class ErrorResponse
{
    public string Error { get; set; } = string.Empty;
    public string? Details { get; set; }
}

#endregion

#region Gemini API Models

public class GeminiRequest
{
    public List<GeminiContent> Contents { get; set; } = new();
    public GenerationConfig? GenerationConfig { get; set; }
}

public class GeminiContent
{
    public List<GeminiPart> Parts { get; set; } = new();
}

public class GeminiPart
{
    public string Text { get; set; } = string.Empty;
}

public class GenerationConfig
{
    public double Temperature { get; set; }
    public int MaxOutputTokens { get; set; }
}

public class GeminiResponse
{
    public List<GeminiCandidate>? Candidates { get; set; }
}

public class GeminiCandidate
{
    public GeminiContent? Content { get; set; }
}

#endregion
