import 'package:ai_business_os/app/responsive.dart';
import 'package:ai_business_os/app/shell_scope.dart';
import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:ai_business_os/app/user_info.dart';
import 'package:ai_business_os/features/alerts/stock_alerts.dart';
import 'package:ai_business_os/features/customers/presentation/customers_screen.dart';
import 'package:ai_business_os/features/home/presentation/home_screen.dart';
import 'package:ai_business_os/features/inventory/presentation/inventory_screen.dart';
import 'package:ai_business_os/features/more/presentation/more_screen.dart';
import 'package:ai_business_os/features/orders/presentation/orders_screen.dart';
import 'package:flutter/material.dart';

class _NavTab {
  const _NavTab(this.label, this.icon, this.selectedIcon);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

const List<_NavTab> _tabs = [
  _NavTab('Home', Icons.home_outlined, Icons.home_rounded),
  _NavTab('Orders', Icons.shopping_bag_outlined, Icons.shopping_bag_rounded),
  _NavTab('Stock', Icons.inventory_2_outlined, Icons.inventory_2_rounded),
  _NavTab('Customers', Icons.people_alt_outlined, Icons.people_alt_rounded),
  _NavTab('More', Icons.more_horiz_rounded, Icons.more_horiz_rounded),
];

/// The main frame of the app. On a phone: the screen with a floating bar at
/// the bottom. On a wide screen (web, tablet): a top bar with the same tabs.
/// A tab is built the first time it is opened, so the app does not load every
/// screen at start.
class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.backendStatusMessage,
    this.testSupabaseConnection,
  });

  final String backendStatusMessage;
  final Future<SupabaseConnectionResult> Function()? testSupabaseConnection;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> {
  int _index = 0;
  int _homeRefresh = 0;
  final Set<int> _opened = {0};

  Widget _tab(int index) {
    switch (index) {
      case 0:
        return HomeScreen(key: ValueKey<int>(_homeRefresh));
      case 1:
        return const OrdersScreen();
      case 2:
        return const InventoryScreen();
      case 3:
        return const CustomersScreen();
      default:
        return MoreScreen(
          backendStatusMessage: widget.backendStatusMessage,
          testSupabaseConnection: widget.testSupabaseConnection,
        );
    }
  }

  void _select(int index) {
    setState(() {
      // Coming back to Home reloads the dashboard with fresh numbers.
      if (index == 0 && _index != 0) _homeRefresh++;
      _index = index;
      _opened.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = isWide(context);

    return ShellScope(
      selectTab: _select,
      child: Scaffold(
        appBar: wide
            ? PreferredSize(
                preferredSize: const Size.fromHeight(64),
                child: _TopBar(index: _index, onSelect: _select),
              )
            : null,
        body: IndexedStack(
          index: _index,
          children: [
            for (var i = 0; i < _tabs.length; i++)
              _opened.contains(i) ? _tab(i) : const SizedBox.shrink(),
          ],
        ),
        bottomNavigationBar: wide
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: _FloatingNav(index: _index, onSelect: _select),
                ),
              ),
      ),
    );
  }
}

class _FloatingNav extends StatelessWidget {
  const _FloatingNav({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: colors.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabs.length; i++)
            Expanded(
              child: _NavItem(
                tab: _tabs[i],
                selected: i == index,
                onTap: () => onSelect(i),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.selected,
    required this.onTap,
  });

  final _NavTab tab;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = selected ? colors.primary : colors.onSurfaceVariant;

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? colors.primary.withValues(alpha: 0.12)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(selected ? tab.selectedIcon : tab.icon, size: 22, color: color),
            const SizedBox(height: 2),
            Text(
              tab.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: color,
                fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.index, required this.onSelect});

  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Material(
      color: colors.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1040),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: colors.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.storefront_rounded,
                      size: 20,
                      color: colors.onPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'AI Business OS',
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (var i = 0; i < _tabs.length; i++)
                            _TopTab(
                              label: _tabs[i].label,
                              selected: i == index,
                              onTap: () => onSelect(i),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  AlertBell(onAddStock: () => onSelect(2)),
                  const SizedBox(width: 10),
                  InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => onSelect(4),
                    child: const UserAvatar(size: 40),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TopTab extends StatelessWidget {
  const _TopTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: selected
                ? colors.primary.withValues(alpha: 0.12)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? colors.primary : colors.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
