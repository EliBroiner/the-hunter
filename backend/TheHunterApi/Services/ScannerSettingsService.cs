namespace TheHunterApi.Services;

/// <summary>
/// מחזיר הגדרות סריקה מ-Firestore scanner_settings. ברירות מחדל אם חסר.
/// </summary>
public class ScannerSettingsService : IScannerSettingsService
{
    private const string KeyGarbageThreshold = "garbageThresholdPercent";
    private const string KeyMinMeaningfulLength = "minMeaningfulLength";
    private const string KeyMinValidCharRatio = "minValidCharRatioPercent";
    private const string KeyCloudVisionFallback = "cloudVisionFallbackEnabled";

    private const double DefaultGarbageThreshold = 30;
    private const int DefaultMinMeaningfulLength = 5;
    private const double DefaultMinValidCharRatio = 70;

    private readonly AdminFirestoreService _firestore;

    public ScannerSettingsService(AdminFirestoreService firestore) => _firestore = firestore;

    public async Task<double> GetGarbageThresholdPercentAsync()
    {
        var d = await _firestore.GetScannerSettingsAsync();
        return d.TryGetValue(KeyGarbageThreshold, out var v) ? v : DefaultGarbageThreshold;
    }

    public async Task<int> GetMinMeaningfulLengthAsync()
    {
        var d = await _firestore.GetScannerSettingsAsync();
        if (!d.TryGetValue(KeyMinMeaningfulLength, out var v)) return DefaultMinMeaningfulLength;
        return (int)Math.Clamp(v, 1, 100);
    }

    public async Task<double> GetMinValidCharRatioPercentAsync()
    {
        var d = await _firestore.GetScannerSettingsAsync();
        return d.TryGetValue(KeyMinValidCharRatio, out var v) ? v : DefaultMinValidCharRatio;
    }

    public Task SetGarbageThresholdPercentAsync(double value) =>
        _firestore.SetScannerSettingAsync(KeyGarbageThreshold, Math.Clamp(value, 0, 100));

    public Task SetMinMeaningfulLengthAsync(int value) =>
        _firestore.SetScannerSettingAsync(KeyMinMeaningfulLength, Math.Clamp(value, 1, 100));

    public Task SetMinValidCharRatioPercentAsync(double value) =>
        _firestore.SetScannerSettingAsync(KeyMinValidCharRatio, Math.Clamp(value, 0, 100));

    public async Task<bool> GetCloudVisionFallbackEnabledAsync()
    {
        var d = await _firestore.GetScannerSettingsAsync();
        return d.TryGetValue(KeyCloudVisionFallback, out var v) && v >= 0.5;
    }

    public Task SetCloudVisionFallbackEnabledAsync(bool value) =>
        _firestore.SetScannerSettingAsync(KeyCloudVisionFallback, value ? 1.0 : 0.0);
}
