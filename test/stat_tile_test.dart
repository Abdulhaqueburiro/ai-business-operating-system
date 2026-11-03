import 'package:ai_business_os/app/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('StatTile and InfoPill show their text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Column(
          children: [
            StatTile(
              icon: Icons.category_rounded,
              accent: Colors.green,
              label: 'Products',
              value: '12',
            ),
            InfoPill('Price 50.00'),
          ],
        ),
      ),
    );
    expect(find.text('12'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Price 50.00'), findsOneWidget);
  });
}
