using Microsoft.AspNetCore.Mvc;
using TheHunterApi.Models;
using TheHunterApi.Services;

namespace TheHunterApi.Controllers;

/// <summary>
/// Webhook ל-Telegram — מעבד callback_query (אשר/דחה מונח).
/// אבטחה: מטפל רק בבקשות שבהן from.id תואם ל-TELEGRAM_CHAT_ID (אדמין).
/// </summary>
[ApiController]
[Route("api/telegram")]
public class TelegramWebhookController : ControllerBase
{
    private readonly AdminFirestoreService _firestore;
    private readonly ITelegramService _telegram;
    private readonly IConfiguration _config;
    private readonly ILogger<TelegramWebhookController> _logger;

    public TelegramWebhookController(
        AdminFirestoreService firestore,
        ITelegramService telegram,
        IConfiguration config,
        ILogger<TelegramWebhookController> logger)
    {
        _firestore = firestore;
        _telegram = telegram;
        _config = config;
        _logger = logger;
    }

    /// <summary>מזהה האדמין — רק מ-IConfiguration / Environment (TELEGRAM_CHAT_ID). ללא hardcode.</summary>
    private string? AllowedAdminUserId => _config["TELEGRAM_CHAT_ID"] ?? Environment.GetEnvironmentVariable("TELEGRAM_CHAT_ID") ?? _config["Admin:Notification:TelegramChatId"];

    [HttpPost("webhook")]
    public async Task<IActionResult> Webhook([FromBody] TelegramUpdate update, CancellationToken cancellationToken = default)
    {
        string? fromId = null;
        if (update.CallbackQuery != null)
            fromId = update.CallbackQuery.From?.Id.ToString();
        else if (update.Message != null)
            fromId = update.Message.From?.Id.ToString();

        if (string.IsNullOrEmpty(AllowedAdminUserId) || string.IsNullOrEmpty(fromId) || fromId != AllowedAdminUserId)
        {
            _logger.LogWarning("Telegram webhook rejected: from.id {FromId} not allowed (TELEGRAM_CHAT_ID not set or mismatch).", fromId);
            return Unauthorized();
        }

        if (update.CallbackQuery == null)
            return Ok();

        var data = update.CallbackQuery.Data ?? "";

        if (data == "approve_all")
        {
            var count = await _firestore.ApproveAllPendingTermsAsync();
            await _telegram.AnswerCallbackQueryAsync(update.CallbackQuery.Id, count > 0 ? $"All {count} pending terms approved!" : "No pending terms.", cancellationToken);
            _logger.LogInformation("Approve all via Telegram: {Count} terms", count);
            return Ok();
        }

        if (data.StartsWith("approve_", StringComparison.Ordinal))
        {
            var termId = data["approve_".Length..].Trim();
            if (string.IsNullOrEmpty(termId)) return Ok();
            var term = await _firestore.GetTermByIdAsync(termId);
            var termText = term?.Term ?? termId;
            var ok = await _firestore.ApproveTermAsync(termId);
            await _telegram.AnswerCallbackQueryAsync(update.CallbackQuery.Id, ok ? $"המונח {EscapeForAlert(termText)} אושר בהצלחה!" : "שגיאה באישור.", cancellationToken);
            if (ok)
                _logger.LogInformation("Term approved via Telegram: {TermId}", termId);
            return Ok();
        }

        if (data.StartsWith("ban_", StringComparison.Ordinal))
        {
            var userId = data["ban_".Length..].Trim();
            if (string.IsNullOrEmpty(userId)) return Ok();
            var ok = await _firestore.SetUserBannedAsync(userId, true);
            await _telegram.AnswerCallbackQueryAsync(update.CallbackQuery.Id, ok ? $"User {EscapeForAlert(userId)} has been banned from the system." : "User not found or error.", cancellationToken);
            if (ok)
                _logger.LogInformation("User banned via Telegram: {UserId}", userId);
            return Ok();
        }

        if (data.StartsWith("reject_", StringComparison.Ordinal))
        {
            var termId = data["reject_".Length..].Trim();
            if (string.IsNullOrEmpty(termId)) return Ok();
            var term = await _firestore.GetTermByIdAsync(termId);
            var termText = term?.Term ?? termId;
            var ok = await _firestore.DeleteTermAsync(termId);
            await _telegram.AnswerCallbackQueryAsync(update.CallbackQuery.Id, ok ? $"המונח {EscapeForAlert(termText)} נדחה." : "שגיאה בדחייה.", cancellationToken);
            if (ok)
                _logger.LogInformation("Term rejected via Telegram: {TermId}", termId);
            return Ok();
        }

        return Ok();
    }

    private static string EscapeForAlert(string s) => s.Length > 50 ? s[..47] + "..." : s;
}
