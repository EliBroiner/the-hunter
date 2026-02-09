using Google.Cloud.Firestore;
using Serilog;

namespace TheHunterApi.Services;

/// <summary>
/// ניהול מכסת שימוש יומי — Firestore collection quotas, document id = {userId}_{yyyyMMdd}.
/// </summary>
public class QuotaService
{
    private const string ColQuotas = "quotas";
    private const int FreeTierLimitPerDay = 1000;
    private readonly FirestoreDb _firestore;

    public QuotaService(FirestoreDb firestore)
    {
        _firestore = firestore;
    }

    private static string DocId(string userId) =>
        $"{userId}_{DateTime.UtcNow:yyyyMMdd}";

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
        var dateStr = DateTime.UtcNow.ToString("yyyyMMdd");
        var docId = $"{userId}_{dateStr}";
        Log.Information("[Quota] Incrementing usage for user {UserId} for date {Date}", userId, dateStr);
        await _firestore.Collection(ColQuotas).Document(docId).SetAsync(
            new Dictionary<string, object>
            {
                { "userId", userId },
                { "date", dateStr },
                { "count", FieldValue.Increment(amount) }
            },
            SetOptions.MergeAll);
    }
}
