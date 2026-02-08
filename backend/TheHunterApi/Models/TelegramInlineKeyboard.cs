using Newtonsoft.Json;

namespace TheHunterApi.Models;

/// <summary>
/// מודל ל-InlineKeyboardMarkup של Telegram Bot API.
/// </summary>
public class InlineKeyboardMarkup
{
    [JsonProperty("inline_keyboard")]
    public List<List<InlineKeyboardButton>> InlineKeyboard { get; set; } = new();
}

public class InlineKeyboardButton
{
    [JsonProperty("text")]
    public string Text { get; set; } = string.Empty;

    [JsonProperty("url", NullValueHandling = NullValueHandling.Ignore)]
    public string? Url { get; set; }

    [JsonProperty("callback_data", NullValueHandling = NullValueHandling.Ignore)]
    public string? CallbackData { get; set; }
}
