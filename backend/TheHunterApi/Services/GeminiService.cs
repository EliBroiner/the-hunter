using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שירות לתקשורת עם Gemini API לפענוח שאילתות חיפוש
/// </summary>
public class GeminiService
{
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly GeminiConfig _geminiConfig;
    private readonly ILogger<GeminiService> _logger;
    private readonly JsonSerializerOptions _jsonOptions;

    private const string GeminiModel = "gemini-3-flash-preview";

    // פרומפט ברירת מחדל - ניתן לדריסה דרך SYSTEM_PROMPT environment variable
    private const string DefaultPrompt = """
        You are a smart query parser for a multilingual file search engine.
        Today's date is: {CurrentDate}
        
        YOUR TASK: Parse the user's natural language query into a structured JSON object.
        OUTPUT: Return ONLY raw JSON - no markdown, no code blocks, no explanations.
        
        === JSON STRUCTURE ===
        {
            "terms": ["keyword1", "keyword2"],
            "fileTypes": ["pdf", "jpg"],
            "dateRange": {
                "start": "2024-01-01",
                "end": "2024-12-31"
            }
        }
        
        === RULES ===
        
        1. TERMS - KEYWORD EXTRACTION:
           - Extract SPECIFIC keywords only (names, subjects, content).
           - NOISE REMOVAL: Strictly remove conversational filler words:
             * English: "find", "search", "show", "get", "look", "for", "me", "please", "my", "the", "a", "an", "file", "files", "where", "is"
             * Hebrew: "תמצא", "חפש", "תחפש", "מצא", "דחוף", "בבקשה", "לי", "את", "של", "שלי", "קובץ", "קבצים", "איפה", "תראה"
        
        2. TERMS - LANGUAGE BRIDGE (CRITICAL):
           If query contains Hebrew, you MUST include BOTH Hebrew AND English translations:
           - "דרכון" → ["דרכון", "passport"]
           - "חשבונית" → ["חשבונית", "invoice", "receipt"]
           - "תעודת זהות" → ["תעודת זהות", "ID", "identity", "teudat"]
           - "חוזה" → ["חוזה", "contract", "agreement"]
           - "קבלה" → ["קבלה", "receipt", "kabala"]
           - "ביטוח" → ["ביטוח", "insurance"]
           - "רישיון" → ["רישיון", "license", "rishyon"]
           - "אישור" → ["אישור", "confirmation", "approval", "ishur"]
           - "הזמנה" → ["הזמנה", "order", "reservation", "hazmana"]
           - "טיסה" → ["טיסה", "flight", "tisa"]
           - "מלון" → ["מלון", "hotel", "malon"]
           - "קורות חיים" → ["קורות חיים", "CV", "resume", "curriculum"]
        
        3. TERMS - SYNONYMS & EXPANSION:
           Expand terms with common synonyms and filename variations:
           - "invoice" → also add: "receipt", "bill", "inv"
           - "contract" → also add: "agreement", "הסכם"
           - "passport" → also add: "travel", "visa"
           - "resume" → also add: "CV", "curriculum", "vitae"
           - "photo" → also add: "pic", "img", "image", "תמונה"
        
        4. FILE TYPES - STANDARD MAPPING:
           - "photos/pictures/images/תמונות" → ["jpg", "jpeg", "png", "heic", "webp"]
           - "documents/docs/מסמכים" → ["pdf", "doc", "docx"]
           - "excel/spreadsheet/אקסל/גיליון" → ["xlsx", "xls", "csv"]
           - "video/videos/סרטון/וידאו" → ["mp4", "mov", "avi", "mkv"]
           - "receipts/invoices/קבלות/חשבוניות" → ["pdf", "jpg", "png"]
           - "presentations/מצגות" → ["pptx", "ppt"]
           - If no file type implied → []
        
        5. FILE TYPES - CONTEXTUAL INFERENCE:
           Infer file extensions from abstract concepts:
           - "contract/חוזה/agreement/הסכם" → ["pdf", "docx"]
           - "book/ספר" → ["pdf", "epub", "mobi"]
           - "song/שיר/music/מוזיקה" → ["mp3", "m4a", "wav", "flac"]
           - "passport/דרכון/ID/תעודת זהות" → ["pdf", "jpg", "png"]
           - "resume/CV/קורות חיים" → ["pdf", "docx"]
           - "screenshot/צילום מסך" → ["png", "jpg"]
           - "scan/סריקה" → ["pdf", "jpg", "png"]
        
        6. DATE RANGE - RELATIVE DATE CONVERSION:
           Calculate dates based on Today: {CurrentDate}
           Convert to EXACT ISO 8601 format (yyyy-MM-dd). NO time component.
           
           - "today/היום" → start: "{CurrentDate}", end: "{CurrentDate}"
           - "yesterday/אתמול" → calculate {CurrentDate} minus 1 day for both start and end
           - "last week/שבוע שעבר" → start: {CurrentDate} minus 7 days, end: "{CurrentDate}"
           - "this week/השבוע" → start: Monday of current week, end: "{CurrentDate}"
           - "last month/חודש שעבר" → start: {CurrentDate} minus 30 days, end: "{CurrentDate}"
           - "this month/החודש" → start: first day of current month, end: "{CurrentDate}"
           - "last year/שנה שעברה" → start: {CurrentDate} minus 365 days, end: "{CurrentDate}"
           - If no time reference → dateRange: null
        
        7. OUTPUT: Return ONLY the raw JSON object. No explanations, no markdown code fences, no text before or after.
        """;

    public GeminiService(
        IHttpClientFactory httpClientFactory,
        GeminiConfig geminiConfig,
        ILogger<GeminiService> logger)
    {
        _httpClientFactory = httpClientFactory;
        _geminiConfig = geminiConfig;
        _logger = logger;
        _jsonOptions = new JsonSerializerOptions
        {
            PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };
    }

    /// <summary>
    /// בודק אם השירות מוגדר כראוי
    /// </summary>
    public bool IsConfigured => !string.IsNullOrEmpty(_geminiConfig.ApiKey);

    /// <summary>
    /// מפענח שאילתת חיפוש בשפה טבעית ל-SearchIntent מובנה
    /// </summary>
    public async Task<GeminiResult<SearchIntent>> ParseSearchIntentAsync(string query)
    {
        if (string.IsNullOrWhiteSpace(query))
        {
            return GeminiResult<SearchIntent>.Failure("Query cannot be empty");
        }

        if (!IsConfigured)
        {
            return GeminiResult<SearchIntent>.Failure("GEMINI_API_KEY is not configured");
        }

        _logger.LogInformation("Parsing search intent for query: {Query}", query);

        try
        {
            var client = _httpClientFactory.CreateClient("GeminiApi");
            var url = $"v1beta/models/{GeminiModel}:generateContent?key={_geminiConfig.ApiKey}";

            var geminiRequest = BuildGeminiRequest(query);
            var jsonContent = JsonSerializer.Serialize(geminiRequest, _jsonOptions);
            var httpContent = new StringContent(jsonContent, Encoding.UTF8, "application/json");

            var response = await client.PostAsync(url, httpContent);
            var responseBody = await response.Content.ReadAsStringAsync();

            // לוג מפורט של התשובה מ-Gemini API - בשורה אחת
            Console.WriteLine($"📡 GEMINI_RAW_RESPONSE | Status: {response.StatusCode} | Body: {responseBody.Replace("\n", " ").Replace("\r", "")}");

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Gemini API error: {StatusCode} - {Body}", response.StatusCode, responseBody);
                return GeminiResult<SearchIntent>.Failure($"Gemini API error: {response.StatusCode}");
            }

            return ParseGeminiResponse(responseBody);
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "Network error calling Gemini API");
            return GeminiResult<SearchIntent>.Failure($"Network error: {ex.Message}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error parsing search intent");
            return GeminiResult<SearchIntent>.Failure($"Unexpected error: {ex.Message}");
        }
    }

    /// <summary>
    /// בונה את הבקשה ל-Gemini API עם הפרומפט הדינמי
    /// </summary>
    private GeminiRequest BuildGeminiRequest(string userQuery)
    {
        var systemPrompt = BuildSystemPrompt();
        
        return new GeminiRequest
        {
            Contents = new List<GeminiContent>
            {
                new GeminiContent
                {
                    Parts = new List<GeminiPart>
                    {
                        new GeminiPart { Text = systemPrompt },
                        new GeminiPart { Text = $"User query: {userQuery}" }
                    }
                }
            },
            GenerationConfig = new GenerationConfig
            {
                Temperature = 0.1,  // נמוך לתוצאות עקביות ומדויקות
                MaxOutputTokens = 3000,  // מוגדל כדי למנוע חיתוך של התשובה
                ResponseMimeType = "application/json"  // רמז למודל להחזיר JSON תקין
            }
        };
    }

    /// <summary>
    /// בונה את הפרומפט המערכתי עם התאריך הנוכחי
    /// תומך בדריסה דרך SYSTEM_PROMPT environment variable
    /// </summary>
    private static string BuildSystemPrompt()
    {
        var today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        
        // בדיקה אם יש פרומפט מותאם אישית ב-environment variable
        var customPrompt = Environment.GetEnvironmentVariable("SYSTEM_PROMPT");
        
        string promptTemplate;
        if (!string.IsNullOrEmpty(customPrompt))
        {
            Console.WriteLine("📝 Using Custom Prompt from SYSTEM_PROMPT environment variable");
            promptTemplate = customPrompt;
        }
        else
        {
            Console.WriteLine("📝 Using Default Prompt");
            promptTemplate = DefaultPrompt;
        }
        
        // החלפת placeholder של תאריך - תמיד מתבצעת
        return promptTemplate.Replace("{CurrentDate}", today);
    }

    /// <summary>
    /// מפרסר את התשובה מ-Gemini ומחלץ את ה-SearchIntent
    /// </summary>
    private GeminiResult<SearchIntent> ParseGeminiResponse(string responseBody)
    {
        string rawText = "";
        string cleanJson = "";
        
        try
        {
            // שלב 1: פירסור התשובה מ-Gemini API
            var geminiResponse = JsonSerializer.Deserialize<GeminiResponse>(responseBody, _jsonOptions);
            rawText = geminiResponse?.Candidates?.FirstOrDefault()?.Content?.Parts?.FirstOrDefault()?.Text ?? "";

            // לוג ראשוני - לפני כל עיבוד
            Console.WriteLine($"[Gemini Raw]: {rawText}");

            if (string.IsNullOrEmpty(rawText))
            {
                Console.WriteLine("❌ ERROR: Empty response from Gemini");
                return GeminiResult<SearchIntent>.Failure("Empty response from AI");
            }

            // לוג מפורט של התשובה הגולמית
            Console.WriteLine($"🔍 EXTRACTED_TEXT | Length: {rawText.Length} | Content: {rawText.Replace("\n", " ").Replace("\r", "")}");

            // שלב 2: ניקוי וסניטציה של ה-JSON
            cleanJson = SanitizeJsonResponse(rawText);
            
            // לוג של ה-JSON המנוקה
            Console.WriteLine($"✅ SANITIZED_JSON | Length: {cleanJson.Length} | Content: {cleanJson.Replace("\n", " ").Replace("\r", "")}");

            // שלב 3: פירסור ה-JSON ל-SearchIntent
            var intent = JsonSerializer.Deserialize<SearchIntent>(cleanJson, _jsonOptions);
            
            if (intent == null)
            {
                Console.WriteLine("❌ ERROR: Deserialized intent is null");
                return GeminiResult<SearchIntent>.Failure("Failed to parse AI response - null result");
            }

            Console.WriteLine($"✅ SUCCESS | Terms: [{string.Join(", ", intent.Terms)}] | FileTypes: [{string.Join(", ", intent.FileTypes)}] | DateRange: {(intent.DateRange != null ? $"{intent.DateRange.Start} to {intent.DateRange.End}" : "null")}");
            return GeminiResult<SearchIntent>.Success(intent);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "Failed to parse Gemini response as JSON");
            Console.WriteLine($"❌ JSON_PARSE_ERROR | Message: {ex.Message} | Path: {ex.Path} | Line: {ex.LineNumber} | BytePos: {ex.BytePositionInLine}");
            Console.WriteLine($"❌ FAILED_JSON_CONTENT: {cleanJson}");
            return GeminiResult<SearchIntent>.Failure($"JSON parse error: {ex.Message}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error parsing Gemini response");
            Console.WriteLine($"❌ UNEXPECTED_ERROR | Type: {ex.GetType().Name} | Message: {ex.Message}");
            return GeminiResult<SearchIntent>.Failure($"Unexpected error: {ex.Message}");
        }
    }

    /// <summary>
    /// מנקה ומסנן את התשובה מ-Gemini - מסיר markdown ומחלץ רק את ה-JSON
    /// </summary>
    private static string SanitizeJsonResponse(string responseText)
    {
        // לוג התחלתי
        Console.WriteLine($"🧹 SANITIZE_START | Input Length: {responseText?.Length ?? 0}");
        
        if (string.IsNullOrWhiteSpace(responseText))
        {
            Console.WriteLine("⚠️ SANITIZE: Empty input, returning empty object");
            return "{}";
        }

        // שלב 1: הסרת Markdown code blocks
        responseText = responseText
            .Replace("```json", "")
            .Replace("```JSON", "")
            .Replace("```", "")
            .Trim();

        Console.WriteLine($"🧹 AFTER_MARKDOWN_REMOVAL | Length: {responseText.Length}");

        // שלב 2: מציאת ה-JSON בלבד (בין הסוגריים המסולסלים הראשונים והאחרונים)
        int firstBrace = responseText.IndexOf('{');
        int lastBrace = responseText.LastIndexOf('}');

        Console.WriteLine($"🧹 BRACE_POSITIONS | FirstBrace: {firstBrace} | LastBrace: {lastBrace}");

        if (firstBrace >= 0 && lastBrace > firstBrace)
        {
            // מצאנו JSON תקין
            responseText = responseText.Substring(firstBrace, lastBrace - firstBrace + 1);
            Console.WriteLine($"🧹 JSON_EXTRACTED | Length: {responseText.Length}");
        }
        else
        {
            // Fallback: אם לא מצאנו סוגריים, ננסה לפרסר את הטקסט המקורי
            Console.WriteLine($"⚠️ WARNING: Could not find valid JSON braces. Attempting to parse raw text. Length: {responseText.Length}");
        }

        // שלב 3: ניקוי תווים בעייתיים שעלולים לשבור JSON
        responseText = responseText
            .Replace("\r\n", "\n")  // נרמול line endings
            .Replace("\r", "")      // הסרת CR בודדים
            .Replace("\t", " ");    // החלפת tabs ברווחים

        var result = responseText.Trim();
        Console.WriteLine($"🧹 SANITIZE_COMPLETE | Final Length: {result.Length}");
        
        return result;
    }
}

#region Result Type

/// <summary>
/// תוצאה מ-Gemini עם תמיכה בהצלחה/כישלון
/// </summary>
public class GeminiResult<T>
{
    public bool IsSuccess { get; private init; }
    public T? Data { get; private init; }
    public string? Error { get; private init; }

    public static GeminiResult<T> Success(T data) => new() { IsSuccess = true, Data = data };
    public static GeminiResult<T> Failure(string error) => new() { IsSuccess = false, Error = error };
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
    public string? ResponseMimeType { get; set; }
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
