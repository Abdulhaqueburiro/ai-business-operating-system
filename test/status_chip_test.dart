import 'package:ai_business_os/app/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatusChip capitalises the status', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            StatusChip(status: 'pending'),
            StatusChip(status: 'confirmed'),
            StatusChip(status: 'cancelled'),
            StatusChip(status: 'udhaar'),
            StatusChip(status: ''),
          ],
        ),
      ),
    );
    expect(find.text('Pending'), findsOneWidget);
    expect(find.text('Confirmed'), findsOneWidget);
    expect(find.text('Cancelled'), findsOneWidget);
    expect(find.text('Udhaar'), findsOneWidget);
  });
}
