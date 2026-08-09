class PaymentSetting {
  const PaymentSetting({
    required this.provider,
    required this.environment,
    this.publicKey,
    required this.accessTokenConfigured,
    this.accessTokenPreview,
    this.webhookUrl,
    required this.active,
  });

  final String provider;
  final String environment;
  final String? publicKey;
  final bool accessTokenConfigured;
  final String? accessTokenPreview;
  final String? webhookUrl;
  final bool active;

  factory PaymentSetting.fromJson(Map<String, dynamic> json) {
    return PaymentSetting(
      provider: json['provider']?.toString() ?? 'mercado_pago',
      environment: json['environment']?.toString() ?? 'test',
      publicKey: json['public_key']?.toString(),
      accessTokenConfigured: json['access_token_configured'] as bool? ?? false,
      accessTokenPreview: json['access_token_preview']?.toString(),
      webhookUrl: json['webhook_url']?.toString(),
      active: json['active'] as bool? ?? true,
    );
  }
}

class PaymentSettingInput {
  const PaymentSettingInput({
    required this.environment,
    this.publicKey,
    this.accessToken,
    this.webhookUrl,
    required this.active,
  });

  final String environment;
  final String? publicKey;
  final String? accessToken;
  final String? webhookUrl;
  final bool active;

  Map<String, dynamic> toJson() {
    return {
      'environment': environment,
      'public_key': _emptyToNull(publicKey),
      'access_token': _emptyToNull(accessToken),
      'webhook_url': _emptyToNull(webhookUrl),
      'active': active,
    };
  }
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
