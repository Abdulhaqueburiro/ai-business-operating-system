class BackendConfiguration {
  const BackendConfiguration({required this.url, required this.publishableKey});

  factory BackendConfiguration.fromEnvironment() {
    return const BackendConfiguration(
      url: String.fromEnvironment('SUPABASE_URL'),
      publishableKey: String.fromEnvironment('SUPABASE_PUBLISHABLE_KEY'),
    );
  }

  final String url;
  final String publishableKey;

  String? get validationMessage {
    final normalizedUrl = url.trim();
    final normalizedKey = publishableKey.trim();

    if (normalizedUrl.isEmpty || normalizedKey.isEmpty) {
      return 'Supabase is not configured. Provide SUPABASE_URL and '
          'SUPABASE_PUBLISHABLE_KEY at launch.';
    }

    final parsedUrl = Uri.tryParse(normalizedUrl);
    if (parsedUrl == null ||
        !parsedUrl.hasAuthority ||
        parsedUrl.host.isEmpty ||
        (parsedUrl.scheme != 'https' && parsedUrl.scheme != 'http') ||
        parsedUrl.userInfo.isNotEmpty) {
      return 'Supabase URL must be a valid HTTP or HTTPS URL.';
    }

    if (!_isSupportedPublishableKey(normalizedKey)) {
      return 'SUPABASE_PUBLISHABLE_KEY must be a Supabase publishable key.';
    }

    return null;
  }

  bool get isValid => validationMessage == null;

  static bool _isSupportedPublishableKey(String key) {
    const publishablePrefix = 'sb_publishable_';
    final keyCharacters = RegExp(r'^[A-Za-z0-9_-]+$');

    if (key.startsWith(publishablePrefix)) {
      final suffix = key.substring(publishablePrefix.length);
      return suffix.isNotEmpty && keyCharacters.hasMatch(suffix);
    }

    final legacyJwtParts = key.split('.');
    return legacyJwtParts.length == 3 &&
        legacyJwtParts.every(
          (part) => part.isNotEmpty && keyCharacters.hasMatch(part),
        );
  }
}
