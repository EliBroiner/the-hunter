using System.Text.Json.Serialization;

namespace TheHunterApi.Models;

public class TelegramCallbackQuery
{
    [JsonPropertyName("id")]
    public string Id { get; set; } = string.Empty;

    [JsonPropertyName("from")]
    public TelegramUser? From { get; set; }

    [JsonPropertyName("data")]
    public string? Data { get; set; }

    [JsonPropertyName("message")]
    public TelegramMessage? Message { get; set; }
}
