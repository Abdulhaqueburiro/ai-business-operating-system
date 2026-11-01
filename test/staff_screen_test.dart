import 'package:ai_business_os/features/staff/business_role.dart';
import 'package:ai_business_os/features/staff/presentation/staff_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Staff screen reports a load error', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: StaffScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Staff'), findsOneWidget);
    expect(find.textContaining('Could not load'), findsOneWidget);
  });

  test('Only owners and admins count as managers', () {
    expect(isManagerRole('owner'), isTrue);
    expect(isManagerRole('admin'), isTrue);
    expect(isManagerRole('staff'), isFalse);
    expect(isManagerRole(null), isFalse);
  });
}
