using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שליחת התראות אדמין ל-Telegram (HTML + Inline Keyboard, כולל Quick Approve/Reject).
/// </summary>
public interface ITelegramService
{
    /// <summary>
    /// שולח הודעת אדמין עם אופציונלי InlineKeyboardMarkup (כפתורים). משתמש ב-Newtonsoft.Json.
    /// </summary>
    Task SendAdminAlertAsync(string message, InlineKeyboardMarkup? replyMarkup = null, CancellationToken cancellationToken = default);

    /// <summary>
    /// שולח התראת "מונחים ממתינים לאישור". uniqueFiles — מספר קבצים ייחודיים (להצגה בהודעה).
    /// </summary>
    Task SendPendingTermsAlertAsync(int count, LearnedTerm? firstTerm = null, int uniqueFiles = 0, CancellationToken cancellationToken = default);

    /// <summary>
    /// שולח דוח יומי: משתמשים חדשים, מונחים שאושרו היום, Top 3 חיפושים.
    /// </summary>
    Task SendDailySummaryAsync(CancellationToken cancellationToken = default);

    /// <summary>
    /// עונה ל-callback_query (לאחר לחיצה על כפתור Inline).
    /// </summary>
    Task AnswerCallbackQueryAsync(string callbackQueryId, string text, CancellationToken cancellationToken = default);

    /// <summary>
    /// שולח הודעה לצ'אט ספציפי (למשל תשובה ל-/start).
    /// </summary>
    Task SendMessageToChatAsync(string chatId, string text, CancellationToken cancellationToken = default);
}
