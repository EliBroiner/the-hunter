namespace TheHunterApi.Models;

/// <summary>
/// הגדרת משקל דירוג — מאפשר שינוי דינמי של משקלי החיפוש מהשרת
/// </summary>
public class RankingSetting
{
    public string Key { get; set; } = string.Empty;
    public double Value { get; set; }
}
