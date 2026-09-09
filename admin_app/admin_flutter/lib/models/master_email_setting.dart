class MasterEmailSetting {
  const MasterEmailSetting({
    required this.authMethod,
    this.smtpHost,
    required this.smtpPort,
    this.username,
    this.clientId,
    this.fromEmail,
    this.fromName,
    required this.enabled,
    required this.passwordConfigured,
    required this.clientSecretConfigured,
    required this.refreshTokenConfigured,
    required this.configured,
  });

  final String authMethod;
  final String? smtpHost;
  final int smtpPort;
  final String? username;
  final String? clientId;
  final String? fromEmail;
  final String? fromName;
  final bool enabled;
  final bool passwordConfigured;
  final bool clientSecretConfigured;
  final bool refreshTokenConfigured;
  final bool configured;

  factory MasterEmailSetting.fromJson(Map<String, dynamic> json) {
    return MasterEmailSetting(
      authMethod: json['auth_method'] as String? ?? 'smtp',
      smtpHost: json['smtp_host'] as String?,
      smtpPort: json['smtp_port'] as int? ?? 587,
      username: json['username'] as String?,
      clientId: json['client_id'] as String?,
      fromEmail: json['from_email'] as String?,
      fromName: json['from_name'] as String?,
      enabled: json['enabled'] == true,
      passwordConfigured: json['password_configured'] == true,
      clientSecretConfigured: json['client_secret_configured'] == true,
      refreshTokenConfigured: json['refresh_token_configured'] == true,
      configured: json['configured'] == true,
    );
  }
}

class MasterEmailSettingInput {
  const MasterEmailSettingInput({
    required this.authMethod,
    required this.smtpHost,
    required this.smtpPort,
    required this.username,
    this.password,
    this.clientId,
    this.clientSecret,
    this.refreshToken,
    required this.fromEmail,
    required this.fromName,
    required this.enabled,
  });

  final String authMethod;
  final String smtpHost;
  final int smtpPort;
  final String username;
  final String? password;
  final String? clientId;
  final String? clientSecret;
  final String? refreshToken;
  final String fromEmail;
  final String fromName;
  final bool enabled;

  Map<String, dynamic> toJson() => {
    'auth_method': authMethod,
    'smtp_host': smtpHost,
    'smtp_port': smtpPort,
    'username': username,
    'password': password,
    'client_id': clientId,
    'client_secret': clientSecret,
    'refresh_token': refreshToken,
    'from_email': fromEmail,
    'from_name': fromName,
    'enabled': enabled,
  };
}
