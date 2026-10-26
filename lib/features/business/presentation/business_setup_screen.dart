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
                      const Icon(Icons.storefront_outlined, size: 48),
                      const SizedBox(height: 12),
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
                          border: OutlineInputBorder(),
                        ),
                        maxLength: 120,
                        validator: (value) =>
                            (value == null || value.trim().isEmpty)
                            ? 'Enter a business name'
                            : null,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _businessType,
                        decoration: const InputDecoration(
                          labelText: 'Business type',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'other',
                            child: Text('Other'),
                          ),
                          DropdownMenuItem(
                            value: 'retail',
                            child: Text('Retail / shop'),
                          ),
                          DropdownMenuItem(
                            value: 'services',
                            child: Text('Services'),
                          ),
                          DropdownMenuItem(
                            value: 'wholesale',
                            child: Text('Wholesale'),
                          ),
                          DropdownMenuItem(
                            value: 'ecommerce',
                            child: Text('E-commerce'),
                          ),
                        ],
                        onChanged: _busy
                            ? null
                            : (value) => setState(
                                () => _businessType = value ?? 'other',
                              ),
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
