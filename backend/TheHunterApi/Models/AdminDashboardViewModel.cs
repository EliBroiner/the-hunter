namespace TheHunterApi.Models;

/// <summary>
/// ViewModel ללוח הבקרה — מונחים ממתינים + הגדרות דירוג + חיפושים נפוצים + סטטוס בריאות
/// </summary>
public class AdminDashboardViewModel
{
    public List<LearnedTerm> PendingTerms { get; set; } = new();
    public Dictionary<string, double> RankingWeights { get; set; } = new();
    public List<SearchActivity> SearchActivities { get; set; } = new();
    public bool DatabaseOk { get; set; }
    public bool GeminiOk { get; set; }
    public bool FirebaseOk { get; set; }
    public IReadOnlyList<string> RecentErrors { get; set; } = new List<string>();
}
