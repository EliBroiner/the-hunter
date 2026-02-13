using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace TheHunterApi.Filters;

/// <summary>
/// פילטר אבטחה ל-Admin Dashboard - בודק AdminKey מתוך header או query
/// </summary>
public class AdminKeyAuthorizationFilter : IAuthorizationFilter
{
    private readonly IConfiguration _config;
    private readonly ILogger<AdminKeyAuthorizationFilter> _logger;

    public AdminKeyAuthorizationFilter(IConfiguration config, ILogger<AdminKeyAuthorizationFilter> logger)
    {
        _config = config;
        _logger = logger;
    }

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var expectedKey = _config["Admin:Key"]
            ?? Environment.GetEnvironmentVariable("ADMIN__KEY")
            ?? "dev-admin-123";

        // סדר עדיפות: cookie (admin_session) → header → query
        var key = context.HttpContext.Request.Cookies["admin_session"]
            ?? context.HttpContext.Request.Headers["X-Admin-Key"].FirstOrDefault()
            ?? context.HttpContext.Request.Query["key"].FirstOrDefault();

        var from = key != null
            ? (context.HttpContext.Request.Cookies["admin_session"] != null ? "cookie" : context.HttpContext.Request.Headers["X-Admin-Key"].FirstOrDefault() != null ? "header" : "query")
            : "none";
        var path = context.HttpContext.Request.Path.Value ?? "";
        _logger.LogDebug("[AdminFilter] Request for {Path}. Key provided: {HasKey}, source: {From}", path, !string.IsNullOrEmpty(key), from);

        if (string.IsNullOrEmpty(key) || key != expectedKey)
        {
            _logger.LogDebug("[AdminFilter] Unauthorized - key missing or invalid for {Path}", path);
            context.Result = new UnauthorizedResult();
            return;
        }
        _logger.LogDebug("[AdminFilter] API Request authorized for {Path}. Key from: {From}", path, from);
    }
}
