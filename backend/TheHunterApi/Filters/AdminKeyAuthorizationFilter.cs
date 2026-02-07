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
        var expectedKey = _config["Admin:Key"]
            ?? Environment.GetEnvironmentVariable("ADMIN_KEY")
            ?? "dev-admin-123";

        // סדר עדיפות: cookie (admin_session) → header → query
        var key = context.HttpContext.Request.Cookies["admin_session"]
            ?? context.HttpContext.Request.Headers["X-Admin-Key"].FirstOrDefault()
            ?? context.HttpContext.Request.Query["key"].FirstOrDefault();

        var from = key != null
            ? (context.HttpContext.Request.Cookies["admin_session"] != null ? "cookie" : context.HttpContext.Request.Headers["X-Admin-Key"].FirstOrDefault() != null ? "header" : "query")
            : "none";
        var path = context.HttpContext.Request.Path.Value ?? "";
        Console.WriteLine($"[AdminFilter] DEBUG: Request for {path}. Key provided: {!string.IsNullOrEmpty(key)}, source: {from}");

        if (string.IsNullOrEmpty(key) || key != expectedKey)
        {
            Console.WriteLine($"[AdminFilter] DEBUG: Unauthorized - key missing or invalid for {path}");
            context.Result = new UnauthorizedResult();
            return;
        }
        Console.WriteLine($"[AdminFilter] DEBUG: API Request authorized for {path}. Key from: {from}");
    }
}
