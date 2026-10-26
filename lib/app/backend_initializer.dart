import 'package:supabase_flutter/supabase_flutter.dart';

import 'backend_configuration.dart';

typedef SupabaseInitializer = Future<void> Function({
  required String url,
  required String publishableKey,
});

enum BackendInitializationStatus { notConfigured, initialized, failed }

class BackendInitializationResult {
  const BackendInitializationResult({
    required this.status,
    required this.message,
  });

  final BackendInitializationStatus status;
  final String message;

  static const notConfigured = BackendInitializationResult(
    status: BackendInitializationStatus.notConfigured,
    message:
        'Supabase is not configured. Provide SUPABASE_URL and '
        'SUPABASE_PUBLISHABLE_KEY at launch. Backend data is unavailable.',
  );

  static const initializationFailed = BackendInitializationResult(
    status: BackendInitializationStatus.failed,
    message:
        'Supabase client initialization failed. Check the launch '
        'configuration and restart. The backend connection is unverified.',
  );

  static const initialized = BackendInitializationResult(
    status: BackendInitializationStatus.initialized,
    message: 'Supabase client initialized; connectivity has not been verified.',
  );
}

Future<void> initializeSupabase({
  required String url,
  required String publishableKey,
}) async {
  await Supabase.initialize(
    url: url,
    publishableKey: publishableKey,
    debug: false,
  );
}

Future<BackendInitializationResult> initializeBackend(
  BackendConfiguration configuration, {
  SupabaseInitializer initializer = initializeSupabase,
}) async {
  final validationMessage = configuration.validationMessage;
  if (validationMessage != null) {
    return BackendInitializationResult(
      status: BackendInitializationStatus.notConfigured,
      message: '$validationMessage Backend data is unavailable.',
    );
  }

  try {
    await initializer(
      url: configuration.url.trim(),
      publishableKey: configuration.publishableKey.trim(),
    );
  } on FormatException {
    return BackendInitializationResult.initializationFailed;
  } on ArgumentError {
    return BackendInitializationResult.initializationFailed;
  } on StateError {
    return BackendInitializationResult.initializationFailed;
  } on Exception {
    return BackendInitializationResult.initializationFailed;
  }

  return BackendInitializationResult.initialized;
}
