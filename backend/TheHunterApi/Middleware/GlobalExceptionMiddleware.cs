using TheHunterApi.Services;

namespace TheHunterApi.Middleware;

/// <summary>
/// Middleware לתפיסת חריגות — רושם שגיאות 500 ב-AdminErrorTracker
/// </summary>
public class GlobalExceptionMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<GlobalExceptionMiddleware> _logger;

    public GlobalExceptionMiddleware(RequestDelegate next, ILogger<GlobalExceptionMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        try
        {
            await _next(context);
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "שגיאה לא מטופלת");
            AdminErrorTracker.AddError(ex.Message);
            throw;
        }
    }
}
