import 'package:ai_business_os/app/app_theme.dart';
import 'package:ai_business_os/app/stat_tile.dart';
import 'package:flutter/material.dart';

/// One product that is running low or is out of stock.
class StockAlert {
  const StockAlert({
    required this.name,
    required this.quantity,
    required this.unit,
    required this.threshold,
  });

  final String name;
  final num quantity;
  final String unit;
  final num threshold;

  bool get isOut => quantity <= 0;
}

String _qty(num value) =>
    value == value.roundToDouble() ? value.toInt().toString() : value.toString();

/// The owner's low-stock alerts. The Home dashboard fills this from the
/// database numbers; the bell and the banner only show it.
class StockAlerts extends ChangeNotifier {
  StockAlerts._();

  static final StockAlerts instance = StockAlerts._();

  List<StockAlert> _all = const [];
  final Set<String> _dismissed = <String>{};

  /// Alerts that have not been dismissed. Out of stock comes first.
  List<StockAlert> get active {
    final list = [
      for (final a in _all)
        if (!_dismissed.contains(a.name)) a,
    ];
    list.sort((a, b) {
      if (a.isOut == b.isOut) return a.name.compareTo(b.name);
      return a.isOut ? -1 : 1;
    });
    return list;
  }

  static List<StockAlert> fromSummary(Object? raw) {
    if (raw is! List) return const [];
    final result = <StockAlert>[];
    for (final item in raw) {
      if (item is! Map) continue;
      result.add(
        StockAlert(
          name: item['name']?.toString() ?? '',
          quantity: (item['quantity'] as num?) ?? 0,
          unit: item['unit']?.toString() ?? '',
          threshold: (item['threshold'] as num?) ?? 5,
        ),
      );
    }
    return result;
  }

  void update(List<StockAlert> alerts) {
    _all = alerts;
    // A product that was restocked can alert again later.
    _dismissed.removeWhere((name) => !alerts.any((a) => a.name == name));
    notifyListeners();
  }

  void dismiss(StockAlert alert) {
    _dismissed.add(alert.name);
    notifyListeners();
  }

  void dismissAll() {
    for (final a in _all) {
      _dismissed.add(a.name);
    }
    notifyListeners();
  }

  void clear() {
    _all = const [];
    _dismissed.clear();
    notifyListeners();
  }
}

/// A bell with a red number for the alerts that are waiting.
class AlertBell extends StatelessWidget {
  const AlertBell({super.key, required this.onAddStock});

  /// Called when the owner taps "Add stock" on an alert.
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: StockAlerts.instance,
      builder: (context, _) {
        final count = StockAlerts.instance.active.length;

        return Tooltip(
          message: 'Notifications',
          child: Material(
            color: colors.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(color: colors.outlineVariant),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => showStockAlerts(context, onAddStock: onAddStock),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    const Icon(Icons.notifications_none_rounded),
                    if (count > 0)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          constraints: const BoxConstraints(
                            minWidth: 18,
                            minHeight: 18,
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: colors.error,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              color: colors.onError,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Opens the list of alerts from the bottom of the screen.
Future<void> showStockAlerts(
  BuildContext context, {
  required VoidCallback onAddStock,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (sheetContext) => _StockAlertsSheet(
      onAddStock: () {
        Navigator.of(sheetContext).pop();
        onAddStock();
      },
    ),
  );
}

class _StockAlertsSheet extends StatelessWidget {
  const _StockAlertsSheet({required this.onAddStock});

  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return ListenableBuilder(
      listenable: StockAlerts.instance,
      builder: (context, _) {
        final alerts = StockAlerts.instance.active;

        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.85,
            ),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 10,
                        runSpacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Notifications',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          if (alerts.isNotEmpty)
                            InfoPill(
                              '${alerts.length} new',
                              color: colors.error,
                            ),
                        ],
                      ),
                    ),
                    if (alerts.isNotEmpty)
                      TextButton(
                        onPressed: StockAlerts.instance.dismissAll,
                        child: const Text('Dismiss all'),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Low-stock alerts for your business',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                if (alerts.isEmpty)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 28,
                        horizontal: 20,
                      ),
                      child: Column(
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: colors.primary.withValues(alpha: 0.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.verified_user_outlined,
                              color: colors.primary,
                              size: 30,
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            'All stock levels are healthy.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'We will alert you when something runs low.',
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  for (final alert in alerts)
                    _AlertCard(alert: alert, onAddStock: onAddStock),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AlertCard extends StatelessWidget {
  const _AlertCard({required this.alert, required this.onAddStock});

  final StockAlert alert;
  final VoidCallback onAddStock;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final amber = dark ? AppColors.darkWarning : AppColors.attention;
    final tone = alert.isOut ? colors.error : amber;
    final title = alert.isOut
        ? '${alert.name} is out of stock: 0 ${alert.unit} left'
        : '${alert.name} is low: only ${_qty(alert.quantity)} ${alert.unit} left';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    alert.isOut
                        ? Icons.inventory_2_outlined
                        : Icons.warning_amber_rounded,
                    color: tone,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Alert level ${_qty(alert.threshold)} ${alert.unit}',
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                InfoPill(alert.isOut ? 'Out' : 'Low', color: tone),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onAddStock,
                    icon: const Icon(Icons.add),
                    label: const Text('Add stock'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: () => StockAlerts.instance.dismiss(alert),
                  child: const Text('Dismiss'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
