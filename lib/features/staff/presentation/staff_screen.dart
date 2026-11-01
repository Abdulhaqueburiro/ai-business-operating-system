import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class StaffScreen extends StatefulWidget {
  const StaffScreen({super.key});

  @override
  State<StaffScreen> createState() => _StaffScreenState();
}

class _StaffScreenState extends State<StaffScreen> {
  final _emailController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _businessId;
  List<Map<String, dynamic>> _people = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  String _message(Object error) {
    if (error is PostgrestException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
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

      final rows = await client
          .from('business_members')
          .select('business_id')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .limit(1);
      if (rows.isEmpty) throw Exception('No active business found.');

      final businessId = rows.first['business_id'].toString();
      final data = await client.rpc(
        'list_business_staff',
        params: {'p_business_id': businessId},
      );

      if (!mounted) return;
      setState(() {
        _businessId = businessId;
        _people = (data as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = _message(e);
        _loading = false;
      });
    }
  }

  Future<void> _add() async {
    final businessId = _businessId;
    if (businessId == null || _busy) return;

    final email = _emailController.text.trim();
    if (email.isEmpty) {
      _snack("Type your staff member's email.");
      return;
    }

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'add_staff_member',
        params: {'p_business_id': businessId, 'p_email': email},
      );
      _emailController.clear();
      _snack('Staff member added.');
      await _load();
    } catch (e) {
      _snack(_message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove(Map<String, dynamic> person) async {
    final businessId = _businessId;
    if (businessId == null || _busy) return;

    final email = person['email']?.toString() ?? 'this person';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove staff member?'),
        content: Text('$email will no longer be able to open your business.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await Supabase.instance.client.rpc(
        'remove_staff_member',
        params: {
          'p_business_id': businessId,
          'p_user_id': person['user_id'].toString(),
        },
      );
      _snack('Staff member removed.');
      await _load();
    } catch (e) {
      _snack(_message(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _roleLabel(String? role) {
    switch (role) {
      case 'owner':
        return 'Owner';
      case 'admin':
        return 'Admin';
      default:
        return 'Staff';
    }
  }

  Widget _personTile(Map<String, dynamic> person) {
    final role = person['role']?.toString();
    final isMe = person['is_me'] == true;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.person_outline),
      title: Text(person['email']?.toString() ?? 'Unknown'),
      subtitle: Text(isMe ? '${_roleLabel(role)} (you)' : _roleLabel(role)),
      trailing: role == 'staff'
          ? IconButton(
              tooltip: 'Remove staff member',
              onPressed: _busy ? null : () => _remove(person),
              icon: const Icon(Icons.person_remove_outlined),
            )
          : null,
    );
  }

  Widget _content() {
    if (_loading) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null) {
      return Column(
        children: [
          const Icon(Icons.error_outline, size: 40),
          const SizedBox(height: 12),
          const Text('Could not load your people.'),
          const SizedBox(height: 8),
          SelectableText(_error!),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    }

    final colors = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Add a staff member',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 4),
        Text(
          'Your staff member must first sign up in the app with their own '
          'email and password, and must not create a business. Then type '
          'that email here.',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: colors.onSurfaceVariant),
        ),
        const SizedBox(height: 12),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _emailController,
                enabled: !_busy,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'Staff email',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _add(),
              ),
            ),
            const SizedBox(width: 12),
            FilledButton(
              onPressed: _busy ? null : _add,
              child: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text('People', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final person in _people) _personTile(person),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Staff can: sell (create and confirm orders), add customers, '
              'take udhaar payments, and look at products and stock.\n\n'
              'Staff cannot: cancel orders, change stock, see expenses, '
              'the dashboard, reports or the AI assistant, void payments, '
              'or manage staff.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [_content()],
      ),
    );
  }
}
