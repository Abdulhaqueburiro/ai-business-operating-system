import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:ai_business_os/features/auth/presentation/auth_screen.dart';
import 'package:ai_business_os/features/business/presentation/business_setup_screen.dart';
import 'package:ai_business_os/features/home/presentation/home_screen.dart';

class AuthGate extends StatefulWidget {
  const AuthGate({
    super.key,
    required this.backendStatusMessage,
    this.testSupabaseConnection,
  });

  final String backendStatusMessage;
  final Future<SupabaseConnectionResult> Function()? testSupabaseConnection;

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool _businessCreated = false;

  Future<bool> _hasBusiness() async {
  final user = Supabase.instance.client.auth.currentUser;

  if (user == null) {
    return false;
  }

  final rows = await Supabase.instance.client
      .from('business_members')
      .select('business_id')
      .eq('user_id', user.id)
      .limit(1);

  return (rows as List).isNotEmpty;
}

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<AuthState>(
      stream: Supabase.instance.client.auth.onAuthStateChange,
      builder: (context, snapshot) {
        final session = Supabase.instance.client.auth.currentSession;
        if (session == null) {
          _businessCreated = false;
          return const AuthScreen();
        }
        if (_businessCreated) {
          return HomeScreen(
            backendStatusMessage: widget.backendStatusMessage,
            testSupabaseConnection: widget.testSupabaseConnection,
          );
        }
        return FutureBuilder<bool>(
          future: _hasBusiness(),
          builder: (context, businessSnapshot) {
            if (businessSnapshot.connectionState != ConnectionState.done) {
              return const Scaffold(
                body: Center(child: CircularProgressIndicator()),
              );
            }
            if (businessSnapshot.hasError) {
              return Scaffold(
                appBar: AppBar(title: const Text('AI Business OS')),
                body: Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('Could not load your business workspace.'),
                        const SizedBox(height: 8),
                        const Text(
                          'Check your database policies and connection, then retry.',
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: () => setState(() {}),
                          child: const Text('Retry'),
                        ),
                        TextButton(
                          onPressed: () =>
                              Supabase.instance.client.auth.signOut(),
                          child: const Text('Sign out'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }
            if (businessSnapshot.data == true) {
              return HomeScreen(
                backendStatusMessage: widget.backendStatusMessage,
                testSupabaseConnection: widget.testSupabaseConnection,
              );
            }
            return BusinessSetupScreen(
              onBusinessCreated: () {
                if (mounted) setState(() => _businessCreated = true);
              },
            );
          },
        );
      },
    );
  }
}

