import 'dart:convert';

class Session {
  const Session({
    required this.apiBaseUrl,
    required this.token,
    required this.userId,
    required this.role,
    required this.companyCode,
    required this.companyName,
    required this.businessType,
    required this.planCode,
    required this.enabledModules,
    required this.permissions,
    this.sellerRoleEnabled = false,
    this.technicianRoleEnabled = false,
    this.mustChangePassword = false,
  });

  final String apiBaseUrl;
  final String token;
  final int? userId;
  final String role;
  final String companyCode;
  final String companyName;
  final String businessType;
  final String planCode;
  final List<String> enabledModules;
  final bool sellerRoleEnabled;
  final bool technicianRoleEnabled;
  final List<String> permissions;
  final bool mustChangePassword;

  factory Session.fromJson(Map<String, dynamic> json, String apiBaseUrl) {
    final token = json['access_token'] as String;
    return Session(
      apiBaseUrl: apiBaseUrl,
      token: token,
      userId: _intClaimFromToken(token, 'sub'),
      role: _roleFromToken(token),
      companyCode:
          json['company_code']?.toString() ??
          _claimFromToken(token, 'company_code', 'papezzosync'),
      companyName:
          json['company_name']?.toString() ??
          _claimFromToken(token, 'company_name', 'PapezzoSync'),
      businessType: json['business_type']?.toString() ?? 'custom',
      planCode:
          json['plan_code']?.toString() ??
          _claimFromToken(token, 'plan_code', 'start'),
      enabledModules: (json['enabled_modules'] as List<dynamic>? ?? const [])
          .map((module) => module.toString())
          .toList(),
      sellerRoleEnabled: json['seller_role_enabled'] as bool? ?? false,
      technicianRoleEnabled: json['technician_role_enabled'] as bool? ?? false,
      permissions: (json['permissions'] as List<dynamic>)
          .map((permission) => permission.toString())
          .toList(),
      mustChangePassword: json['must_change_password'] as bool? ?? false,
    );
  }

  factory Session.fromStorageJson(Map<String, dynamic> json) {
    return Session(
      apiBaseUrl: json['apiBaseUrl'] as String,
      token: json['token'] as String,
      userId: json['userId'] as int?,
      role: json['role'] as String,
      companyCode: json['companyCode'] as String? ?? 'papezzosync',
      companyName: json['companyName'] as String? ?? 'PapezzoSync',
      businessType: json['businessType'] as String? ?? 'custom',
      planCode:
          json['planCode'] as String? ??
          ((json['companyCode'] as String? ?? '') == 'master'
              ? 'enterprise'
              : 'start'),
      enabledModules: (json['enabledModules'] as List<dynamic>? ?? const [])
          .map((module) => module.toString())
          .toList(),
      sellerRoleEnabled: json['sellerRoleEnabled'] as bool? ?? false,
      technicianRoleEnabled: json['technicianRoleEnabled'] as bool? ?? false,
      permissions: (json['permissions'] as List<dynamic>)
          .map((permission) => permission.toString())
          .toList(),
      mustChangePassword: json['mustChangePassword'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toStorageJson() {
    return {
      'apiBaseUrl': apiBaseUrl,
      'token': token,
      'userId': userId,
      'role': role,
      'companyCode': companyCode,
      'companyName': companyName,
      'businessType': businessType,
      'planCode': planCode,
      'enabledModules': enabledModules,
      'sellerRoleEnabled': sellerRoleEnabled,
      'technicianRoleEnabled': technicianRoleEnabled,
      'permissions': permissions,
      'mustChangePassword': mustChangePassword,
    };
  }

  bool can(String permission) => permissions.contains(permission);

  bool hasModule(String module) => enabledModules.contains(module);

  bool get isMasterCompany =>
      companyCode == 'master' &&
      (role == 'superadmin' || role == 'master_staff');

  bool canMaster(String permission) =>
      permissions.contains('master:manage') || permissions.contains(permission);

  bool get canUseFiscal => hasModule('fiscal') && _planAtLeastPro(planCode);

  bool get isTokenExpired {
    final expiresAt = _expiresAtFromToken(token);
    if (expiresAt == null) {
      return false;
    }
    return DateTime.now().toUtc().isAfter(expiresAt);
  }

  DateTime? get expiresAt => _expiresAtFromToken(token);

  bool tokenExpiresWithin(Duration duration) {
    final value = expiresAt;
    if (value == null) {
      return false;
    }
    return DateTime.now().toUtc().add(duration).isAfter(value);
  }

  static bool _planAtLeastPro(String value) {
    final normalized = switch (value.trim().toLowerCase()) {
      'starter' || 'erp' => 'start',
      'premium' => 'business',
      final code => code,
    };
    const order = {'start': 0, 'pro': 1, 'business': 2, 'enterprise': 3};
    return (order[normalized] ?? 0) >= order['pro']!;
  }

  static String _roleFromToken(String token) {
    return _claimFromToken(token, 'role', 'usuário');
  }

  static String _claimFromToken(String token, String claim, String fallback) {
    try {
      final payload = token.split('.')[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      return data[claim]?.toString() ?? fallback;
    } catch (_) {
      return fallback;
    }
  }

  static int? _intClaimFromToken(String token, String claim) {
    try {
      final payload = token.split('.')[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final value = data[claim];
      if (value is int) return value;
      return int.tryParse(value?.toString() ?? '');
    } catch (_) {
      return null;
    }
  }

  static DateTime? _expiresAtFromToken(String token) {
    try {
      final payload = token.split('.')[1];
      final normalized = base64Url.normalize(payload);
      final decoded = utf8.decode(base64Url.decode(normalized));
      final data = jsonDecode(decoded) as Map<String, dynamic>;
      final expiresAtSeconds = data['exp'];
      if (expiresAtSeconds is! int) {
        return null;
      }
      return DateTime.fromMillisecondsSinceEpoch(
        expiresAtSeconds * 1000,
        isUtc: true,
      );
    } catch (_) {
      return null;
    }
  }
}
