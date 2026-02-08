using System.Runtime.InteropServices;

namespace TheHunterApi.Services;

/// <summary>
/// שולח דוח יומי ב-Telegram כל יום בשעה 09:00 (ברירת מחדל: Israel Standard Time).
/// </summary>
public class DailySummaryHostedService : BackgroundService
{
    private readonly IServiceProvider _services;
    private readonly ILogger<DailySummaryHostedService> _logger;
    private readonly IConfiguration _config;

    public DailySummaryHostedService(IServiceProvider services, ILogger<DailySummaryHostedService> logger, IConfiguration config)
    {
        _services = services;
        _logger = logger;
        _config = config;
    }

    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        var hour = _config.GetValue("Admin:Notification:DailySummaryHour", 9);
        TimeZoneInfo tz;
        try
        {
            tz = TimeZoneInfo.FindSystemTimeZoneById(
                _config["Admin:Notification:DailySummaryTimeZone"] ?? (RuntimeInformation.IsOSPlatform(OSPlatform.Windows) ? "Israel Standard Time" : "Asia/Jerusalem"));
        }
        catch
        {
            tz = TimeZoneInfo.Utc;
        }

        while (!stoppingToken.IsCancellationRequested)
        {
            var now = TimeZoneInfo.ConvertTimeFromUtc(DateTime.UtcNow, tz);
            var next = now.Date.AddHours(hour);
            if (now >= next) next = next.AddDays(1);
            var delay = next - now;
            _logger.LogInformation("Daily summary next run at {Next} ({Tz})", next, tz.Id);
            try
            {
                await Task.Delay(delay, stoppingToken);
            }
            catch (TaskCanceledException)
            {
                break;
            }

            try
            {
                using var scope = _services.CreateScope();
                var telegram = scope.ServiceProvider.GetService<ITelegramService>();
                if (telegram != null)
                    await telegram.SendDailySummaryAsync(stoppingToken);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Daily summary send failed");
            }
        }
    }
}
