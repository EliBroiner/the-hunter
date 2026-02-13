using Newtonsoft.Json;

namespace TheHunterApi.Models;

/// <summary>מודל ל-InlineKeyboardMarkup של Telegram Bot API.</summary>
public class InlineKeyboardMarkup
{
    [JsonProperty("inline_keyboard")]
    public List<List<InlineKeyboardButton>> InlineKeyboard { get; set; } = new();
}
