class MasterPedeOnCustomer {
  const MasterPedeOnCustomer({
    required this.id,
    required this.email,
    required this.name,
    required this.active,
    required this.linkedStores,
    this.phone,
  });

  final int id;
  final String email;
  final String name;
  final String? phone;
  final bool active;
  final int linkedStores;

  factory MasterPedeOnCustomer.fromJson(Map<String, dynamic> json) =>
      MasterPedeOnCustomer(
        id: json['id'] as int,
        email: json['email'] as String? ?? '',
        name: json['name'] as String? ?? '',
        phone: json['phone'] as String?,
        active: json['active'] == true,
        linkedStores: json['linked_stores'] as int? ?? 0,
      );
}
