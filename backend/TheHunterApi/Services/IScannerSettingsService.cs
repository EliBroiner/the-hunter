namespace TheHunterApi.Services;

/// <summary>
/// הגדרות סריקה דינמיות — נקרא מ-Firestore scanner_settings. שינויים ב-Admin מיושמים מיד.
/// </summary>
public interface IScannerSettingsService
{
    Task<double> GetGarbageThresholdPercentAsync();
    Task<int> GetMinMeaningfulLengthAsync();
    Task<double> GetMinValidCharRatioPercentAsync();
    Task<bool> GetCloudVisionFallbackEnabledAsync();
    Task SetGarbageThresholdPercentAsync(double value);
    Task SetMinMeaningfulLengthAsync(int value);
    Task SetMinValidCharRatioPercentAsync(double value);
    Task SetCloudVisionFallbackEnabledAsync(bool value);
}
