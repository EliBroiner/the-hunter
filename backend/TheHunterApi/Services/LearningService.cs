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
    /// </summary>
    /// <param name="userId">מזהה משתמש לאימות/לוג (אופציונלי)</param>
    Task ProcessAiResultAsync(string term, string category, string? userId = null);

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

    public LearningService(FirestoreDb firestore, ILogger<LearningService> logger, INotificationService notification)
    {
        _firestore = firestore;
        _logger = logger;
        _notification = notification;
    }

    public async Task ProcessAiResultAsync(string term, string category, string? userId = null)
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

        var data = new Dictionary<string, object>
        {
            { "term", t },
            { "category", cat },
            { "confidence", 1.0 },
            { "original_text_snippet", "" },
            { "created_at", Timestamp.FromDateTime(DateTime.UtcNow) },
            { "status", StatusPendingApproval },
        };
        if (!string.IsNullOrWhiteSpace(userId))
            data["userId"] = userId;

        _logger.LogInformation("[Server] Attempting to save to Firestore. Collection: {Collection}. Term: {Term}, Category: {Category}",
            CollectionSuggestions, t.Length > 40 ? t[..40] + "…" : t, cat);

        try
        {
            var col = _firestore.Collection(CollectionSuggestions);
            var newDoc = await col.AddAsync(data);
            _logger.LogInformation("[Server] Successfully saved to DB. Document ID: {Id}", newDoc.Id);

            // התראה בזמן אמת — אם יש >= 5 מונחים ממתינים
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
            var col = _firestore.Collection(CollectionSuggestions);
            var query = col.WhereEqualTo("status", StatusPendingApproval);
            var snapshot = await query.GetSnapshotAsync(cancellationToken);
            var count = snapshot.Count;
            if (count < RealtimeAlertThreshold) return;

            LearnedTerm? firstTerm = null;
            var firstDoc = snapshot.Documents.OrderBy(d => d.CreateTime).FirstOrDefault();
            if (firstDoc != null)
            {
                var d = firstDoc.ToDictionary();
                static string? Get(Dictionary<string, object> dict, string key) =>
                    dict.TryGetValue(key, out var v) ? v?.ToString() : null;
                firstTerm = new LearnedTerm
                {
                    FirestoreId = firstDoc.Id,
                    Term = Get(d, "term") ?? "",
                    Category = Get(d, "category") ?? "",
                    UserId = Get(d, "userId"),
                };
            }
            _logger.LogInformation("[TELEGRAM] Real-time alert triggered by new AI results.");
            await _notification.NotifyIfPendingThresholdAsync(count, firstTerm, cancellationToken);
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
