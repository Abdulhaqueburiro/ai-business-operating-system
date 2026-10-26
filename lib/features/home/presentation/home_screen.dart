import 'package:ai_business_os/features/inventory/presentation/inventory_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:ai_business_os/features/products/presentation/products_screen.dart';
import 'package:ai_business_os/features/orders/presentation/orders_screen.dart';
import 'package:ai_business_os/features/expenses/presentation/expenses_screen.dart';

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
  Future<Map<String, dynamic>?> _loadBusinessDetails() async {
    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) return null;

    final rows = await client
        .from('business_members')
        .select('business_id, businesses(name, business_type, currency_code, timezone)')
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

  Widget _buildBusinessDetailsCard(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: FutureBuilder<Map<String, dynamic>?>(
          future: _loadBusinessDetails(),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Row(
                children: [
                  SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  SizedBox(width: 12),
                  Text('Loading business details...'),
                ],
              );
            }

            if (snapshot.hasError) {
              return Text(
                'Unable to load business details. Check database access.',
                style: TextStyle(color: colors.error),
              );
            }

            final business = snapshot.data;
            if (business == null) {
              return const Text(
                'No business found for the signed-in user.',
              );
            }

            String value(String key) {
              final result = business[key];
              return result == null || result.toString().trim().isEmpty
                  ? 'Not set'
                  : result.toString();
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Your business',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 10),
                Text(
                  value('name'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 6),
                Text('Business type: ${value('business_type')}'),
                Text('Currency: ${value('currency_code')}'),
                Text('Time zone: ${value('time_zone')}'),
              ],
            );
          },
        ),
      ),
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

  static const _areas = [
    _WorkspaceArea(
      icon: Icons.inventory_2_outlined,
      title: 'Products',
      description: 'Add, edit, and manage your business products.',
      opensProductsPreview: true,
    ),
    _WorkspaceArea(
      icon: Icons.warehouse_outlined,
      title: 'Inventory',
      description: 'Manage stock quantities with Stock In and Stock Out.',
      opensInventory: true,
    ),
    _WorkspaceArea(
      icon: Icons.local_shipping_outlined,
      title: 'Orders and fulfillment',
      description: 'A workspace for order and delivery workflows.',
      opensOrders: true,
    ),
    _WorkspaceArea(
      icon: Icons.request_quote_outlined,
      title: 'Expenses',
      description: 'Record business expenses such as rent, salary and supplies.',
      opensExpenses: true,
    ),
    _WorkspaceArea(
      icon: Icons.payments_outlined,
      title: 'Payments and reports',
      description: 'Tools for payment tracking and operational insights.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('AI Business OS')),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final areaWidth = constraints.maxWidth < 600
              ? constraints.maxWidth
              : (constraints.maxWidth - 16) / 2;

          return SingleChildScrollView(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 880),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Your business workspace',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'A clearer place to organize the work of your business.',
                        style: Theme.of(context).textTheme.bodyLarge
                            ?.copyWith(color: colors.onSurfaceVariant),
                      ),
                      const SizedBox(height: 20),
                      Card(
                        color: colors.tertiaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.cloud_outlined,
                                color: colors.onTertiaryContainer,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  widget.backendStatusMessage,
                                  style: Theme.of(context).textTheme.bodyMedium
                                      ?.copyWith(
                                        color: colors.onTertiaryContainer,
                                      ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _buildBusinessDetailsCard(context),
                      const SizedBox(height: 12),
                      _buildConnectionTestCard(context),
                      const SizedBox(height: 28),
                      Card(
                        color: colors.primaryContainer,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lightbulb_outline,
                                color: colors.onPrimaryContainer,
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      'A simple foundation to get started',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            color: colors.onPrimaryContainer,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'This starter is not connected to business '
                                      'data. It does not show real products, '
                                      'stock, orders, or payments.',
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyMedium
                                          ?.copyWith(
                                            color: colors.onPrimaryContainer,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 28),
                      Text(
                        'Workspace areas',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 16,
                        runSpacing: 16,
                        children: [
                          for (final area in _areas)
                            SizedBox(
                              width: areaWidth,
                              child: _WorkspaceAreaCard(
                                area: area,
                                onTap: area.opensProductsPreview
                                    ? () {
                                        Navigator.of(context).push(
                                          MaterialPageRoute<void>(
                                            builder: (_) =>
                                                const ProductsScreen(),
                                          ),
                                        );
                                      }
                                    : area.opensInventory
                                        ? () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) =>
                                                    const InventoryScreen(),
                                              ),
                                            );
                                          }
                                        : area.opensOrders
                                        ? () {
                                            Navigator.of(context).push(
                                              MaterialPageRoute<void>(
                                                builder: (_) => const OrdersScreen(),
                                              ),
                                            );
                                          }
                                        : area.opensExpenses
                                            ? () {
                                                Navigator.of(context).push(
                                                    MaterialPageRoute<void>(
                                                        builder: (_) =>
                                                            const ExpensesScreen(),
                                                    ),
                                                );
                                            }
                                            : null,
                              ),
                            ),
                        ],
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
    this.opensProductsPreview = false,
    this.opensInventory = false,
    this.opensOrders = false,
    this.opensExpenses = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final bool opensProductsPreview;
  final bool opensInventory;
  final bool opensOrders;
  final bool opensExpenses;
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
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(area.icon, color: colors.primary),
              const SizedBox(height: 16),
              Text(
                area.title,
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Text(
                area.description,
                style: Theme.of(context).textTheme.bodyMedium
                    ?.copyWith(color: colors.onSurfaceVariant),
              ),
              if (onTap != null) ...[
                const SizedBox(height: 12),
                Text(
                  'Open local preview',
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(color: colors.primary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}







