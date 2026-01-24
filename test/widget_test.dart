import 'package:flutter_test/flutter_test.dart';

import 'package:the_hunter/main.dart';

void main() {
  testWidgets('TheHunter app smoke test', (WidgetTester tester) async {
    // בדיקה בסיסית שהאפליקציה נטענת
    await tester.pumpWidget(const TheHunterApp());

    // מוודא שהכותרת מופיעה במסך החיפוש
    expect(find.text('The Hunter'), findsOneWidget);
    
    // מוודא שניווט תחתון קיים
    expect(find.text('חיפוש'), findsOneWidget);
    expect(find.text('סריקה'), findsOneWidget);
  });
}
