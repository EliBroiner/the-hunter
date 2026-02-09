namespace TheHunterApi.Middleware;

/// <summary>
/// Deep Network Tracing — רץ לפני Authentication/Authorization.
/// לוג כל בקשה נכנסת ונוכחות כותרת Auth כדי לזהות איפה החיבור נופל.
/// </summary>
public class RequestLoggingMiddleware
{
    private readonly RequestDelegate _next;

    public RequestLoggingMiddleware(RequestDelegate next) => _next = next;

    public async Task InvokeAsync(HttpContext context)
    {
        var method = context.Request.Method;
        var path = context.Request.Path;
        Console.WriteLine($"[SPY] Incoming: {method} {path}");
        Console.WriteLine($"[SPY] Auth Header Present: {context.Request.Headers.ContainsKey("Authorization")}");
        Console.WriteLine($"[SPY] X-Firebase-AppCheck Present: {context.Request.Headers.ContainsKey("X-Firebase-AppCheck")}");
        await _next(context);
    }
}
