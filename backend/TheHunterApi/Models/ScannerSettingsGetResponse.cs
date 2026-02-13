namespace TheHunterApi.Models;

/// <summary>תשובת GET — כולל metadata לכל פרמטר (עריכה / מקור).</summary>
public class ScannerSettingsGetResponse
{
    public required ScannerSettingItem GarbageThresholdPercent { get; set; }
    public required ScannerSettingItem MinMeaningfulLength { get; set; }
    public required ScannerSettingItem MinValidCharRatioPercent { get; set; }
    public required ScannerSettingItem CloudVisionFallbackEnabled { get; set; }
}
