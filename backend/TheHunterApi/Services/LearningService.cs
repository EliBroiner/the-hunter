using Google.Cloud.Firestore;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שירות לולאת למידה — כתיבת הצעות מונחים מ-AI ל-Firestore (מתאים ל-Cloud Run, לא ל-SQLite אפימרלי).
/// </summary>
public interface ILearningService
{
    /// <summary>
    /// מעבד תוצאה מ-AI: כותב מסמך חדש ל-collection suggestions ב-Firestore עם status pending_approval.
    /// אם קיים כבר מונח זהה (term+category) — מעדכן lastSeen במקום ליצור כפילות.
    /// </summary>
    /// <param name="sourceDocumentId">מזהה המסמך המקור — לספירת קבצים ייחודיים בהודעת Telegram</param>
    Task ProcessAiResultAsync(string term, string category, string? userId = null, string? originalTextSnippet = null, double confidenceScore = 1.0, string? sourceDocumentId = null);

    /// <summary>
    /// כותב מסמך בדיקה ל-Firestore — לאבחון חיבור DB (Database Doctor).
    /// </summary>
    /// <returns>DocId בהצלחה, אחרת null + הודעת שגיאה</returns>
    Task<(string? DocId, string? Error)> TryWriteTestDocumentAsync();
}

public class LearningService : ILearningService
{
    private const string CollectionSuggestions = "suggestions";
    /// <summary>אוסף קטגוריות חכמות — key, display_names, keywords, regex_patterns (קריאה/כתיבה מהלקוח או Admin).</summary>
    public const string CollectionSmartCategories = "smart_categories";
    private const string StatusPendingApproval = "pending_approval";

    private readonly FirestoreDb _firestore;
    private readonly ILogger<LearningService> _logger;
    private readonly INotificationService _notification;
    private readonly AdminFirestoreService _adminFirestore;

    public LearningService(FirestoreDb firestore, ILogger<LearningService> logger, INotificationService notification, AdminFirestoreService adminFirestore)
    {
        _firestore = firestore;
        _logger = logger;
        _notification = notification;
        _adminFirestore = adminFirestore;
    }

    public async Task ProcessAiResultAsync(string term, string category, string? userId = null, string? originalTextSnippet = null, double confidenceScore = 1.0, string? sourceDocumentId = null)
    {
        if (!TermValidator.IsValidTerm(term))
        {
            _logger.LogDebug("מונח נדחה - לא עבר ולידציה: {Term}", term.Length > 50 ? term[..50] + "…" : term);
            return;
        }
        if (!TermValidator.IsValidCategory(category))
        {
            _logger.LogDebug("קטגוריה נדחתה: {Category}", category);
            return;
        }

        var cat = string.IsNullOrWhiteSpace(category) ? "general" : category.Trim();
        var t = term.Trim();
        var snippet = (originalTextSnippet ?? "").Trim();
        var conf = Math.Clamp(confidenceScore, 0, 1);

        _logger.LogInformation("[Server] Attempting to save to Firestore. Collection: {Collection}. Term: {Term}, Category: {Category}",
            CollectionSuggestions, t.Length > 40 ? t[..40] + "…" : t, cat);

        try
        {
            var col = _firestore.Collection(CollectionSuggestions);
            var existing = await col.WhereEqualTo("term", t).WhereEqualTo("category", cat).WhereEqualTo("status", StatusPendingApproval).Limit(1).GetSnapshotAsync();
            if (existing.Count > 0)
            {
                var doc = existing.Documents[0];
                await doc.Reference.UpdateAsync(new Dictionary<string, object> { { "lastSeen", Timestamp.FromDateTime(DateTime.UtcNow) } });
                _logger.LogDebug("[Server] Dedup: updated lastSeen for existing term {Term}", t);
                return;
            }

            var data = new Dictionary<string, object>
            {
                { "term", t },
                { "category", cat },
                { "confidence_score", conf },
                { "original_text_snippet", snippet },
                { "created_at", Timestamp.FromDateTime(DateTime.UtcNow) },
                { "status", StatusPendingApproval },
                { "userId", userId ?? "" },
            };
            if (!string.IsNullOrWhiteSpace(sourceDocumentId))
                data["sourceDocumentId"] = sourceDocumentId.Trim();

            var newDoc = await col.AddAsync(data);
            _logger.LogInformation("[Server] Successfully saved to DB. Document ID: {Id}", newDoc.Id);

            await TriggerRealtimeAlertIfNeededAsync(cancellationToken: default);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "[Server] CRITICAL: Failed to save to DB. Error: {Message}", ex.Message);
            throw;
        }
    }

    private const int RealtimeAlertThreshold = 5;

    private async Task TriggerRealtimeAlertIfNeededAsync(CancellationToken cancellationToken)
    {
        try
        {
            var (count, uniqueFiles, firstTerm) = await _adminFirestore.GetPendingTermsStatsAsync();
            if (count < RealtimeAlertThreshold) return;

            _logger.LogInformation("[TELEGRAM] Real-time alert triggered by new AI results.");
            await _notification.NotifyIfPendingThresholdAsync(count, firstTerm, uniqueFiles, cancellationToken);
        }
        catch (Exception ex)
        {
            _logger.LogWarning(ex, "[LearningService] Failed to trigger real-time alert");
        }
    }

    /// <inheritdoc />
    public async Task<(string? DocId, string? Error)> TryWriteTestDocumentAsync()
    {
        const string collectionName = CollectionSuggestions;
        var now = DateTime.UtcNow;
        var data = new Dictionary<string, object>
        {
            { "term", "TEST_CONNECTIVITY" },
            { "definition", "Checking DB Write" },
            { "timestamp", Timestamp.FromDateTime(now) },
            { "status", "test" },
        };

        _logger.LogInformation("[Server] Database Doctor: Writing test document to collection: {Collection}", collectionName);

        try
        {
            var col = _firestore.Collection(collectionName);
            var newDoc = await col.AddAsync(data);
            _logger.LogInformation("[Server] Database Doctor: Write successful. Document ID: {Id}", newDoc.Id);
            return (newDoc.Id, null);
        }
        catch (Exception ex)
        {
            var msg = ex.ToString();
            _logger.LogError(ex, "[Server] Database Doctor: Write failed. Error: {Message}", ex.Message);
            return (null, msg);
        }
    }
}
