using Microsoft.AspNetCore.Mvc;

namespace TheHunterApi.Controllers;

/// <summary>
/// כניסת Admin — בלי פילטר. אם המפתח תקין, מגדיר cookie ומפנה ל-/admin.
/// </summary>
[Route("admin")]
public class AdminAuthController : Controller
{
    private readonly IConfiguration _config;
    private readonly ILogger<AdminAuthController> _logger;

    public AdminAuthController(IConfiguration config, ILogger<AdminAuthController> logger)
    {
        _config = config;
        _logger = logger;
    }

    /// <summary>
    /// GET /admin/login?key=XXX — אם המפתח תקין, מגדיר admin_session cookie ומפנה ל-/admin.
    /// </summary>
    [HttpGet("login")]
    public IActionResult Login([FromQuery] string? key)
    {
        var expectedKey = _config["Admin:Key"]
            ?? Environment.GetEnvironmentVariable("ADMIN_KEY")
            ?? "dev-admin-123";

        if (string.IsNullOrEmpty(key) || key != expectedKey)
        {
            _logger.LogWarning("Admin login failed: invalid or missing key");
            return Unauthorized();
        }

        var options = new CookieOptions
        {
            HttpOnly = true,
            Secure = Request.IsHttps,
            SameSite = SameSiteMode.Lax,
            Path = "/",
            MaxAge = TimeSpan.FromDays(7),
        };
        Response.Cookies.Append("admin_session", key, options);
        _logger.LogInformation("Admin session cookie set, redirecting to /admin");
        return Redirect("/admin");
    }

    /// <summary>
    /// GET /admin/logout — מוחק את ה-cookie ומפנה.
    /// </summary>
    [HttpGet("logout")]
    public IActionResult Logout()
    {
        Response.Cookies.Delete("admin_session", new CookieOptions { Path = "/" });
        _logger.LogInformation("Admin session cookie removed");
        return Redirect("/admin/login");
    }
}
