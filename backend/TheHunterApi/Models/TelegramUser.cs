using System.Text.Json.Serialization;

namespace TheHunterApi.Models;

public class TelegramUser
{
    [JsonPropertyName("id")]
    public long Id { get; set; }
}
