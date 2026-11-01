import 'package:ai_business_os/features/assistant/presentation/assistant_screen.dart';
import 'package:ai_business_os/features/expenses/presentation/expenses_screen.dart';
import 'package:ai_business_os/features/products/presentation/products_screen.dart';
import 'package:ai_business_os/features/reports/presentation/reports_screen.dart';
import 'package:ai_business_os/features/staff/business_role.dart';
import 'package:ai_business_os/features/staff/presentation/staff_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything that does not fit in the bottom bar, plus sign out.
class MoreScreen extends StatefulWidget {
  const MoreScreen({super.key});

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String? _role;

  bool get _isManager => isManagerRole(_role);

  @override
  void initState() {
    super.initState();
    _loadRole();
  }

  Future<void> _loadRole() async {
    final role = await loadMyRole();
    if (!mounted) return;
    setState(() => _role = role);
  }

  String? _email() {
    try {
      return Supabase.instance.client.auth.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  void _open(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));
  }

  Future<void> _confirmSignOut() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to log in again to use the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not sign out. Try again.')),
      );
    }
  }

  Widget _tile({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    final colors = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: accent),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final email = _email();

    return Scaffold(
      appBar: AppBar(title: const Text('More')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (email != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: colors.primaryContainer,
                    child: Icon(Icons.person_rounded,
                        color: colors.onPrimaryContainer),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
          _tile(
            icon: Icons.category_rounded,
            accent: const Color(0xFF2B6CB0),
            title: 'Products',
            subtitle: 'Your items, prices and units.',
            onTap: () => _open(const ProductsScreen()),
          ),
          if (_isManager) ...[
            _tile(
              icon: Icons.receipt_long_rounded,
              accent: const Color(0xFFA15C08),
              title: 'Expenses',
              subtitle: 'Rent, salary, supplies and other costs.',
              onTap: () => _open(const ExpensesScreen()),
            ),
            _tile(
              icon: Icons.bar_chart_rounded,
              accent: const Color(0xFF18794E),
              title: 'Reports',
              subtitle: 'Sales, profit, top products and customers.',
              onTap: () => _open(const ReportsScreen()),
            ),
            _tile(
              icon: Icons.smart_toy_rounded,
              accent: const Color(0xFFD9534F),
              title: 'AI assistant',
              subtitle: 'Ask questions about your business.',
              onTap: () => _open(const AssistantScreen()),
            ),
            _tile(
              icon: Icons.badge_rounded,
              accent: const Color(0xFF6B7C75),
              title: 'Staff',
              subtitle: 'Add or remove the people who work with you.',
              onTap: () => _open(const StaffScreen()),
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _confirmSignOut,
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Sign out'),
          ),
        ],
      ),
    );
  }
}
