import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ai_business_os/features/customers/presentation/customers_screen.dart';

void main() {
  testWidgets('customers screen shows a safe error and blocks add without a business', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: CustomersScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Customers'), findsOneWidget);
    expect(find.text('Could not load customers.'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.tap(find.text('Add customer'));
    await tester.pump();

    expect(find.text('Business is not loaded. Refresh first.'), findsOneWidget);
    expect(find.text('Save customer'), findsNothing);
  });
}
