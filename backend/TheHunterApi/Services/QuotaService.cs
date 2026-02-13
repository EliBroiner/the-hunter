using Google.Cloud.Firestore;
using Serilog;

namespace TheHunterApi.Services;

/// <summary>
/// ניהול מכסת שימוש יומי — Firestore collection "quotas", document id = {userId}_{yyyyMMdd}.
/// איפוס: Firebase Console → Firestore → quotas → מחק/ערוך מסמך עבור userId_תאריך.
/// </summary>
public class QuotaService
{
    private const string ColQuotas = "quotas";
    private const int FreeTierLimitPerDay = 100000;
    private readonly FirestoreDb _firestore;

    public QuotaService(FirestoreDb firestore)
    {
        _firestore = firestore;
    }

    private static string DocId(string userId, string? dateYyyyMmDd = null) =>
        $"{userId}_{(dateYyyyMmDd ?? DateTime.UtcNow.ToString("yyyyMMdd"))}";

    /// <summary>
    /// מחזיר את מספר השימושים היום למשתמש (0 אם אין מסמך).
    /// </summary>
    public async Task<long> GetUsageAsync(string userId)
    {
        var snap = await _firestore.Collection(ColQuotas).Document(DocId(userId)).GetSnapshotAsync();
        if (!snap.Exists)
            return 0;
        var v = snap.GetValue<long?>("count");
        return v ?? 0;
    }

    /// <summary>
    /// בודק אם למשתמש יש מכסה פנויה ליום.
    /// </summary>
    public async Task<bool> CanUserScanAsync(string userId, int requestedAmount)
    {
        var current = await GetUsageAsync(userId);
        var allowed = current + requestedAmount <= FreeTierLimitPerDay;
        Log.Information("User {UserId} quota: {Current}/{Max} (requested {Requested}) → {Result}",
            userId, current, FreeTierLimitPerDay, requestedAmount, allowed ? "ALLOWED" : "BLOCKED");
        return allowed;
    }

    /// <summary>
    /// מעלה את מונה השימוש ב־1 (אטומי — FieldValue.Increment).
    /// </summary>
    public async Task IncrementUsageAsync(string userId, int amount)
    {
        var docId = DocId(userId);
        Log.Information("[Quota] Incrementing usage for user {UserId}", userId);
        await _firestore.Collection(ColQuotas).Document(docId).SetAsync(
            new Dictionary<string, object>
            {
                { "userId", userId },
                { "date", DateTime.UtcNow.ToString("yyyyMMdd") },
                { "count", FieldValue.Increment(amount) }
            },
            SetOptions.MergeAll);
    }

    /// <summary>
    /// מאפס מכסה למשתמש לתאריך נתון (דיבאג/אדמין). תאריך ברירת מחדל = היום.
    /// </summary>
    public async Task ResetQuotaAsync(string userId, string? dateYyyyMmDd = null)
    {
        var docId = DocId(userId, dateYyyyMmDd);
        var dateStr = dateYyyyMmDd ?? DateTime.UtcNow.ToString("yyyyMMdd");
        await _firestore.Collection(ColQuotas).Document(docId).SetAsync(
            new Dictionary<string, object>
            {
                { "userId", userId },
                { "date", dateStr },
                { "count", 0L }
            },
            SetOptions.MergeAll);
        Log.Information("[Quota] Reset to 0 for user {UserId} date {Date} (docId={DocId})", userId, dateStr, docId);
    }
}
