import 'package:ai_business_os/features/home/presentation/home_screen.dart';
import 'package:flutter/material.dart';

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
    const brandColor = Color(0xFF176B63);

    return MaterialApp(
      title: 'AI Business OS',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: brandColor),
        useMaterial3: true,
      ),
      home: enableAuthentication
          ? AuthGate(
              backendStatusMessage: backendStatusMessage,
              testSupabaseConnection: testSupabaseConnection,
            )
          : HomeScreen(
              backendStatusMessage: backendStatusMessage,
              testSupabaseConnection: testSupabaseConnection,
            ),
    );
  }
}
