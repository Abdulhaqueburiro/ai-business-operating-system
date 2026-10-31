import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _money(num value) => 'PKR ${value.toStringAsFixed(2)}';

String _qty(num value) =>
    value % 1 == 0 ? value.toInt().toString() : value.toStringAsFixed(2);

String _dateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Today's date in Pakistan time (UTC+5, no daylight saving).
DateTime _pakistanToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5));
  return DateTime.utc(now.year, now.month, now.day);
}

enum _Range { today, last7, thisMonth, last30 }

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  _Range _range = _Range.thisMonth;
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _report;

  @override
  void initState() {
    super.initState();
    _load();
  }

  (DateTime, DateTime) _dates() {
    final today = _pakistanToday();
    switch (_range) {
      case _Range.today:
        return (today, today);
      case _Range.last7:
        return (today.subtract(const Duration(days: 6)), today);
      case _Range.thisMonth:
        return (DateTime.utc(today.year, today.month, 1), today);
      case _Range.last30:
        return (today.subtract(const Duration(days: 29)), today);
    }
  }

  String _rangeLabel(_Range range) {
    switch (range) {
      case _Range.today:
        return 'Today';
      case _Range.last7:
        return 'Last 7 days';
      case _Range.thisMonth:
        return 'This month';
      case _Range.last30:
        return 'Last 30 days';
    }
  }

  Future<String> _getActiveBusinessId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Please log in first.');

    final rows = await _client
        .from('business_members')
        .select('business_id')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .limit(1);

    if (rows.isEmpty) {
      throw Exception('No active business membership found.');
    }

    return rows.first['business_id'].toString();
  }

  Future<void> _load() async {
    final requested = _range;

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final businessId = await _getActiveBusinessId();
      final (from, to) = _dates();

      final data = await _client.rpc(
        'get_sales_report',
        params: {
          'p_business_id': businessId,
          'p_from': _dateText(from),
          'p_to': _dateText(to),
        },
      );

      if (!mounted || requested != _range) return;

      setState(() {
        _report = Map<String, dynamic>.from(data as Map);
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted || requested != _range) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || requested != _range) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  num _num(String key) => (_report?[key] as num?) ?? 0;

  List<Map<String, dynamic>> _list(String key) {
    final raw = _report?[key];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Widget _tile(String label, String value, {String? note, Color? color}) {
    return SizedBox(
      width: 220,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelMedium),
              const SizedBox(height: 4),
              Text(
                value,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: color, fontWeight: FontWeight.w600),
              ),
              if (note != null) ...[
                const SizedBox(height: 2),
                Text(note, style: Theme.of(context).textTheme.bodySmall),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String title, List<Widget> children, {String? empty}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 20),
        Text(title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        if (children.isEmpty)
          Text(empty ?? 'Nothing to show for this period.')
        else
          ...children,
      ],
    );
  }

  Widget _dayRow(Map<String, dynamic> day, num maxSales) {
    final sales = (day['sales'] as num?) ?? 0;
    final orders = (day['orders'] as num?) ?? 0;
    final fraction = maxSales <= 0 ? 0.0 : (sales / maxSales).clamp(0.0, 1.0);
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          SizedBox(
            width: 92,
            child: Text(day['date']?.toString() ?? ''),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.toDouble(),
                minHeight: 10,
                backgroundColor: colors.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 140,
            child: Text(
              '${_money(sales)} (${_qty(orders)})',
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReport() {
    final colors = Theme.of(context).colorScheme;
    final net = _num('net_profit');
    final missing = _num('items_missing_cost').toInt();
    final days = _list('by_day');
    final maxSales = days.fold<num>(
      0,
      (m, d) => ((d['sales'] as num?) ?? 0) > m ? (d['sales'] as num) : m,
    );
    final products = _list('top_products');
    final customers = _list('top_customers');
    final categories = _list('expenses_by_category');
    final (from, to) = _dates();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_dateText(from)} to ${_dateText(to)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _tile('Sales', _money(_num('sales')),
                note: '${_num('orders').toInt()} confirmed orders'),
            _tile('Cost of goods', _money(_num('cost_of_goods'))),
            _tile('Gross profit', _money(_num('gross_profit'))),
            _tile('Expenses', _money(_num('expenses'))),
            _tile(
              'Net profit',
              _money(net),
              note: 'Gross profit minus expenses',
              color: net < 0 ? colors.error : null,
            ),
          ],
        ),
        if (missing > 0) ...[
          const SizedBox(height: 12),
          Text(
            '$missing sold item(s) have no cost price, so profit leaves '
            'them out. Add cost prices in Products.',
            style: TextStyle(color: colors.error),
          ),
        ],
        _section(
          'Sales by day',
          [for (final day in days) _dayRow(day, maxSales)],
        ),
        _section(
          'Top products',
          [
            for (final p in products)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(p['name']?.toString() ?? ''),
                subtitle: Text(
                  '${_qty((p['quantity'] as num?) ?? 0)} ${p['unit'] ?? ''} sold',
                ),
                trailing: Text(_money((p['sales'] as num?) ?? 0)),
              ),
          ],
          empty: 'No sales in this period.',
        ),
        _section(
          'Top customers',
          [
            for (final c in customers)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(c['name']?.toString() ?? ''),
                subtitle: Text('${_qty((c['orders'] as num?) ?? 0)} order(s)'),
                trailing: Text(_money((c['sales'] as num?) ?? 0)),
              ),
          ],
          empty: 'No sales to saved customers in this period.',
        ),
        _section(
          'Expenses by category',
          [
            for (final c in categories)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(c['category']?.toString() ?? ''),
                trailing: Text(_money((c['amount'] as num?) ?? 0)),
              ),
          ],
          empty: 'No expenses in this period.',
        ),
        const SizedBox(height: 16),
        Text(
          'Numbers come from your database. Only confirmed orders count as '
          'sales. Dates follow Pakistan time.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reports'),
        actions: [
          IconButton(
            tooltip: 'Refresh report',
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final range in _Range.values)
                ChoiceChip(
                  label: Text(_rangeLabel(range)),
                  selected: _range == range,
                  onSelected: (_) {
                    if (_range == range) return;
                    setState(() => _range = range);
                    _load();
                  },
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            Column(
              children: [
                const Icon(Icons.error_outline, size: 40),
                const SizedBox(height: 12),
                const Text('Could not load the report.'),
                const SizedBox(height: 8),
                SelectableText(_error!),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: _load,
                  child: const Text('Try again'),
                ),
              ],
            )
          else if (_report != null)
            _buildReport(),
        ],
      ),
    );
  }
}
