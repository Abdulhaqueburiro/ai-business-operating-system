import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:ai_business_os/features/assistant/presentation/assistant_screen.dart';
import 'package:ai_business_os/features/customers/presentation/customers_screen.dart';
import 'package:ai_business_os/features/dashboard/presentation/dashboard_summary_card.dart';
import 'package:ai_business_os/features/expenses/presentation/expenses_screen.dart';
import 'package:ai_business_os/features/inventory/presentation/inventory_screen.dart';
import 'package:ai_business_os/features/orders/presentation/orders_screen.dart';
import 'package:ai_business_os/features/products/presentation/products_screen.dart';
import 'package:ai_business_os/features/reports/presentation/reports_screen.dart';
import 'package:ai_business_os/features/staff/business_role.dart';
import 'package:ai_business_os/features/staff/presentation/staff_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.backendStatusMessage,
    this.testSupabaseConnection,
  });

  final String backendStatusMessage;
  final Future<SupabaseConnectionResult> Function()? testSupabaseConnection;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

enum _ConnectionTestState { notTested, testing, connected, failed }

class _HomeScreenState extends State<HomeScreen> {
  _ConnectionTestState _connectionTestState = _ConnectionTestState.notTested;
  String? _connectionTestMessage;
  String? _role;
  late final Future<Map<String, dynamic>?> _businessFuture;

  bool get _isManager => isManagerRole(_role);

  @override
  void initState() {
    super.initState();
    _businessFuture = _loadBusinessDetails();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await loadMyRole();
    if (!mounted) return;
    setState(() => _role = role);
  }

  Future<Map<String, dynamic>?> _loadBusinessDetails() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    final rows = await client
        .from('business_members')
        .select(
          'business_id, businesses(name, business_type, currency_code, timezone)',
        )
        .eq('user_id', user.id)
        .limit(1);

    if (rows.isEmpty) return null;

    final row = Map<String, dynamic>.from(rows.first);
    final raw = row['businesses'];

    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  void _open(Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _testSupabaseConnection() async {
    setState(() {
      _connectionTestState = _ConnectionTestState.testing;
      _connectionTestMessage = null;
    });

    final checker = widget.testSupabaseConnection;
    if (checker == null) {
      setState(() {
        _connectionTestState = _ConnectionTestState.failed;
        _connectionTestMessage =
            'Auth service check is unavailable because the project URL is not configured.';
      });
      return;
    }

    final result = await checker();
    if (!mounted) return;

    setState(() {
      _connectionTestState = result.isConnected
          ? _ConnectionTestState.connected
          : _ConnectionTestState.failed;
      _connectionTestMessage = result.message;
    });
  }

  List<_WorkspaceArea> _areas() {
    return [
      _WorkspaceArea(
        icon: Icons.inventory_2_outlined,
        title: 'Products',
        description: 'Add, edit, and manage your business products.',
        openScreen: () => const ProductsScreen(),
      ),
      _WorkspaceArea(
        icon: Icons.warehouse_outlined,
        title: 'Inventory',
        description: 'Manage stock quantities with Stock In and Stock Out.',
        openScreen: () => const InventoryScreen(),
      ),
      _WorkspaceArea(
        icon: Icons.local_shipping_outlined,
        title: 'Orders and fulfillment',
        description: 'Create orders, confirm them and track their status.',
        openScreen: () => const OrdersScreen(),
      ),
      _WorkspaceArea(
        icon: Icons.people_alt_outlined,
        title: 'Customers',
        description: 'Keep your customers, their phone numbers and udhaar.',
        openScreen: () => const CustomersScreen(),
      ),
      _WorkspaceArea(
        icon: Icons.request_quote_outlined,
        title: 'Expenses',
        description: 'Record business expenses such as rent, salary and supplies.',
        openScreen: () => const ExpensesScreen(),
        managerOnly: true,
      ),
      _WorkspaceArea(
        icon: Icons.bar_chart_outlined,
        title: 'Reports',
        description: 'See sales, profit, top products and customers for a period.',
        openScreen: () => const ReportsScreen(),
        managerOnly: true,
      ),
      _WorkspaceArea(
        icon: Icons.smart_toy_outlined,
        title: 'AI assistant',
        description: 'Ask questions about your sales, profit, stock and udhaar.',
        openScreen: () => const AssistantScreen(),
        managerOnly: true,
      ),
      _WorkspaceArea(
        icon: Icons.badge_outlined,
        title: 'Staff',
        description: 'Add or remove the people who work in your business.',
        openScreen: () => const StaffScreen(),
        managerOnly: true,
      ),
      const _WorkspaceArea(
        icon: Icons.payments_outlined,
        title: 'Payments and reports',
        description: 'Tools for payment tracking and operational insights.',
      ),
    ];
  }

  Widget _buildGreeting(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colors = Theme.of(context).colorScheme;

    return FutureBuilder<Map<String, dynamic>?>(
      future: _businessFuture,
      builder: (context, snapshot) {
        final raw = snapshot.data?['name']?.toString().trim() ?? '';
        final name = raw.isEmpty ? null : raw;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Assalam-o-alaikum',
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              name == null
                  ? 'Here is how your business is doing.'
                  : 'Here is how $name is doing.',
              style: textTheme.bodyMedium?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FilledButton.icon(
          onPressed: () => _open(const OrdersScreen()),
          icon: const Icon(Icons.add),
          label: const Text('New order'),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _open(const CustomersScreen()),
                icon: const Icon(Icons.payments_outlined),
                label: const Text('Record payment'),
              ),
            ),
            if (_isManager) ...[
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _open(const ProductsScreen()),
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: const Text('Add product'),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Business OS')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final areaWidth = constraints.maxWidth < 600
              ? constraints.maxWidth
              : (constraints.maxWidth - 16) / 2;
          final areas = [
            for (final area in _areas())
              if (!area.managerOnly || _isManager) area,
          ];

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildGreeting(context),
                      const SizedBox(height: 16),
                      _buildQuickActions(context),
                      if (_isManager) ...[
                        const SizedBox(height: 20),
                        const DashboardSummaryCard(),
                      ],
                      const SizedBox(height: 24),
                      Text(
                        'Workspace areas',
                        style: textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 12,
                        children: [
                          for (final area in areas)
                            SizedBox(
                              width: areaWidth,
                              child: _WorkspaceAreaCard(
                                area: area,
                                onTap: area.openScreen == null
                                    ? null
                                    : () => _open(area.openScreen!()),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'System status',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        color: colors.surfaceContainerHighest,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.cloud_outlined,
                                color: colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.backendStatusMessage,
                                  style: textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildConnectionTestCard(context),
                      const SizedBox(height: 12),
                      Text(
                        'Products, stock, orders and expenses are saved in '
                        'your business database.',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionTestCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final isTesting = _connectionTestState == _ConnectionTestState.testing;
    final statusText = switch (_connectionTestState) {
      _ConnectionTestState.notTested => 'Not tested',
      _ConnectionTestState.testing => 'Testing',
      _ConnectionTestState.connected => 'Connected',
      _ConnectionTestState.failed => 'Connection failed',
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Auth service availability: $statusText',
              style: Theme.of(context).textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            if (_connectionTestMessage case final message?) ...[
              const SizedBox(height: 6),
              Text(
                message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _connectionTestState == _ConnectionTestState.failed
                      ? colors.error
                      : colors.onSurfaceVariant,
                ),
              ),
            ],
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: isTesting ? null : _testSupabaseConnection,
                icon: isTesting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_tethering),
                label: const Text('Check Auth Service Availability'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkspaceArea {
  const _WorkspaceArea({
    required this.icon,
    required this.title,
    required this.description,
    this.openScreen,
    this.managerOnly = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget Function()? openScreen;
  final bool managerOnly;
}

class _WorkspaceAreaCard extends StatelessWidget {
  const _WorkspaceAreaCard({required this.area, this.onTap});

  final _WorkspaceArea area;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colors.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(area.icon, color: colors.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      area.title,
                      style: Theme.of(context).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      area.description,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              if (onTap != null)
                Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
