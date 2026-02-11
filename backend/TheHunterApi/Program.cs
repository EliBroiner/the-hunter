using Google.Cloud.Firestore;
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
builder.Services.AddScoped<ISmartCategoriesService, SmartCategoriesService>();
builder.Services.AddScoped<AdminFirestoreService>();
builder.Services.AddScoped<ISystemPromptService, SystemPromptService>();
// EF Core — SQLite ל-SystemPrompts
builder.Services.AddDbContext<AppDbContext>(options =>
    options.UseSqlite(builder.Configuration.GetConnectionString("DefaultConnection") ?? "Data Source=thehunter.db"));

// Firestore — ל-LearningService (suggestions). אותו ProjectId כמו AdminFirestoreService
builder.Services.AddSingleton<FirestoreDb>(sp =>
{
    var config = sp.GetRequiredService<IConfiguration>();
    var projectId = config["FIRESTORE_PROJECT_ID"]
        ?? Environment.GetEnvironmentVariable("FIRESTORE_PROJECT_ID")
        ?? "thehunter-485508";
    return new FirestoreDbBuilder { ProjectId = projectId }.Build();
});
// Telegram: TELEGRAM_BOT_TOKEN ו-TELEGRAM_CHAT_ID נטענים מ-Environment / IConfiguration (ללא hardcode)
builder.Services.AddScoped<ITelegramService, TelegramService>();
builder.Services.AddScoped<INotificationService, NotificationService>();
builder.Services.AddHttpClient();
builder.Services.AddHostedService<DailySummaryHostedService>();

// פילטר אבטחה ל-Admin Dashboard
builder.Services.AddScoped<TheHunterApi.Filters.AdminKeyAuthorizationFilter>();

var app = builder.Build();

// החלת migrations על SQLite (יצירת DB אם לא קיים)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<AppDbContext>();
    db.Database.Migrate();
}

// לוג הפעלה — בודק טעינת Telegram מ-IConfiguration (ללא הדפסת הסוד)
var telegramToken = builder.Configuration["TELEGRAM_BOT_TOKEN"];
Log.Information("Server starting... Telegram integration enabled: {Enabled}", !string.IsNullOrEmpty(telegramToken));

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

// Deep Network Tracing — ראשון בצינור כדי לראות כל בקשה לפני Auth
app.UseMiddleware<RequestLoggingMiddleware>();
app.UseCors();
app.UseStaticFiles(); // לפני App Check — favicon וקבצים סטטיים לא דורשים אימות
app.UseMiddleware<GlobalExceptionMiddleware>();
app.UseMiddleware<FirebaseAppCheckMiddleware>();
app.UseAuthorization();
app.MapControllers();

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
