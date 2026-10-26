import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  final _priceController = TextEditingController(text: '0');

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _businessId;
  List<Map<String, dynamic>> _products = [];

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  Future<void> _loadProducts() async {
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

      final rows = await _client
          .from('products')
          .select('id, name, unit, price, created_at')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      if (!mounted) return;

      setState(() {
        _businessId = businessId;
        _products = rows
            .map((row) => Map<String, dynamic>.from(row))
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

  Future<void> _addProduct() async {
    final name = _nameController.text.trim();
    final unit = _unitController.text.trim();
    final price = num.tryParse(_priceController.text.trim());

    if (name.isEmpty || unit.isEmpty ||
        price == null || !price.isFinite || price < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid price (0 or greater), name and unit.')),
      );
      return;
    }

    if (name.isEmpty || unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter product name and unit.')),
      );
      return;
    }

    final businessId = _businessId;
    if (businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business is not loaded. Refresh and try again.'),
        ),
      );
      return;
    }

    setState(() => _saving = true);

    try {
      await _client.from('products').insert({
        'business_id': businessId,
        'name': name,
        'unit': unit,
        'price': price,
      });

      _nameController.clear();
      _unitController.clear();
      _priceController.text = '0';

      await _loadProducts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product saved successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save product: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editProduct(Map<String, dynamic> product) async {
    final id = product['id']?.toString();
    final businessId = _businessId;

    if (id == null || businessId == null) return;

    final nameController = TextEditingController(
      text: product['name']?.toString() ?? '',
    );
    final unitController = TextEditingController(
      text: product['unit']?.toString() ?? '',
    );
    final priceController = TextEditingController(
      text: product['price']?.toString() ?? '0',
    );

    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit product'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: nameController,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Product name',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter product name.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: unitController,
                decoration: const InputDecoration(
                  labelText: 'Unit label',
                  hintText: 'piece, bottle, kg',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().isEmpty
                    ? 'Enter unit label.'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: priceController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Price',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final price = double.tryParse(value?.trim() ?? '');
                  if (price == null || !price.isFinite || price < 0) {
                    return 'Enter a valid price (0 or greater).';
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );

    if (confirmed != true) {
      return;
    }

    final name = nameController.text.trim();
    final unit = unitController.text.trim();
    final price = double.parse(priceController.text.trim());

    if (!mounted) return;
    setState(() => _saving = true);

    try {
      await _client
          .from('products')
          .update({'name': name, 'unit': unit, 'price': price})
          .eq('id', id)
          .eq('business_id', businessId);

      await _loadProducts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product updated successfully.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update product: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _archiveProduct(Map<String, dynamic> product) async {
    final id = product['id']?.toString();
    final businessId = _businessId;

    if (id == null || businessId == null) return;

    final name = product['name']?.toString() ?? 'this product';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Archive product?'),
        content: Text(
          'Archive "$name"? It will be hidden from the product list and new '
          'orders, but past orders keep their history.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
              foregroundColor: Theme.of(dialogContext).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Archive'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _saving = true);

    try {
      await _client
          .from('products')
          .update({'is_active': false})
          .eq('id', id)
          .eq('business_id', businessId);

      await _loadProducts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Product archived.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not archive product: $e')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Products'),
        actions: [
          IconButton(
            onPressed: _loading || _saving ? null : _loadProducts,
            tooltip: 'Refresh products',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            color: colors.secondaryContainer,
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Business products',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  SizedBox(height: 6),
                  Text(
                    'Products are saved to your business database. '
                    'Price and stock management will be added separately.',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Product name',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _priceController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Price',
                hintText: '0.00',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _unitController,
            decoration: const InputDecoration(
              labelText: 'Unit label',
              hintText: 'For example: piece, bottle, kg',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(
              onPressed: _saving || _loading ? null : _addProduct,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_saving ? 'Please wait...' : 'Save product'),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'Saved products (${_products.length})',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_error != null)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Could not load products.'),
                    const SizedBox(height: 8),
                    SelectableText(_error!),
                    TextButton(
                      onPressed: _loadProducts,
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_products.isEmpty)
            const Text('No products yet. Add your first product above.')
          else
            for (final product in _products)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.inventory_2_outlined),
                  title: Text(product['name'].toString()),
                  subtitle: Text(
                    '${product['unit']} \u2022 Price: '
                    '${((product['price'] as num?) ?? 0).toStringAsFixed(2)}',
                  ),
                  trailing: Wrap(
                    spacing: 0,
                    children: [
                      IconButton(
                        tooltip: 'Edit product',
                        onPressed: _saving || _loading
                            ? null
                            : () => _editProduct(product),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Archive product',
                        onPressed: _saving || _loading
                            ? null
                            : () => _archiveProduct(product),
                        icon: const Icon(Icons.archive_outlined),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}
