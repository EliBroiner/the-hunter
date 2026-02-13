namespace TheHunterApi.Models;

/// <summary>DTO לשמירת טיוטת פרומפט.</summary>
public class SavePromptRequest
{
    public string Feature { get; set; } = "";
    public string Content { get; set; } = "";
    public string Version { get; set; } = "";
}
