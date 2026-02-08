using System.Text;
using MailKit.Net.Smtp;
using TheHunterApi.Models;
using MailKit.Security;
using MimeKit;

namespace TheHunterApi.Services;

/// <summary>
/// Admin Alert: Telegram (עם cooldown 30 דקות), אימייל או Webhook כשמונחים ממתינים >= סף.
/// </summary>
public class NotificationService : INotificationService
{
    private static readonly TimeSpan Cooldown = TimeSpan.FromMinutes(30);
    private static DateTime _lastTelegramSentAt = DateTime.MinValue;

    private readonly IConfiguration _config;
    private readonly ILogger<NotificationService> _logger;
    private readonly IHttpClientFactory? _httpClientFactory;
    private readonly ITelegramService? _telegram;

    public NotificationService(
        IConfiguration config,
        ILogger<NotificationService> logger,
        IHttpClientFactory? httpClientFactory = null,
        ITelegramService? telegram = null)
    {
        _config = config;
        _logger = logger;
        _httpClientFactory = httpClientFactory;
        _telegram = telegram;
    }

    private int Threshold => _config.GetValue("Admin:Notification:PendingThreshold", 10);
    private string? SmtpHost => _config["Admin:Notification:SmtpHost"];
    private int SmtpPort => _config.GetValue("Admin:Notification:SmtpPort", 587);
    private string? SmtpUser => _config["Admin:Notification:SmtpUser"];
    private string? SmtpPassword => _config["Admin:Notification:SmtpPassword"];
    private string? AdminEmail => _config["Admin:Notification:AdminEmail"];
    private string? WebhookUrl => _config["Admin:Notification:WebhookUrl"];

    public async Task NotifyIfPendingThresholdAsync(int pendingCount, LearnedTerm? firstTerm = null, CancellationToken cancellationToken = default)
    {
        if (pendingCount < Threshold) return;

        var message = $"The Hunter Alert: There are {pendingCount} terms waiting for your review. Please visit the dashboard.";
        var sent = false;

        // 1) Telegram — עם cooldown 30 דקות
        if (_telegram != null && (DateTime.UtcNow - _lastTelegramSentAt) >= Cooldown)
        {
            try
            {
                await _telegram.SendPendingTermsAlertAsync(pendingCount, firstTerm, cancellationToken);
                _lastTelegramSentAt = DateTime.UtcNow;
                sent = true;
                _logger.LogInformation("Admin alert sent via Telegram");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Telegram notification failed");
            }
        }
        else if (_telegram != null)
            _logger.LogDebug("Telegram cooldown active, skipping.");

        // 2) SMTP Email (אם מוגדר)
        if (!sent && !string.IsNullOrWhiteSpace(SmtpHost) && !string.IsNullOrWhiteSpace(AdminEmail))
        {
            try
            {
                await SendEmailAsync(message, cancellationToken);
                sent = true;
                _logger.LogInformation("Notification email sent to {Email}", AdminEmail);
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Failed to send notification email");
            }
        }

        // 3) Generic Webhook (Slack/Discord)
        if (!sent && !string.IsNullOrWhiteSpace(WebhookUrl))
        {
            try
            {
                await SendWebhookAsync(message, cancellationToken);
                sent = true;
                _logger.LogInformation("Notification webhook sent");
            }
            catch (Exception ex)
            {
                _logger.LogWarning(ex, "Webhook notification failed");
            }
        }

        if (!sent)
            _logger.LogInformation("Dashboard Alert: {Message} (no Telegram/SMTP/Webhook configured)", message);
    }

    private async Task SendEmailAsync(string body, CancellationToken ct)
    {
        var msg = new MimeMessage();
        msg.From.Add(MailboxAddress.Parse(SmtpUser ?? "noreply@thehunter.app"));
        msg.To.Add(MailboxAddress.Parse(AdminEmail!));
        msg.Subject = "The Hunter Alert — Terms Pending Review";
        msg.Body = new TextPart("plain") { Text = body };

        using var client = new SmtpClient();
        await client.ConnectAsync(SmtpHost!, SmtpPort, SecureSocketOptions.StartTls, ct);
        if (!string.IsNullOrEmpty(SmtpUser) && !string.IsNullOrEmpty(SmtpPassword))
            await client.AuthenticateAsync(SmtpUser, SmtpPassword, ct);
        await client.SendAsync(msg, ct);
        await client.DisconnectAsync(true, ct);
    }

    private async Task SendWebhookAsync(string text, CancellationToken ct)
    {
        var http = _httpClientFactory?.CreateClient() ?? new HttpClient();
        var payload = new { text = $"[The Hunter Admin] {text}" };
        var content = new StringContent(System.Text.Json.JsonSerializer.Serialize(payload), Encoding.UTF8, "application/json");
        var res = await http.PostAsync(WebhookUrl, content, ct);
        res.EnsureSuccessStatusCode();
    }
}
