using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace TheHunterApi.Filters;

/// <summary>
/// פילטר אבטחה ל-Admin Dashboard - בודק AdminKey מתוך header או query
/// </summary>
public class AdminKeyAuthorizationFilter : IAuthorizationFilter
{
    private readonly IConfiguration _config;

    public AdminKeyAuthorizationFilter(IConfiguration config)
    {
        _config = config;
    }

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        // קריאת מפתח מ-appsettings / env (ברירת מחדל לפיתוח)
        var expectedKey = _config["Admin:Key"]
            ?? Environment.GetEnvironmentVariable("ADMIN_KEY")
            ?? "dev-admin-123";

        var key = context.HttpContext.Request.Headers["X-Admin-Key"].FirstOrDefault()
            ?? context.HttpContext.Request.Query["key"].FirstOrDefault();

        // Debug זמני — בדיקת 401
        var fromHeader = context.HttpContext.Request.Headers["X-Admin-Key"].FirstOrDefault();
        var fromQuery = context.HttpContext.Request.Query["key"].FirstOrDefault();
        var received = fromHeader ?? fromQuery ?? "(empty)";
        var masked = expectedKey?.Length >= 2
            ? expectedKey[..2] + new string('*', expectedKey.Length - 2)
            : "***";
        Console.WriteLine($"[AdminFilter] Received key: {(string.IsNullOrEmpty(received) ? "(empty)" : received.Length > 2 ? received[..2] + "***" : "***")} | Config key (masked): {masked} | From: {(fromHeader != null ? "header" : fromQuery != null ? "query" : "none")}");

        if (string.IsNullOrEmpty(key) || key != expectedKey)
        {
            context.Result = new UnauthorizedResult();
        }
    }
}
