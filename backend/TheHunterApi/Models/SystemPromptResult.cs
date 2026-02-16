namespace TheHunterApi.Models;

/// <summary>תוצאת getLatestPrompt — טקסט, גרסה, האם fallback מוטבע.</summary>
public class SystemPromptResult
{
    public string Text { get; set; } = "";
    public string Version { get; set; } = "";
    public bool IsFallback { get; set; }
}
