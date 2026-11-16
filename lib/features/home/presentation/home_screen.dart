import 'package:ai_business_os/app/animations.dart';
import 'package:ai_business_os/app/app_theme.dart';
import 'package:ai_business_os/app/responsive.dart';
import 'package:ai_business_os/app/shell_scope.dart';
import 'package:ai_business_os/app/stat_tile.dart';
import 'package:ai_business_os/app/user_info.dart';
import 'package:ai_business_os/features/alerts/assistant_panel.dart';
import 'package:ai_business_os/features/alerts/stock_alerts.dart';
import 'package:ai_business_os/features/assistant/presentation/assistant_screen.dart';
import 'package:ai_business_os/features/business/business_info.dart';
import 'package:ai_business_os/features/customers/presentation/customers_screen.dart';
import 'package:ai_business_os/features/dashboard/presentation/dashboard_summary_card.dart';
import 'package:ai_business_os/features/expenses/presentation/expenses_screen.dart';
import 'package:ai_business_os/features/inventory/presentation/inventory_screen.dart';
import 'package:ai_business_os/features/orders/presentation/orders_screen.dart';
import 'package:ai_business_os/features/products/presentation/products_screen.dart';
import 'package:ai_business_os/features/reports/presentation/reports_screen.dart';
import 'package:ai_business_os/features/staff/business_role.dart';
import 'package:ai_business_os/features/staff/presentation/staff_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

String _money(num value) {
  final whole = value.abs() == value.abs().roundToDouble();
  final text = value.abs().toStringAsFixed(whole ? 0 : 2);
  final parts = text.split('.');
  final digits = parts[0];
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  final cents = parts.length > 1 ? '.${parts[1]}' : '';
  return 'PKR ${buffer.toString()}$cents';
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String? _role;
  String? _businessName;
  Map<String, dynamic>? _summary;
  int? _productCount;
  bool _bannerDismissed = false;

  bool get _isManager => isManagerRole(_role);

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final role = await loadMyRole();
    final name = await loadBusinessName();
    if (!mounted) return;
    setState(() {
      _role = role;
      _businessName = name;
    });
    if (isManagerRole(role)) _loadProductCount();
  }

  Future<void> _loadProductCount() async {
    try {
      final rows = await Supabase.instance.client
          .from('products')
          .select('id')
          .eq('is_active', true);
      if (!mounted) return;
      setState(() => _productCount = rows.length);
    } catch (_) {
      // The count is only a small extra. The card still works without it.
    }
  }

  void _onSummary(Map<String, dynamic> summary) {
    StockAlerts.instance.update(
      StockAlerts.fromSummary(summary['low_stock_items']),
    );
    if (!mounted) return;
    setState(() => _summary = summary);
  }

  void _push(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  /// Switch to a tab of the main frame, or open the screen on its own when
  /// there is no frame around (for example in a test).
  void _goTab(int index, Widget fallback) {
    final scope = ShellScope.maybeOf(context);
    if (scope != null) {
      scope.selectTab(index);
    } else {
      _push(fallback);
    }
  }

  void _openAlerts() {
    showStockAlerts(
      context,
      onAddStock: () => _goTab(2, const InventoryScreen()),
    );
  }

  num _n(String key) => (_summary?[key] as num?) ?? 0;

  // ---------- header ----------

  Widget _greeting(BuildContext context, {required bool trailing}) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;
    final name = currentFirstName();
    final business = _businessName;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assalam-o-alaikum',
                style: textTheme.bodySmall?.copyWith(
                  color: colors.onSurfaceVariant,
                ),
              ),
              Row(
                children: [
                  Flexible(
                    child: Text(
                      name == null ? 'Hello' : 'Hello, $name',
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (_role != null && !_isManager) ...[
                    const SizedBox(width: 10),
                    const InfoPill('Staff', color: Color(0xFF2B6CB0)),
                  ],
                ],
              ),
              if (business != null)
                Text(
                  business,
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
        if (trailing) ...[
          AlertBell(onAddStock: () => _goTab(2, const InventoryScreen())),
          const SizedBox(width: 10),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: () => ShellScope.maybeOf(context)?.selectTab(4),
            child: const UserAvatar(size: 44),
          ),
        ],
      ],
    );
  }

  List<Widget> _actionTiles() {
    final tiles = <_ActionTile>[
      _ActionTile(
        icon: Icons.add_rounded,
        label: 'New order',
        primary: true,
        onTap: () => _goTab(1, const OrdersScreen()),
      ),
      _ActionTile(
        icon: Icons.payments_outlined,
        label: 'Record payment',
        onTap: () => _goTab(3, const CustomersScreen()),
      ),
      if (_isManager)
        _ActionTile(
          icon: Icons.sell_outlined,
          label: 'Add product',
            onTap: () => _push(const ProductsScreen()),
        )
      else
        _ActionTile(
          icon: Icons.inventory_2_outlined,
          label: 'Stock In',
            onTap: () => _goTab(2, const InventoryScreen()),
        ),
    ];
    return tiles;
  }

  Widget _actionRow() {
    final tiles = _actionTiles();
    return Row(
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: tiles[i]),
        ],
      ],
    );
  }

  // ---------- alert banner ----------

  String _names(List<StockAlert> list) {
    final names = [for (final a in list) a.name];
    if (names.length <= 2) return names.join(' and ');
    return '${names.take(2).join(', ')} +${names.length - 2}';
  }

  Widget _banner(BuildContext context) {
    return ListenableBuilder(
      listenable: StockAlerts.instance,
      builder: (context, _) {
        final alerts = StockAlerts.instance.active;
        if (alerts.isEmpty || _bannerDismissed) return const SizedBox.shrink();

        final dark = Theme.of(context).brightness == Brightness.dark;
        final amber = dark ? AppColors.darkWarning : AppColors.attention;
        final out = [for (final a in alerts) if (a.isOut) a];
        final low = [for (final a in alerts) if (!a.isOut) a];
        final detail = [
          if (out.isNotEmpty)
            '${_names(out)} ${out.length == 1 ? 'is' : 'are'} out.',
          if (low.isNotEmpty)
            '${_names(low)} ${low.length == 1 ? 'is' : 'are'} low.',
        ].join(' ');
        final title = alerts.length == 1
            ? '1 item needs restocking'
            : '${alerts.length} items need restocking';

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Material(
            color: amber.withValues(alpha: 0.12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: amber.withValues(alpha: 0.35)),
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: _openAlerts,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_rounded, color: amber),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            style: TextStyle(
                              color: amber,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            detail,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    if (isWide(context))
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: amber,
                          foregroundColor: dark ? Colors.black : Colors.white,
                          minimumSize: const Size(64, 40),
                        ),
                        onPressed: () => _goTab(2, const InventoryScreen()),
                        child: const Text('Add stock'),
                      ),
                    IconButton(
                      tooltip: 'Hide',
                      onPressed: () => setState(() => _bannerDismissed = true),
                      icon: const Icon(Icons.close_rounded, size: 20),
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

  // ---------- "Your business" cards ----------

  List<_Area> _managerAreas() {
    final pending = _n('pending_orders').toInt();
    final low = _n('low_stock_count').toInt();
    final receivable = _n('receivable');
    final hasSummary = _summary != null;

    return [
      _Area(
        icon: Icons.shopping_bag_outlined,
        accent: const Color(0xFF145C4A),
        title: 'Orders',
        subtitle: 'Sales and udhaar',
        pill: hasSummary ? '$pending pending' : null,
        pillColor: pending > 0 ? const Color(0xFFA15C08) : null,
        onTap: () => _goTab(1, const OrdersScreen()),
      ),
      _Area(
        icon: Icons.inventory_2_outlined,
        accent: const Color(0xFFA15C08),
        title: 'Stock',
        subtitle: 'Stock in and out',
        pill: hasSummary ? (low > 0 ? '$low low' : 'All good') : null,
        pillColor: low > 0 ? const Color(0xFFB4232F) : const Color(0xFF18794E),
        onTap: () => _goTab(2, const InventoryScreen()),
      ),
      _Area(
        icon: Icons.people_alt_outlined,
        accent: const Color(0xFF2B6CB0),
        title: 'Customers',
        subtitle: 'Udhaar and payments',
        pill: hasSummary
            ? (receivable > 0 ? '${_money(receivable)} udhaar' : 'No udhaar')
            : null,
        pillColor: receivable > 0 ? const Color(0xFFA15C08) : null,
        onTap: () => _goTab(3, const CustomersScreen()),
      ),
      _Area(
        icon: Icons.sell_outlined,
        accent: const Color(0xFFC2417A),
        title: 'Products',
        subtitle: 'Prices and alert levels',
        pill: _productCount == null ? null : '$_productCount items',
        onTap: () => _push(const ProductsScreen()),
      ),
      _Area(
        icon: Icons.bar_chart_rounded,
        accent: const Color(0xFF0E8F9A),
        title: 'Reports',
        subtitle: 'Sales and profit',
        pill: 'This month',
        pillColor: const Color(0xFF18794E),
        onTap: () => _push(const ReportsScreen()),
      ),
      _Area(
        icon: Icons.account_balance_wallet_outlined,
        accent: const Color(0xFFB4232F),
        title: 'Expenses',
        subtitle: 'Rent, salary, bills',
        pill: hasSummary ? _money(_n('expenses')) : null,
        onTap: () => _push(const ExpensesScreen()),
      ),
      _Area(
        icon: Icons.auto_awesome_rounded,
        accent: const Color(0xFF7C3AED),
        title: 'AI assistant',
        subtitle: 'Ask in Urdu or English',
        pill: 'Ask now',
        pillColor: const Color(0xFF7C3AED),
        onTap: () => _push(const AssistantScreen()),
      ),
      _Area(
        icon: Icons.badge_outlined,
        accent: const Color(0xFF5B6B65),
        title: 'Staff',
        subtitle: 'Who can use the app',
        onTap: () => _push(const StaffScreen()),
      ),
    ];
  }

  List<_Area> _staffAreas() {
    return [
      _Area(
        icon: Icons.shopping_bag_outlined,
        accent: const Color(0xFF145C4A),
        title: 'Orders',
        subtitle: 'Sales and udhaar',
        onTap: () => _goTab(1, const OrdersScreen()),
      ),
      _Area(
        icon: Icons.inventory_2_outlined,
        accent: const Color(0xFFA15C08),
        title: 'Stock',
        subtitle: 'Stock in and out',
        onTap: () => _goTab(2, const InventoryScreen()),
      ),
      _Area(
        icon: Icons.people_alt_outlined,
        accent: const Color(0xFF2B6CB0),
        title: 'Customers',
        subtitle: 'Payments and udhaar',
        onTap: () => _goTab(3, const CustomersScreen()),
      ),
      _Area(
        icon: Icons.sell_outlined,
        accent: const Color(0xFFC2417A),
        title: 'Products',
        subtitle: 'Prices and stock levels',
        onTap: () => _push(const ProductsScreen()),
      ),
    ];
  }

  Widget _areaGrid(List<_Area> areas) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 640 ? 4 : 2;
        final width = (constraints.maxWidth - 12 * (columns - 1)) / columns;

        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var i = 0; i < areas.length; i++)
              FadeSlideIn(
                delay: Duration(milliseconds: 40 * i),
                child: SizedBox(
                  width: width,
                  child: _AreaCard(area: areas[i]),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _sectionTitle(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 12),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  // ---------- build ----------

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);
    final colors = Theme.of(context).colorScheme;

    Widget header = _greeting(context, trailing: !wide);
    if (wide) {
      header = Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(child: header),
          const SizedBox(width: 16),
          SizedBox(width: 460, child: _actionRow()),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: PageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                if (_isManager) _banner(context),
                if (!wide) ...[
                  const SizedBox(height: 14),
                  _actionRow(),
                ],
                const SizedBox(height: 18),
                if (_isManager) ...[
                  DashboardSummaryCard(
                    onLoaded: _onSummary,
                    middle: const AssistantPanel(),
                  ),
                  _sectionTitle(context, 'Your business'),
                  _areaGrid(_managerAreas()),
                ] else ...[
                  _sectionTitle(context, 'Shortcuts'),
                  _areaGrid(_staffAreas()),
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2B6CB0).withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.lock_outline_rounded,
                          color: Color(0xFF2B6CB0),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Profit, expenses, reports and the AI assistant '
                            'are only visible to the owner.',
                            style: TextStyle(color: colors.onSurface),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Area {
  const _Area({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.pill,
    this.pillColor,
  });

  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final String? pill;
  final Color? pillColor;
  final VoidCallback onTap;
}

class _AreaCard extends StatelessWidget {
  const _AreaCard({required this.area});

  final _Area area;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: area.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: area.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(area.icon, color: area.accent),
                  ),
                  const Spacer(),
                  Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                area.title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                area.subtitle,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (area.pill != null) ...[
                const SizedBox(height: 10),
                InfoPill(area.pill!, color: area.pillColor),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.primary = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = primary ? Colors.white : colors.onSurface;

    return Material(
      color: Colors.transparent,
      child: Ink(
        decoration: BoxDecoration(
          gradient: primary
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primaryLight, AppColors.primaryDark],
                )
              : null,
          color: primary ? null : colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: primary ? null : Border.all(color: colors.outlineVariant),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            height: 84,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: primary ? Colors.white : colors.primary),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  style: TextStyle(
                    color: fg,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
