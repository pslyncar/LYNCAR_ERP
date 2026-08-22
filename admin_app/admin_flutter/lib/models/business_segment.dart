class BusinessSegment {
  const BusinessSegment({
    required this.id,
    required this.code,
    required this.name,
    this.description,
    this.maxUsers,
    this.maxPdvTerminals,
    required this.defaultModules,
    required this.sellerRoleEnabled,
    required this.technicianRoleEnabled,
    required this.active,
    required this.sortOrder,
  });

  final int id;
  final String code;
  final String name;
  final String? description;
  final int? maxUsers;
  final int? maxPdvTerminals;
  final List<String> defaultModules;
  final bool sellerRoleEnabled;
  final bool technicianRoleEnabled;
  final bool active;
  final int sortOrder;

  factory BusinessSegment.fromJson(Map<String, dynamic> json) {
    return BusinessSegment(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      description: json['description'] as String?,
      maxUsers: json['max_users'] as int?,
      maxPdvTerminals: json['max_pdv_terminals'] as int?,
      defaultModules: (json['default_modules'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      sellerRoleEnabled: json['seller_role_enabled'] as bool? ?? false,
      technicianRoleEnabled: json['technician_role_enabled'] as bool? ?? false,
      active: json['active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toCreateJson() {
    return {
      'code': code,
      'name': name,
      'description': description,
      'max_users': maxUsers,
      'max_pdv_terminals': maxPdvTerminals,
      'default_modules': defaultModules,
      'seller_role_enabled': sellerRoleEnabled,
      'technician_role_enabled': technicianRoleEnabled,
      'active': active,
      'sort_order': sortOrder,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name,
      'description': description,
      'max_users': maxUsers,
      'max_pdv_terminals': maxPdvTerminals,
      'default_modules': defaultModules,
      'seller_role_enabled': sellerRoleEnabled,
      'technician_role_enabled': technicianRoleEnabled,
      'active': active,
      'sort_order': sortOrder,
    };
  }
}
