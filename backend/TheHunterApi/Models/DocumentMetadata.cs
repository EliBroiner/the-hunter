namespace TheHunterApi.Models;

/// <summary>מטא־דאטה מחולצת מהמסמך — שמות, מזהים, מיקומים (לא ב-tags)</summary>
public class DocumentMetadata
{
    public List<string> Names { get; set; } = new();
    public List<string> Ids { get; set; } = new();
    public List<string> Locations { get; set; } = new();
}
