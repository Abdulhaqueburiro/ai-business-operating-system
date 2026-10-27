import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_business_os/features/dashboard/presentation/dashboard_summary_card.dart';
import 'package:ai_business_os/features/expenses/presentation/expenses_screen.dart';

void main() {
  testWidgets('dashboard card shows a safe error and no invented numbers', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: DashboardSummaryCard())),
    );
    await tester.pumpAndSettle();

    expect(find.text('This month at a glance'), findsOneWidget);
    expect(find.text('Could not load the dashboard.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('PKR'), findsNothing);
    expect(find.text('Confirmed sales'), findsNothing);
  });

  testWidgets('expenses screen shows a safe error and blocks add without a business', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExpensesScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Expenses'), findsOneWidget);
    expect(find.text('Could not load expenses.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    expect(find.textContaining('PKR'), findsNothing);

    await tester.tap(find.text('Add expense'));
    await tester.pump();

    expect(find.text('Business is not loaded. Refresh first.'), findsOneWidget);
    expect(find.text('Save expense'), findsNothing);
  });

  test('expense categories are the fixed list', () {
    expect(kExpenseCategories, [
      'Rent',
      'Salary',
      'Utilities',
      'Transport',
      'Supplies',
      'Marketing',
      'Other',
    ]);
  });
}
