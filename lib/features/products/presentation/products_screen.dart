import 'package:ai_business_os/features/staff/business_role.dart';
import 'package:ai_business_os/app/stat_tile.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key});

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {


  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _businessId;
  List<Map<String, dynamic>> _products = [];
  bool _isStaff = false;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  @override
  void dispose() {

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
          .select('id, name, unit, price, low_stock_threshold, created_at')
          .eq('business_id', businessId)
          .eq('is_active', true)
          .order('created_at', ascending: false);

      if (!mounted) return;

      // Cost prices are hidden from staff. Managers get them from a
      // manager-only function; if it is not available the costs stay empty.
      final role = await loadMyRole();
      final costById = <String, dynamic>{};
      if (isManagerRole(role)) {
        try {
          final costs = await _client.rpc(
            'get_product_costs',
            params: {'p_business_id': businessId},
          );
          for (final c in (costs as List)) {
            costById[c['id'].toString()] = c['cost_price'];
          }
        } catch (_) {
          // Costs stay empty.
        }
      }
      if (!mounted) return;

      setState(() {
        _businessId = businessId;
        _isStaff = role == 'staff';
        _products = rows.map((row) {
          final product = Map<String, dynamic>.from(row);
          product['cost_price'] = costById[product['id'].toString()];
          return product;
        }).toList();
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

  Future<void> _openAddPage() async {
    final saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        fullscreenDialog: true,
        builder: (_) => _AddProductPage(businessId: _businessId),
      ),
    );
    if (saved != true || !mounted) return;
    await _loadProducts();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Product saved successfully.')),
    );
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
    final costController = TextEditingController(
      text: product['cost_price']?.toString() ?? '',
    );
    final lowController = TextEditingController(
      text: product['low_stock_threshold'] == null
          ? ''
          : (product['low_stock_threshold'] as num).toStringAsFixed(
              (product['low_stock_threshold'] as num) % 1 == 0 ? 0 : 3,
            ),
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
              const SizedBox(height: 12),
              TextFormField(
                controller: costController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Cost price (optional)',
                  helperText: 'What you paid for one unit. Used to work out profit.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final cost = double.tryParse(text);
                  if (cost == null || !cost.isFinite || cost < 0) {
                    return 'Enter a valid cost (0 or greater) or leave empty.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: lowController,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'Low-stock alert level (optional)',
                  helperText: 'Warn when this many or fewer are left. Empty = 5.',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return null;
                  final level = double.tryParse(text);
                  if (level == null || !level.isFinite || level < 0) {
                    return 'Enter 0 or greater, or leave empty.';
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
    final costText = costController.text.trim();
    final cost = costText.isEmpty ? null : double.parse(costText);
    final lowText = lowController.text.trim();
    final low = lowText.isEmpty ? null : double.parse(lowText);

    if (!mounted) return;
    setState(() => _saving = true);

    try {
      await _client
          .from('products')
          .update({
            'name': name,
            'unit': unit,
            'price': price,
            'cost_price': cost,
            'low_stock_threshold': low,
          })
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
    return Scaffold(
      floatingActionButton: _isStaff
          ? null
          : FloatingActionButton.extended(
              onPressed: _saving || _loading ? null : _openAddPage,
              icon: const Icon(Icons.add),
              label: const Text('Add product'),
            ),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [

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
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.inventory_2_rounded,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              product['name'].toString(),
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                InfoPill(product['unit'].toString()),
                                InfoPill(
                                  'Price ${((product['price'] as num?) ?? 0).toStringAsFixed(2)}',
                                  color: const Color(0xFF18794E),
                                ),
                                if (!_isStaff)
                                  InfoPill(
                                    product['cost_price'] == null
                                        ? 'No cost set'
                                        : 'Cost ${(product['cost_price'] as num).toStringAsFixed(2)}',
                                    color: product['cost_price'] == null
                                        ? const Color(0xFFB4232F)
                                        : null,
                                  ),
                                if (product['low_stock_threshold'] != null)
                                  InfoPill(
                                    'Low at ${(product['low_stock_threshold'] as num).toStringAsFixed((product['low_stock_threshold'] as num) % 1 == 0 ? 0 : 3)}',
                                    color: const Color(0xFFA15C08),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!_isStaff)
                        Wrap(
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
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

class _AddProductPage extends StatefulWidget {
  const _AddProductPage({required this.businessId});

  final String? businessId;

  @override
  State<_AddProductPage> createState() => _AddProductPageState();
}

class _AddProductPageState extends State<_AddProductPage> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _unitController = TextEditingController();
  final _priceController = TextEditingController(text: '0');
  final _costController = TextEditingController();
  final _lowController = TextEditingController();
  bool _saving = false;

  static const _units = ['piece', 'kg', 'bottle', 'dozen', 'box', 'litre'];

  @override
  void dispose() {
    _nameController.dispose();
    _unitController.dispose();
    _priceController.dispose();
    _costController.dispose();
    _lowController.dispose();
    super.dispose();
  }

  String? _optionalNumber(String? value, String message) {
    final text = value?.trim() ?? '';
    if (text.isEmpty) return null;
    final n = double.tryParse(text);
    if (n == null || !n.isFinite || n < 0) return message;
    return null;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final businessId = widget.businessId;
    if (businessId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Business is not loaded. Refresh and try again.'),
        ),
      );
      return;
    }

    final costText = _costController.text.trim();
    final lowText = _lowController.text.trim();

    setState(() => _saving = true);
    try {
      await Supabase.instance.client.from('products').insert({
        'business_id': businessId,
        'name': _nameController.text.trim(),
        'unit': _unitController.text.trim(),
        'price': num.parse(_priceController.text.trim()),
        'cost_price': costText.isEmpty ? null : num.parse(costText),
        'low_stock_threshold': lowText.isEmpty ? null : num.parse(lowText),
      });
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save product: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Add product'),
        leading: IconButton(
          tooltip: 'Close',
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
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
                        TextFormField(
                          controller: _nameController,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Product name',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter product name.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final u in _units)
                              ActionChip(
                                label: Text(u),
                                onPressed: _saving
                                    ? null
                                    : () => setState(
                                          () => _unitController.text = u,
                                        ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _unitController,
                          enabled: !_saving,
                          decoration: const InputDecoration(
                            labelText: 'Unit label',
                            hintText: 'For example: piece, bottle, kg',
                          ),
                          validator: (v) => v == null || v.trim().isEmpty
                              ? 'Enter unit label.'
                              : null,
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
                        TextFormField(
                          controller: _priceController,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Selling price',
                            prefixText: 'PKR ',
                          ),
                          validator: (v) {
                            final price = double.tryParse(v?.trim() ?? '');
                            if (price == null || !price.isFinite || price < 0) {
                              return 'Enter a valid price (0 or greater).';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _costController,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Cost price (optional)',
                            prefixText: 'PKR ',
                            helperText:
                                'Visible to the owner only. Used to work out profit.',
                          ),
                          validator: (v) => _optionalNumber(
                            v,
                            'Enter a valid cost (0 or greater) or leave empty.',
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _lowController,
                          enabled: !_saving,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Low-stock alert level (optional)',
                            helperText: 'Warn when this many or fewer are left. Empty = 5.',
                          ),
                          validator: (v) => _optionalNumber(
                            v,
                            'Enter 0 or greater, or leave empty.',
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
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
          child: FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save product'),
          ),
        ),
      ),
    );
  }
}
