import 'package:ai_business_os/app/app_theme.dart';
import 'package:ai_business_os/app/responsive.dart';
import 'package:ai_business_os/app/stat_tile.dart';
import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:ai_business_os/app/user_info.dart';
import 'package:ai_business_os/features/assistant/presentation/assistant_screen.dart';
import 'package:ai_business_os/features/business/business_info.dart';
import 'package:ai_business_os/features/expenses/presentation/expenses_screen.dart';
import 'package:ai_business_os/features/more/presentation/system_status_card.dart';
import 'package:ai_business_os/features/products/presentation/products_screen.dart';
import 'package:ai_business_os/features/reports/presentation/reports_screen.dart';
import 'package:ai_business_os/features/staff/business_role.dart';
import 'package:ai_business_os/features/staff/presentation/staff_screen.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Everything that does not fit in the bottom bar, the dark mode switch,
/// sign out and the system status.
class MoreScreen extends StatefulWidget {
  const MoreScreen({
    super.key,
    this.backendStatusMessage = '',
    this.testSupabaseConnection,
  });

  final String backendStatusMessage;
  final Future<SupabaseConnectionResult> Function()? testSupabaseConnection;

  @override
  State<MoreScreen> createState() => _MoreScreenState();
}

class _MoreScreenState extends State<MoreScreen> {
  String? _role;
  String? _businessName;

  bool get _isManager => isManagerRole(_role);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final role = await loadMyRole();
    final name = await loadBusinessName();
    if (!mounted) return;
    setState(() {
      _role = role;
      _businessName = name;
    });
  }

  String get _roleLabel {
    switch (_role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      case 'staff':
        return 'Staff';
      default:
        return 'Member';
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

  Widget _profile(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = currentFirstName() ?? 'Your account';
    final email = currentUserEmail();
    final label = _businessName == null
        ? _roleLabel
        : '$_roleLabel · $_businessName';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            const UserAvatar(size: 60),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  if (email != null)
                    Text(
                      email,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                  const SizedBox(height: 8),
                  InfoPill(label, color: colors.primary),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _row({
    required IconData icon,
    required Color accent,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    String? pill,
    Color? pillColor,
  }) {
    final colors = Theme.of(context).colorScheme;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            if (pill != null) ...[
              InfoPill(pill, color: pillColor),
              const SizedBox(width: 6),
            ],
            Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;

    final rows = <Widget>[
      _row(
        icon: Icons.sell_outlined,
        accent: const Color(0xFFC2417A),
        title: 'Products',
        subtitle: 'Prices and alert levels',
        onTap: () => _open(const ProductsScreen()),
      ),
      if (_isManager) ...[
        _row(
          icon: Icons.account_balance_wallet_outlined,
          accent: const Color(0xFFB4232F),
          title: 'Expenses',
          subtitle: 'Rent, salary, bills',
          onTap: () => _open(const ExpensesScreen()),
        ),
        _row(
          icon: Icons.bar_chart_rounded,
          accent: const Color(0xFF0E8F9A),
          title: 'Reports',
          subtitle: 'Sales and profit',
          pill: 'This month',
          pillColor: const Color(0xFF18794E),
          onTap: () => _open(const ReportsScreen()),
        ),
        _row(
          icon: Icons.auto_awesome_rounded,
          accent: const Color(0xFF7C3AED),
          title: 'AI assistant',
          subtitle: 'Ask in Urdu or English',
          onTap: () => _open(const AssistantScreen()),
        ),
        _row(
          icon: Icons.badge_outlined,
          accent: const Color(0xFF5B6B65),
          title: 'Staff',
          subtitle: 'Who can use the app',
          onTap: () => _open(const StaffScreen()),
        ),
      ],
    ];

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          child: PageBody(
            maxWidth: 640,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: Text(
                    'More',
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ),
                _profile(context),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    children: [
                      for (var i = 0; i < rows.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: 72,
                            color: colors.outlineVariant,
                          ),
                        rows[i],
                      ],
                    ],
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 8,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.onSurfaceVariant
                                .withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(
                            Icons.dark_mode_outlined,
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Dark mode',
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              Text(
                                'Easier on the eyes at night',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(color: colors.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: dark,
                          onChanged: (value) {
                            AppTheme.mode.value =
                                value ? ThemeMode.dark : ThemeMode.light;
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.error.withValues(alpha: 0.12),
                    foregroundColor: colors.error,
                  ),
                  onPressed: _confirmSignOut,
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('Sign out'),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(
                    'AI Business OS · Version 1.0',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: colors.onSurfaceVariant),
                  ),
                ),
                const SizedBox(height: 22),
                Text(
                  'System status',
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                SystemStatusCard(
                  backendStatusMessage: widget.backendStatusMessage,
                  testSupabaseConnection: widget.testSupabaseConnection,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
