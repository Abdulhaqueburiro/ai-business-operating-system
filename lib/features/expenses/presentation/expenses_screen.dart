import 'dart:math';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const List<String> kExpenseCategories = [
  'Rent',
  'Salary',
  'Utilities',
  'Transport',
  'Supplies',
  'Marketing',
  'Other',
];

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

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

String _two(int value) => value.toString().padLeft(2, '0');

String _isoDate(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

String _displayDate(DateTime date) =>
    '${_two(date.day)}/${_two(date.month)}/${date.year}';

typedef _SubmitExpense = Future<void> Function({
  required String category,
  required double amount,
  required String date,
  required String? description,
  required String idempotencyKey,
});

class ExpensesScreen extends StatefulWidget {
  const ExpensesScreen({super.key});

  @override
  State<ExpensesScreen> createState() => _ExpensesScreenState();
}

class _ExpensesScreenState extends State<ExpensesScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  bool _loading = true;
  bool _busy = false;
  String? _error;
  String? _businessId;
  List<Map<String, dynamic>> _expenses = [];

  @override
  void initState() {
    super.initState();
    _loadExpenses();
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

  Future<void> _loadExpenses() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final businessId = await _getActiveBusinessId();

      final rows = await _client
          .from('expenses')
          .select(
            'id, category, amount, expense_date, description, archived_at',
          )
          .eq('business_id', businessId)
          .order('expense_date', ascending: false)
          .order('created_at', ascending: false)
          .limit(200);

      if (!mounted) return;

      setState(() {
        _businessId = businessId;
        _expenses = rows
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

  Future<void> _addExpense() async {
    final businessId = _businessId;

    if (businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business is not loaded. Refresh first.')),
      );
      return;
    }

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddExpenseDialog(
        onSubmit: ({
          required category,
          required amount,
          required date,
          required description,
          required idempotencyKey,
        }) async {
          await _client.rpc(
            'create_expense',
            params: {
              'p_business_id': businessId,
              'p_category': category,
              'p_amount': amount,
              'p_expense_date': date,
              'p_description': description,
              'p_idempotency_key': idempotencyKey,
            },
          );
        },
      ),
    );

    if (created != true || !mounted) return;

    await _loadExpenses();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expense saved.')),
    );
  }

  Future<void> _archiveExpense(Map<String, dynamic> expense) async {
    if (_busy) return;

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Remove this expense?'),
        content: const Text(
          'It will be hidden from the list and from future reports.',
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
        'archive_expense',
        params: {'p_expense_id': expense['id'].toString()},
      );

      await _loadExpenses();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Expense removed.')),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove expense: $e')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _dateText(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Date unavailable';
    return _displayDate(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Expenses'),
        actions: [
          IconButton(
            tooltip: 'Refresh expenses',
            onPressed: _loading || _busy ? null : _loadExpenses,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading || _busy ? null : _addExpense,
        icon: const Icon(Icons.add),
        label: const Text('Add expense'),
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
                        const Text('Could not load expenses.'),
                        const SizedBox(height: 8),
                        SelectableText(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadExpenses,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Text(
                      'Expenses (${_expenses.length})',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_expenses.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No expenses yet. Tap Add expense to record one.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final expense in _expenses)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.payments_outlined),
                            ),
                            title: Text(
                              '${expense['category']} - PKR '
                              '${((expense['amount'] as num?) ?? 0).toStringAsFixed(2)}',
                            ),
                            subtitle: Text(
                              '${_dateText(expense['expense_date'])}'
                              '${(expense['description']?.toString().trim().isNotEmpty ?? false) ? '\n${expense['description']}' : ''}',
                            ),
                            isThreeLine:
                                expense['description']?.toString().trim().isNotEmpty ??
                                    false,
                            trailing: IconButton(
                              tooltip: 'Remove expense',
                              onPressed:
                                  _busy ? null : () => _archiveExpense(expense),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}

class _AddExpenseDialog extends StatefulWidget {
  const _AddExpenseDialog({required this.onSubmit});

  final _SubmitExpense onSubmit;

  @override
  State<_AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<_AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _descriptionController = TextEditingController();

  // One key per dialog session: a retry after a failure re-uses it, so the
  // database can never save the same expense twice.
  final String _idempotencyKey = _newUuidV4();

  String? _category;
  DateTime _date = _today();
  bool _submitting = false;
  String? _submitError;

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  double? _parseAmount(String? text) {
    final value = double.tryParse(text?.trim() ?? '');
    if (value == null || !value.isFinite || value <= 0) return null;
    if (value > 9999999999.99) return null;
    return value;
  }

  Future<void> _pickDate() async {
    final today = _today();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(today.year - 5),
      lastDate: today,
    );

    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final category = _category;
    final amount = _parseAmount(_amountController.text);
    if (category == null || amount == null) return;

    final description = _descriptionController.text.trim();

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await widget.onSubmit(
        category: category,
        amount: amount,
        date: _isoDate(_date),
        description: description.isEmpty ? null : description,
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
        _submitError = 'Could not save expense: $e';
        _submitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add expense'),
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
                DropdownButtonFormField<String>(
                  initialValue: _category,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Category',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final category in kExpenseCategories)
                      DropdownMenuItem<String>(
                        value: category,
                        child: Text(category),
                      ),
                  ],
                  onChanged: _submitting
                      ? null
                      : (value) => setState(() => _category = value),
                  validator: (value) =>
                      value == null ? 'Choose a category.' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _amountController,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'Amount (PKR)',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) => _parseAmount(value) == null
                      ? 'Enter an amount greater than zero.'
                      : null,
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text('Date: ${_displayDate(_date)}'),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _descriptionController,
                  enabled: !_submitting,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    border: OutlineInputBorder(),
                  ),
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
              : const Text('Save expense'),
        ),
      ],
    );
  }
}
