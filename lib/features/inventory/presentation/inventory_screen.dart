
import 'package:ai_business_os/app/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final SupabaseClient _client = Supabase.instance.client;

  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadInventory();
  }

  Future<void> _loadInventory() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final user = _client.auth.currentUser;
      if (user == null) {
        throw Exception('Please log in first.');
      }

      final memberships = await _client
          .from('business_members')
          .select('business_id')
          .eq('user_id', user.id)
          .eq('status', 'active')
          .limit(1);

      if (memberships.isEmpty) {
        throw Exception('No active business membership found.');
      }

      final businessId = memberships.first['business_id'].toString();

      final products = await _client
          .from('products')
          .select('id, name, unit')
          .eq('business_id', businessId)
          .order('name');

      final stockRows = await _client
          .from('inventory')
          .select('product_id, quantity')
          .eq('business_id', businessId);

      final stockByProduct = <String, num>{};

      for (final row in stockRows) {
        stockByProduct[row['product_id'].toString()] =
            (row['quantity'] as num?) ?? 0;
      }

      final items = products.map<Map<String, dynamic>>((product) {
        final id = product['id'].toString();
        return {
          'id': id,
          'name': product['name'].toString(),
          'unit': product['unit'].toString(),
          'quantity': stockByProduct[id] ?? 0,
        };
      }).toList();

      if (!mounted) return;

      setState(() {
        _items = items;
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

  Future<void> _changeStock(
    Map<String, dynamic> item,
    bool stockIn,
  ) async {
    if (_saving) return;

    final quantityController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(stockIn ? 'Stock In' : 'Stock Out'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${item['name']} (${item['unit']})\n'
                'Current stock: ${item['quantity']}',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: quantityController,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantity',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final quantity = num.tryParse(value?.trim() ?? '');
                  if (quantity == null ||
                      !quantity.isFinite ||
                      quantity <= 0) {
                    return 'Enter a quantity greater than zero.';
                  }

                  if (!stockIn && quantity > (item['quantity'] as num)) {
                    return 'Not enough stock available.';
                  }

                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(
                  dialogContext,
                  double.parse(quantityController.text.trim()),
                );
              }
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );


    if (amount == null || !mounted || _saving) return;
    if (!amount.isFinite || amount <= 0) return;

    final productId = item['id'].toString();

    setState(() => _saving = true);

    try {
      await _client.rpc(
        'adjust_stock',
        params: {
          'p_product_id': productId,
          'p_delta': stockIn ? amount : -amount,
          'p_reason': stockIn ? 'Stock in' : 'Stock out',
        },
      );

      await _loadInventory();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            stockIn
                ? 'Stock added successfully.'
                : 'Stock reduced successfully.',
          ),
        ),
      );
    } on PostgrestException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update stock: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Inventory'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            onPressed: _loading || _saving ? null : _loadInventory,
            icon: const Icon(Icons.refresh),
          ),
        ],
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
                        Text(_error!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: _loadInventory,
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                )
              : _items.isEmpty
                  ? const Center(
                      child: Text(
                        'No products found. Add products first.',
                      ),
                    )
                  : Stack(
                      children: [
                        ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: StatTile(
                                    icon: Icons.category_rounded,
                                    accent: const Color(0xFF2B6CB0),
                                    label: 'Products',
                                    value: '${_items.length}',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: StatTile(
                                    icon: Icons.inventory_2_rounded,
                                    accent: const Color(0xFF145C4A),
                                    label: 'Total units',
                                    value: _items
                                        .fold<num>(
                                          0,
                                          (sum, item) =>
                                              sum + (item['quantity'] as num),
                                        )
                                        .toString(),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: StatTile(
                                    icon: Icons.remove_shopping_cart_rounded,
                                    accent: const Color(0xFFB4232F),
                                    label: 'Out of stock',
                                    value:
                                        '${_items.where((i) => (i['quantity'] as num) <= 0).length}',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            for (final item in _items)
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 44,
                                            height: 44,
                                            decoration: BoxDecoration(
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary
                                                  .withValues(alpha: 0.12),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                            ),
                                            child: Icon(
                                              Icons.inventory_2_rounded,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item['name'].toString(),
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .titleSmall
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                ),
                                                Text(
                                                  'Available: ${item['quantity']} ${item['unit']}',
                                                  style: Theme.of(context)
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color: (item['quantity']
                                                                    as num) <=
                                                                0
                                                            ? Theme.of(context)
                                                                .colorScheme
                                                                .error
                                                            : Theme.of(context)
                                                                .colorScheme
                                                                .onSurfaceVariant,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 12),
                                      Wrap(
                                        spacing: 8,
                                        children: [
                                          FilledButton.icon(
                                            onPressed: _saving
                                                ? null
                                                : () => _changeStock(
                                                      item,
                                                      true,
                                                    ),
                                            icon: const Icon(
                                              Icons.add,
                                            ),
                                            label: const Text('Stock In'),
                                          ),
                                          OutlinedButton.icon(
                                            onPressed: _saving ||
                                                    (item['quantity'] as num) <=
                                                        0
                                                ? null
                                                : () => _changeStock(
                                                      item,
                                                      false,
                                                    ),
                                            icon: const Icon(
                                              Icons.remove,
                                            ),
                                            label: const Text('Stock Out'),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                        if (_saving)
                          const Positioned(
                            top: 0,
                            left: 0,
                            right: 0,
                            child: LinearProgressIndicator(),
                          ),
                      ],
                    ),
    );
  }
}

