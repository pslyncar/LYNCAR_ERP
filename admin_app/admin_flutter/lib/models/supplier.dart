class Supplier {
  const Supplier({
    required this.id,
    required this.name,
    this.tradeName,
    this.documentNumber,
    this.stateRegistration,
    this.phone,
    this.email,
    this.addressLine,
    this.city,
    this.state,
    this.notes,
    required this.active,
  });

  final int id;
  final String name;
  final String? tradeName;
  final String? documentNumber;
  final String? stateRegistration;
  final String? phone;
  final String? email;
  final String? addressLine;
  final String? city;
  final String? state;
  final String? notes;
  final bool active;

  factory Supplier.fromJson(Map<String, dynamic> json) {
    return Supplier(
      id: json['id'] as int,
      name: json['name'] as String,
      tradeName: json['trade_name'] as String?,
      documentNumber: json['document_number'] as String?,
      stateRegistration: json['state_registration'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      addressLine: json['address_line'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      notes: json['notes'] as String?,
      active: json['active'] as bool? ?? true,
    );
  }
}

class SupplierPayload {
  const SupplierPayload({
    required this.name,
    this.tradeName,
    this.documentNumber,
    this.stateRegistration,
    this.phone,
    this.email,
    this.addressLine,
    this.city,
    this.state,
    this.notes,
    this.active = true,
  });

  final String name;
  final String? tradeName;
  final String? documentNumber;
  final String? stateRegistration;
  final String? phone;
  final String? email;
  final String? addressLine;
  final String? city;
  final String? state;
  final String? notes;
  final bool active;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'trade_name': _emptyToNull(tradeName),
      'document_number': _emptyToNull(documentNumber),
      'state_registration': _emptyToNull(stateRegistration),
      'phone': _emptyToNull(phone),
      'email': _emptyToNull(email),
      'address_line': _emptyToNull(addressLine),
      'city': _emptyToNull(city),
      'state': _emptyToNull(state),
      'notes': _emptyToNull(notes),
      'active': active,
    };
  }
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
