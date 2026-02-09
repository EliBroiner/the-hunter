using Google.Cloud.Firestore;

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
}

public class LearningService : ILearningService
{
    private const string CollectionSuggestions = "suggestions";
    private const string StatusPendingApproval = "pending_approval";

    private readonly FirestoreDb _firestore;
    private readonly ILogger<LearningService> _logger;

    public LearningService(FirestoreDb firestore, ILogger<LearningService> logger)
    {
        _firestore = firestore;
        _logger = logger;
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

        try
        {
            var col = _firestore.Collection(CollectionSuggestions);
            var newDoc = await col.AddAsync(data);
            _logger.LogInformation("Successfully wrote suggestion to Firestore. ID: {Id}", newDoc.Id);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to write suggestion to Firestore: {Term}, {Category}", t, cat);
            throw;
        }
    }
}
