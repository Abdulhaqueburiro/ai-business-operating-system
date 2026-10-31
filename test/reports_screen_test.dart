import 'package:ai_business_os/features/reports/presentation/reports_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Reports screen shows range chips and a load error', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ReportsScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Last 7 days'), findsOneWidget);
    expect(find.text('This month'), findsOneWidget);
    expect(find.text('Last 30 days'), findsOneWidget);
    expect(find.text('Could not load the report.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
