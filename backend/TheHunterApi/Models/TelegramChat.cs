using System.Text.Json.Serialization;

namespace TheHunterApi.Models;

public class TelegramChat
{
    [JsonPropertyName("id")]
    public long Id { get; set; }
}
