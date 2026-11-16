import 'package:ai_business_os/app/app_theme.dart';
import 'package:ai_business_os/app/responsive.dart';
import 'package:ai_business_os/features/alerts/assistant_panel.dart';
import 'package:ai_business_os/features/alerts/stock_alerts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(StockAlerts.instance.clear);

  test('fromSummary reads items and skips bad ones', () {
    final list = StockAlerts.fromSummary([
      {'name': 'Cheeni', 'quantity': 0, 'unit': 'kg', 'threshold': 10},
      {'name': 'Chawal', 'quantity': 3, 'unit': 'kg', 'threshold': 5},
      'not a map',
    ]);
    expect(list.length, 2);
    expect(list.first.isOut, isTrue);
    expect(list.last.isOut, isFalse);
    expect(StockAlerts.fromSummary(null), isEmpty);
  });

  test('out of stock comes first and dismissed alerts are hidden', () {
    StockAlerts.instance.update(const [
      StockAlert(name: 'Chawal', quantity: 3, unit: 'kg', threshold: 5),
      StockAlert(name: 'Cheeni', quantity: 0, unit: 'kg', threshold: 10),
    ]);
    expect(StockAlerts.instance.active.first.name, 'Cheeni');

    StockAlerts.instance.dismiss(StockAlerts.instance.active.first);
    expect(StockAlerts.instance.active.length, 1);

    // After a restock the product leaves the list, so it can alert again.
    StockAlerts.instance.update(const []);
    StockAlerts.instance.update(const [
      StockAlert(name: 'Cheeni', quantity: 0, unit: 'kg', threshold: 10),
    ]);
    expect(StockAlerts.instance.active.length, 1);
  });

  test('wide breakpoint', () {
    expect(isWideWidth(390), isFalse);
    expect(isWideWidth(720), isTrue);
  });

  testWidgets('bell shows the count and the sheet lists the alerts', (
    tester,
  ) async {
    var addStockTapped = false;
    StockAlerts.instance.update(const [
      StockAlert(name: 'Cheeni', quantity: 0, unit: 'kg', threshold: 10),
      StockAlert(name: 'Chawal', quantity: 3, unit: 'kg', threshold: 5),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(
            child: AlertBell(onAddStock: () => addStockTapped = true),
          ),
        ),
      ),
    );
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Cheeni is out of stock: 0 kg left'), findsOneWidget);
    expect(find.text('Chawal is low: only 3 kg left'), findsOneWidget);

    await tester.tap(find.text('Dismiss').first);
    await tester.pumpAndSettle();
    expect(find.text('Cheeni is out of stock: 0 kg left'), findsNothing);

    await tester.tap(find.text('Add stock').first);
    await tester.pumpAndSettle();
    expect(addStockTapped, isTrue);
  });

  testWidgets('empty alerts say everything is healthy', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Center(child: AlertBell(onAddStock: () {})),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Notifications'));
    await tester.pumpAndSettle();
    expect(find.text('All stock levels are healthy.'), findsOneWidget);
  });

  testWidgets('assistant panel opens the chat with the question', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(
          body: SingleChildScrollView(child: AssistantPanel()),
        ),
      ),
    );
    expect(find.text('Ask your business'), findsOneWidget);
    expect(find.text('Kuch bhi poochein...'), findsOneWidget);

    await tester.tap(find.text('Is mahine kitna profit hua?'));
    await tester.pumpAndSettle();

    expect(find.text('AI assistant'), findsOneWidget);
    expect(find.textContaining('Could not reach the assistant'), findsOneWidget);
  });
}
