/// בודק תבנית Regex מול טקסט — מטפל ב־FormatException מתבניות לא תקינות (למשל מ-AI).
class RegexTester {
  RegexTester._();

  /// מחזיר true רק אם התבנית תקינה והטקסט תואם. מחזיר false אם Regex לא תקין.
  static bool test(String pattern, String input) {
    try {
      return RegExp(pattern).hasMatch(input);
    } on FormatException {
      return false;
    }
  }
}
