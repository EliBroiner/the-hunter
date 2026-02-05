namespace TheHunterApi.Models;

/// <summary>
/// ViewModel ללוח הבקרה — מונחים ממתינים + הגדרות דירוג + חיפושים נפוצים
/// </summary>
public class AdminDashboardViewModel
{
    public List<LearnedTerm> PendingTerms { get; set; } = new();
    public Dictionary<string, double> RankingWeights { get; set; } = new();
    public List<SearchActivity> SearchActivities { get; set; } = new();
}
