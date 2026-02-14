using System.Text.Json.Serialization;

namespace TheHunterApi.Models;

public class TelegramMessage
{
    [JsonPropertyName("from")]
    public TelegramUser? From { get; set; }

    [JsonPropertyName("chat")]
    public TelegramChat? Chat { get; set; }

    [JsonPropertyName("text")]
    public string? Text { get; set; }
}
