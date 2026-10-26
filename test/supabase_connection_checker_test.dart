import 'package:ai_business_os/app/backend_configuration.dart';
import 'package:ai_business_os/app/supabase_connection_checker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const configuration = BackendConfiguration(
    url: 'https://project.example',
    publishableKey: 'sb_publishable_test-value',
  );

  test(
    'checks Auth health with the configured publishable key, not OpenAPI',
    () async {
      http.Request? capturedRequest;
      final checker = SupabaseConnectionChecker(
        configuration,
        clientFactory: () => MockClient((request) async {
          capturedRequest = request;
          return http.Response('{}', 200);
        }),
      );

      final result = await checker.check();

      expect(capturedRequest?.method, 'GET');
      expect(
        capturedRequest?.url.toString(),
        'https://project.example/auth/v1/health',
      );
      expect(capturedRequest?.headers['accept'], 'application/json');
      expect(capturedRequest?.headers['apikey'], 'sb_publishable_test-value');
      expect(capturedRequest?.headers.containsKey('authorization'), isFalse);
      expect(result.status, SupabaseConnectionStatus.connected);
      expect(result.message, contains('Auth service responded with HTTP 200'));
      expect(result.message, contains('Auth service availability only'));
      expect(result.message, contains('does not verify publishable API key'));
      expect(result.message, contains('database connectivity'));
      expect(result.message, contains('RLS access'));
    },
  );

  test(
    'does not request Auth health without a configured publishable key',
    () async {
      var requestMade = false;
      const configurationWithoutKey = BackendConfiguration(
        url: 'https://project.example',
        publishableKey: '',
      );
      final checker = SupabaseConnectionChecker(
        configurationWithoutKey,
        clientFactory: () => MockClient((request) async {
          requestMade = true;
          return http.Response('{}', 200);
        }),
      );

      final result = await checker.check();

      expect(requestMade, isFalse);
      expect(result.status, SupabaseConnectionStatus.failed);
      expect(result.message, contains('SUPABASE_PUBLISHABLE_KEY'));
    },
  );

  test(
    'explains HTTP 401 without exposing response details or API key',
    () async {
      final checker = SupabaseConnectionChecker(
        configuration,
        clientFactory: () => MockClient(
          (_) async => http.Response('sensitive response body', 401),
        ),
      );

      final result = await checker.check();

      expect(result.status, SupabaseConnectionStatus.failed);
      expect(result.message, contains('HTTP 401'));
      expect(result.message, contains('Auth service returned HTTP 401'));
      expect(result.message, isNot(contains('sensitive response body')));
      expect(result.message, isNot(contains('sb_publishable_test-value')));
    },
  );

  test(
    'displays validated code and message from an HTTP error response',
    () async {
      final checker = SupabaseConnectionChecker(
        configuration,
        clientFactory: () => MockClient(
          (_) async => http.Response(
            '{"code":"PGRST301","message":"JWT expired",'
            '"details":"sb_publishable_unrelated-secret",'
            '"headers":{"apikey":"private-header"}}',
            401,
          ),
        ),
      );

      final result = await checker.check();

      expect(result.status, SupabaseConnectionStatus.failed);
      expect(result.message, contains('PGRST301 - JWT expired'));
      expect(result.message, isNot(contains('details')));
      expect(result.message, isNot(contains('unrelated-secret')));
      expect(result.message, isNot(contains('private-header')));
      expect(result.message, isNot(contains('sb_publishable_test-value')));
    },
  );

  test('displays a validated message when the error code is absent', () async {
    final checker = SupabaseConnectionChecker(
      configuration,
      clientFactory: () => MockClient(
        (_) async => http.Response('{"message":"Invalid API key"}', 401),
      ),
    );

    final result = await checker.check();

    expect(result.status, SupabaseConnectionStatus.failed);
    expect(result.message, contains('Diagnostic: Invalid API key'));
    expect(result.message, isNot(contains('Diagnostic: -')));
  });

  test('keeps the generic error for malformed error response JSON', () async {
    final checker = SupabaseConnectionChecker(
      configuration,
      clientFactory: () => MockClient(
        (_) async => http.Response('{"code":"PGRST301","message":', 401),
      ),
    );

    final result = await checker.check();

    expect(result.message, contains('HTTP 401'));
    expect(result.message, isNot(contains('PGRST301')));
  });

  test('keeps the generic error when an error field is missing', () async {
    final checker = SupabaseConnectionChecker(
      configuration,
      clientFactory: () =>
          MockClient((_) async => http.Response('{"code":"PGRST301"}', 401)),
    );

    final result = await checker.check();

    expect(result.message, contains('HTTP 401'));
    expect(result.message, isNot(contains('PGRST301')));
  });

  test('keeps the generic error for oversized error fields', () async {
    final oversizedCode = 'C' * 65;
    final oversizedMessage = 'x' * 241;
    final oversizedBodyPadding = 'x' * 4100;
    final oversizedBodies = [
      '{"code":"$oversizedCode","message":"Request failed"}',
      '{"code":"PGRST301","message":"$oversizedMessage"}',
      '{"code":"PGRST301","message":"Request failed",'
          '"other":"$oversizedBodyPadding"}',
    ];

    for (final body in oversizedBodies) {
      final checker = SupabaseConnectionChecker(
        configuration,
        clientFactory: () => MockClient((_) async => http.Response(body, 401)),
      );

      final result = await checker.check();

      expect(result.message, contains('HTTP 401'));
      expect(result.message, isNot(contains('Diagnostic:')));
      expect(result.message, isNot(contains(oversizedCode)));
      expect(result.message, isNot(contains(oversizedMessage)));
      expect(result.message, isNot(contains(oversizedBodyPadding)));
    }
  });

  test(
    'keeps the generic error when a diagnostic resembles a header',
    () async {
      final checker = SupabaseConnectionChecker(
        configuration,
        clientFactory: () => MockClient(
          (_) async => http.Response(
            '{"code":"PGRST301","message":"apikey: private-header"}',
            401,
          ),
        ),
      );

      final result = await checker.check();

      expect(result.message, contains('HTTP 401'));
      expect(result.message, isNot(contains('private-header')));
    },
  );

  test('does not expose a credential supplied as the error code', () async {
    final checker = SupabaseConnectionChecker(
      configuration,
      clientFactory: () => MockClient(
        (_) async => http.Response(
          '{"code":"sb_publishable_test-value","message":"Request failed"}',
          401,
        ),
      ),
    );

    final result = await checker.check();

    expect(result.message, contains('HTTP 401'));
    expect(result.message, isNot(contains('sb_publishable_test-value')));
    expect(result.message, isNot(contains('Request failed')));
  });

  test(
    'reports other HTTP failures without exposing response details',
    () async {
      final checker = SupabaseConnectionChecker(
        configuration,
        clientFactory: () => MockClient(
          (_) async => http.Response('sensitive response body', 503),
        ),
      );

      final result = await checker.check();

      expect(result.status, SupabaseConnectionStatus.failed);
      expect(result.message, contains('HTTP 503'));
      expect(result.message, isNot(contains('sensitive response body')));
      expect(result.message, isNot(contains('sb_publishable_test-value')));
    },
  );

  test('returns a safe failure for network errors', () async {
    final checker = SupabaseConnectionChecker(
      configuration,
      clientFactory: () => MockClient((_) async {
        throw http.ClientException('sensitive transport detail');
      }),
    );

    final result = await checker.check();

    expect(result.status, SupabaseConnectionStatus.failed);
    expect(result.message, contains('Could not reach'));
    expect(result.message, isNot(contains('sensitive transport detail')));
  });

  test('times out and reports a safe message', () async {
    final checker = SupabaseConnectionChecker(
      configuration,
      timeout: const Duration(milliseconds: 1),
      clientFactory: () => MockClient(
        (_) => Future<http.Response>.delayed(
          const Duration(milliseconds: 20),
          () => http.Response('{}', 200),
        ),
      ),
    );

    final result = await checker.check();

    expect(result.status, SupabaseConnectionStatus.failed);
    expect(result.message, contains('timed out'));
  });

  test('does not make a request for an invalid project URL', () async {
    var requestMade = false;
    const invalidConfiguration = BackendConfiguration(
      url: 'ftp://project.example',
      publishableKey: 'invalid-key',
    );
    final checker = SupabaseConnectionChecker(
      invalidConfiguration,
      clientFactory: () => MockClient((_) async {
        requestMade = true;
        return http.Response('{}', 200);
      }),
    );

    final result = await checker.check();

    expect(requestMade, isFalse);
    expect(result.status, SupabaseConnectionStatus.failed);
    expect(result.message, contains('valid HTTP or HTTPS URL'));
  });
}
