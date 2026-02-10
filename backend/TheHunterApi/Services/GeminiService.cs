using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Hosting;
using Serilog;
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
    private const string GeminiDocModel = "gemini-2.5-flash";
    private const int MaxLogPayloadChars = 200; // היגיינת לוגים — לא לדפיס Body/JSON מלא (Cloud Run ~256KB limit)

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

    /// <summary>פרומפט ניתוח מסמכים — fallback אם הקובץ לא נטען.</summary>
    private const string DocAnalysisPromptFallback = """
        Analyze the following document text. Output JSON with: category, date (YYYY-MM-DD or null if unknown), tags (list of keywords), summary (brief).
        Return ONLY raw JSON - no markdown, no code blocks. Format: {"category":"...","date":"yyyy-MM-dd or null","tags":["..."],"summary":"..."}
        """;

    private readonly ILearningService _learningService;
    private readonly ISearchActivityService _searchActivityService;
    private readonly IWebHostEnvironment _webHost;

    public GeminiService(
        IHttpClientFactory httpClientFactory,
        GeminiConfig geminiConfig,
        ILogger<GeminiService> logger,
        ILearningService learningService,
        ISearchActivityService searchActivityService,
        IWebHostEnvironment webHost)
    {
        _httpClientFactory = httpClientFactory;
        _geminiConfig = geminiConfig;
        _logger = logger;
        _learningService = learningService;
        _searchActivityService = searchActivityService;
        _webHost = webHost;
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

            _logger.LogDebug("📡 GEMINI_RAW_RESPONSE | Status: {StatusCode} | Body: {Body}",
                response.StatusCode, TruncateForLog(responseBody));

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Gemini API error: {StatusCode} - {Body}", response.StatusCode, TruncateForLog(responseBody));
                return GeminiResult<SearchIntent>.Failure($"Gemini API error: {response.StatusCode}");
            }

            var result = ParseGeminiResponse(responseBody);
            if (result.IsSuccess && result.Data != null)
            {
                await LearnFromSearchTermsAsync(result.Data.Terms);
                await _searchActivityService.RecordSearchTermsAsync(result.Data.Terms);
            }
            return result;
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
    /// מנתח אצווה של מסמכים ב-Gemini 1.5 Flash במקביל - חסכוני ומהיר
    /// </summary>
    /// <param name="userId">מזהה משתמש ללולאת למידה (מכסת הצעות יומית)</param>
    /// <param name="customPromptOverride">דריסת פרומפט — רק Admin (מגיע כבר מאומת Controller)</param>
    public async Task<List<DocumentAnalysisResponse>> AnalyzeDocumentsBatchAsync(
        List<DocumentPayload> documents,
        string? userId = null,
        string? customPromptOverride = null)
    {
        if (documents.Count == 0) return new List<DocumentAnalysisResponse>();
        if (!IsConfigured)
        {
            _logger.LogWarning("Gemini not configured - returning empty results");
            return documents.Select(d => new DocumentAnalysisResponse { DocumentId = d.Id, Result = new DocumentAnalysisResult() }).ToList();
        }

        var tasks = documents.Select(d => AnalyzeOneDocumentAsync(d, userId, customPromptOverride));
        var results = await Task.WhenAll(tasks);
        return results.ToList();
    }

    private async Task<DocumentAnalysisResponse> AnalyzeOneDocumentAsync(
        DocumentPayload doc,
        string? userId = null,
        string? customPromptOverride = null)
    {
        var text = (doc.Text ?? "").Trim();
        var filename = doc.Filename ?? doc.Id ?? "";

        // CASE A: יש טקסט (OCR) — שולחים רק Text ל-Gemini. לא FileUri / FileData (מונע 404).
        if (!string.IsNullOrEmpty(text))
        {
            _logger.LogInformation("[LOGIC] Item {DocumentId} has text ({TextLength} chars). Using Text Generation only (no FileUri).",
                doc.Id, text.Length);
            return await SendTextOnlyToGeminiAsync(doc.Id, filename, text, userId, customPromptOverride);
        }

        // CASE B: אין טקסט — לא קוראים ל-Gemini (אין fallback ל-FileUri — הלקוח שולח רק טקסט).
        _logger.LogWarning("[LOGIC] Item {DocumentId} has NO text. Skipping Gemini (returning empty result).", doc.Id);
        return new DocumentAnalysisResponse { DocumentId = doc.Id, Result = new DocumentAnalysisResult() };
    }

    /// <summary>
    /// שולח ל-Gemini רק Part מסוג Text. לא מוסיף FileData/FileUri — מונע 404.
    /// </summary>
    private async Task<DocumentAnalysisResponse> SendTextOnlyToGeminiAsync(
        string documentId,
        string filename,
        string text,
        string? userId,
        string? customPromptOverride)
    {
        try
        {
            string systemInstructions = GetDocAnalysisPrompt();
            if (!string.IsNullOrEmpty(customPromptOverride))
            {
                _logger.LogWarning("Using Custom Developer Prompt (Admin override) for doc {DocId}", documentId);
                systemInstructions = customPromptOverride;
            }

            // פרומפט אחד — הוראות + תוכן. רק Part.Text, בלי FileData/FileUri.
            var prompt = $"Analyze this document text.\nFilename: {filename}\nContent:\n{text}\n\n{systemInstructions}";
            var previewLen = Math.Min(100, prompt.Length);
            _logger.LogInformation("🤖 [SERVER_TO_AI] Sending prompt to Gemini. Length: {Length}. Preview: {Preview}...",
                prompt.Length, prompt.Substring(0, previewLen));

            var client = _httpClientFactory.CreateClient("GeminiApi");
            var url = $"v1beta/models/{GeminiDocModel}:generateContent?key={_geminiConfig.ApiKey}";

            // רק Parts עם Text — אין שום FileData/FileUri
            var request = new GeminiRequest
            {
                Contents = new List<GeminiContent>
                {
                    new()
                    {
                        Parts = new List<GeminiPart> { new GeminiPart { Text = prompt } }
                    }
                },
                GenerationConfig = new GenerationConfig
                {
                    Temperature = 0.1,
                    MaxOutputTokens = 512,
                    ResponseMimeType = "application/json"
                }
            };

            var jsonContent = JsonSerializer.Serialize(request, _jsonOptions);
            var httpContent = new StringContent(jsonContent, Encoding.UTF8, "application/json");
            var response = await client.PostAsync(url, httpContent);
            var responseBody = await response.Content.ReadAsStringAsync();

            _logger.LogInformation("⬅️ [AI_TO_SERVER] Raw JSON from Gemini: {Raw}", TruncateForLog(responseBody));

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Gemini doc analysis failed: {StatusCode} for doc {Id}. Batch continues.", response.StatusCode, documentId);
                return new DocumentAnalysisResponse { DocumentId = documentId, Result = new DocumentAnalysisResult() };
            }

            var rawText = JsonSerializer.Deserialize<GeminiResponse>(responseBody, _jsonOptions)
                ?.Candidates?.FirstOrDefault()?.Content?.Parts?.FirstOrDefault()?.Text ?? "";
            var cleanJson = SanitizeJsonResponse(rawText);
            var result = JsonSerializer.Deserialize<DocumentAnalysisResult>(cleanJson, _jsonOptions) ?? new DocumentAnalysisResult();
            await LearnFromDocumentResultAsync(result, userId);

            var finalJson = JsonSerializer.Serialize(new DocumentAnalysisResponse { DocumentId = documentId, Result = result }, _jsonOptions);
            _logger.LogInformation("✅ [SERVER_OUT] Sending result to Client: {Final}", TruncateForLog(finalJson));

            return new DocumentAnalysisResponse { DocumentId = documentId, Result = result };
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error analyzing document {Id}. Batch continues.", documentId);
            return new DocumentAnalysisResponse { DocumentId = documentId, Result = new DocumentAnalysisResult() };
        }
    }

    /// <summary>
    /// ניתוח מסמך בודד עם פרומפט מותאם — לשימוש AI Lab (דיבאג). לא קורא ל-Learning.
    /// </summary>
    public async Task<DocumentAnalysisResult> AnalyzeDocumentWithCustomPromptAsync(string text, string? customPrompt)
    {
        if (!IsConfigured)
            return new DocumentAnalysisResult();

        var systemPrompt = string.IsNullOrWhiteSpace(customPrompt) ? GetDocAnalysisPrompt() : customPrompt.Trim();
        try
        {
            var client = _httpClientFactory.CreateClient("GeminiApi");
            var url = $"v1beta/models/{GeminiDocModel}:generateContent?key={_geminiConfig.ApiKey}";
            var request = new GeminiRequest
            {
                Contents = new List<GeminiContent>
                {
                    new()
                    {
                        Parts = new List<GeminiPart>
                        {
                            new GeminiPart { Text = systemPrompt },
                            new GeminiPart { Text = text }
                        }
                    }
                },
                GenerationConfig = new GenerationConfig
                {
                    Temperature = 0.1,
                    MaxOutputTokens = 512,
                    ResponseMimeType = "application/json"
                }
            };
            var jsonContent = JsonSerializer.Serialize(request, _jsonOptions);
            var httpContent = new StringContent(jsonContent, Encoding.UTF8, "application/json");
            var response = await client.PostAsync(url, httpContent);
            var responseBody = await response.Content.ReadAsStringAsync();

            if (!response.IsSuccessStatusCode)
            {
                _logger.LogError("Gemini analyze-debug failed: {StatusCode}", response.StatusCode);
                return new DocumentAnalysisResult();
            }
            var rawText = JsonSerializer.Deserialize<GeminiResponse>(responseBody, _jsonOptions)
                ?.Candidates?.FirstOrDefault()?.Content?.Parts?.FirstOrDefault()?.Text ?? "";
            var cleanJson = SanitizeJsonResponse(rawText);
            return JsonSerializer.Deserialize<DocumentAnalysisResult>(cleanJson, _jsonOptions) ?? new DocumentAnalysisResult();
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AnalyzeDocumentWithCustomPrompt failed");
            return new DocumentAnalysisResult();
        }
    }

    /// <summary>
    /// טוען פרומפט ניתוח מסמכים מקובץ. קובץ נבחר לפי DOC_ANALYSIS_PROMPT_FILE (למשל doc_analysis_learning.txt).
    /// ברירת מחדל: doc_analysis_default.txt. אם הקובץ חסר — משתמשים ב-fallback מוטבע (לא מוחקים את הקודם).
    /// </summary>
    private string GetDocAnalysisPrompt()
    {
        var fileName = Environment.GetEnvironmentVariable("DOC_ANALYSIS_PROMPT_FILE")?.Trim()
            ?? "doc_analysis_default.txt";
        var dirs = new[]
        {
            Path.Combine(_webHost.ContentRootPath, "Prompts"),
            Path.Combine(AppContext.BaseDirectory, "Prompts")
        };
        foreach (var dir in dirs)
        {
            var path = Path.Combine(dir, fileName);
            if (File.Exists(path))
            {
                try
                {
                    var content = File.ReadAllText(path);
                    _logger.LogDebug("פרומפט ניתוח מסמכים נטען מקובץ: {Path}", path);
                    return content;
                }
                catch (Exception ex)
                {
                    _logger.LogWarning(ex, "כשלון בקריאת קובץ פרומפט {Path}, משתמשים ב-fallback", path);
                }
            }
        }
        _logger.LogDebug("פרומפט ניתוח מסמכים: שימוש ב-fallback מוטבע");
        return DocAnalysisPromptFallback;
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
            Log.Information("📝 Using Custom Prompt from SYSTEM_PROMPT environment variable");
            promptTemplate = customPrompt;
        }
        else
        {
            Log.Debug("📝 Using Default Prompt");
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

            _logger.LogDebug("[Gemini Raw]: {RawText}", TruncateForLog(rawText));

            if (string.IsNullOrEmpty(rawText))
            {
                _logger.LogError("❌ Empty response from Gemini");
                return GeminiResult<SearchIntent>.Failure("Empty response from AI");
            }

            _logger.LogDebug("🔍 EXTRACTED_TEXT | Length: {Length} | Content: {Content}",
                rawText.Length, TruncateForLog(rawText));

            cleanJson = SanitizeJsonResponse(rawText);

            _logger.LogDebug("✅ SANITIZED_JSON | Length: {Length} | Content: {Content}",
                cleanJson.Length, TruncateForLog(cleanJson));

            var intent = JsonSerializer.Deserialize<SearchIntent>(cleanJson, _jsonOptions);

            if (intent == null)
            {
                _logger.LogError("❌ Deserialized intent is null");
                return GeminiResult<SearchIntent>.Failure("Failed to parse AI response - null result");
            }

            _logger.LogInformation("✅ SUCCESS | Terms: [{Terms}] | FileTypes: [{FileTypes}] | DateRange: {DateRange}",
                string.Join(", ", intent.Terms), string.Join(", ", intent.FileTypes),
                intent.DateRange != null ? $"{intent.DateRange.Start} to {intent.DateRange.End}" : "null");
            return GeminiResult<SearchIntent>.Success(intent);
        }
        catch (JsonException ex)
        {
            _logger.LogError(ex, "❌ JSON_PARSE_ERROR | Message: {Message} | Path: {Path} | Line: {Line} | BytePos: {BytePos} | FAILED_JSON: {Json}",
                ex.Message, ex.Path, ex.LineNumber, ex.BytePositionInLine, TruncateForLog(cleanJson));
            return GeminiResult<SearchIntent>.Failure($"JSON parse error: {ex.Message}");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "❌ UNEXPECTED_ERROR | Type: {Type} | Message: {Message}", ex.GetType().Name, ex.Message);
            return GeminiResult<SearchIntent>.Failure($"Unexpected error: {ex.Message}");
        }
    }

    /// <summary>
    /// לומד מונחים משאילתות חיפוש - כל term עם קטגוריה "search" (ללא userId)
    /// </summary>
    private async Task LearnFromSearchTermsAsync(List<string> terms)
    {
        try
        {
            foreach (var term in terms.Where(t => !string.IsNullOrWhiteSpace(t)))
                await _learningService.ProcessAiResultAsync(term, "search", userId: null);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "לולאת למידה: כשלון בעדכון מונחים מחיפוש");
        }
    }

    /// <summary>
    /// לומד מניתוח מסמך - קטגוריה וכל תגית עם קטגוריית המסמך
    /// </summary>
    private async Task LearnFromDocumentResultAsync(DocumentAnalysisResult result, string? userId = null)
    {
        var category = result.Category ?? "—";
        var tagCount = (result.Tags ?? []).Count(t => !string.IsNullOrWhiteSpace(t));
        _logger.LogInformation("[Server] Gemini response received. Category: {Category}, Tags: {TagCount}. Attempting to save to DB (collection: suggestions)...",
            category, tagCount);

        try
        {
            if (!string.IsNullOrWhiteSpace(result.Category))
                await _learningService.ProcessAiResultAsync(result.Category, "category", userId);
            foreach (var tag in (result.Tags ?? []).Where(t => !string.IsNullOrWhiteSpace(t)))
                await _learningService.ProcessAiResultAsync(tag, result.Category ?? "general", userId);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Server] CRITICAL: Failed to save to DB (learn from document). Error: {Message}", ex.Message);
        }
    }

    /// <summary>
    /// מנקה ומסנן את התשובה מ-Gemini - מסיר markdown ומחלץ רק את ה-JSON
    /// </summary>
    private static string SanitizeJsonResponse(string responseText)
    {
        Log.Debug("🧹 SANITIZE_START | Input Length: {Length}", responseText?.Length ?? 0);

        if (string.IsNullOrWhiteSpace(responseText))
        {
            Log.Warning("⚠️ SANITIZE: Empty input, returning empty object");
            return "{}";
        }

        responseText = responseText
            .Replace("```json", "")
            .Replace("```JSON", "")
            .Replace("```", "")
            .Trim();

        Log.Debug("🧹 AFTER_MARKDOWN_REMOVAL | Length: {Length}", responseText.Length);

        int firstBrace = responseText.IndexOf('{');
        int lastBrace = responseText.LastIndexOf('}');

        Log.Debug("🧹 BRACE_POSITIONS | FirstBrace: {First} | LastBrace: {Last}", firstBrace, lastBrace);

        if (firstBrace >= 0 && lastBrace > firstBrace)
        {
            responseText = responseText.Substring(firstBrace, lastBrace - firstBrace + 1);
            Log.Debug("🧹 JSON_EXTRACTED | Length: {Length}", responseText.Length);
        }
        else
        {
            Log.Warning("⚠️ Could not find valid JSON braces. Attempting to parse raw text. Length: {Length}", responseText.Length);
        }

        responseText = responseText
            .Replace("\r\n", "\n")
            .Replace("\r", "")
            .Replace("\t", " ");

        var result = responseText.Trim();
        Log.Debug("🧹 SANITIZE_COMPLETE | Final Length: {Length}", result.Length);

        return result;
    }

    /// <summary>היגיינת לוגים — חיתוך Body/JSON כדי לא לחרוג ממגבלת שורת לוג (Cloud Run).</summary>
    private static string TruncateForLog(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "(empty)";
        if (value.Length <= MaxLogPayloadChars) return value;
        return $"{value.Substring(0, MaxLogPayloadChars)}… [truncated, total {value.Length} chars]";
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
