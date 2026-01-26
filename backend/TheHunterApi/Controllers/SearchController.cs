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

    // פרומפט דינמי - מוזרק עם התאריך הנוכחי, תומך בעברית ומילים נרדפות
    private static string GetSystemPrompt()
    {
        var today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        return $$"""
            You are a query parser for a multilingual file search engine. Today is {{today}}.
            
            Your task: Parse the user's natural language query into a structured JSON object.
            Output ONLY valid JSON - no markdown, no code blocks, no explanations.
            
            Output format:
            {
                "terms": ["keyword1", "keyword2"],
                "fileTypes": ["pdf", "jpg"],
                "dateRange": {
                    "start": "2024-01-01",
                    "end": "2024-12-31"
                }
            }
            
            === CRITICAL RULES ===
            
            1. "terms" - KEYWORD EXTRACTION:
               a) Extract SPECIFIC keywords only (names, content, subjects).
               b) NOISE REDUCTION - STRICTLY REMOVE these filler words (do NOT include them):
                  - English: "find", "search", "show", "get", "look", "for", "me", "please", "my", "the", "a", "an", "file", "files"
                  - Hebrew: "תמצא", "חפש", "תחפש", "מצא", "דחוף", "בבקשה", "לי", "את", "של", "שלי", "קובץ", "קבצים"
               c) Include proper nouns, specific topics, or content descriptions only.
            
            2. "terms" - HEBREW-ENGLISH TRANSLATION (MANDATORY):
               If the query contains Hebrew words, you MUST include BOTH the Hebrew term AND its English translation.
               Examples:
               - "דרכון" -> add BOTH: ["דרכון", "passport"]
               - "חשבונית" -> add BOTH: ["חשבונית", "invoice", "receipt"]
               - "תעודת זהות" -> add BOTH: ["תעודת זהות", "ID", "identity"]
               - "חוזה" -> add BOTH: ["חוזה", "contract", "agreement"]
               - "קבלה" -> add BOTH: ["קבלה", "receipt"]
               - "ביטוח" -> add BOTH: ["ביטוח", "insurance"]
               - "רישיון" -> add BOTH: ["רישיון", "license"]
               - "אישור" -> add BOTH: ["אישור", "confirmation", "approval"]
               - "הזמנה" -> add BOTH: ["הזמנה", "order", "reservation"]
               - "טיסה" -> add BOTH: ["טיסה", "flight"]
               - "מלון" -> add BOTH: ["מלון", "hotel"]
            
            3. "terms" - SYNONYM EXPANSION:
               Add common synonyms and filename variations:
               - "invoice" -> also add: "receipt", "bill"
               - "contract" -> also add: "agreement"
               - "passport" -> also add: "travel"
               - "resume" -> also add: "CV", "curriculum"
               - "photo" -> also add: "pic", "img", "image"
            
            4. "fileTypes" - STANDARD MAPPING:
               - "photos/pictures/images/תמונות" -> ["jpg", "jpeg", "png", "heic", "webp"]
               - "documents/docs/מסמכים" -> ["pdf", "doc", "docx"]
               - "excel/spreadsheet/אקסל" -> ["xlsx", "xls", "csv"]
               - "video/videos/סרטון" -> ["mp4", "mov", "avi", "mkv"]
               - "receipts/invoices/קבלות/חשבוניות" -> ["pdf", "jpg", "png"]
               - "presentations/מצגות" -> ["pptx", "ppt"]
               - If no file type implied -> []
            
            5. "fileTypes" - CONTEXTUAL INFERENCE:
               Infer file types from abstract concepts:
               - "contract/חוזה", "agreement" -> ["pdf", "docx"]
               - "book/ספר" -> ["pdf", "epub", "mobi"]
               - "song/שיר", "music/מוזיקה" -> ["mp3", "m4a", "wav", "flac"]
               - "passport/דרכון", "ID/תעודת זהות" -> ["pdf", "jpg", "png"]
               - "resume/קורות חיים", "CV" -> ["pdf", "docx"]
               - "screenshot" -> ["png", "jpg"]
               - "scan" -> ["pdf", "jpg", "png"]
            
            6. "dateRange" - RELATIVE DATE CONVERSION:
               Convert ALL relative dates to EXACT ISO 8601 format (yyyy-MM-dd):
               - "yesterday/אתמול" -> start & end: {{today}} minus 1 day
               - "last week/שבוע שעבר" -> start: {{today}} minus 7 days, end: {{today}}
               - "last month/חודש שעבר" -> start: {{today}} minus 30 days, end: {{today}}
               - "this week/השבוע" -> start: Monday of current week, end: {{today}}
               - "last year/שנה שעברה" -> start: {{today}} minus 365 days, end: {{today}}
               - "today/היום" -> start & end: {{today}}
               - If no time reference -> dateRange: null
            
            7. OUTPUT: Pure JSON only. No explanations, no markdown, no text before or after.
            """;
    }

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
            var url = $"v1beta/models/gemini-3-flash-preview:generateContent?key={_geminiConfig.ApiKey}";

            var geminiRequest = new GeminiRequest
            {
                Contents = new List<GeminiContent>
                {
                    new GeminiContent
                    {
                        Parts = new List<GeminiPart>
                        {
                            new GeminiPart { Text = GetSystemPrompt() },
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

            var geminiResponse = JsonSerializer.Deserialize<GeminiResponse>(responseBody, jsonOptions);
            var generatedText = geminiResponse?.Candidates?.FirstOrDefault()?.Content?.Parts?.FirstOrDefault()?.Text;

            if (string.IsNullOrEmpty(generatedText))
            {
                _logger.LogWarning("Empty response from Gemini for query: {Query}", request.Query);
                return StatusCode(500, new ErrorResponse { Error = "Empty response from AI" });
            }

            var cleanJson = CleanJsonResponse(generatedText);
            _logger.LogInformation("Generated intent: {Intent}", cleanJson);

            try
            {
                var intent = JsonSerializer.Deserialize<SearchIntentResponse>(cleanJson, jsonOptions);
                return Ok(intent);
            }
            catch (JsonException)
            {
                return Content(cleanJson, "application/json");
            }
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Network error calling Gemini API");
            return StatusCode(500, new ErrorResponse { Error = "Network error", Details = ex.Message });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error processing search intent");
            return StatusCode(500, new ErrorResponse { Error = "Unexpected error", Details = ex.Message });
        }
    }

    private static string CleanJsonResponse(string text)
    {
        var cleaned = text.Trim();
        if (cleaned.StartsWith("```json")) cleaned = cleaned[7..];
        else if (cleaned.StartsWith("```")) cleaned = cleaned[3..];
        if (cleaned.EndsWith("```")) cleaned = cleaned[..^3];
        return cleaned.Trim();
    }
}

#region Models

public class SearchRequest
{
    public string Query { get; set; } = string.Empty;
}

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

public class ErrorResponse
{
    public string Error { get; set; } = string.Empty;
    public string? Details { get; set; }
}

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
