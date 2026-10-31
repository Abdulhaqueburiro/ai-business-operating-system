import 'package:ai_business_os/features/assistant/presentation/assistant_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Assistant screen shows examples and reports a connection error',
      (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: AssistantScreen()));
    await tester.pumpAndSettle();

    expect(find.text('AI assistant'), findsOneWidget);
    expect(find.text('Type your question'), findsOneWidget);
    expect(find.text('Is mahine kitna profit hua?'), findsOneWidget);

    await tester.tap(find.text('Is mahine kitna profit hua?'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the assistant'), findsOneWidget);
  });
}
