namespace TheHunterApi.Models;

/// <summary>תשובת שגיאה</summary>
public class ErrorResponse
{
    public string Error { get; set; } = string.Empty;
    public string? Details { get; set; }
}
