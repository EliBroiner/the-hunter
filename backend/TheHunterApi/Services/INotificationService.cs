using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שירות התראות — אימייל או Telegram כשמספר המונחים הממתינים עובר סף.
/// </summary>
public interface INotificationService
{
    /// <summary>
    /// בודק אם יש לשלוח התראה (מספיק מונחים ממתינים). firstTerm מועבר ל-Telegram לכפתורי אשר/דחה.
    /// </summary>
    Task NotifyIfPendingThresholdAsync(int pendingCount, LearnedTerm? firstTerm = null, CancellationToken cancellationToken = default);
}
