String _cell(Object? value) {
  if (value == null) return '';
  if (value is num) {
    return value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);
  }
  return value.toString().replaceAll(RegExp(r'[\t\r\n]+'), ' ');
}

String _row(List<Object?> cells) => cells.map(_cell).join('\t');

/// Builds tab-separated text from a get_sales_report result. Pasting it into
/// Excel or Google Sheets fills rows and columns, and amounts stay numbers.
String buildReportExport({
  required String fromDate,
  required String toDate,
  required Map<String, dynamic> report,
}) {
  num number(String key) => (report[key] as num?) ?? 0;

  List<Map<dynamic, dynamic>> list(String key) {
    final raw = report[key];
    if (raw is! List) return const [];
    return raw.whereType<Map<dynamic, dynamic>>().toList();
  }

  final lines = <String>[
    _row(['Report', fromDate, 'to', toDate]),
    '',
    _row(['Summary (PKR)', 'Amount']),
    _row(['Sales', number('sales')]),
    _row(['Confirmed orders', number('orders')]),
    _row(['Cost of goods', number('cost_of_goods')]),
    _row(['Gross profit', number('gross_profit')]),
    _row(['Expenses', number('expenses')]),
    _row(['Net profit', number('net_profit')]),
    _row(['Sold items without cost price', number('items_missing_cost')]),
    '',
    _row(['Sales by day']),
    _row(['Date', 'Sales (PKR)', 'Orders']),
  ];

  for (final d in list('by_day')) {
    lines.add(_row([d['date'], d['sales'], d['orders']]));
  }

  lines
    ..add('')
    ..add(_row(['Top products']))
    ..add(_row(['Product', 'Unit', 'Quantity sold', 'Sales (PKR)']));
  for (final p in list('top_products')) {
    lines.add(_row([p['name'], p['unit'], p['quantity'], p['sales']]));
  }

  lines
    ..add('')
    ..add(_row(['Top customers']))
    ..add(_row(['Customer', 'Orders', 'Sales (PKR)']));
  for (final c in list('top_customers')) {
    lines.add(_row([c['name'], c['orders'], c['sales']]));
  }

  lines
    ..add('')
    ..add(_row(['Expenses by category']))
    ..add(_row(['Category', 'Amount (PKR)']));
  for (final c in list('expenses_by_category')) {
    lines.add(_row([c['category'], c['amount']]));
  }

  return lines.join('\n');
}
