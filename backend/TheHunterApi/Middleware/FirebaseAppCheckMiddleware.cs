using System.IdentityModel.Tokens.Jwt;
using Microsoft.IdentityModel.Tokens;

namespace TheHunterApi.Middleware;

/// <summary>
/// Middleware לוולידציה של Firebase App Check token - וידוא שהבקשה מגיעה מאפליקציית Flutter שלנו
/// מופעל רק כשמוגדר FIREBASE_PROJECT_NUMBER
/// </summary>
public class FirebaseAppCheckMiddleware
{
    private readonly RequestDelegate _next;
    private readonly ILogger<FirebaseAppCheckMiddleware> _logger;
    private readonly IHttpClientFactory _httpClientFactory;
    private readonly string? _projectNumber;
    private readonly bool _enabled;

    // נתיבים שפטורים מ-App Check (health, swagger, root, admin)
    private static readonly HashSet<string> ExemptPaths = new(StringComparer.OrdinalIgnoreCase)
    {
        "/",
        "/health",
        "/swagger",
        "/swagger/index.html",
        "/swagger/v1/swagger.json",
        "/admin",
        "/admin/index"
    };

    public FirebaseAppCheckMiddleware(
        RequestDelegate next,
        ILogger<FirebaseAppCheckMiddleware> logger,
        IHttpClientFactory httpClientFactory)
    {
        _next = next;
        _logger = logger;
        _httpClientFactory = httpClientFactory;
        _projectNumber = Environment.GetEnvironmentVariable("FIREBASE_PROJECT_NUMBER");
        _enabled = !string.IsNullOrWhiteSpace(_projectNumber);
    }

    public async Task InvokeAsync(HttpContext context)
    {
        var path = context.Request.Path.Value ?? "";

        // נתיבים פטורים
        if (ExemptPaths.Contains(path) ||
            path.StartsWith("/swagger", StringComparison.OrdinalIgnoreCase) ||
            path.StartsWith("/admin", StringComparison.OrdinalIgnoreCase))
        {
            await _next(context);
            return;
        }

        if (!_enabled)
        {
            _logger.LogDebug("Firebase App Check כבוי - FIREBASE_PROJECT_NUMBER לא מוגדר");
            await _next(context);
            return;
        }

        var token = context.Request.Headers["X-Firebase-AppCheck"].FirstOrDefault();

        if (string.IsNullOrEmpty(token))
        {
            _logger.LogWarning("בקשה ללא X-Firebase-AppCheck header");
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "App Check token required" });
            return;
        }

        if (!await ValidateTokenAsync(token))
        {
            _logger.LogWarning("App Check token לא תקין");
            context.Response.StatusCode = 401;
            await context.Response.WriteAsJsonAsync(new { error = "Invalid App Check token" });
            return;
        }

        await _next(context);
    }

    private async Task<bool> ValidateTokenAsync(string token)
    {
        try
        {
            // שליפת מפתחות JWKS מ-Firebase App Check (לפי Firebase docs)
            var client = _httpClientFactory.CreateClient();
            var jwksJson = await client.GetStringAsync("https://firebaseappcheck.googleapis.com/v1/jwks");
            var jwks = JsonWebKeySet.Create(jwksJson);

            var validationParams = new TokenValidationParameters
            {
                ValidateIssuer = true,
                ValidIssuer = $"https://firebaseappcheck.googleapis.com/{_projectNumber}",
                ValidateAudience = true,
                ValidAudiences = new[] { $"projects/{_projectNumber}" },
                ValidateLifetime = true,
                ClockSkew = TimeSpan.FromMinutes(1),
                IssuerSigningKeys = jwks.GetSigningKeys(),
                ValidateIssuerSigningKey = true
            };

            var handler = new JwtSecurityTokenHandler();
            handler.ValidateToken(token, validationParams, out _);
            return true;
        }
        catch (Exception ex)
        {
            _logger.LogDebug(ex, "כשלון ולידציה של App Check token");
            return false;
        }
    }
}
