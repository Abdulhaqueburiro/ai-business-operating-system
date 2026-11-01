String _cell(Object? value) {
  if (value == null) return '';
  if (value is num) {
    return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
  }
  return value.toString().replaceAll(RegExp(r'[\t\r\n]+'), ' ');
}

String _row(List<Object?> cells) => cells.map(_cell).join('\t');

/// Builds tab-separated text of customers and what each one owes.
/// Pasting it into Excel or Google Sheets fills rows and columns.
/// A positive balance means the customer owes the shop; a negative balance
/// means the customer paid in advance.
String buildCustomersExport({
  required List<Map<String, dynamic>> customers,
  required Map<String, double> balances,
}) {
  final rows = customers.map((customer) {
    final id = customer['id'].toString();
    return (
      name: customer['name'],
      phone: customer['phone'],
      balance: balances[id] ?? 0.0,
    );
  }).toList()
    ..sort((a, b) => b.balance.compareTo(a.balance));

  final lines = <String>[
    _row(['Customer', 'Phone', 'Balance (PKR, positive = owes you)']),
  ];
  for (final r in rows) {
    lines.add(_row([r.name, r.phone, r.balance]));
  }
  return lines.join('\n');
}
