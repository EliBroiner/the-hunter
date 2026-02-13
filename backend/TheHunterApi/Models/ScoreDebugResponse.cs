namespace TheHunterApi.Models;

public class ScoreDebugResponse
{
    public string Query { get; set; } = "";
    public List<string> Terms { get; set; } = [];
    public double FilenameScore { get; set; }
    public double ContentScore { get; set; }
    public double MetadataScore { get; set; }
    public double TotalScore { get; set; }
    public string Breakdown { get; set; } = "";
}
