namespace TheHunterApi.Models;

public class ScoreDebugRequest
{
    public string Query { get; set; } = "";
    public string? Filename { get; set; }
    public string? Content { get; set; }
    public string? Metadata { get; set; }
}
