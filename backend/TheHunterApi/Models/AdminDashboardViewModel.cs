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
    public int TotalUsers { get; set; }
    public int PendingTermsCount { get; set; }
    public int ApprovedTermsCount { get; set; }
    public Dictionary<string, int> NewTermsPerDay { get; set; } = new();
    /// <summary>כשלונות Meaningful Text — 10 אחרונים לדיבאג ב-AI Lab.</summary>
    public List<ScanFailure> ScanFailures { get; set; } = new();
    /// <summary>הגדרות סריקה — garbageThresholdPercent, minMeaningfulLength, minValidCharRatioPercent.</summary>
    public ScannerSettingsViewModel? ScannerSettings { get; set; }
}

public class ScannerSettingsViewModel
{
    public double GarbageThresholdPercent { get; set; } = 30;
    public int MinMeaningfulLength { get; set; } = 5;
    public double MinValidCharRatioPercent { get; set; } = 70;
    public bool CloudVisionFallbackEnabled { get; set; }
}
