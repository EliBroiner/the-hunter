namespace TheHunterApi.Models;

/// <summary>נתוני File X-Ray — חילוץ מלא לדיבאג PII ו־Cloud Vision.</summary>
public class FileXRayData
{
    public string DocumentId { get; set; } = "";
    public string Filename { get; set; } = "";
    public string? ProcessingChain { get; set; }
    public string RawText { get; set; } = "";
    public string? CleanedText { get; set; }
    public string? OcrSource { get; set; }
    public List<string> Tags { get; set; } = new();
    public string? Category { get; set; }
}
