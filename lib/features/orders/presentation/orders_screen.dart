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

typedef _SubmitOrder = Future<void> Function({
  required String? customerName,
  required String? customerId,
  required String? notes,
  required List<Map<String, Object>> items,
  required String idempotencyKey,
});

class OrdersScreen extends StatefulWidget {
  const OrdersScreen({super.key});

  @override
  State<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends State<OrdersScreen> {
  SupabaseClient get _client => Supabase.instance.client;

  bool _loading = true;
  String? _error;
  String? _businessId;
  List<Map<String, dynamic>> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
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

  Future<void> _loadOrders() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final businessId = await _getActiveBusinessId();

      final rows = await _client
          .from('sales_orders')
          .select(
            'id, order_number, customer_name, status, total_amount, notes, created_at',
          )
          .eq('business_id', businessId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _businessId = businessId;
        _orders = rows.map((row) => Map<String, dynamic>.from(row)).toList();
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

  Future<List<Map<String, dynamic>>> _loadProducts() async {
    final businessId = _businessId ?? await _getActiveBusinessId();

    final rows = await _client
        .from('products')
        .select('id, name, unit, price')
        .eq('business_id', businessId)
        .eq('is_active', true)
        .order('name');

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  // Saved customers are optional: if they cannot be loaded, orders can still
  // be created with a typed name.
  Future<List<Map<String, dynamic>>> _loadCustomers() async {
    try {
      final businessId = _businessId ?? await _getActiveBusinessId();

      final rows = await _client
          .from('customers')
          .select('id, name, phone, archived_at')
          .eq('business_id', businessId)
          .order('name');

      return rows
          .map((row) => Map<String, dynamic>.from(row))
          .where((row) => row['archived_at'] == null)
          .toList();
    } catch (_) {
      return <Map<String, dynamic>>[];
    }
  }

  Future<void> _createOrder() async {
    final businessId = _businessId;

    if (businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Business is not loaded. Refresh first.')),
      );
      return;
    }

    List<Map<String, dynamic>> products;
    try {
      products = await _loadProducts();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not load products: $e')),
      );
      return;
    }

    if (!mounted) return;

    // Empty-list check comes BEFORE any use of products.first.
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a product first, then create an order.'),
        ),
      );
      return;
    }

    final customers = await _loadCustomers();

    if (!mounted) return;

    final created = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _NewOrderDialog(
        products: products,
        customers: customers,
        onSubmit: ({
          required customerName,
          required customerId,
          required notes,
          required items,
          required idempotencyKey,
        }) async {
          await _client.rpc(
            'create_sales_order',
            params: {
              'p_business_id': businessId,
              'p_items': items,
              'p_customer_name': customerName,
              'p_notes': notes,
              'p_idempotency_key': idempotencyKey,
              'p_customer_id': customerId,
            },
          );
        },
      ),
    );

    if (created != true || !mounted) return;

    await _loadOrders();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Order created.')),
    );
  }

  Future<void> _openOrder(Map<String, dynamic> order) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => _OrderDetailDialog(order: order),
    );

    if (result == null || !mounted) return;

    await _loadOrders();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result == 'confirmed' ? 'Order confirmed.' : 'Order cancelled.',
        ),
      ),
    );
  }

  String _formatDate(dynamic value) {
    final date = DateTime.tryParse(value?.toString() ?? '');
    if (date == null) return 'Date unavailable';

    final local = date.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    return '$day/$month/${local.year}';
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales & Orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh orders',
            onPressed: _loading ? null : _loadOrders,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _loading ? null : _createOrder,
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New order'),
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
                        const Text('Could not load sales orders.'),
                        const SizedBox(height: 8),
                        SelectableText(_error!),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadOrders,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                  children: [
                    Card(
                      color: colors.primaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Sales overview',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text('Total orders: ${_orders.length}'),
                            Text(
                              'Pending orders: ${_orders.where((o) => o['status'] == 'pending').length}',
                            ),
                            Text(
                              'Order value: ${_orders.fold<num>(0, (sum, o) => sum + ((o['total_amount'] as num?) ?? 0))}',
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Orders',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    if (_orders.isEmpty)
                      const Card(
                        child: Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'No orders yet. Tap New order to create one.',
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final order in _orders)
                        Card(
                          child: ListTile(
                            leading: const CircleAvatar(
                              child: Icon(Icons.receipt_long),
                            ),
                            title: Text(
                              'Order #${order['order_number']}',
                            ),
                            subtitle: Text(
                              '${(order['customer_name']?.toString().trim().isNotEmpty ?? false) ? order['customer_name'] : 'No customer name'}'
                              '\n${_formatDate(order['created_at'])}'
                              '\nStatus: ${order['status']}',
                            ),
                            isThreeLine: true,
                            onTap: () => _openOrder(order),
                            trailing: Text(
                              (order['total_amount'] as num? ?? 0)
                                  .toStringAsFixed(2),
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                          ),
                        ),
                  ],
                ),
    );
  }
}

class _OrderLine {
  _OrderLine() : quantity = TextEditingController(text: '1');

  String? productId;
  final TextEditingController quantity;

  void dispose() => quantity.dispose();
}

class _NewOrderDialog extends StatefulWidget {
  const _NewOrderDialog({
    required this.products,
    required this.customers,
    required this.onSubmit,
  });

  final List<Map<String, dynamic>> products;
  final List<Map<String, dynamic>> customers;
  final _SubmitOrder onSubmit;

  @override
  State<_NewOrderDialog> createState() => _NewOrderDialogState();
}

class _NewOrderDialogState extends State<_NewOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _customerController = TextEditingController();
  final _notesController = TextEditingController();
  final List<_OrderLine> _lines = [_OrderLine()];
  String? _customerId;

  // One key per dialog session: a retry after a failure re-uses it, so the
  // database can never create a duplicate order.
  final String _idempotencyKey = _newUuidV4();

  bool _submitting = false;
  String? _submitError;

  late final Map<String, Map<String, dynamic>> _byId = {
    for (final p in widget.products) p['id'].toString(): p,
  };

  @override
  void dispose() {
    _customerController.dispose();
    _notesController.dispose();
    for (final line in _lines) {
      line.dispose();
    }
    super.dispose();
  }

  num _priceOf(Map<String, dynamic> product) =>
      (product['price'] as num?) ?? 0;

  double? _parseQuantity(String? text) {
    final value = double.tryParse(text?.trim() ?? '');
    if (value == null || !value.isFinite || value <= 0) return null;
    return value;
  }

  double get _estimatedTotal {
    var total = 0.0;
    for (final line in _lines) {
      final product = _byId[line.productId];
      final quantity = _parseQuantity(line.quantity.text);
      if (product == null || quantity == null) continue;
      total += _priceOf(product).toDouble() * quantity;
    }
    return total;
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_formKey.currentState!.validate()) return;

    final items = <Map<String, Object>>[];
    for (final line in _lines) {
      final quantity = _parseQuantity(line.quantity.text);
      final productId = line.productId;
      if (productId == null || quantity == null) return;
      items.add({'product_id': productId, 'quantity': quantity});
    }

    final customer = _customerId == null ? _customerController.text.trim() : '';
    final notes = _notesController.text.trim();

    setState(() {
      _submitting = true;
      _submitError = null;
    });

    try {
      await widget.onSubmit(
        customerName: customer.isEmpty ? null : customer,
        customerId: _customerId,
        notes: notes.isEmpty ? null : notes,
        items: items,
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
        _submitError = 'Could not create order: $e';
        _submitting = false;
      });
    }
  }

  String _customerLabel(Map<String, dynamic> customer) {
    final name = customer['name']?.toString() ?? '';
    final phone = customer['phone']?.toString().trim() ?? '';
    return phone.isEmpty ? name : '$name - $phone';
  }

  Widget _buildLine(int index, _OrderLine line) {
    final product = _byId[line.productId];
    final unit = product?['unit']?.toString();

    return Padding(
      key: ObjectKey(line),
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DropdownButtonFormField<String>(
            initialValue: line.productId,
            isExpanded: true,
            decoration: InputDecoration(
              labelText: 'Product ${index + 1}',
              border: const OutlineInputBorder(),
            ),
            items: widget.products.map((p) {
              return DropdownMenuItem<String>(
                value: p['id'].toString(),
                child: Text(
                  '${p['name']} - ${_priceOf(p).toStringAsFixed(2)}',
                  overflow: TextOverflow.ellipsis,
                ),
              );
            }).toList(),
            onChanged: _submitting
                ? null
                : (value) => setState(() => line.productId = value),
            validator: (value) {
              if (value == null) return 'Select a product.';
              final duplicate = _lines.any(
                (other) => !identical(other, line) && other.productId == value,
              );
              if (duplicate) return 'This product is already in the order.';
              return null;
            },
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: line.quantity,
                  enabled: !_submitting,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: unit,
                    border: const OutlineInputBorder(),
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) => _parseQuantity(value) == null
                      ? 'Enter a quantity greater than zero.'
                      : null,
                ),
              ),
              IconButton(
                tooltip: 'Remove item',
                onPressed: _submitting || _lines.length == 1
                    ? null
                    : () => setState(() {
                          _lines.remove(line);
                          // Dispose after the frame so the field is unmounted.
                          WidgetsBinding.instance.addPostFrameCallback(
                            (_) => line.dispose(),
                          );
                        }),
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Create sales order'),
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
                for (var i = 0; i < _lines.length; i++) _buildLine(i, _lines[i]),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => setState(() => _lines.add(_OrderLine())),
                    icon: const Icon(Icons.add),
                    label: const Text('Add item'),
                  ),
                ),
                const SizedBox(height: 8),
                if (widget.customers.isNotEmpty) ...[
                  DropdownButtonFormField<String?>(
                    initialValue: _customerId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Saved customer (optional)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('No saved customer'),
                      ),
                      for (final customer in widget.customers)
                        DropdownMenuItem<String?>(
                          value: customer['id'].toString(),
                          child: Text(
                            _customerLabel(customer),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: _submitting
                        ? null
                        : (value) => setState(() => _customerId = value),
                  ),
                  const SizedBox(height: 12),
                ],
                if (_customerId == null)
                  TextFormField(
                    controller: _customerController,
                    enabled: !_submitting,
                    decoration: const InputDecoration(
                      labelText: 'Customer name (optional)',
                      border: OutlineInputBorder(),
                    ),
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
                ),
                const SizedBox(height: 16),
                Text(
                  'Estimated total: PKR ${_estimatedTotal.toStringAsFixed(2)}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const Text(
                  'The final total is calculated by the server from current '
                  'product prices.',
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
              : const Text('Create order'),
        ),
      ],
    );
  }
}


String _formatNumber(num? value) {
  final number = value ?? 0;
  if (number == number.roundToDouble()) return number.toInt().toString();
  return number.toString();
}

class _OrderDetailDialog extends StatefulWidget {
  const _OrderDetailDialog({required this.order});

  final Map<String, dynamic> order;

  @override
  State<_OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends State<_OrderDetailDialog> {
  SupabaseClient get _client => Supabase.instance.client;

  late final Future<List<Map<String, dynamic>>> _itemsFuture = _loadItems();

  bool _busy = false;
  String? _error;

  String get _orderId => widget.order['id'].toString();
  String get _status => widget.order['status']?.toString() ?? '';

  Future<List<Map<String, dynamic>>> _loadItems() async {
    final rows = await _client
        .from('sales_order_items')
        .select('quantity, unit_price, line_total, products(name, unit)')
        .eq('order_id', _orderId)
        .order('created_at');

    return rows.map((row) => Map<String, dynamic>.from(row)).toList();
  }

  Map<String, dynamic>? _productOf(Map<String, dynamic> row) {
    final raw = row['products'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty && raw.first is Map) {
      return Map<String, dynamic>.from(raw.first as Map);
    }
    return null;
  }

  Future<void> _act({
    required String function,
    required String question,
    required String result,
  }) async {
    if (_busy) return;

    final approved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(question),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('No'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    );

    if (approved != true || !mounted) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await _client.rpc(function, params: {'p_order_id': _orderId});
      if (!mounted) return;
      Navigator.of(context).pop(result);
    } on PostgrestException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not update order: $e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = widget.order;
    final customer = order['customer_name']?.toString().trim() ?? '';
    final notes = order['notes']?.toString().trim() ?? '';
    final total = (order['total_amount'] as num?) ?? 0;

    return AlertDialog(
      title: Text('Order #${order['order_number']}'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Status: $_status'),
              Text('Customer: ${customer.isEmpty ? 'No customer name' : customer}'),
              if (notes.isNotEmpty) Text('Notes: $notes'),
              const SizedBox(height: 12),
              Text('Items', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              FutureBuilder<List<Map<String, dynamic>>>(
                future: _itemsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(8),
                      child: LinearProgressIndicator(),
                    );
                  }
                  if (snapshot.hasError) {
                    return Text('Could not load items: ${snapshot.error}');
                  }
                  final items = snapshot.data ?? [];
                  if (items.isEmpty) {
                    return const Text('This order has no items.');
                  }
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final row in items)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(
                            '${_productOf(row)?['name'] ?? 'Unknown product'}: '
                            '${_formatNumber(row['quantity'] as num?)} '
                            '${_productOf(row)?['unit'] ?? ''} x '
                            '${((row['unit_price'] as num?) ?? 0).toStringAsFixed(2)} = '
                            '${((row['line_total'] as num?) ?? 0).toStringAsFixed(2)}',
                          ),
                        ),
                    ],
                  );
                },
              ),
              const Divider(),
              Text(
                'Total: PKR ${total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (_status == 'pending')
                const Text('Confirming deducts stock from inventory.'),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
        if (_status == 'pending' || _status == 'confirmed')
          TextButton(
            onPressed: _busy
                ? null
                : () => _act(
                      function: 'cancel_sales_order',
                      question: _status == 'confirmed'
                          ? 'Cancel this order? Stock will be returned.'
                          : 'Cancel this order?',
                      result: 'cancelled',
                    ),
            child: const Text('Cancel order'),
          ),
        if (_status == 'pending')
          FilledButton(
            onPressed: _busy
                ? null
                : () => _act(
                      function: 'confirm_sales_order',
                      question: 'Confirm this order? Stock will be deducted.',
                      result: 'confirmed',
                    ),
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Confirm order'),
          ),
      ],
    );
  }
}
