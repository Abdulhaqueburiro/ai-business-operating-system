import 'package:ai_business_os/app/backend_configuration.dart';
import 'package:ai_business_os/app/backend_initializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('BackendConfiguration', () {
    test('is invalid when either launch value is missing', () {
      const configuration = BackendConfiguration(
        url: '',
        publishableKey: 'publishable-key',
      );

      expect(configuration.isValid, isFalse);
      expect(configuration.validationMessage, contains('SUPABASE_URL'));
      expect(
        configuration.validationMessage,
        contains('SUPABASE_PUBLISHABLE_KEY'),
      );
    });

    test('rejects malformed or non-HTTP URLs', () {
      const configuration = BackendConfiguration(
        url: 'ftp://project.example',
        publishableKey: 'sb_publishable_test-value',
      );

      expect(configuration.isValid, isFalse);
      expect(
        configuration.validationMessage,
        'Supabase URL must be a valid HTTP or HTTPS URL.',
      );
    });

    test('rejects a malformed publishable key', () {
      const configuration = BackendConfiguration(
        url: 'https://project.example',
        publishableKey: 'publishable-key',
      );

      expect(configuration.isValid, isFalse);
      expect(
        configuration.validationMessage,
        'SUPABASE_PUBLISHABLE_KEY must be a Supabase publishable key.',
      );
    });

    test('accepts supported publishable and legacy anon JWT key formats', () {
      const configuration = BackendConfiguration(
        url: 'https://project.example',
        publishableKey: 'sb_publishable_test-value',
      );
      const legacyConfiguration = BackendConfiguration(
        url: 'https://project.example',
        publishableKey: 'header.payload.signature',
      );

      expect(configuration.isValid, isTrue);
      expect(configuration.validationMessage, isNull);
      expect(legacyConfiguration.isValid, isTrue);
    });
  });

  group('initializeBackend', () {
    test('does not call initializer when configuration is missing', () async {
      var initializerCalled = false;
      const configuration = BackendConfiguration(url: '', publishableKey: '');

      final result = await initializeBackend(
        configuration,
        initializer: ({required url, required publishableKey}) async {
          initializerCalled = true;
        },
      );

      expect(initializerCalled, isFalse);
      expect(result.status, BackendInitializationStatus.notConfigured);
    });

    test(
      'does not call initializer when the URL or key is malformed',
      () async {
        var initializerCalled = false;
        const malformedConfigurations = [
          BackendConfiguration(
            url: 'ftp://project.example',
            publishableKey: 'sb_publishable_test-value',
          ),
          BackendConfiguration(
            url: 'https://project.example',
            publishableKey: 'not-a-supabase-key',
          ),
        ];

        for (final configuration in malformedConfigurations) {
          final result = await initializeBackend(
            configuration,
            initializer: ({required url, required publishableKey}) async {
              initializerCalled = true;
            },
          );

          expect(result.status, BackendInitializationStatus.notConfigured);
        }

        expect(initializerCalled, isFalse);
      },
    );

    test('passes configured values to the initializer', () async {
      String? initializedUrl;
      String? initializedKey;
      const configuration = BackendConfiguration(
        url: ' https://project.example ',
        publishableKey: ' sb_publishable_test-value ',
      );

      final result = await initializeBackend(
        configuration,
        initializer: ({required url, required publishableKey}) async {
          initializedUrl = url;
          initializedKey = publishableKey;
        },
      );

      expect(initializedUrl, 'https://project.example');
      expect(initializedKey, 'sb_publishable_test-value');
      expect(result.status, BackendInitializationStatus.initialized);
      expect(result.message, contains('connectivity has not been verified'));
    });

    test('returns a safe status when initialization throws', () async {
      const configuration = BackendConfiguration(
        url: 'https://project.example',
        publishableKey: 'sb_publishable_sensitive-key',
      );

      final result = await initializeBackend(
        configuration,
        initializer: ({required url, required publishableKey}) async {
          throw Exception('private detail $publishableKey');
        },
      );

      expect(result.status, BackendInitializationStatus.failed);
      expect(result.message, isNot(contains('private detail')));
      expect(result.message, isNot(contains('sensitive-key')));
    });

    test('handles format errors without exposing exception details', () async {
      const configuration = BackendConfiguration(
        url: 'https://project.example',
        publishableKey: 'sb_publishable_test-value',
      );

      final result = await initializeBackend(
        configuration,
        initializer: ({required url, required publishableKey}) async {
          throw const FormatException('sensitive startup detail');
        },
      );

      expect(result.status, BackendInitializationStatus.failed);
      expect(result.message, isNot(contains('sensitive startup detail')));
    });
  });
}
