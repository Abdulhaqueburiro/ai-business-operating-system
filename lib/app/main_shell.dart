import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:ai_business_os/features/customers/presentation/customers_screen.dart';
import 'package:ai_business_os/features/home/presentation/home_screen.dart';
import 'package:ai_business_os/features/inventory/presentation/inventory_screen.dart';
import 'package:ai_business_os/features/more/presentation/more_screen.dart';
import 'package:ai_business_os/features/orders/presentation/orders_screen.dart';
import 'package:flutter/material.dart';

/// The main frame of the app: the screen on top and a bottom bar to jump
/// between Home, Orders, Stock, Customers and More. A tab is built the first
/// time it is opened, so the app does not load every screen at start.
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
        return HomeScreen(
          key: ValueKey<int>(_homeRefresh),
          backendStatusMessage: widget.backendStatusMessage,
          testSupabaseConnection: widget.testSupabaseConnection,
        );
      case 1:
        return const OrdersScreen();
      case 2:
        return const InventoryScreen();
      case 3:
        return const CustomersScreen();
      default:
        return const MoreScreen();
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
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          for (var i = 0; i < 5; i++)
            _opened.contains(i) ? _tab(i) : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag_rounded),
            label: 'Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.inventory_2_outlined),
            selectedIcon: Icon(Icons.inventory_2_rounded),
            label: 'Stock',
          ),
          NavigationDestination(
            icon: Icon(Icons.people_alt_outlined),
            selectedIcon: Icon(Icons.people_alt_rounded),
            label: 'Customers',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'More',
          ),
        ],
      ),
    );
  }
}
