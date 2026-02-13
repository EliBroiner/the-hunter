namespace TheHunterApi.Models;

public class OcrStepVisionResponse
{
    public string Text { get; set; } = "";
    public bool IsPureImageNoText { get; set; }
}
