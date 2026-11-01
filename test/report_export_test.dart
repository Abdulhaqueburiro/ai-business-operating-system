import 'package:ai_business_os/features/reports/presentation/report_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Report export builds tab separated rows for Excel', () {
    final text = buildReportExport(
      fromDate: '2026-10-01',
      toDate: '2026-10-31',
      report: {
        'sales': 1500,
        'orders': 3,
        'cost_of_goods': 900.5,
        'gross_profit': 599.5,
        'expenses': 100,
        'net_profit': 499.5,
        'items_missing_cost': 0,
        'by_day': [
          {'date': '2026-10-30', 'sales': 1000, 'orders': 2},
        ],
        'top_products': [
          {'name': 'Tea\tPack', 'unit': 'pcs', 'quantity': 4, 'sales': 800},
        ],
        'top_customers': [],
        'expenses_by_category': [
          {'category': 'Rent', 'amount': 100},
        ],
      },
    );

    final lines = text.split('\n');
    expect(lines.first, 'Report\t2026-10-01\tto\t2026-10-31');
    expect(lines, contains('Sales\t1500'));
    expect(lines, contains('Cost of goods\t900.50'));
    expect(lines, contains('Net profit\t499.50'));
    expect(lines, contains('2026-10-30\t1000\t2'));
    expect(lines, contains('Tea Pack\tpcs\t4\t800'));
    expect(lines, contains('Rent\t100'));
    expect(text.contains('\r'), isFalse);
  });
}
