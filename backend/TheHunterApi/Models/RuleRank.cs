namespace TheHunterApi.Models;

/// <summary>דירוג כלל — Strong דורס Weak, רק Weak → ambiguous (שליחה ל-AI).</summary>
public enum RuleRank
{
    Medium = 0,
    Strong = 1,
    Weak = 2,
}
