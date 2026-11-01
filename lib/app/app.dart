import 'package:ai_business_os/app/main_shell.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'auth_gate.dart';
import 'supabase_connection_checker.dart';

class App extends StatelessWidget {
  const App({
    super.key,
    this.backendStatusMessage =
        'Supabase is not configured. Provide SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY at launch. Backend data is unavailable.',
    this.testSupabaseConnection,
    this.enableAuthentication = false,
  });

  final String backendStatusMessage;
  final Future<SupabaseConnectionResult> Function()? testSupabaseConnection;
  final bool enableAuthentication;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Business OS',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: enableAuthentication
          ? AuthGate(
              backendStatusMessage: backendStatusMessage,
              testSupabaseConnection: testSupabaseConnection,
            )
          : MainShell(
              backendStatusMessage: backendStatusMessage,
              testSupabaseConnection: testSupabaseConnection,
            ),
    );
  }
}
