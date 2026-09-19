class PedeOnSocialProvider {
  const PedeOnSocialProvider({
    required this.provider,
    this.clientId,
    this.redirectUri,
    required this.enabled,
    required this.configured,
    required this.clientSecretConfigured,
    required this.extraConfigured,
  });
  final String provider;
  final String? clientId;
  final String? redirectUri;
  final bool enabled;
  final bool configured;
  final bool clientSecretConfigured;
  final bool extraConfigured;
  factory PedeOnSocialProvider.fromJson(Map<String, dynamic> json) =>
      PedeOnSocialProvider(
        provider: json['provider'] as String? ?? '',
        clientId: json['client_id'] as String?,
        redirectUri: json['redirect_uri'] as String?,
        enabled: json['enabled'] == true,
        configured: json['configured'] == true,
        clientSecretConfigured: json['client_secret_configured'] == true,
        extraConfigured: json['extra_configured'] == true,
      );
}

class PedeOnSocialProviderInput {
  const PedeOnSocialProviderInput({
    required this.provider,
    this.clientId,
    this.clientSecret,
    this.redirectUri,
    required this.enabled,
    this.extra = const {},
  });
  final String provider;
  final String? clientId;
  final String? clientSecret;
  final String? redirectUri;
  final bool enabled;
  final Map<String, String?> extra;
  Map<String, dynamic> toJson() => {
    'provider': provider,
    'client_id': clientId,
    'client_secret': clientSecret,
    'redirect_uri': redirectUri,
    'enabled': enabled,
    'extra': extra,
  };
}
