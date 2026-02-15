/// דירוג כלל — Strong דורס Weak, רק Weak → ambiguous (שליחה ל-AI).
enum RuleRank {
  medium,
  strong,
  weak,
}

extension RuleRankExt on RuleRank {
  static RuleRank fromString(String? s) {
    if (s == null) return RuleRank.medium;
    switch (s.toLowerCase()) {
      case 'strong':
        return RuleRank.strong;
      case 'weak':
        return RuleRank.weak;
      default:
        return RuleRank.medium;
    }
  }
}
