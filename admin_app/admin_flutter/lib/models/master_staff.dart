class MasterPermission {
  const MasterPermission({
    required this.code,
    required this.label,
    required this.module,
    required this.description,
  });

  final String code;
  final String label;
  final String module;
  final String description;

  factory MasterPermission.fromJson(Map<String, dynamic> json) {
    return MasterPermission(
      code: json['code'].toString(),
      label: json['label'].toString(),
      module: json['module'].toString(),
      description: json['description'].toString(),
    );
  }
}

class MasterStaff {
  const MasterStaff({
    required this.id,
    required this.name,
    required this.email,
    required this.active,
    required this.mustChangePassword,
    required this.permissions,
  });

  final int id;
  final String name;
  final String email;
  final bool active;
  final bool mustChangePassword;
  final List<String> permissions;

  factory MasterStaff.fromJson(Map<String, dynamic> json) {
    return MasterStaff(
      id: json['id'] as int,
      name: json['name'].toString(),
      email: json['email'].toString(),
      active: json['active'] as bool? ?? true,
      mustChangePassword: json['must_change_password'] as bool? ?? false,
      permissions: ((json['permissions'] as List<dynamic>?) ?? const [])
          .map((item) => item.toString())
          .toList(),
    );
  }
}

class MasterStaffInput {
  const MasterStaffInput({
    required this.name,
    required this.email,
    required this.permissions,
    this.password,
    this.active = true,
    this.mustChangePassword = true,
  });

  final String name;
  final String email;
  final String? password;
  final bool active;
  final bool mustChangePassword;
  final List<String> permissions;

  Map<String, dynamic> toCreateJson() => {
    'name': name,
    'email': email,
    'password': password,
    'active': active,
    'must_change_password': mustChangePassword,
    'permissions': permissions,
  };

  Map<String, dynamic> toUpdateJson() => {
    'name': name,
    'email': email,
    if (password != null && password!.isNotEmpty) 'password': password,
    'active': active,
    'must_change_password': mustChangePassword,
    'permissions': permissions,
  };
}
