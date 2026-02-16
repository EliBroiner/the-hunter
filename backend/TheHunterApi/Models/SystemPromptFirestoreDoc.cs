namespace TheHunterApi.Models;

/// <summary>מסמך פרומפט מ-Firestore system_prompts.</summary>
public class SystemPromptFirestoreDoc
{
    public string Id { get; set; } = "";
    public string Feature { get; set; } = "";
    public string Version { get; set; } = "";
    public string Text { get; set; } = "";
    public bool IsActive { get; set; }
    public DateTime CreatedAt { get; set; }
}
