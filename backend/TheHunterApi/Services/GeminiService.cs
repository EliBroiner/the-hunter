using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Hosting;
using Serilog;
using TheHunterApi.Config;
using TheHunterApi.Constants;
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
    private readonly ILearningService _learningService;
    private readonly ISearchActivityService _searchActivityService;
    private readonly IWebHostEnvironment _webHost;
    private readonly AdminFirestoreService _firestore;

    public GeminiService(
        IHttpClientFactory httpClientFactory,
        GeminiConfig geminiConfig,
        ILogger<GeminiService> logger,
        ILearningService learningService,
        ISearchActivityService searchActivityService,
        IWebHostEnvironment webHost,
        AdminFirestoreService firestore)
    {
        _httpClientFactory = httpClientFactory;
        _geminiConfig = geminiConfig;
        _logger = logger;
        _learningService = learningService;
        _searchActivityService = searchActivityService;
        _webHost = webHost;
        _firestore = firestore;
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

    /// <summary>מחזיר HttpClient + URL ל-Gemini — שימוש חוזר בכל הקריאות.</summary>
    private (HttpClient Client, string Url) GetGeminiClientAndUrl(string model) => (
        _httpClientFactory.CreateClient("GeminiApi"),
        $"v1beta/models/{model}:generateContent?key={_geminiConfig.ApiKey}");

    /// <summary>
    /// מפענח שאילתת חיפוש בשפה טבעית ל-SearchIntent מובנה.
    /// systemPromptOverride — רק Admin (מאומת ב-Controller).
    /// </summary>
    public async Task<GeminiResult<SearchIntent>> ParseSearchIntentAsync(string query, string? systemPromptOverride = null)
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
            var (client, url) = GetGeminiClientAndUrl(GeminiModel);
            var geminiRequest = await BuildGeminiRequestAsync(query, systemPromptOverride);
            var jsonContent = JsonSerializer.Serialize(geminiRequest, _jsonOptions);
            var (response, responseBody) = await GeminiHttpHelper.PostWith429RetryAsync(client, url, jsonContent, _logger, "ParseSearchIntent");

            if (response == null || !response.IsSuccessStatusCode)
            {
                if (response != null && (int)response.StatusCode == 429)
                    return GeminiResult<SearchIntent>.Failure("Gemini quota exceeded (429). Try again in a minute.");
                return GeminiResult<SearchIntent>.Failure("Gemini API error or quota exceeded. Try again later.");
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
    /// ניתוח טקסט OCR בודד (מ-Cloud Vision) — חילוץ קטגוריה, תגיות, תאריך, סיכום. לדריסת קטגוריה מקומית כושלת.
    /// </summary>
    public async Task<DocumentAnalysisResponse> AnalyzeOcrTextAsync(string documentId, string filename, string text, string? userId = null)
    {
        var doc = new DocumentPayload { Id = documentId, Filename = filename, Text = text };
        var list = await AnalyzeDocumentsBatchAsync([doc], userId, null);
        return list.FirstOrDefault() ?? new DocumentAnalysisResponse { DocumentId = documentId, Result = new DocumentAnalysisResult() };
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

        // טעינת פרומפט פעם אחת — מונע N קריאות DB/קובץ באצווה
        var systemPrompt = customPromptOverride ?? await GetDocAnalysisPromptAsync();
        if (customPromptOverride != null)
            _logger.LogWarning("Using Custom Developer Prompt (Admin override) for batch of {Count} docs", documents.Count);
        var tasks = documents.Select(d => AnalyzeOneDocumentAsync(d, userId, systemPrompt));
        var results = await Task.WhenAll(tasks);
        return results.ToList();
    }

    private async Task<DocumentAnalysisResponse> AnalyzeOneDocumentAsync(
        DocumentPayload doc,
        string? userId,
        string systemPrompt)
    {
        var text = (doc.Text ?? "").Trim();
        var filename = doc.Filename ?? doc.Id ?? "";

        // CASE A: יש טקסט (OCR) — שולחים רק Text ל-Gemini. לא FileUri / FileData (מונע 404).
        if (!string.IsNullOrEmpty(text))
        {
            _logger.LogInformation("[LOGIC] Item {DocumentId} has text ({TextLength} chars). Using Text Generation only (no FileUri).",
                doc.Id, text.Length);
            return await SendTextOnlyToGeminiAsync(doc.Id ?? "", filename, text, userId, systemPrompt);
        }

        // CASE B: אין טקסט — לא קוראים ל-Gemini (אין fallback ל-FileUri — הלקוח שולח רק טקסט).
        _logger.LogWarning("[LOGIC] Item {DocumentId} has NO text. Skipping Gemini (returning empty result).", doc.Id);
        return new DocumentAnalysisResponse { DocumentId = doc.Id ?? "", Result = new DocumentAnalysisResult() };
    }

    /// <summary>
    /// שולח ל-Gemini רק Part מסוג Text. לא מוסיף FileData/FileUri — מונע 404.
    /// systemPrompt — כבר נטען ברמת האצווה (מונע N קריאות DB).
    /// </summary>
    private async Task<DocumentAnalysisResponse> SendTextOnlyToGeminiAsync(
        string documentId,
        string filename,
        string text,
        string? userId,
        string systemPrompt)
    {
        try
        {
            // פרומפט אחד — הוראות + תוכן. רק Part.Text, בלי FileData/FileUri.
            var prompt = $"Analyze this document text.\nFilename: {filename}\nContent:\n{text}\n\n{systemPrompt}";
            var (client, url) = GetGeminiClientAndUrl(GeminiDocModel);

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
                    MaxOutputTokens = 2048,
                    ResponseMimeType = "application/json"
                }
            };

            var jsonContent = JsonSerializer.Serialize(request, _jsonOptions);
            _logger.LogInformation("[GEMINI_REQUEST] Model={Model} | Request length={Len} | Prompt: {Preview}",
                GeminiDocModel, jsonContent.Length, TruncateForLog(prompt));

            var (response, responseBody) = await GeminiHttpHelper.PostWith429RetryAsync(client, url, jsonContent, _logger, $"Doc {documentId}");
            if (response == null || !response.IsSuccessStatusCode)
            {
                if (response != null)
                    _logger.LogError("[GEMINI_FAIL] Doc {Id} — HTTP {Status}. Batch continues.", documentId, response.StatusCode);
                return new DocumentAnalysisResponse { DocumentId = documentId, Result = new DocumentAnalysisResult() };
            }

            var rawText = GeminiHttpHelper.ExtractRawTextFromResponse(responseBody, _jsonOptions);
            var cleanJson = GeminiHttpHelper.SanitizeJsonResponse(rawText);
            DocumentAnalysisResult result;
            try
            {
                result = JsonSerializer.Deserialize<DocumentAnalysisResult>(cleanJson, _jsonOptions) ?? new DocumentAnalysisResult();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to parse Gemini JSON for doc {Id}. Raw length: {Len}. Using empty result.", documentId, cleanJson.Length);
                result = new DocumentAnalysisResult();
            }

            _logger.LogInformation("[GEMINI_PARSED] Doc {Id} — Category={Category} | Tags count={TagCount} | Raw text length={RawLen}",
                documentId, result?.Category ?? "(null)", result?.Tags?.Count ?? 0, rawText.Length);

            var safeResult = result ?? new DocumentAnalysisResult();
            await LearnFromDocumentResultAsync(safeResult, userId, text, documentId, filename);

            var finalJson = JsonSerializer.Serialize(new DocumentAnalysisResponse { DocumentId = documentId, Result = safeResult }, _jsonOptions);
            _logger.LogInformation("[GEMINI_TO_CLIENT] Doc {Id} — Sending result: {Preview}", documentId, TruncateForLog(finalJson));

            return new DocumentAnalysisResponse { DocumentId = documentId, Result = safeResult };
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

        var systemPrompt = string.IsNullOrWhiteSpace(customPrompt) ? await GetDocAnalysisPromptAsync() : customPrompt.Trim();
        try
        {
            var (client, url) = GetGeminiClientAndUrl(GeminiDocModel);
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
                    MaxOutputTokens = 2048,
                    ResponseMimeType = "application/json"
                }
            };
            var jsonContent = JsonSerializer.Serialize(request, _jsonOptions);
            _logger.LogInformation("[GEMINI_REQUEST] analyze-debug | Model={Model} | Request length={Len}", GeminiDocModel, jsonContent.Length);

            var (response, responseBody) = await GeminiHttpHelper.PostWith429RetryAsync(client, url, jsonContent, _logger, "analyze-debug");
            if (response == null || !response.IsSuccessStatusCode)
            {
                if (response != null) _logger.LogError("[GEMINI_FAIL] analyze-debug — HTTP {Status}", response.StatusCode);
                return new DocumentAnalysisResult();
            }

            var rawText = GeminiHttpHelper.ExtractRawTextFromResponse(responseBody, _jsonOptions);
            var cleanJson = GeminiHttpHelper.SanitizeJsonResponse(rawText);
            try
            {
                return JsonSerializer.Deserialize<DocumentAnalysisResult>(cleanJson, _jsonOptions) ?? new DocumentAnalysisResult();
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to parse Gemini JSON (analyze-debug). Raw length: {Len}.", cleanJson.Length);
                return new DocumentAnalysisResult();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "AnalyzeDocumentWithCustomPrompt failed");
            return new DocumentAnalysisResult();
        }
    }

    /// <summary>
    /// OCR Fallback — שולח PDF/תמונה ל-Gemini עם פרומפט לחילוץ טקסט. לשימוש ב-AI Lab.
    /// </summary>
    public async Task<(string ExtractedText, bool Success, string? Error)> ExtractTextFromFileAsync(byte[] fileBytes, string mimeType, string prompt)
    {
        if (!IsConfigured)
            return ("", false, "Gemini API not configured");

        try
        {
            var b64 = Convert.ToBase64String(fileBytes);
            var (client, url) = GetGeminiClientAndUrl(GeminiDocModel);
            var request = new GeminiRequest
            {
                Contents = new List<GeminiContent>
                {
                    new()
                    {
                        Parts =
                        [
                            new GeminiPart { InlineData = new GeminiInlineData { MimeType = mimeType, Data = b64 } },
                            new GeminiPart { Text = prompt }
                        ]
                    }
                },
                GenerationConfig = new GenerationConfig
                {
                    Temperature = 0.1,
                    MaxOutputTokens = 2048
                }
            };
            var jsonContent = JsonSerializer.Serialize(request, _jsonOptions);
            var (response, responseBody) = await GeminiHttpHelper.PostWith429RetryAsync(client, url, jsonContent, _logger, "GEMINI_OCR");
            if (response == null || !response.IsSuccessStatusCode)
            {
                if (response != null) _logger.LogError("[GEMINI_OCR] HTTP {Status}. Body: {Body}", response.StatusCode, TruncateForLog(responseBody));
                return ("", false, response != null ? $"HTTP {(int)response.StatusCode}" : "Request failed");
            }
            var rawText = GeminiHttpHelper.ExtractRawTextFromResponse(responseBody, _jsonOptions);
            return (rawText, true, null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "ExtractTextFromFileAsync failed");
            return ("", false, ex.Message);
        }
    }

    /// <summary>
    /// Playground — שולח System + User ל-Gemini, מחזיר תשובה גולמית (לשימוש Admin Debug).
    /// </summary>
    public async Task<(string RawText, bool Success, string? Error)> GenerateContentRawAsync(string systemPrompt, string userQuery)
    {
        if (!IsConfigured)
            return ("", false, "Gemini API not configured");

        try
        {
            var (client, url) = GetGeminiClientAndUrl(GeminiDocModel);
            var request = new GeminiRequest
            {
                Contents = new List<GeminiContent>
                {
                    new()
                    {
                        Parts = new List<GeminiPart>
                        {
                            new GeminiPart { Text = systemPrompt },
                            new GeminiPart { Text = userQuery }
                        }
                    }
                },
                GenerationConfig = new GenerationConfig { Temperature = 0.1, MaxOutputTokens = 4096 }
            };
            var jsonContent = JsonSerializer.Serialize(request, _jsonOptions);
            var (response, responseBody) = await GeminiHttpHelper.PostWith429RetryAsync(client, url, jsonContent, _logger, "GEMINI_PLAYGROUND");
            if (response == null || !response.IsSuccessStatusCode)
            {
                if (response != null) _logger.LogError("[GEMINI_PLAYGROUND] HTTP {Status}. Body: {Body}", response.StatusCode, TruncateForLog(responseBody));
                return (responseBody, false, response != null ? $"HTTP {(int)response.StatusCode}" : "Request failed");
            }
            var rawText = GeminiHttpHelper.ExtractRawTextFromResponse(responseBody, _jsonOptions);
            return (rawText, true, null);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "GenerateContentRawAsync failed");
            return ("", false, ex.Message);
        }
    }

    /// <summary>מקור: Firestore (analysis) → fallback מוטבע מ-SystemPromptFallbacks.</summary>
    private async Task<string> GetDocAnalysisPromptAsync()
    {
        var result = await _firestore.GetLatestPromptAsync(TheHunterApi.Constants.FeatureType.DocumentAnalysis);
        return result.Text;
    }

    /// <summary>
    /// בונה את הבקשה ל-Gemini API עם הפרומפט הדינמי
    /// </summary>
    private async Task<GeminiRequest> BuildGeminiRequestAsync(string userQuery, string? systemPromptOverride = null)
    {
        string systemPrompt;
        if (!string.IsNullOrWhiteSpace(systemPromptOverride))
        {
            var today = DateTime.UtcNow.ToString("yyyy-MM-dd");
            systemPrompt = systemPromptOverride.Replace("{CurrentDate}", today);
        }
        else
        {
            systemPrompt = await BuildSystemPromptAsync();
        }
        
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

    /// <summary>מקור: Firestore (search) → fallback. מזריק learned_knowledge מאושר ל-SmartSearch.</summary>
    private async Task<string> BuildSystemPromptAsync()
    {
        var today = DateTime.UtcNow.ToString("yyyy-MM-dd");
        var result = await _firestore.GetLatestPromptAsync(TheHunterApi.Constants.FeatureType.SmartSearch);
        var prompt = result.Text.Replace("{CurrentDate}", today);

        var learned = await _firestore.GetApprovedLearnedKnowledgeForSearchAsync();
        var learnedBlock = learned.Count == 0
            ? "(none)"
            : string.Join("\n", learned.Select(x => $"- \"{x.Term}\" → category: {x.Category}"));
        var learnedText = $"Use the following learned domain knowledge from the user's own documents when expanding queries:\n{learnedBlock}";

        if (prompt.Contains("{LearnedKnowledge}"))
            prompt = prompt.Replace("{LearnedKnowledge}", learnedBlock);
        else
            prompt += $"\n\n{learnedText}\n";

        return prompt;
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
            // שלב 1: חילוץ טקסט גולמי — שימוש חוזר ב-Helper
            rawText = GeminiHttpHelper.ExtractRawTextFromResponse(responseBody, _jsonOptions);

            _logger.LogDebug("[Gemini Raw]: {RawText}", TruncateForLog(rawText));

            if (string.IsNullOrEmpty(rawText))
            {
                _logger.LogError("❌ Empty response from Gemini");
                return GeminiResult<SearchIntent>.Failure("Empty response from AI");
            }

            _logger.LogDebug("🔍 EXTRACTED_TEXT | Length: {Length} | Content: {Content}",
                rawText.Length, TruncateForLog(rawText));

            cleanJson = GeminiHttpHelper.SanitizeJsonResponse(rawText);

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
    /// לומד מניתוח מסמך — קטגוריה, תגיות, והצעות (suggestions) עם הקשר מהטקסט.
    /// </summary>
    /// <param name="sourceDocumentId">מזהה המסמך — נשמר ל-sourceDocumentId לספירת קבצים ייחודיים.</param>
    private const int MaxSuggestionsPerDocument = 15;

    private async Task LearnFromDocumentResultAsync(DocumentAnalysisResult result, string? userId = null, string? documentText = null, string? sourceDocumentId = null, string? sourceFile = null)
    {
        var category = result.Category ?? "—";
        var tagCount = (result.Tags ?? []).Count(t => !string.IsNullOrWhiteSpace(t));
        var suggCount = (result.Suggestions ?? []).Count;
        _logger.LogInformation("[Server] Gemini response received. Category: {Category}, Tags: {TagCount}, Suggestions: {SuggCount}. Saving to suggestions...",
            category, tagCount, suggCount);

        // שמירה ל-learned_knowledge — לולאת למידה סגורה. מונחים מאושרים יוזרקו ל-SmartSearch
        if (suggCount > 0)
            await _firestore.SaveLearnedKnowledgeAsync(result.Suggestions!, sourceFile ?? sourceDocumentId, userId);

        var saved = 0;
        try
        {
            if (saved < MaxSuggestionsPerDocument && !string.IsNullOrWhiteSpace(result.Category))
            {
                await _learningService.ProcessAiResultAsync(result.Category, "category", userId, ExtractSnippet(documentText, result.Category), 1.0, sourceDocumentId);
                saved++;
            }
            foreach (var tag in (result.Tags ?? []).Where(t => !string.IsNullOrWhiteSpace(t)))
            {
                if (saved >= MaxSuggestionsPerDocument) break;
                await _learningService.ProcessAiResultAsync(tag, result.Category ?? "general", userId, ExtractSnippet(documentText, tag), 1.0, sourceDocumentId);
                saved++;
            }
            foreach (var sugg in (result.Suggestions ?? []))
            {
                if (saved >= MaxSuggestionsPerDocument) break;
                var cat = string.IsNullOrWhiteSpace(sugg.SuggestedCategory) ? (result.Category ?? "general") : sugg.SuggestedCategory;
                var conf = Math.Clamp(sugg.Confidence, 0, 1);
                foreach (var kw in (sugg.SuggestedKeywords ?? []).Where(k => !string.IsNullOrWhiteSpace(k)))
                {
                    if (saved >= MaxSuggestionsPerDocument) break;
                    await _learningService.ProcessAiResultAsync(kw.Trim(), cat, userId, ExtractSnippet(documentText, kw), conf, sourceDocumentId);
                    saved++;
                }
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Server] CRITICAL: Failed to save to DB (learn from document). Error: {Message}", ex.Message);
        }
    }

    /// <summary>מחלץ ≥100 תווים סביב המונח מהטקסט.</summary>
    private static string ExtractSnippet(string? text, string term)
    {
        if (string.IsNullOrWhiteSpace(text) || string.IsNullOrWhiteSpace(term)) return "";
        var idx = text.IndexOf(term, StringComparison.OrdinalIgnoreCase);
        if (idx < 0) return text.Length >= 100 ? text[..100] : text;
        var half = 50;
        var start = Math.Max(0, idx - half);
        var len = Math.Min(text.Length - start, Math.Max(100, term.Length + 2 * half));
        return text.Substring(start, len).Trim();
    }

    /// <summary>היגיינת לוגים — חיתוך Body/JSON כדי לא לחרוג ממגבלת שורת לוג (Cloud Run).</summary>
    private static string TruncateForLog(string? value)
    {
        if (string.IsNullOrEmpty(value)) return "(empty)";
        if (value.Length <= MaxLogPayloadChars) return value;
        return $"{value.Substring(0, MaxLogPayloadChars)}… [truncated, total {value.Length} chars]";
    }
}

