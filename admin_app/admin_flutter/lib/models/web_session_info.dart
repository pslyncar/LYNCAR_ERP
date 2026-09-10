class WebSessionInfo {
  const WebSessionInfo({
    required this.id,
    required this.current,
    required this.companyCode,
    required this.companyName,
    required this.userHint,
    this.createdAt,
    this.lastSeenAt,
    this.expiresAt,
    this.userAgent,
    this.ipHint,
  });

  final int id;
  final bool current;
  final String companyCode;
  final String companyName;
  final String userHint;
  final DateTime? createdAt;
  final DateTime? lastSeenAt;
  final DateTime? expiresAt;
  final String? userAgent;
  final String? ipHint;

  factory WebSessionInfo.fromJson(Map<String, dynamic> json) {
    DateTime? date(String key) {
      final value = json[key];
      return value is String ? DateTime.tryParse(value) : null;
    }

    return WebSessionInfo(
      id: (json['id'] as num?)?.toInt() ?? 0,
      current: json['current'] == true,
      companyCode: json['company_code'] as String? ?? '',
      companyName: json['company_name'] as String? ?? '',
      userHint: json['user_hint'] as String? ?? 'Usuário da empresa',
      createdAt: date('created_at'),
      lastSeenAt: date('last_seen_at'),
      expiresAt: date('expires_at'),
      userAgent: json['user_agent'] as String?,
      ipHint: json['ip_hint'] as String?,
    );
  }
}
