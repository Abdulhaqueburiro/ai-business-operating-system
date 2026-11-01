import 'package:ai_business_os/features/customers/presentation/customers_export.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Customers export lists balances, biggest udhaar first', () {
    final text = buildCustomersExport(
      customers: [
        {'id': 'a', 'name': 'Ali', 'phone': '0300'},
        {'id': 'b', 'name': 'Bilal\tTraders', 'phone': null},
        {'id': 'c', 'name': 'Sara', 'phone': '0311'},
      ],
      balances: {'a': 500.0, 'b': 1250.5, 'c': -100.0},
    );

    final lines = text.split('\n');
    expect(lines.first,
        'Customer\tPhone\tBalance (PKR, positive = owes you)');
    expect(lines[1], 'Bilal Traders\t\t1250.50');
    expect(lines[2], 'Ali\t0300\t500');
    expect(lines[3], 'Sara\t0311\t-100');
    expect(lines.length, 4);
  });

  test('Customer without a balance shows 0', () {
    final text = buildCustomersExport(
      customers: [
        {'id': 'x', 'name': 'New customer', 'phone': ''},
      ],
      balances: {},
    );
    expect(text.split('\n')[1], 'New customer\t\t0');
  });
}
