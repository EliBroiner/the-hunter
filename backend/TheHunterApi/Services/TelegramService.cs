using System.Text;
using Newtonsoft.Json;
using TheHunterApi.Models;

namespace TheHunterApi.Services;

/// <summary>
/// שליחת הודעות ל-Telegram Bot API — HTML + Inline Keyboard.
/// Token ו-ChatId רק מ-IConfiguration / Environment (TELEGRAM_BOT_TOKEN, TELEGRAM_CHAT_ID) — ללא hardcode.
/// סיריאליזציה: Newtonsoft.Json.
/// </summary>
public class TelegramService : ITelegramService
{
    private readonly IConfiguration _config;
    private readonly ILogger<TelegramService> _logger;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly AdminFirestoreService _firestore;

    public TelegramService(
        IConfiguration config,
        ILogger<TelegramService> logger,
        IHttpClientFactory httpClientFactory,
        AdminFirestoreService firestore)
    {
        _config = config;
        _logger = logger;
        _httpClientFactory = httpClientFactory;
        _firestore = firestore;
    }

    private string? BotToken => _config["TELEGRAM_BOT_TOKEN"] ?? Environment.GetEnvironmentVariable("TELEGRAM_BOT_TOKEN") ?? _config["Admin:Notification:TelegramBotToken"];
    private string? ChatId => _config["TELEGRAM_CHAT_ID"] ?? Environment.GetEnvironmentVariable("TELEGRAM_CHAT_ID") ?? _config["Admin:Notification:TelegramChatId"];
    private string AppUrl => Environment.GetEnvironmentVariable("APP_URL") ?? _config["Admin:AppUrl"] ?? "https://your-app-url.run.app";
    private string AdminKey => _config["Admin:Key"] ?? "";

    public async Task SendAdminAlertAsync(string message, InlineKeyboardMarkup? replyMarkup = null, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(BotToken) || string.IsNullOrWhiteSpace(ChatId))
        {
            _logger.LogWarning("Telegram not configured: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID missing.");
            return;
        }
        var payload = new { chat_id = ChatId, text = message, parse_mode = "HTML", reply_markup = replyMarkup };
        await SendTelegramPayloadAsync("sendMessage", payload, cancellationToken);
        _logger.LogInformation("Telegram SendAdminAlert sent.");
    }

    public async Task SendPendingTermsAlertAsync(int count, LearnedTerm? firstTerm = null, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(BotToken) || string.IsNullOrWhiteSpace(ChatId))
        {
            _logger.LogWarning("Telegram not configured: TELEGRAM_BOT_TOKEN or TELEGRAM_CHAT_ID missing.");
            return;
        }

        var sb = new StringBuilder();
        sb.Append("<b>🔔 התראת המערכת: The Hunter</b>\n\n");
        sb.Append("הצטברו ").Append(count).Append(" מונחים חדשים שמחכים לאישור שלך.\nהגיע הזמן לעבור עליהם!");
        if (firstTerm != null)
            sb.Append("\n\n<b>מונח ראשון בתור:</b> <code>").Append(EscapeHtml(firstTerm.Term ?? "")).Append("</code>");
        var message = sb.ToString();
        var dashboardUrl = $"{AppUrl.TrimEnd('/')}/admin/login?key={Uri.EscapeDataString(AdminKey)}";

        var buttons = new List<object[]>();
        if (count >= 10)
        {
            buttons.Add(new object[]
            {
                new { text = "✅ Approve All", callback_data = "approve_all" },
                new { text = "📋 View List", url = dashboardUrl }
            });
        }
        else
        {
            buttons.Add(new object[] { new { text = "📋 View List", url = dashboardUrl } });
        }
        if (firstTerm != null && !string.IsNullOrEmpty(firstTerm.FirestoreId))
        {
            var row = new List<object> { new { text = "✅ Approve", callback_data = "approve_" + firstTerm.FirestoreId } };
            var userId = (firstTerm.UserId ?? "").Trim();
            if (userId.Length > 0 && userId.Length <= 50)
                row.Add(new { text = "🚫 Ban User", callback_data = "ban_" + userId });
            buttons.Add(row.ToArray());
        }

        var payload = new
        {
            chat_id = ChatId,
            text = message,
            parse_mode = "HTML",
            reply_markup = new { inline_keyboard = buttons }
        };

        await SendTelegramPayloadAsync("sendMessage", payload, cancellationToken);
        _logger.LogInformation("Telegram admin alert sent. Pending terms: {Count}", count);
    }

    public async Task SendDailySummaryAsync(CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(BotToken) || string.IsNullOrWhiteSpace(ChatId))
        {
            _logger.LogWarning("Telegram not configured; skipping daily summary.");
            return;
        }

        var newUsers = await _firestore.GetNewUsersCountLast24hAsync();
        var pendingCount = await _firestore.GetPendingTermsCountAsync();
        var approvedCount = await _firestore.GetApprovedTermsCountAsync();
        var (activities, _) = await _firestore.GetLogsAsync(1);
        var topTerm = activities.Count > 0 ? activities[0].Term ?? "—" : "—";

        var sb = new StringBuilder();
        sb.Append("<b>📊 דוח יומי — The Hunter</b>\n\n");
        sb.Append("👤 <b>New Users:</b> ").Append(newUsers).Append("\n");
        sb.Append("📝 <b>Terms Pending/Approved:</b> ").Append(pendingCount).Append("/").Append(approvedCount).Append("\n");
        sb.Append("⚡ <b>Top Search:</b> \"").Append(EscapeHtml(topTerm)).Append("\"");

        var payload = new
        {
            chat_id = ChatId,
            text = sb.ToString(),
            parse_mode = "HTML"
        };

        await SendTelegramPayloadAsync("sendMessage", payload, cancellationToken);
        _logger.LogInformation("Telegram daily summary sent.");
    }

    public async Task AnswerCallbackQueryAsync(string callbackQueryId, string text, CancellationToken cancellationToken = default)
    {
        if (string.IsNullOrWhiteSpace(BotToken)) return;
        var payload = new { callback_query_id = callbackQueryId, text };
        await SendTelegramPayloadAsync("answerCallbackQuery", payload, cancellationToken);
    }

    internal async Task SendTelegramPayloadAsync(string method, object payload, CancellationToken cancellationToken)
    {
        var url = $"https://api.telegram.org/bot{BotToken}/{method}";
        var http = _httpClientFactory.CreateClient();
        var json = JsonConvert.SerializeObject(payload, new JsonSerializerSettings { NullValueHandling = NullValueHandling.Ignore });
        var content = new StringContent(json, Encoding.UTF8, "application/json");
        var response = await http.PostAsync(url, content, cancellationToken);
        if (!response.IsSuccessStatusCode)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            _logger.LogWarning("Telegram API error: {StatusCode} {Body}", response.StatusCode, body);
            response.EnsureSuccessStatusCode();
        }
    }

    private static string EscapeHtml(string s)
    {
        return s
            .Replace("&", "&amp;")
            .Replace("<", "&lt;")
            .Replace(">", "&gt;");
    }
}
