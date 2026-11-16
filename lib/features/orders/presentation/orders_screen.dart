import 'dart:math';

import 'package:ai_business_os/app/status_chip.dart';
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
  required bool onCredit,
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
  String _filter = 'all';

  List<Map<String, dynamic>> get _visibleOrders => _filter == 'all'
      ? _orders
      : [for (final o in _orders) if (o['status'] == _filter) o];

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
            'id, order_number, customer_name, status, total_amount, notes, created_at, on_credit',
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

    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => _NewOrderDialog(
        products: products,
        customers: customers,
        onSubmit: ({
          required customerName,
          required customerId,
          required onCredit,
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
              'p_on_credit': onCredit,
            },
          );
        },
        ),
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
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => _OrderDetailDialog(order: order),
      ),
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
        title: const Text('Orders'),
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
                    Row(
                      children: [
                        Expanded(
                          child: _OrderStat(
                            icon: Icons.receipt_long_rounded,
                            accent: colors.primary,
                            label: 'Total orders',
                            value: '${_orders.length}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OrderStat(
                            icon: Icons.pending_actions_rounded,
                            accent: const Color(0xFFA15C08),
                            label: 'Pending',
                            value:
                                '${_orders.where((o) => o['status'] == 'pending').length}',
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _OrderStat(
                            icon: Icons.paid_rounded,
                            accent: const Color(0xFF18794E),
                            label: 'Order value',
                            value: _orders
                                .fold<num>(
                                  0,
                                  (sum, o) =>
                                      sum + ((o['total_amount'] as num?) ?? 0),
                                )
                                .round()
                                .toString(),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final f in const [
                            ['all', 'All'],
                            ['pending', 'Pending'],
                            ['confirmed', 'Confirmed'],
                            ['cancelled', 'Cancelled'],
                          ])
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ChoiceChip(
                                label: Text(f[1]),
                                selected: _filter == f[0],
                                showCheckmark: false,
                                selectedColor: colors.primary,
                                labelStyle: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: _filter == f[0]
                                      ? colors.onPrimary
                                      : colors.onSurface,
                                ),
                                onSelected: (_) =>
                                    setState(() => _filter = f[0]),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
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
                      for (final order in _visibleOrders)
                        Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () => _openOrder(order),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Row(
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: colors.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      Icons.receipt_long_rounded,
                                      color: colors.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Order #${order['order_number']}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleSmall
                                              ?.copyWith(
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          '${(order['customer_name']?.toString().trim().isNotEmpty ?? false) ? order['customer_name'] : 'No customer name'}'
                                          ' · ${_formatDate(order['created_at'])}',
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodySmall
                                              ?.copyWith(
                                                color: colors.onSurfaceVariant,
                                              ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        (order['total_amount'] as num? ?? 0)
                                            .toStringAsFixed(2),
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        children: [
                                          if (order['on_credit'] == true)
                                            const StatusChip(status: 'udhaar'),
                                          StatusChip(
                                            status:
                                                order['status']?.toString() ??
                                                    '',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
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
  bool _onCredit = false;

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
        onCredit: _customerId != null && _onCredit,
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

  void _step(_OrderLine line, double delta) {
    final current = _parseQuantity(line.quantity.text) ?? 0;
    var next = current + delta;
    if (next < 1) next = 1;
    setState(() => line.quantity.text = _formatNumber(next));
  }

  Widget _buildLine(int index, _OrderLine line) {
    final product = _byId[line.productId];
    final unit = product?['unit']?.toString();
    final quantity = _parseQuantity(line.quantity.text);
    final lineTotal = (product == null || quantity == null)
        ? null
        : _priceOf(product).toDouble() * quantity;

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              IconButton.outlined(
                tooltip: 'Less',
                onPressed: _submitting ? null : () => _step(line, -1),
                icon: const Icon(Icons.remove),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 96,
                child: TextFormField(
                  controller: line.quantity,
                  enabled: !_submitting,
                  textAlign: TextAlign.center,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: 'Quantity',
                    suffixText: unit,
                  ),
                  onChanged: (_) => setState(() {}),
                  validator: (value) => _parseQuantity(value) == null
                      ? 'Enter a quantity above zero.'
                      : null,
                ),
              ),
              const SizedBox(width: 6),
              IconButton.outlined(
                tooltip: 'More',
                onPressed: _submitting ? null : () => _step(line, 1),
                icon: const Icon(Icons.add),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14, left: 8),
                  child: Text(
                    lineTotal == null
                        ? ''
                        : 'PKR ${lineTotal.toStringAsFixed(2)}',
                    textAlign: TextAlign.end,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
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

  Widget _cardTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(
        text,
        style: Theme.of(context)
            .textTheme
            .titleMedium
            ?.copyWith(fontWeight: FontWeight.w800),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final amber = dark ? const Color(0xFFF0B25A) : const Color(0xFFA15C08);
    final chosen = [
      for (final c in widget.customers)
        if (c['id'].toString() == _customerId) c,
    ];
    final chosenName = chosen.isEmpty ? null : chosen.first['name']?.toString();

    return Scaffold(
      appBar: AppBar(
        title: const Text('New order'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed:
              _submitting ? null : () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close_rounded),
        ),
      ),
      body: Form(
        key: _formKey,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _cardTitle('Customer'),
                        if (widget.customers.isNotEmpty) ...[
                          DropdownButtonFormField<String?>(
                            initialValue: _customerId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Saved customer (optional)',
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
                                : (value) => setState(() {
                                      _customerId = value;
                                      if (value == null) _onCredit = false;
                                    }),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (_customerId == null)
                          TextFormField(
                            controller: _customerController,
                            enabled: !_submitting,
                            decoration: const InputDecoration(
                              labelText: 'Customer name (optional)',
                              prefixIcon: Icon(Icons.person_outline),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _cardTitle('Items'),
                        for (var i = 0; i < _lines.length; i++)
                          _buildLine(i, _lines[i]),
                        OutlinedButton.icon(
                          onPressed: _submitting
                              ? null
                              : () => setState(() => _lines.add(_OrderLine())),
                          icon: const Icon(Icons.add),
                          label: const Text('Add product'),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_customerId != null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _cardTitle('Payment'),
                          SegmentedButton<bool>(
                            showSelectedIcon: false,
                            segments: const [
                              ButtonSegment<bool>(
                                value: false,
                                icon: Icon(Icons.payments_outlined),
                                label: Text('Cash'),
                              ),
                              ButtonSegment<bool>(
                                value: true,
                                icon: Icon(Icons.menu_book_outlined),
                                label: Text('Udhaar'),
                              ),
                            ],
                            selected: {_onCredit},
                            onSelectionChanged: _submitting
                                ? null
                                : (value) =>
                                    setState(() => _onCredit = value.first),
                          ),
                          if (_onCredit) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: amber.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Row(
                                children: [
                                  Icon(Icons.info_outline, color: amber),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Sell on credit: PKR '
                                      '${_estimatedTotal.toStringAsFixed(2)} '
                                      'will be added to '
                                      '${chosenName ?? 'the customer'}'
                                      "'s udhaar once the order is confirmed.",
                                      style: TextStyle(
                                        color: amber,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _cardTitle('Notes (optional)'),
                        TextFormField(
                          controller: _notesController,
                          enabled: !_submitting,
                          maxLines: 3,
                          decoration: const InputDecoration(
                            hintText: 'e.g. Deliver by evening',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Text(
                  'The final total is calculated by the server from current '
                  'product prices.',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _submitError!,
                    style: TextStyle(color: colors.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(top: BorderSide(color: colors.outlineVariant)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Total · ${_lines.length} '
                      '${_lines.length == 1 ? 'item' : 'items'}',
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: colors.onSurfaceVariant),
                    ),
                    Text(
                      'PKR ${_estimatedTotal.toStringAsFixed(2)}',
                      style: Theme.of(context)
                          .textTheme
                          .titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              FilledButton(
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save order'),
              ),
            ],
          ),
        ),
      ),
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
    final colors = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final amber = dark ? const Color(0xFFF0B25A) : const Color(0xFFA15C08);
    final customer = order['customer_name']?.toString().trim() ?? '';
    final notes = order['notes']?.toString().trim() ?? '';
    final total = (order['total_amount'] as num?) ?? 0;
    final placed = DateTime.tryParse(order['created_at']?.toString() ?? '')
        ?.toLocal();
    final placedText = placed == null
        ? 'Date unavailable'
        : '${placed.day.toString().padLeft(2, '0')}/'
            '${placed.month.toString().padLeft(2, '0')}/${placed.year}';
    final onCredit = order['on_credit'] == true;
    final canAct = _status == 'pending' || _status == 'confirmed';

    return Scaffold(
      appBar: AppBar(
        title: Text('Order #${order['order_number']}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(child: StatusChip(status: _status)),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          CircleAvatar(
                            backgroundColor:
                                colors.primary.withValues(alpha: 0.14),
                            foregroundColor: colors.primary,
                            child: Text(
                              customer.isEmpty
                                  ? '?'
                                  : customer.substring(0, 1).toUpperCase(),
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              customer.isEmpty ? 'No customer name' : customer,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          if (onCredit) const StatusChip(status: 'udhaar'),
                        ],
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Placed',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          Text(
                            placedText,
                            style:
                                const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Items',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 8),
                      FutureBuilder<List<Map<String, dynamic>>>(
                        future: _itemsFuture,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState !=
                              ConnectionState.done) {
                            return const Padding(
                              padding: EdgeInsets.all(8),
                              child: LinearProgressIndicator(),
                            );
                          }
                          if (snapshot.hasError) {
                            return Text(
                              'Could not load items: ${snapshot.error}',
                            );
                          }
                          final items = snapshot.data ?? [];
                          if (items.isEmpty) {
                            return const Text('This order has no items.');
                          }
                          return Column(
                            children: [
                              for (final row in items)
                                Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${_productOf(row)?['name'] ?? 'Unknown product'}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                            Text(
                                              '${_formatNumber(row['quantity'] as num?)} '
                                              '${_productOf(row)?['unit'] ?? ''} x '
                                              '${((row['unit_price'] as num?) ?? 0).toStringAsFixed(2)}',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                    color: colors
                                                        .onSurfaceVariant,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Text(
                                        ((row['line_total'] as num?) ?? 0)
                                            .toStringAsFixed(2),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                      const Divider(height: 24),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Total',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                          Text(
                            'PKR ${total.toStringAsFixed(2)}',
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: colors.primary,
                                ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (_status == 'pending')
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: amber),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          onCredit
                              ? 'When you confirm, stock goes down and '
                                  'PKR ${total.toStringAsFixed(2)} is added '
                                  'to the customer\'s udhaar.'
                              : 'Confirming deducts stock from inventory.',
                          style: TextStyle(color: amber),
                        ),
                      ),
                    ],
                  ),
                ),
              if (notes.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notes',
                          style: TextStyle(color: colors.onSurfaceVariant),
                        ),
                        const SizedBox(height: 2),
                        Text(notes),
                      ],
                    ),
                  ),
                ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(_error!, style: TextStyle(color: colors.error)),
              ],
            ],
          ),
        ),
      ),
      bottomNavigationBar: canAct
          ? SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                decoration: BoxDecoration(
                  color: colors.surface,
                  border:
                      Border(top: BorderSide(color: colors.outlineVariant)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_status == 'pending')
                      FilledButton.icon(
                        onPressed: _busy
                            ? null
                            : () => _act(
                                  function: 'confirm_sales_order',
                                  question:
                                      'Confirm this order? Stock will be deducted.',
                                  result: 'confirmed',
                                ),
                        icon: _busy
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.check_rounded),
                        label: const Text('Confirm order'),
                      ),
                    if (_status == 'pending') const SizedBox(height: 8),
                    FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: colors.error.withValues(alpha: 0.12),
                        foregroundColor: colors.error,
                      ),
                      onPressed: _busy
                          ? null
                          : () => _act(
                                function: 'cancel_sales_order',
                                question: _status == 'confirmed'
                                    ? 'Cancel this order? Stock will be returned.'
                                    : 'Cancel this order?',
                                result: 'cancelled',
                              ),
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel order'),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _OrderStat extends StatelessWidget {
  const _OrderStat({
    required this.icon,
    required this.accent,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final Color accent;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: accent),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(
            label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: colors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}