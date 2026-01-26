var builder = WebApplication.CreateBuilder(args);

// קריאת PORT מ-environment variables (ברירת מחדל: 8080 עבור Cloud Run)
var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";

// קריאת GEMINI_API_KEY מ-environment variables (אופציונלי - יתריע אם חסר)
var geminiApiKey = Environment.GetEnvironmentVariable("GEMINI_API_KEY") ?? "";
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

// שמירת ה-API key ב-Configuration לשימוש ב-Controllers
builder.Services.AddSingleton(new GeminiConfig { ApiKey = geminiApiKey });

var app = builder.Build();
app.MapGet("/", () => new { 
    status = "Alive", 
    message = "The Hunter API is running!", 
    time = DateTime.UtcNow 
});

// Swagger UI בנתיב /swagger
app.UseSwagger();
app.UseSwaggerUI(options =>
{
    options.SwaggerEndpoint("/swagger/v1/swagger.json", "The Hunter API v1");
    options.RoutePrefix = "swagger"; // Swagger בנתיב /swagger
});

app.UseCors();
app.UseAuthorization();
app.MapControllers();

// Health check endpoint עבור Cloud Run
app.MapGet("/health", () => Results.Ok(new { status = "healthy", timestamp = DateTime.UtcNow }));

Console.WriteLine($"🚀 The Hunter API is running on port {port}");
// הקשבה לכל הכתובות (0.0.0.0) בפורט הנכון - קריטי לענן!
app.Run($"http://0.0.0.0:{port}");

/// <summary>
/// הגדרות Gemini API
/// </summary>
public class GeminiConfig
{
    public required string ApiKey { get; init; }
}
