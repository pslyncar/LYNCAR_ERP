class SystemUser {
  const SystemUser({
    required this.id,
    required this.name,
    required this.email,
    this.sellerCode,
    this.technicianCode,
    required this.role,
    required this.active,
    required this.createdAt,
    required this.permissions,
  });

  final int id;
  final String name;
  final String email;
  final String? sellerCode;
  final String? technicianCode;
  final String role;
  final bool active;
  final DateTime createdAt;
  final List<String> permissions;

  factory SystemUser.fromJson(Map<String, dynamic> json) {
    return SystemUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      sellerCode: json['seller_code'] as String?,
      technicianCode: json['technician_code'] as String?,
      role: json['role'] as String,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      permissions: ((json['permissions'] as List<dynamic>?) ?? [])
          .map((permission) => permission.toString())
          .toList(),
    );
  }
}

class SystemRole {
  const SystemRole({
    required this.id,
    required this.name,
    required this.label,
    required this.active,
    this.description,
    this.isSellerProfile = false,
    this.isTechnicianProfile = false,
    this.permissions = const [],
  });

  final int id;
  final String name;
  final String label;
  final String? description;
  final bool isSellerProfile;
  final bool isTechnicianProfile;
  final bool active;
  final List<String> permissions;

  factory SystemRole.fromJson(Map<String, dynamic> json) {
    return SystemRole(
      id: json['id'] as int,
      name: json['name'] as String,
      label: json['label'] as String,
      description: json['description'] as String?,
      isSellerProfile: json['is_seller_profile'] as bool? ?? false,
      isTechnicianProfile: json['is_technician_profile'] as bool? ?? false,
      active: json['active'] as bool? ?? true,
      permissions: ((json['permissions'] as List<dynamic>?) ?? [])
          .map((permission) => permission.toString())
          .toList(),
    );
  }
}

class SystemRolePayload {
  const SystemRolePayload({
    required this.label,
    required this.permissions,
    this.description,
    this.isSellerProfile = false,
    this.isTechnicianProfile = false,
    this.active = true,
  });

  final String label;
  final String? description;
  final List<String> permissions;
  final bool isSellerProfile;
  final bool isTechnicianProfile;
  final bool active;

  Map<String, dynamic> toJson() {
    return {
      'label': label.trim(),
      'description': _emptyToNull(description),
      'permissions': permissions,
      'is_seller_profile': isSellerProfile,
      'is_technician_profile': isTechnicianProfile,
      'active': active,
    };
  }
}

class CurrentSystemUser {
  const CurrentSystemUser({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.permissions,
  });

  final int id;
  final String name;
  final String email;
  final String role;
  final List<String> permissions;

  factory CurrentSystemUser.fromJson(Map<String, dynamic> json) {
    return CurrentSystemUser(
      id: json['id'] as int,
      name: json['name'] as String,
      email: json['email'] as String,
      role: json['role'] as String,
      permissions: ((json['permissions'] as List<dynamic>?) ?? [])
          .map((permission) => permission.toString())
          .toList(),
    );
  }
}

class SystemPermission {
  const SystemPermission({
    required this.id,
    required this.code,
    required this.label,
    required this.module,
    required this.active,
    this.description,
  });

  final int id;
  final String code;
  final String label;
  final String module;
  final String? description;
  final bool active;

  factory SystemPermission.fromJson(Map<String, dynamic> json) {
    return SystemPermission(
      id: json['id'] as int,
      code: json['code'] as String,
      label: json['label'] as String,
      module: json['module'] as String,
      description: json['description'] as String?,
      active: json['active'] as bool? ?? true,
    );
  }
}

class SystemUserPayload {
  const SystemUserPayload({
    required this.name,
    required this.email,
    required this.role,
    required this.active,
    this.sellerCode,
    this.technicianCode,
    this.allowCrossCompanyDuplicate = false,
    this.appAccess,
    this.password,
  });

  final String name;
  final String email;
  final String? sellerCode;
  final String? technicianCode;
  final String role;
  final bool active;
  final bool allowCrossCompanyDuplicate;
  final bool? appAccess;
  final String? password;

  Map<String, dynamic> toCreateJson() {
    return {
      'name': name.trim(),
      'email': email.trim(),
      'seller_code': _emptyToNull(sellerCode),
      'technician_code': _emptyToNull(technicianCode),
      'password': password,
      'role': role,
      'active': active,
      'app_access': appAccess,
      'allow_cross_company_duplicate': allowCrossCompanyDuplicate,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name.trim(),
      'email': email.trim(),
      'seller_code': _emptyToNull(sellerCode),
      'technician_code': _emptyToNull(technicianCode),
      if (password != null && password!.isNotEmpty) 'password': password,
      'role': role,
      'active': active,
      'app_access': appAccess,
      'allow_cross_company_duplicate': allowCrossCompanyDuplicate,
    };
  }
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  return trimmed;
}
