namespace TheHunterApi.Models;

/// <summary>הצעת אנקר מהפרומפט המאוחד — term, rank (STRONG/WEAK), reason.</summary>
public class DocumentSuggestion
{
    public string Term { get; set; } = string.Empty;
    public string Rank { get; set; } = string.Empty; // STRONG | WEAK
    public string Reason { get; set; } = string.Empty;
}
