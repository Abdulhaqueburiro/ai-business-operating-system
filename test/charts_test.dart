import 'package:ai_business_os/app/animations.dart';
import 'package:ai_business_os/features/dashboard/presentation/dashboard_charts.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('CountUp ends on the final formatted value', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CountUp(value: 1200, format: (v) => 'PKR ${v.round()}'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('PKR 1200'), findsOneWidget);
  });

  testWidgets('FadeSlideIn shows its child', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: FadeSlideIn(
          delay: Duration(milliseconds: 100),
          child: Text('Hello'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hello'), findsOneWidget);
  });

  testWidgets('SalesBarChart draws with data and with all zeros',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SalesBarChart(
            values: [0, 100, 250, 0, 40, 0, 300],
            labels: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(SalesBarChart), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SalesBarChart(
            values: [0, 0, 0],
            labels: ['A', 'B', 'C'],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('DonutChart draws and shows its center', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: DonutChart(
            segments: [
              ChartSegment(label: 'Rent', value: 300, color: Colors.green),
              ChartSegment(label: 'Salary', value: 700, color: Colors.blue),
            ],
            center: Text('Total'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Total'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
