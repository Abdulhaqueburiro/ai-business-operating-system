import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Creates a random UUID v4 string (used as the idempotency key).
String _newUuidV4() {
  final rng = Random.secure();
  final b = List<int>.generate(16, (_) => rng.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  String h(int i) => b[i].toRadixString(16).padLeft(2, '0');
  return '${h(0)}${h(1)}${h(2)}${h(3)}-${h(4)}${h(5)}-${h(6)}${h(7)}-'
      '${h(8)}${h(9)}-${h(10)}${h(11)}${h(12)}${h(13)}${h(14)}${h(15)}';
}

final RegExp _phonePattern = RegExp(r'^[0-9+() -]{5,20}$');

typedef _SaveCustomer = Future<void> Function({
  required String name,
  required String? phone,
  required String? notes,
  required String idempotencyKey,
});

class CustomersScreen extends StatefulWidget {
  const CustomersScreen({super.key});

  @override
  State<CustomersScreen> createState() => _CustomersScreenState();
}

class _CustomersScreenState extends State<CustomersScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  final _searchController = TextEditingController();

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _businessId;
  String _query = '';
  List<Map<String, dynamic>> _customers = [];
  Map<String, double> _balances = {};

  @override
  void initState() {
    super.initState();
    _loadCustomers();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<String> _getActiveBusinessId() async {
    final user = _client.auth.currentUser;
    if (user == null) throw Exception('Please log in first.');

    final rows = await _client
        .from('business_members')
        .select('business_id')
        .eq('user_id', user.id)
        .eq('status', 'active')
        .limit(1);

    if (rows.isEmpty) {
      throw Exception('No active business membership found.');
    }

    return rows.first['business_id'].toString();
  }

  Future<void> _loadCustomers() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final businessId = await _getActiveBusinessId();

      final rows = await _client
          .from('customers')
          .select('id, name, phone, notes, archived_at')
          .eq('business_id', businessId)
          .order('name', ascending: true)
          .limit(1000);

      final balances = await _loadBalances(businessId);

      if (!mounted) return;

      setState(() {
        _businessId = businessId;
        _balances = balances;
        _customers = rows
            .map((row) => Map<String, dynamic>.from(row))
            .where((row) => row['archived_at'] == null)
            .toList();
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

  List<Map<String, dynamic>> get _visibleCustomers {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _customers;

    return _customers.where((customer) {
      final name = (customer['name']?.toString() ?? '').toLowerCase();
      final phone = (customer['phone']?.toString() ?? '').toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  Future<void> _openCustomerDialog({Map<String, dynamic>? existing}) async {
    final businessId = _businessId;

    if (businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business is not loaded. Refresh first.')),
      );
      return;
    }

    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _CustomerDialog(
        existing: existing,
        onSave: ({
          required name,
          required phone,
          required notes,
          required idempotencyKey,
        }) async {
          if (existing == null) {
            await _client.rpc(
              'create_customer',
              params: {
                'p_business_id': businessId,
                'p_name': name,
                'p_phone': phone,
                'p_notes': notes,
                'p_idempotency_key': idempotencyKey,
              },
            );
          } else {
            await _client.rpc(
              'update_customer',
              params: {
                'p_customer_id': existing['id'].toString(),
                'p_name': name,
                'p_phone': phone,
                'p_notes': notes,
              },
            );
          }
        },
      ),
    );

    if (saved != true || !mounted) return;

    await _loadCustomers();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(existing == null ? 'Customer saved.' : 'Customer updated.'),
      ),
    );
  }

  Future<void> _archiveCustomer(Map<String, dynamic> customer) async {
    if (_busy) return;

    final name = customer['name']?.toString() ?? 'this customer';

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this customer?'),
        content: Text(
          'Remove "$name"? They will be hidden from the list. '
          'Past orders keep their history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, remove'),
          ),
        ],
      ),
    );

    if (approved != true || !mounted) return;

    setState(() => _busy = true);

    try {
      await _client.rpc(
        'archive_customer',
        params: {'p_customer_id': customer['id'].toString()},
      );

      await _loadCustomers();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Customer removed.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove customer: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  // Balances are extra information: the customer list still works without them.
  Future<Map<String, double>> _loadBalances(String businessId) async {
    try {
      final rows = await _client.rpc(
        'get_customer_balances',
        params: {'p_business_id': businessId},
      );
      final result = <String, double>{};
      for (final row in (rows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final value = num.tryParse(map['balance'].toString());
        if (value != null) {
          result[map['customer_id'].toString()] = value.toDouble();
        }
      }
      return result;
    } catch (_) {
      return {};
    }
  }

  Future<void> _openLedger(Map<String, dynamic> customer) async {
    final businessId = _businessId;
    if (businessId == null) return;

    await showDialog<void>(
      context: context,
      builder: (_) => _LedgerDialog(
        client: _client,
        businessId: businessId,
        customer: customer,
      ),
    );

    if (!mounted) return;
    await _loadCustomers();
  }

  Widget _buildCustomerCard(Map<String, dynamic> customer) {
    final name = customer['name']?.toString() ?? '';
    final phone = customer['phone']?.toString().trim() ?? '';
    final notes = customer['notes']?.toString().trim() ?? '';
    final balance = _balances[customer['id'].toString()] ?? 0;
    final lines = <String>[
      if (phone.isNotEmpty) phone,
      if (notes.isNotEmpty) notes,
      if (balance > 0.004) 'Owes PKR ${balance.toStringAsFixed(2)}',
      if (balance < -0.004) 'Advance PKR ${(-balance).toStringAsFixed(2)}',
    ];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()),
        ),
        title: Text(name),
        subtitle: lines.isEmpty ? null : Text(lines.join('\n')),
        isThreeLine: lines.length > 1,
        trailing: Wrap(
          children: [
            IconButton(
              tooltip: 'Udhaar statement and payments',
              onPressed: _busy ? null : () => _openLedger(customer),
              icon: const Icon(Icons.receipt_long_outlined),
            ),
            IconButton(
              tooltip: 'Edit customer',
              onPressed:
                  _busy ? null : () => _openCustomerDialog(existing: customer),
              icon: const Icon(Icons.edit_outlined),
            ),
            IconButton(
              tooltip: 'Remove customer',
              onPressed: _busy ? null : () => _archiveCustomer(customer),
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visibleCustomers;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Customers'),
        actions: [
          IconButton(
            tooltip: 'Refresh customers',
            onPressed: _loading || _busy ? null : _loadCustomers,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _busy ? null : () => _openCustomerDialog(),
        icon: const Icon(Icons.person_add_alt_1_outlined),
        label: const Text('Add customer'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.error_outline, size: 40),
                        const SizedBox(height: 12),
                        const Text('Could not load customers.'),
                        const SizedBox(height: 8),
                        SelectableText(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadCustomers,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        labelText: 'Search by name or phone',
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.clear),
                              ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Customers (${visible.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_customers.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No customers yet. Tap Add customer to create one.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else if (visible.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No customer matches your search.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final customer in visible)
                        _buildCustomerCard(customer),
                  ],
                ),
    );
  }
}

class _LedgerDialog extends StatefulWidget {
  const _LedgerDialog({
    required this.client,
    required this.businessId,
    required this.customer,
  });

  final SupabaseClient client;
  final String businessId;
  final Map<String, dynamic> customer;

  @override
  State<_LedgerDialog> createState() => _LedgerDialogState();
}

class _LedgerDialogState extends State<_LedgerDialog> {
  bool _loading = true;
  String? _error;
  double _balance = 0;
  double _credit = 0;
  double _paid = 0;
  List<Map<String, dynamic>> _entries = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  double _toDouble(Object? value) =>
      num.tryParse(value?.toString() ?? '')?.toDouble() ?? 0;

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final data = await widget.client.rpc(
        'get_customer_ledger',
        params: {
          'p_business_id': widget.businessId,
          'p_customer_id': widget.customer['id'].toString(),
        },
      );
      final map = Map<String, dynamic>.from(data as Map);
      final entries = ((map['entries'] as List?) ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();

      if (!mounted) return;
      setState(() {
        _credit = _toDouble(map['credit_total']);
        _paid = _toDouble(map['paid_total']);
        _balance = _toDouble(map['balance']);
        _entries = entries;
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
        _error = 'Could not load the statement: $e';
        _loading = false;
      });
    }
  }

  Future<void> _recordPayment() async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _PaymentDialog(
        client: widget.client,
        businessId: widget.businessId,
        customerId: widget.customer['id'].toString(),
        owed: _balance,
      ),
    );

    if (saved != true || !mounted) return;
    await _load();
  }

  Future<void> _voidPayment(String paymentId) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Cancel this payment?'),
        content: const Text(
          'Use this only if the payment was entered by mistake. '
          'The amount will be owed again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes, cancel payment'),
          ),
        ],
      ),
    );

    if (approved != true || !mounted) return;

    try {
      await widget.client.rpc(
        'void_customer_payment',
        params: {'p_payment_id': paymentId},
      );
      if (!mounted) return;
      await _load();
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not cancel the payment: $e')),
      );
    }
  }

  Widget _entryTile(Map<String, dynamic> entry) {
    final isPayment = entry['type'] == 'payment';
    final amount = _toDouble(entry['amount']);
    final note = entry['note']?.toString().trim() ?? '';
    final rawDate = (isPayment ? entry['paid_on'] : entry['at'])?.toString() ?? '';
    final date = rawDate.split('T').first;
    final title = isPayment ? 'Payment received' : 'Credit sale';
    final details = <String>[
      if (date.isNotEmpty) date,
      if (note.isNotEmpty) note,
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      dense: true,
      title: Text(title),
      subtitle: details.isEmpty ? null : Text(details.join(' - ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '${amount < 0 ? '-' : '+'} ${amount.abs().toStringAsFixed(2)}',
            style: TextStyle(
              color: amount < 0 ? Colors.green.shade700 : null,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isPayment)
            IconButton(
              tooltip: 'Cancel this payment',
              onPressed: () => _voidPayment(entry['id'].toString()),
              icon: const Icon(Icons.undo),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = widget.customer['name']?.toString() ?? 'Customer';
    final colors = Theme.of(context).colorScheme;

    Widget body;
    if (_loading) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (_error != null) {
      body = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(_error!, style: TextStyle(color: colors.error)),
          const SizedBox(height: 12),
          FilledButton(onPressed: _load, child: const Text('Try again')),
        ],
      );
    } else {
      body = SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _balance > 0.004
                  ? 'Owes PKR ${_balance.toStringAsFixed(2)}'
                  : _balance < -0.004
                      ? 'Advance PKR ${(-_balance).toStringAsFixed(2)}'
                      : 'Nothing owed',
              style: Theme.of(context).textTheme.titleLarge,
            ),
            Text(
              'Credit sales ${_credit.toStringAsFixed(2)} - '
              'paid ${_paid.toStringAsFixed(2)}',
            ),
            const SizedBox(height: 12),
            if (_entries.isEmpty)
              const Text('No credit sales or payments yet.')
            else
              for (final entry in _entries) _entryTile(entry),
          ],
        ),
      );
    }

    return AlertDialog(
      title: Text('Udhaar: $name'),
      content: SizedBox(width: 480, child: body),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        FilledButton(
          onPressed: (_loading || _error != null || _balance <= 0.004)
              ? null
              : _recordPayment,
          child: const Text('Record payment'),
        ),
      ],
    );
  }
}

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({
    required this.client,
    required this.businessId,
    required this.customerId,
    required this.owed,
  });

  final SupabaseClient client;
  final String businessId;
  final String customerId;
  final double owed;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _noteController = TextEditingController();

  // One key per dialog session: a retry re-uses it, so a payment can never
  // be saved twice.
  final String _idempotencyKey = _newUuidV4();

  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final note = _noteController.text.trim();

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await widget.client.rpc(
        'record_customer_payment',
        params: {
          'p_business_id': widget.businessId,
          'p_customer_id': widget.customerId,
          'p_amount': double.parse(_amountController.text.trim()),
          'p_note': note.isEmpty ? null : note,
          'p_idempotency_key': _idempotencyKey,
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.message;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = 'Could not save the payment: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Record payment'),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Owed: PKR ${widget.owed.toStringAsFixed(2)}'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  enabled: !_submitting,
                  autofocus: true,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'Amount received',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final amount = double.tryParse(value?.trim() ?? '');
                    if (amount == null || !amount.isFinite || amount <= 0) {
                      return 'Enter an amount greater than zero.';
                    }
                    if (amount > widget.owed + 0.005) {
                      return 'More than the customer owes.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _noteController,
                  enabled: !_submitting,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _submitError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save payment'),
        ),
      ],
    );
  }
}

class _CustomerDialog extends StatefulWidget {
  const _CustomerDialog({required this.onSave, this.existing});

  final _SaveCustomer onSave;
  final Map<String, dynamic>? existing;

  @override
  State<_CustomerDialog> createState() => _CustomerDialogState();
}

class _CustomerDialogState extends State<_CustomerDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _notesController;

  // One key per dialog session: a retry after a failure re-uses it, so the
  // database can never save the same new customer twice.
  final String _idempotencyKey = _newUuidV4();

  bool _submitting = false;
  String? _submitError;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(
      text: widget.existing?['name']?.toString() ?? '',
    );
    _phoneController = TextEditingController(
      text: widget.existing?['phone']?.toString() ?? '',
    );
    _notesController = TextEditingController(
      text: widget.existing?['notes']?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final phone = _phoneController.text.trim();
    final notes = _notesController.text.trim();

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await widget.onSave(
        name: _nameController.text.trim(),
        phone: phone.isEmpty ? null : phone,
        notes: notes.isEmpty ? null : notes,
        idempotencyKey: _idempotencyKey,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = e.message;
        _submitting = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _submitError = 'Could not save customer: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEdit ? 'Edit customer' : 'Add customer'),
      content: SizedBox(
        width: 480,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  enabled: !_submitting,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Name',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return 'Enter the customer name.';
                    if (text.length > 120) {
                      return 'Name must be 120 characters or fewer.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _phoneController,
                  enabled: !_submitting,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Phone (optional)',
                    hintText: '0300-1234567',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty) return null;
                    if (!_phonePattern.hasMatch(text)) {
                      return 'Use 5-20 digits, spaces, + or -.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  enabled: !_submitting,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => (value?.trim().length ?? 0) > 500
                      ? 'Notes must be 500 characters or fewer.'
                      : null,
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _submitError!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _submitting ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submitting ? null : _submit,
          child: _submitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save customer'),
        ),
      ],
    );
  }
}
