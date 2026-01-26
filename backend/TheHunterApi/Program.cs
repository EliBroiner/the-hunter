var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

var port = Environment.GetEnvironmentVariable("PORT") ?? "8080";

app.MapGet("/", () => new { 
    status = "OK", 
    message = "The Hunter API is alive!",
    time = DateTime.UtcNow 
});

app.MapGet("/health", () => new { 
    status = "healthy" 
});

Console.WriteLine($"Starting on port {port}");
app.Run($"http://0.0.0.0:{port}");
