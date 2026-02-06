using Microsoft.EntityFrameworkCore;
using Serilog;
using TheHunterApi.Data;
using TheHunterApi.Middleware;
using TheHunterApi.Services;

// לוגר גלובלי — קונסול + קובץ יומי בתיקיית logs
Log.Logger = new LoggerConfiguration()
    .WriteTo.Console()
    .WriteTo.File("logs/log-.txt", rollingInterval: RollingInterval.Day)
    .CreateLogger();

var builder = WebApplication.CreateBuilder(args);
builder.Host.UseSerilog();

// קריאת PORT מ-environment variables (ברירת מחדל: 8080 עבור Cloud Run)
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";

// קריאת GEMINI_API_KEY מ-environment / user secrets / appsettings
var geminiApiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY")
    ?? builder.Configuration["GEMINI_API_KEY"]
    ?? "";
if (string.IsNullOrEmpty(geminiApiKey))
{
    Log.Warning("GEMINI_API_KEY is not set. AI search will not work.");
}

// הגדרת Services
builder.Services.AddControllersWithViews();
builder.Services.AddEndpointsApiExplorer();
builder.Services.AddSwaggerGen(options =>
{
    options.SwaggerDoc("v1", new() 
    { 
        Title = "The Hunter API", 
        Version = "v1",
        Description = "Backend API for The Hunter mobile app - AI-powered file search"
    });
});

// הגדרת CORS - מאפשר כל origin (לפיתוח ו-mobile apps)
builder.Services.AddCors(options =>
{
    options.AddDefaultPolicy(policy =>
    {
        policy.AllowAnyOrigin()
              .AllowAnyMethod()
              .AllowAnyHeader();
    });
});

// רישום HttpClient עבור Gemini API
builder.Services.AddHttpClient("GeminiApi", client =>
{
    client.BaseAddress = new Uri("https://generativelanguage.googleapis.com/");
    client.DefaultRequestHeaders.Add("Accept", "application/json");
});

// רישום GeminiConfig כ-Singleton
builder.Services.AddSingleton(new GeminiConfig { ApiKey = geminiApiKey });

// רישום GeminiService, QuotaService ו-LearningService
builder.Services.AddScoped<GeminiService>();
builder.Services.AddScoped<QuotaService>();
builder.Services.AddScoped<UserRoleService>();
builder.Services.AddScoped<ILearningService, LearningService>();
builder.Services.AddScoped<ISearchActivityService, SearchActivityService>();

// פילטר אבטחה ל-Admin Dashboard
builder.Services.AddScoped<TheHunterApi.Filters.AdminKeyAuthorizationFilter>();

// SQLite - מכסת AI
var dbPath = Path.Combine(
    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
    "the-hunter",
    "usage.db");
var dbDir = Path.GetDirectoryName(dbPath);
if (!string.IsNullOrEmpty(dbDir)) Directory.CreateDirectory(dbDir);
builder.Services.AddDbContextFactory<AppDbContext>(opts =>
    opts.UseSqlite($"Data Source={dbPath}"));

var app = builder.Build();

// יצירת DB והרצת migrations
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<IDbContextFactory<AppDbContext>>().CreateDbContext();
    await db.Database.MigrateAsync();

    // Bootstrap: Admin ראשון לפי INITIAL_ADMIN_EMAIL (UserId ריק — יתקשר בהתחברות הראשונה)
    var initialEmail = Environment.GetEnvironmentVariable("INITIAL_ADMIN_EMAIL")
        ?? builder.Configuration["INITIAL_ADMIN_EMAIL"];
    if (!string.IsNullOrWhiteSpace(initialEmail) && !await db.AppManagedUsers.AnyAsync())
    {
        var now = DateTime.UtcNow;
        db.AppManagedUsers.Add(new AppManagedUser
        {
            Email = initialEmail.Trim(),
            UserId = "",
            Role = "Admin",
            CreatedAt = now,
            UpdatedAt = now,
        });
        await db.SaveChangesAsync();
        Log.Information("Bootstrap: Admin ראשון נוצר עבור {Email}", initialEmail);
    }
}

// Root endpoint
app.MapGet("/", () => new { 
    status = "OK", 
    message = "The Hunter API is running!",
    version = "1.0",
    time = DateTime.UtcNow 
});

// Swagger UI
app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/swagger/v1/swagger.json", "The Hunter API v1");
    options.RoutePrefix = "swagger";
});

app.UseCors();
app.UseMiddleware<GlobalExceptionMiddleware>();
app.UseMiddleware<FirebaseAppCheckMiddleware>();
app.UseAuthorization();
app.MapControllers();

// הוספת נתיב views
app.UseStaticFiles();

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

try
{
    Log.Information("🚀 Starting Web API...");
    app.Run($"http://0.0.0.0:{port}");
}
catch (Exception ex)
{
    Log.Fatal(ex, "💥 Host terminated unexpectedly");
}
finally
{
    Log.CloseAndFlush();
}

/// <summary>
/// הגדרות Gemini API
/// </summary>
public class GeminiConfig
{
    public required string ApiKey { get; init; }
}
