namespace TheHunterApi.Models;

/// <summary>DTO לשמירת טיוטת פרומפט.</summary>
public class SavePromptRequest
{
    public string Feature { get; set; } = "";
    public string Content { get; set; } = "";
    public string Version { get; set; } = "";
    /// <summary>אם true — מיד מפעיל את הפרומפט (IsActive) לאחר השמירה.</summary>
    public bool SetActive { get; set; }
}
