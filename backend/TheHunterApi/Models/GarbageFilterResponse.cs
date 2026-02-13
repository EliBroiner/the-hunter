namespace TheHunterApi.Models;

public class GarbageFilterResponse
{
    public int TextLength { get; set; }
    public int GarbageCount { get; set; }
    public double GarbageRatioPercent { get; set; }
    public bool PassesThreshold { get; set; }
    public double ThresholdPercent { get; set; }
}
