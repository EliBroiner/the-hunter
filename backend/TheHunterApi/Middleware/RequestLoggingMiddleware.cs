namespace TheHunterApi.Middleware;

/// <summary>
/// Deep Network Tracing — רץ לפני Authentication/Authorization.
/// לוג כל בקשה נכנסת ונוכחות כותרת Auth כדי לזהות איפה החיבור נופל.
/// </summary>
public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<RequestLoggingMiddleware> _logger;

    public RequestLoggingMiddleware(RequestDelegate next, ILogger<RequestLoggingMiddleware> logger)
    {
        _next = next;
        _logger = logger;
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var method = context.Request.Method;
        var path = context.Request.Path;
        _logger.LogDebug("[SPY] Incoming: {Method} {Path} | Auth: {Auth} | AppCheck: {AppCheck}",
            method, path,
            context.Request.Headers.ContainsKey("Authorization"),
            context.Request.Headers.ContainsKey("X-Firebase-AppCheck"));
        await _next(context);
    }
}
