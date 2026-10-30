import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _money(num value) {
  final negative = value < 0;
  final parts = value.abs().toStringAsFixed(2).split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return '${negative ? '-' : ''}PKR ${buffer.toString()}.${parts[1]}';
}

String _qty(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

class DashboardSummaryCard extends StatefulWidget {
  const DashboardSummaryCard({super.key});

  @override
  State<DashboardSummaryCard> createState() => _DashboardSummaryCardState();
}

class _DashboardSummaryCardState extends State<DashboardSummaryCard> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final client = Supabase.instance.client;
      final user = client.auth.currentUser;
      if (user == null) throw Exception('Please log in first.');

      final memberships = await client
          .from('business_members')
          .select('business_id')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .limit(1);

      if (memberships.isEmpty) {
        throw Exception('No active business membership found.');
      }

      final businessId = memberships.first['business_id'].toString();

      final result = await client.rpc(
        'get_dashboard_summary',
        params: {'p_business_id': businessId},
      );

      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(result as Map);
        _loading = false;
      });
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  num _num(String key) => (_data?[key] as num?) ?? 0;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'This month at a glance',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: 'Refresh dashboard',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Could not load the dashboard.',
                    style: TextStyle(color: colors.error),
                  ),
                  const SizedBox(height: 4),
                  SelectableText(_error!),
                  TextButton(onPressed: _load, child: const Text('Retry')),
                ],
              )
            else
              _buildSummary(context),
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final netProfit = _num('net_profit');
    final missingCost = _num('items_missing_cost').toInt();
    final lowItems = (_data?['low_stock_items'] as List?) ?? const [];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricTile(
              label: 'Confirmed sales',
              value: _money(_num('confirmed_sales')),
              note: '${_num('confirmed_orders').toInt()} confirmed orders',
            ),
            _MetricTile(
              label: 'Expenses',
              value: _money(_num('expenses')),
              note: 'Recorded this month',
            ),
            _MetricTile(
              label: 'Cost of goods',
              value: _money(_num('cost_of_goods')),
              note: 'Cost of items sold',
            ),
            _MetricTile(
              label: 'Gross profit',
              value: _money(_num('gross_profit')),
              note: 'Sales minus cost of goods',
            ),
            _MetricTile(
              label: 'Net profit',
              value: _money(netProfit),
              note: 'Gross profit minus expenses',
              valueColor: netProfit < 0 ? colors.error : null,
            ),
            _MetricTile(
              label: 'Udhaar to collect',
              value: _money(_num('receivable')),
              note: 'Owed by customers',
            ),
            _MetricTile(
              label: 'Pending orders',
              value: _num('pending_orders').toInt().toString(),
              note: 'Waiting to be confirmed',
            ),
            _MetricTile(
              label: 'Low stock',
              value: _num('low_stock_count').toInt().toString(),
              note: 'At or below the alert level',
              valueColor: _num('low_stock_count') > 0 ? colors.error : null,
            ),
          ],
        ),
        if (missingCost > 0) ...[
          const SizedBox(height: 12),
          Text(
            '$missingCost sold item(s) have no cost price, so profit leaves '
            'them out. Add cost prices in Products.',
            style: TextStyle(color: colors.error),
          ),
        ],
        if (lowItems.isNotEmpty) ...[
          const SizedBox(height: 12),
          Text(
            'Running low',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const SizedBox(height: 4),
          for (final item in lowItems)
            if (item is Map)
              Text(
                '${item['name']}: ${_qty((item['quantity'] as num?) ?? 0)} '
                '${item['unit']} (alert at '
                '${_qty((item['threshold'] as num?) ?? 5)})',
              ),
        ],
        const SizedBox(height: 12),
        Text(
          'Numbers come from your database. Only confirmed orders count as '
          'sales. Month follows Pakistan time.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.label,
    required this.value,
    required this.note,
    this.valueColor,
  });

  final String label;
  final String value;
  final String note;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: 200,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelMedium),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: valueColor,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            note,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
