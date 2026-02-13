namespace TheHunterApi.Models;

public class GenerationConfig
{
    public double Temperature { get; set; }
    public int MaxOutputTokens { get; set; }
    public string? ResponseMimeType { get; set; }
}
