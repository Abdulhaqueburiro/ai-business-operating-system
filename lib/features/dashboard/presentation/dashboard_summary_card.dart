import 'package:ai_business_os/app/animations.dart';
import 'package:ai_business_os/app/app_theme.dart';
import 'package:ai_business_os/features/dashboard/presentation/dashboard_charts.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _money(num value) {
  final negative = value < 0;
  final whole = value.abs() == value.abs().roundToDouble();
  final parts = value.abs().toStringAsFixed(whole ? 0 : 2).split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final cents = parts.length > 1 ? '.${parts[1]}' : '';
  return '${negative ? '-' : ''}PKR ${buffer.toString()}$cents';
}

String _whole(double value) => value.round().toString();

String _qty(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

String _dateText(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Today's date in Pakistan time (UTC+5, no daylight saving).
DateTime _pakistanToday() {
  final now = DateTime.now().toUtc().add(const Duration(hours: 5));
  return DateTime.utc(now.year, now.month, now.day);
}

bool _isDark(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark;

Color _attention(BuildContext context) =>
    _isDark(context) ? const Color(0xFFE8B15A) : AppColors.attention;

Color _success(BuildContext context) =>
    _isDark(context) ? const Color(0xFF5FD39A) : AppColors.success;

Color _goodOrBad(BuildContext context, num value) {
  if (value < 0) return Theme.of(context).colorScheme.error;
  return _success(context);
}

const List<String> _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class DashboardSummaryCard extends StatefulWidget {
  const DashboardSummaryCard({super.key});

  @override
  State<DashboardSummaryCard> createState() => _DashboardSummaryCardState();
}

class _DashboardSummaryCardState extends State<DashboardSummaryCard> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _data;
  List<Map<String, dynamic>> _week = const [];
  List<Map<String, dynamic>> _categories = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<Map<String, dynamic>> _asList(Object? raw) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
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

      var week = <Map<String, dynamic>>[];
      var categories = <Map<String, dynamic>>[];
      try {
        final today = _pakistanToday();
        final weekReport = await client.rpc(
          'get_sales_report',
          params: {
            'p_business_id': businessId,
            'p_from': _dateText(today.subtract(const Duration(days: 6))),
            'p_to': _dateText(today),
          },
        );
        week = _asList((weekReport as Map)['by_day']);

        final monthReport = await client.rpc(
          'get_sales_report',
          params: {
            'p_business_id': businessId,
            'p_from': _dateText(DateTime.utc(today.year, today.month, 1)),
            'p_to': _dateText(today),
          },
        );
        categories = _asList((monthReport as Map)['expenses_by_category']);
      } catch (_) {
        // The charts are optional. The numbers above them still show.
      }

      if (!mounted) return;
      setState(() {
        _data = Map<String, dynamic>.from(result as Map);
        _week = week;
        _categories = categories;
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'This month at a glance',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(
              tooltip: 'Refresh dashboard',
              onPressed: _loading ? null : _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_loading)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          )
        else if (_error != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
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
              ),
            ),
          )
        else
          _buildSummary(context),
      ],
    );
  }

  Widget _buildHero(BuildContext context) {
    final netProfit = _num('net_profit');
    final colors = Theme.of(context).colorScheme;
    final isLoss = netProfit < 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF1B7A62), AppColors.primary, Color(0xFF0E4034)],
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.paid_rounded, color: Colors.white70, size: 20),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Net profit this month',
                  style: TextStyle(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLoss
                      ? colors.error.withValues(alpha: 0.9)
                      : Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  isLoss ? 'Loss' : 'Profit',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          CountUp(
            value: netProfit.toDouble(),
            format: _money,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 34,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _heroStat(
                  Icons.trending_up_rounded,
                  'Sales',
                  _money(_num('confirmed_sales')),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _heroStat(
                  Icons.receipt_long_rounded,
                  'Expenses',
                  _money(_num('expenses')),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _heroStat(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekChart(BuildContext context) {
    final values = [
      for (final d in _week) ((d['sales'] as num?) ?? 0).toDouble(),
    ];
    final labels = [
      for (final d in _week)
        () {
          final parsed = DateTime.tryParse(d['date']?.toString() ?? '');
          return parsed == null ? '' : _weekdays[parsed.weekday - 1];
        }(),
    ];
    final total = values.fold<double>(0, (a, b) => a + b);

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
                    'Sales, last 7 days',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                Text(
                  _money(total),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SalesBarChart(values: values, labels: labels),
          ],
        ),
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    final palette = <Color>[
      AppColors.primary,
      const Color(0xFF2B6CB0),
      AppColors.attention,
      const Color(0xFF7C3AED),
      const Color(0xFF0E9AA7),
      const Color(0xFFD9534F),
      const Color(0xFF6B7C75),
    ];

    final segments = <ChartSegment>[];
    for (var i = 0; i < _categories.length; i++) {
      final c = _categories[i];
      segments.add(
        ChartSegment(
          label: c['category']?.toString() ?? '',
          value: ((c['amount'] as num?) ?? 0).toDouble(),
          color: palette[i % palette.length],
        ),
      );
    }
    final total = segments.fold<double>(0, (a, s) => a + s.value);
    if (total <= 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Where the money went',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                DonutChart(
                  segments: segments,
                  size: 130,
                  center: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Expenses',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      Text(
                        _money(total),
                        style: Theme.of(context)
                            .textTheme
                            .labelLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      for (final s in segments)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              Container(
                                width: 10,
                                height: 10,
                                decoration: BoxDecoration(
                                  color: s.color,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  s.label,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Text(
                                '${(s.value / total * 100).round()}%',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
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
    final grossProfit = _num('gross_profit');
    final receivable = _num('receivable');
    final pending = _num('pending_orders').toInt();
    final lowCount = _num('low_stock_count').toInt();
    const step = Duration(milliseconds: 70);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FadeSlideIn(child: _buildHero(context)),
        if (_week.isNotEmpty) ...[
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: step,
            child: _buildWeekChart(context),
          ),
        ],
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final tileWidth = (constraints.maxWidth - 12) / 2;

            final tiles = <_MetricTile>[
              _MetricTile(
                width: tileWidth,
                icon: Icons.trending_up_rounded,
                accent: colors.primary,
                label: 'Confirmed sales',
                number: _num('confirmed_sales').toDouble(),
                format: _money,
                note: '${_num('confirmed_orders').toInt()} confirmed orders',
              ),
              _MetricTile(
                width: tileWidth,
                icon: Icons.receipt_long_rounded,
                accent: _attention(context),
                label: 'Expenses',
                number: _num('expenses').toDouble(),
                format: _money,
                note: 'Recorded this month',
              ),
              _MetricTile(
                width: tileWidth,
                icon: Icons.inventory_2_rounded,
                accent: colors.onSurfaceVariant,
                label: 'Cost of goods',
                number: _num('cost_of_goods').toDouble(),
                format: _money,
                note: 'Cost of items sold',
              ),
              _MetricTile(
                width: tileWidth,
                icon: Icons.savings_rounded,
                accent: _goodOrBad(context, grossProfit),
                label: 'Gross profit',
                number: grossProfit.toDouble(),
                format: _money,
                note: 'Sales minus cost of goods',
                valueColor: _goodOrBad(context, grossProfit),
              ),
              _MetricTile(
                width: tileWidth,
                icon: Icons.account_balance_wallet_rounded,
                accent: _attention(context),
                label: 'Udhaar to collect',
                number: receivable.toDouble(),
                format: _money,
                note: 'Owed by customers',
                valueColor: receivable > 0 ? _attention(context) : null,
              ),
              _MetricTile(
                width: tileWidth,
                icon: Icons.pending_actions_rounded,
                accent: _attention(context),
                label: 'Pending orders',
                number: pending.toDouble(),
                format: _whole,
                note: 'Waiting to be confirmed',
                valueColor: pending > 0 ? _attention(context) : null,
              ),
              _MetricTile(
                width: tileWidth,
                icon: Icons.warning_amber_rounded,
                accent: lowCount > 0 ? colors.error : colors.onSurfaceVariant,
                label: 'Low stock',
                number: lowCount.toDouble(),
                format: _whole,
                note: 'At or below the alert level',
                valueColor: lowCount > 0 ? colors.error : null,
              ),
              _MetricTile(
                width: tileWidth,
                icon: Icons.paid_rounded,
                accent: _goodOrBad(context, netProfit),
                label: 'Net profit',
                number: netProfit.toDouble(),
                format: _money,
                note: 'Gross profit minus expenses',
                valueColor: _goodOrBad(context, netProfit),
              ),
            ];

            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (var i = 0; i < tiles.length; i++)
                  FadeSlideIn(
                    delay: step * (i + 2),
                    child: tiles[i],
                  ),
              ],
            );
          },
        ),
        if (_categories.isNotEmpty) ...[
          const SizedBox(height: 14),
          FadeSlideIn(
            delay: step * 10,
            child: _buildCategories(context),
          ),
        ],
        if (missingCost > 0) ...[
          const SizedBox(height: 12),
          Text(
            '$missingCost sold item(s) have no cost price, so profit leaves '
            'them out. Add cost prices in Products.',
            style: TextStyle(color: colors.error),
          ),
        ],
        if (lowItems.isNotEmpty) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: _attention(context)),
              const SizedBox(width: 8),
              Text(
                'Running low',
                style: Theme.of(context)
                    .textTheme
                    .titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final item in lowItems)
                if (item is Map)
                  Chip(
                    avatar: Icon(
                      Icons.inventory_2_rounded,
                      size: 16,
                      color: _attention(context),
                    ),
                    label: Text(
                      '${item['name']}: ${_qty((item['quantity'] as num?) ?? 0)} '
                      '${item['unit']} (alert at '
                      '${_qty((item['threshold'] as num?) ?? 5)})',
                    ),
                  ),
            ],
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
    required this.width,
    required this.icon,
    required this.accent,
    required this.label,
    required this.number,
    required this.format,
    required this.note,
    this.valueColor,
  });

  final double width;
  final IconData icon;
  final Color accent;
  final String label;
  final double number;
  final String Function(double value) format;
  final String note;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      width: width,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          CountUp(
            value: number,
            format: format,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
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
