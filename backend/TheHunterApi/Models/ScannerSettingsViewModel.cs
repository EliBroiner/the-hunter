namespace TheHunterApi.Models;

/// <summary>הגדרות סריקה — garbageThresholdPercent, minMeaningfulLength, minValidCharRatioPercent.</summary>
public class ScannerSettingsViewModel
{
    public double GarbageThresholdPercent { get; set; } = 30;
    public int MinMeaningfulLength { get; set; } = 5;
    public double MinValidCharRatioPercent { get; set; } = 70;
    public bool CloudVisionFallbackEnabled { get; set; }
}
