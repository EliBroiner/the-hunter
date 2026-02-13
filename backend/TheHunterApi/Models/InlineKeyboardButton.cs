using Newtonsoft.Json;

namespace TheHunterApi.Models;

public class InlineKeyboardButton
{
    [JsonProperty("text")]
    public string Text { get; set; } = string.Empty;

    [JsonProperty("url", NullValueHandling = NullValueHandling.Ignore)]
    public string? Url { get; set; }

    [JsonProperty("callback_data", NullValueHandling = NullValueHandling.Ignore)]
    public string? CallbackData { get; set; }
}
