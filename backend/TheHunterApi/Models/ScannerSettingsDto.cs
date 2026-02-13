namespace TheHunterApi.Models;

public class ScannerSettingsDto
{
    public double? GarbageThresholdPercent { get; set; }
    public int? MinMeaningfulLength { get; set; }
    public double? MinValidCharRatioPercent { get; set; }
    public bool? CloudVisionFallbackEnabled { get; set; }
}
