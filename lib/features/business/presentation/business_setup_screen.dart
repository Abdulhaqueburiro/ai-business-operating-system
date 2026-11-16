import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class BusinessSetupScreen extends StatefulWidget {
  const BusinessSetupScreen({super.key, required this.onBusinessCreated});

  final VoidCallback onBusinessCreated;

  @override
  State<BusinessSetupScreen> createState() => _BusinessSetupScreenState();
}

class _BusinessSetupScreenState extends State<BusinessSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String _businessType = 'other';
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _createBusiness() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await Supabase.instance.client.rpc(
        'create_business',
        params: {
          'p_name': _nameController.text.trim(),
          'p_business_type': _businessType,
          'p_currency_code': 'PKR',
          'p_timezone': 'Asia/Karachi',
        },
      );
      if (mounted) widget.onBusinessCreated();
    } on PostgrestException catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Business could not be created: ${error.message}',
        );
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Could not create business. Please check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set up your business'),
        actions: [
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Center(
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [Color(0xFF1B7A62), Color(0xFF0E4034)],
                            ),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: const Icon(
                            Icons.storefront_rounded,
                            size: 34,
                            color: Colors.white,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Create your business workspace',
                        style: Theme.of(context).textTheme.headlineSmall,
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'This creates your business and assigns your account as its owner.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 24),
                      TextFormField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Business name',
                          hintText: 'e.g. My Store',
                          prefixIcon: Icon(Icons.storefront_outlined),
                        ),
                        maxLength: 120,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Enter a business name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'Business type',
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (final t in const [
                            ['retail', 'Retail / shop', Icons.storefront_rounded],
                            ['wholesale', 'Wholesale', Icons.warehouse_rounded],
                            ['services', 'Services', Icons.handyman_rounded],
                            ['ecommerce', 'E-commerce', Icons.shopping_cart_rounded],
                            ['other', 'Other', Icons.category_rounded],
                          ])
                            ChoiceChip(
                              avatar: Icon(
                                t[2] as IconData,
                                size: 18,
                                color: _businessType == t[0]
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.primary,
                              ),
                              label: Text(t[1] as String),
                              selected: _businessType == t[0],
                              showCheckmark: false,
                              selectedColor: Theme.of(context).colorScheme.primary,
                              labelStyle: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _businessType == t[0]
                                    ? Theme.of(context).colorScheme.onPrimary
                                    : Theme.of(context).colorScheme.onSurface,
                              ),
                              onSelected: _busy
                                  ? null
                                  : (_) => setState(
                                        () => _businessType = t[0] as String,
                                      ),
                            ),
                        ],
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 20),
                      FilledButton(
                        onPressed: _busy ? null : _createBusiness,
                        child: _busy
                            ? const CircularProgressIndicator()
                            : const Text('Create workspace'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
