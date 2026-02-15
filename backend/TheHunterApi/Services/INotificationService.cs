using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שירות התראות — אימייל או Telegram כשמספר המונחים הממתינים עובר סף.
/// </summary>
public interface INotificationService
{
    /// <summary>
    /// בודק אם יש לשלוח התראה (מספיק מונחים ממתינים). uniqueFiles — להצגה בהודעת Telegram.
    /// </summary>
    Task NotifyIfPendingThresholdAsync(int pendingCount, LearnedTerm? firstTerm = null, int uniqueFiles = 0, CancellationToken cancellationToken = default);
}
