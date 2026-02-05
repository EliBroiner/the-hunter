namespace TheHunterApi.Models;

/// <summary>
/// סטטיסטיקת חיפושים — מונחים שחיפשו המשתמשים (לסיוע בהחלטה אילו synonyms להוסיף)
/// </summary>
public class SearchActivity
{
    public int Id { get; set; }
    public string Term { get; set; } = string.Empty;
    public int Count { get; set; }
    public DateTime LastSearch { get; set; }
}
