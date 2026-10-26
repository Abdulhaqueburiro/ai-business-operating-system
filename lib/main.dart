import 'package:ai_business_os/app/backend_configuration.dart';
import 'package:ai_business_os/app/backend_initializer.dart';
import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:ai_business_os/app/app.dart';
import 'package:flutter/material.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final configuration = BackendConfiguration.fromEnvironment();
  final backendResult = await initializeBackend(configuration);

  runApp(
    App(
      backendStatusMessage: backendResult.message,
      testSupabaseConnection: SupabaseConnectionChecker(configuration).check,
      enableAuthentication:
          backendResult.status == BackendInitializationStatus.initialized,
    ),
  );
}
