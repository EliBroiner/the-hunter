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

        if (string.IsNullOrEmpty(key) || key != expectedKey)
        {
            context.Result = new UnauthorizedResult();
        }
    }
}
