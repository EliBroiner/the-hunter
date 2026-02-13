namespace TheHunterApi.Models;

public class GeminiRequest
{
    public List<GeminiContent> Contents { get; set; } = new();
    public GenerationConfig? GenerationConfig { get; set; }
}
