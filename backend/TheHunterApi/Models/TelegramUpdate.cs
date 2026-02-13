using System.Text.Json.Serialization;

namespace TheHunterApi.Models;

/// <summary>מודל ל-Telegram Update (webhook).</summary>
public class TelegramUpdate
{
    [JsonPropertyName("update_id")]
    public long UpdateId { get; set; }

    [JsonPropertyName("message")]
    public TelegramMessage? Message { get; set; }

    [JsonPropertyName("callback_query")]
    public TelegramCallbackQuery? CallbackQuery { get; set; }
}
