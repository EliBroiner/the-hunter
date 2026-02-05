namespace TheHunterApi.Models;

/// <summary>
/// מונח שנלמד מ-AI - לולאת למידה לשיפור מילון החיפוש
/// </summary>
public class LearnedTerm
{
    public int Id { get; set; }
    public string Term { get; set; } = string.Empty;
    public string Category { get; set; } = string.Empty;
    public int Frequency { get; set; } = 1;
    public bool IsApproved { get; set; }
    public DateTime LastSeen { get; set; }
}
