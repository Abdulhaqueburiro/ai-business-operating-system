import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'backend_configuration.dart';

const _maxErrorBodyLength = 4096;
const _maxErrorCodeLength = 64;
const _maxErrorMessageLength = 240;

enum SupabaseConnectionStatus { connected, failed }

class SupabaseConnectionResult {
  const SupabaseConnectionResult({required this.status, required this.message});

  final SupabaseConnectionStatus status;
  final String message;

  bool get isConnected => status == SupabaseConnectionStatus.connected;
}

class SupabaseConnectionChecker {
  SupabaseConnectionChecker(
    this.configuration, {
    http.Client Function()? clientFactory,
    this.timeout = const Duration(seconds: 8),
  }) : _clientFactory = clientFactory ?? http.Client.new;

  final BackendConfiguration configuration;
  final http.Client Function() _clientFactory;
  final Duration timeout;

  Future<SupabaseConnectionResult> check() async {
    final configurationError = configuration.validationMessage;
    if (configurationError != null) {
      return SupabaseConnectionResult(
        status: SupabaseConnectionStatus.failed,
        message: 'Auth service check unavailable. $configurationError',
      );
    }

    final projectUrl = Uri.tryParse(configuration.url.trim());
    if (projectUrl == null ||
        !projectUrl.hasAuthority ||
        projectUrl.host.isEmpty ||
        (projectUrl.scheme != 'https' && projectUrl.scheme != 'http') ||
        projectUrl.userInfo.isNotEmpty) {
      return const SupabaseConnectionResult(
        status: SupabaseConnectionStatus.failed,
        message: 'Supabase project URL is missing or invalid.',
      );
    }

    http.Client? client;

    try {
      final uri = projectUrl.resolve('/auth/v1/health');
      client = _clientFactory();
      final response = await client
          .get(
            uri,
            headers: {
              'apikey': configuration.publishableKey.trim(),
              'accept': 'application/json',
            },
          )
          .timeout(timeout);

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return SupabaseConnectionResult(
          status: SupabaseConnectionStatus.connected,
          message:
              'Auth service responded with HTTP ${response.statusCode}. '
              'This confirms Auth service availability only; it does not '
              'verify publishable API key validity, database connectivity, '
              'or RLS access.',
        );
      }

      final message = switch (response.statusCode) {
        401 => 'Auth service returned HTTP 401.',
        403 => 'Auth service returned HTTP 403.',
        _ =>
          'Auth service returned HTTP ${response.statusCode}. '
              'Check Auth service availability.',
      };
      final diagnostic = _parseErrorDiagnostic(
        response.body,
        configuration.publishableKey.trim(),
      );

      return SupabaseConnectionResult(
        status: SupabaseConnectionStatus.failed,
        message: diagnostic == null
            ? message
            : '$message Diagnostic: ${diagnostic.display}',
      );
    } on TimeoutException {
      return const SupabaseConnectionResult(
        status: SupabaseConnectionStatus.failed,
        message:
            'Auth service check timed out. Check your network and try again.',
      );
    } on Exception {
      return const SupabaseConnectionResult(
        status: SupabaseConnectionStatus.failed,
        message:
            'Could not reach the Supabase Auth service. Check your network and '
            'project URL, then try again.',
      );
    } finally {
      client?.close();
    }
  }

  _SupabaseErrorDiagnostic? _parseErrorDiagnostic(
    String body,
    String publishableKey,
  ) {
    if (body.length > _maxErrorBodyLength) return null;

    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;

    final codeValue = decoded['code'];
    final messageValue = decoded['message'];
    if ((codeValue != null && codeValue is! String) ||
        messageValue is! String) {
      return null;
    }

    final errorMessage = messageValue.trim();
    if (!_isSafeErrorMessage(errorMessage, publishableKey)) {
      return null;
    }

    final code = codeValue is String ? codeValue.trim() : null;
    if (code != null && !_isSafeErrorCode(code, publishableKey)) return null;

    return _SupabaseErrorDiagnostic(code: code, message: errorMessage);
  }

  bool _isSafeErrorCode(String code, String publishableKey) {
    return code.isNotEmpty &&
        code.length <= _maxErrorCodeLength &&
        RegExp(r'^[A-Za-z0-9_.-]+$').hasMatch(code) &&
        !_containsSensitiveDiagnosticContent(code, publishableKey);
  }

  bool _isSafeErrorMessage(String message, String publishableKey) {
    if (message.isEmpty ||
        message.length > _maxErrorMessageLength ||
        !RegExp(r"^[A-Za-z0-9][A-Za-z0-9 .,:;()'/_-]*$").hasMatch(message)) {
      return false;
    }

    return !_containsSensitiveDiagnosticContent(message, publishableKey);
  }

  bool _containsSensitiveDiagnosticContent(
    String value,
    String publishableKey,
  ) {
    if (publishableKey.isNotEmpty &&
        value.toLowerCase().contains(publishableKey.toLowerCase())) {
      return true;
    }

    return RegExp(
      r'https?://|www\.|'
      r'\b(?:authorization|apikey|accept|x-api-key|api[_ -]?key)\s*[:=]\s*\S+|'
      r'\b(?:secret|token|credential|password)\s*[:=]\s*\S+|'
      r'\bBearer\s+\S+|'
      r'\bsb_(?:publishable|secret)_[A-Za-z0-9_-]+|'
      r'\b[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\b|'
      r'\b[A-Za-z0-9_+/=-]{32,}\b',
      caseSensitive: false,
    ).hasMatch(value);
  }
}

class _SupabaseErrorDiagnostic {
  const _SupabaseErrorDiagnostic({required this.code, required this.message});

  final String? code;
  final String message;

  String get display => code == null ? message : '$code - $message';
}
