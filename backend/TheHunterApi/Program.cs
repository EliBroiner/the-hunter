using Microsoft.EntityFrameworkCore;
using TheHunterApi.Data;
using TheHunterApi.Services;

var builder = WebApplication.CreateBuilder(args);

// קריאת PORT מ-environment variables (ברירת מחדל: 8080 עבור Cloud Run)
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";

// קריאת GEMINI_API_KEY מ-environment / user secrets / appsettings
var geminiApiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY")
    ?? builder.Configuration["GEMINI_API_KEY"]
    ?? "";
if (string.IsNullOrEmpty(geminiApiKey))
{
    Console.WriteLine("⚠️ WARNING: GEMINI_API_KEY is not set. AI search will not work.");
}

// הגדרת Services
builder.Services.AddControllers();
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

// רישום GeminiService ו-QuotaService
builder.Services.AddScoped<GeminiService>();
builder.Services.AddScoped<QuotaService>();

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

// יצירת DB אם לא קיים
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<IDbContextFactory<AppDbContext>>().CreateDbContext();
    await db.Database.EnsureCreatedAsync();
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
app.UseAuthorization();
app.MapControllers();

// Health check endpoint
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

Console.WriteLine($"🚀 The Hunter API is running on port {port}");
app.Run($"http://0.0.0.0:{port}");

/// <summary>
/// הגדרות Gemini API
/// </summary>
public class GeminiConfig
{
    public required string ApiKey { get; init; }
}
