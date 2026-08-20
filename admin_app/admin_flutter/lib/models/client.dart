class Client {
  const Client({
    required this.id,
    required this.name,
    required this.personType,
    required this.contractType,
    required this.active,
    required this.createdAt,
    required this.allowCredit,
    required this.creditLimit,
    required this.creditStatus,
    required this.monthlyFee,
    this.tradeName,
    this.documentNumber,
    this.stateRegistration,
    this.municipalRegistration,
    this.taxContributorType,
    this.cityCode,
    this.countryCode,
    this.countryName,
    this.suframa,
    this.contactPerson,
    this.phone,
    this.mobilePhone,
    this.email,
    this.address,
    this.addressNumber,
    this.addressComplement,
    this.neighborhood,
    this.city,
    this.state,
    this.zipCode,
    this.monthlyDueDay,
    this.paymentTerms,
    this.billingNotes,
    this.notes,
  });

  final int id;
  final String name;
  final String personType;
  final String contractType;
  final bool active;
  final DateTime createdAt;
  final bool allowCredit;
  final double creditLimit;
  final String creditStatus;
  final double monthlyFee;
  final String? tradeName;
  final String? documentNumber;
  final String? stateRegistration;
  final String? municipalRegistration;
  final String? taxContributorType;
  final String? cityCode;
  final String? countryCode;
  final String? countryName;
  final String? suframa;
  final String? contactPerson;
  final String? phone;
  final String? mobilePhone;
  final String? email;
  final String? address;
  final String? addressNumber;
  final String? addressComplement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? zipCode;
  final int? monthlyDueDay;
  final String? paymentTerms;
  final String? billingNotes;
  final String? notes;

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['id'] as int,
      name: json['name'] as String,
      personType: json['person_type'] as String? ?? 'PF',
      contractType: json['contract_type'] as String? ?? 'avulso',
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      allowCredit: json['allow_credit'] as bool? ?? false,
      creditLimit: _toDouble(json['credit_limit']),
      creditStatus: json['credit_status'] as String? ?? 'liberado',
      monthlyFee: _toDouble(json['monthly_fee']),
      tradeName: json['trade_name'] as String?,
      documentNumber: json['document_number'] as String?,
      stateRegistration: json['state_registration'] as String?,
      municipalRegistration: json['municipal_registration'] as String?,
      taxContributorType: json['tax_contributor_type'] as String?,
      cityCode: json['city_code'] as String?,
      countryCode: json['country_code'] as String?,
      countryName: json['country_name'] as String?,
      suframa: json['suframa'] as String?,
      contactPerson: json['contact_person'] as String?,
      phone: json['phone'] as String?,
      mobilePhone: json['mobile_phone'] as String?,
      email: json['email'] as String?,
      address: json['address'] as String?,
      addressNumber: json['address_number'] as String?,
      addressComplement: json['address_complement'] as String?,
      neighborhood: json['neighborhood'] as String?,
      city: json['city'] as String?,
      state: json['state'] as String?,
      zipCode: json['zip_code'] as String?,
      monthlyDueDay: json['monthly_due_day'] as int?,
      paymentTerms: json['payment_terms'] as String?,
      billingNotes: json['billing_notes'] as String?,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'person_type': personType,
      'trade_name': tradeName,
      'document_number': documentNumber,
      'state_registration': stateRegistration,
      'municipal_registration': municipalRegistration,
      'tax_contributor_type': taxContributorType,
      'city_code': cityCode,
      'country_code': countryCode,
      'country_name': countryName,
      'suframa': suframa,
      'contact_person': contactPerson,
      'phone': phone,
      'mobile_phone': mobilePhone,
      'email': email,
      'address': address,
      'address_number': addressNumber,
      'address_complement': addressComplement,
      'neighborhood': neighborhood,
      'city': city,
      'state': state,
      'zip_code': zipCode,
      'contract_type': contractType,
      'monthly_fee': monthlyFee,
      'monthly_due_day': monthlyDueDay,
      'allow_credit': allowCredit,
      'credit_limit': creditLimit,
      'credit_status': creditStatus,
      'payment_terms': paymentTerms,
      'billing_notes': billingNotes,
      'notes': notes,
      'active': active,
      'created_at': createdAt.toIso8601String(),
    };
  }
}

double _toDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

class ClientCreate {
  const ClientCreate({
    required this.name,
    required this.personType,
    required this.contractType,
    required this.allowCredit,
    required this.creditLimit,
    required this.creditStatus,
    required this.monthlyFee,
    this.tradeName,
    this.documentNumber,
    this.stateRegistration,
    this.municipalRegistration,
    this.taxContributorType,
    this.cityCode,
    this.countryCode,
    this.countryName,
    this.suframa,
    this.contactPerson,
    this.phone,
    this.mobilePhone,
    this.email,
    this.address,
    this.addressNumber,
    this.addressComplement,
    this.neighborhood,
    this.city,
    this.state,
    this.zipCode,
    this.monthlyDueDay,
    this.paymentTerms,
    this.billingNotes,
    this.notes,
  });

  final String name;
  final String personType;
  final String contractType;
  final bool allowCredit;
  final double creditLimit;
  final String creditStatus;
  final double monthlyFee;
  final String? tradeName;
  final String? documentNumber;
  final String? stateRegistration;
  final String? municipalRegistration;
  final String? taxContributorType;
  final String? cityCode;
  final String? countryCode;
  final String? countryName;
  final String? suframa;
  final String? contactPerson;
  final String? phone;
  final String? mobilePhone;
  final String? email;
  final String? address;
  final String? addressNumber;
  final String? addressComplement;
  final String? neighborhood;
  final String? city;
  final String? state;
  final String? zipCode;
  final int? monthlyDueDay;
  final String? paymentTerms;
  final String? billingNotes;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'person_type': personType,
      'contract_type': contractType,
      'monthly_fee': monthlyFee,
      'monthly_due_day': monthlyDueDay,
      'allow_credit': allowCredit,
      'credit_limit': creditLimit,
      'credit_status': creditStatus,
      'trade_name': _emptyToNull(tradeName),
      'document_number': _emptyToNull(documentNumber),
      'state_registration': _emptyToNull(stateRegistration),
      'municipal_registration': _emptyToNull(municipalRegistration),
      'tax_contributor_type': _emptyToNull(taxContributorType),
      'city_code': _emptyToNull(cityCode),
      'country_code': _emptyToNull(countryCode),
      'country_name': _emptyToNull(countryName),
      'suframa': _emptyToNull(suframa),
      'contact_person': _emptyToNull(contactPerson),
      'phone': _emptyToNull(phone),
      'mobile_phone': _emptyToNull(mobilePhone),
      'email': _emptyToNull(email),
      'address': _emptyToNull(address),
      'address_number': _emptyToNull(addressNumber),
      'address_complement': _emptyToNull(addressComplement),
      'neighborhood': _emptyToNull(neighborhood),
      'city': _emptyToNull(city),
      'state': _emptyToNull(state?.toUpperCase()),
      'zip_code': _emptyToNull(zipCode),
      'payment_terms': _emptyToNull(paymentTerms),
      'billing_notes': _emptyToNull(billingNotes),
      'notes': _emptyToNull(notes),
      'active': true,
    };
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }
}

class ClientUpdate extends ClientCreate {
  const ClientUpdate({
    required super.name,
    required super.personType,
    required super.contractType,
    required super.allowCredit,
    required super.creditLimit,
    required super.creditStatus,
    required super.monthlyFee,
    super.tradeName,
    super.documentNumber,
    super.stateRegistration,
    super.municipalRegistration,
    super.taxContributorType,
    super.cityCode,
    super.countryCode,
    super.countryName,
    super.suframa,
    super.contactPerson,
    super.phone,
    super.mobilePhone,
    super.email,
    super.address,
    super.addressNumber,
    super.addressComplement,
    super.neighborhood,
    super.city,
    super.state,
    super.zipCode,
    super.monthlyDueDay,
    super.paymentTerms,
    super.billingNotes,
    super.notes,
  });
}
