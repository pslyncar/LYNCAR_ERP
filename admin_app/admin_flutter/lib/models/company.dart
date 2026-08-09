class Company {
  const Company({
    required this.id,
    required this.code,
    required this.name,
    required this.businessType,
    required this.personType,
    this.documentNumber,
    this.stateRegistration,
    this.municipalRegistration,
    this.tradeName,
    this.contactName,
    this.responsibleCpf,
    this.responsibleBirthDate,
    this.phone,
    this.email,
    this.addressLine,
    this.addressNumber,
    this.neighborhood,
    this.city,
    this.cityCode,
    this.state,
    this.zipCode,
    this.taxRegime,
    this.crt,
    this.taxRegimeSource,
    this.taxRegimeCheckedAt,
    this.cnpjLookupStatus,
    this.cnpjLookupMessage,
    this.cnaeMain,
    this.legalNature,
    this.companySize,
    required this.databaseUrl,
    required this.plan,
    this.planOverrides,
    required this.enabledModules,
    this.monthlyPrice,
    this.billingDay,
    this.paymentMethod,
    this.contractSignedAt,
    this.contractExpiresAt,
    this.contractFileUrl,
    this.contractFileName,
    this.contractNotes,
    this.digitalCertificateConfigured = false,
    this.digitalCertificateName,
    this.digitalCertificateExpiresAt,
    this.digitalCertificateNotes,
    required this.status,
    required this.active,
    this.notes,
    this.databaseUsageMb,
    this.fileUsageMb,
    this.databaseLimitMb,
    this.fileLimitMb,
  });

  final int id;
  final String code;
  final String name;
  final String businessType;
  final String personType;
  final String? documentNumber;
  final String? stateRegistration;
  final String? municipalRegistration;
  final String? tradeName;
  final String? contactName;
  final String? responsibleCpf;
  final String? responsibleBirthDate;
  final String? phone;
  final String? email;
  final String? addressLine;
  final String? addressNumber;
  final String? neighborhood;
  final String? city;
  final String? cityCode;
  final String? state;
  final String? zipCode;
  final String? taxRegime;
  final String? crt;
  final String? taxRegimeSource;
  final String? taxRegimeCheckedAt;
  final String? cnpjLookupStatus;
  final String? cnpjLookupMessage;
  final String? cnaeMain;
  final String? legalNature;
  final String? companySize;
  final String databaseUrl;
  final String plan;
  final Map<String, dynamic>? planOverrides;
  final List<String> enabledModules;
  final String? monthlyPrice;
  final String? billingDay;
  final String? paymentMethod;
  final String? contractSignedAt;
  final String? contractExpiresAt;
  final String? contractFileUrl;
  final String? contractFileName;
  final String? contractNotes;
  final bool digitalCertificateConfigured;
  final String? digitalCertificateName;
  final String? digitalCertificateExpiresAt;
  final String? digitalCertificateNotes;
  final String status;
  final bool active;
  final String? notes;
  final int? databaseUsageMb;
  final int? fileUsageMb;
  final int? databaseLimitMb;
  final int? fileLimitMb;

  factory Company.fromJson(Map<String, dynamic> json) {
    return Company(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      businessType: json['business_type'] as String? ?? 'custom',
      personType: json['person_type'] as String? ?? 'PF',
      documentNumber: json['document_number'] as String?,
      stateRegistration: json['state_registration'] as String?,
      municipalRegistration: json['municipal_registration'] as String?,
      tradeName: json['trade_name'] as String?,
      contactName: json['contact_name'] as String?,
      responsibleCpf: json['responsible_cpf'] as String?,
      responsibleBirthDate: json['responsible_birth_date'] as String?,
      phone: json['phone'] as String?,
      email: json['email'] as String?,
      addressLine: json['address_line'] as String?,
      addressNumber: json['address_number'] as String?,
      neighborhood: json['neighborhood'] as String?,
      city: json['city'] as String?,
      cityCode: json['city_code'] as String?,
      state: json['state'] as String?,
      zipCode: json['zip_code'] as String?,
      taxRegime: json['tax_regime'] as String?,
      crt: json['crt'] as String?,
      taxRegimeSource: json['tax_regime_source'] as String?,
      taxRegimeCheckedAt: json['tax_regime_checked_at'] as String?,
      cnpjLookupStatus: json['cnpj_lookup_status'] as String?,
      cnpjLookupMessage: json['cnpj_lookup_message'] as String?,
      cnaeMain: json['cnae_main'] as String?,
      legalNature: json['legal_nature'] as String?,
      companySize: json['company_size'] as String?,
      databaseUrl: json['database_url'] as String,
      plan: json['plan'] as String? ?? 'erp',
      planOverrides: json['plan_overrides'] as Map<String, dynamic>?,
      enabledModules: (json['enabled_modules'] as List<dynamic>? ?? [])
          .map((module) => module.toString())
          .toList(),
      monthlyPrice: json['monthly_price'] as String?,
      billingDay: json['billing_day'] as String?,
      paymentMethod: json['payment_method'] as String?,
      contractSignedAt: json['contract_signed_at'] as String?,
      contractExpiresAt: json['contract_expires_at'] as String?,
      contractFileUrl: json['contract_file_url'] as String?,
      contractFileName: json['contract_file_name'] as String?,
      contractNotes: json['contract_notes'] as String?,
      digitalCertificateConfigured:
          json['digital_certificate_configured'] as bool? ?? false,
      digitalCertificateName: json['digital_certificate_name'] as String?,
      digitalCertificateExpiresAt:
          json['digital_certificate_expires_at'] as String?,
      digitalCertificateNotes: json['digital_certificate_notes'] as String?,
      status: json['status'] as String? ?? 'active',
      active: json['active'] as bool? ?? true,
      notes: json['notes'] as String?,
      databaseUsageMb: json['database_usage_mb'] as int?,
      fileUsageMb: json['file_usage_mb'] as int?,
      databaseLimitMb: json['database_limit_mb'] as int?,
      fileLimitMb: json['file_limit_mb'] as int?,
    );
  }
}

class CompanyInput {
  const CompanyInput({
    required this.code,
    required this.name,
    required this.businessType,
    required this.personType,
    this.documentNumber,
    this.stateRegistration,
    this.municipalRegistration,
    this.tradeName,
    this.contactName,
    this.responsibleCpf,
    this.responsibleBirthDate,
    this.phone,
    this.email,
    this.addressLine,
    this.addressNumber,
    this.neighborhood,
    this.city,
    this.cityCode,
    this.state,
    this.zipCode,
    this.taxRegime,
    this.crt,
    required this.databaseUrl,
    required this.plan,
    this.planOverrides,
    required this.enabledModules,
    this.monthlyPrice,
    this.billingDay,
    this.paymentMethod,
    this.contractSignedAt,
    this.contractExpiresAt,
    this.contractFileUrl,
    this.contractFileName,
    this.contractNotes,
    this.digitalCertificateConfigured = false,
    this.digitalCertificateName,
    this.digitalCertificateExpiresAt,
    this.digitalCertificateNotes,
    required this.status,
    required this.active,
    required this.provisionDatabase,
    required this.adminName,
    required this.adminEmail,
    required this.adminPassword,
    this.allowCrossCompanyDuplicate = false,
    this.notes,
  });

  final String code;
  final String name;
  final String businessType;
  final String personType;
  final String? documentNumber;
  final String? stateRegistration;
  final String? municipalRegistration;
  final String? tradeName;
  final String? contactName;
  final String? responsibleCpf;
  final String? responsibleBirthDate;
  final String? phone;
  final String? email;
  final String? addressLine;
  final String? addressNumber;
  final String? neighborhood;
  final String? city;
  final String? cityCode;
  final String? state;
  final String? zipCode;
  final String? taxRegime;
  final String? crt;
  final String databaseUrl;
  final String plan;
  final Map<String, dynamic>? planOverrides;
  final List<String> enabledModules;
  final String? monthlyPrice;
  final String? billingDay;
  final String? paymentMethod;
  final String? contractSignedAt;
  final String? contractExpiresAt;
  final String? contractFileUrl;
  final String? contractFileName;
  final String? contractNotes;
  final bool digitalCertificateConfigured;
  final String? digitalCertificateName;
  final String? digitalCertificateExpiresAt;
  final String? digitalCertificateNotes;
  final String status;
  final bool active;
  final bool provisionDatabase;
  final String adminName;
  final String adminEmail;
  final String adminPassword;
  final bool allowCrossCompanyDuplicate;
  final String? notes;

  Map<String, dynamic> toCreateJson() {
    return {
      'code': code,
      'name': name,
      'business_type': businessType,
      'person_type': personType,
      'document_number': documentNumber,
      'state_registration': stateRegistration,
      'municipal_registration': municipalRegistration,
      'trade_name': tradeName,
      'contact_name': contactName,
      'responsible_cpf': responsibleCpf,
      'responsible_birth_date': responsibleBirthDate,
      'phone': phone,
      'email': email,
      'address_line': addressLine,
      'address_number': addressNumber,
      'neighborhood': neighborhood,
      'city': city,
      'city_code': cityCode,
      'state': state,
      'zip_code': zipCode,
      'tax_regime': taxRegime,
      'crt': crt,
      if (databaseUrl.trim().isNotEmpty) 'database_url': databaseUrl,
      'plan': plan,
      'plan_overrides': planOverrides,
      'enabled_modules': enabledModules,
      'monthly_price': monthlyPrice,
      'billing_day': billingDay,
      'payment_method': paymentMethod,
      'contract_signed_at': contractSignedAt,
      'contract_expires_at': contractExpiresAt,
      'contract_file_url': contractFileUrl,
      'contract_file_name': contractFileName,
      'contract_notes': contractNotes,
      'status': status,
      'active': active,
      'notes': notes,
      'provision_database': provisionDatabase,
      'admin_name': adminName,
      'admin_email': adminEmail,
      'admin_password': adminPassword,
      'allow_cross_company_duplicate': allowCrossCompanyDuplicate,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name,
      'business_type': businessType,
      'person_type': personType,
      'document_number': documentNumber,
      'state_registration': stateRegistration,
      'municipal_registration': municipalRegistration,
      'trade_name': tradeName,
      'contact_name': contactName,
      'responsible_cpf': responsibleCpf,
      'responsible_birth_date': responsibleBirthDate,
      'phone': phone,
      'email': email,
      'address_line': addressLine,
      'address_number': addressNumber,
      'neighborhood': neighborhood,
      'city': city,
      'city_code': cityCode,
      'state': state,
      'zip_code': zipCode,
      'tax_regime': taxRegime,
      'crt': crt,
      if (databaseUrl.trim().isNotEmpty) 'database_url': databaseUrl,
      'plan': plan,
      'plan_overrides': planOverrides,
      'enabled_modules': enabledModules,
      'monthly_price': monthlyPrice,
      'billing_day': billingDay,
      'payment_method': paymentMethod,
      'contract_signed_at': contractSignedAt,
      'contract_expires_at': contractExpiresAt,
      'contract_file_url': contractFileUrl,
      'contract_file_name': contractFileName,
      'contract_notes': contractNotes,
      'status': status,
      'active': active,
      'notes': notes,
    };
  }
}

class CompanyContract {
  const CompanyContract({
    required this.id,
    required this.code,
    required this.name,
    required this.status,
    required this.active,
    required this.attentionLevel,
    this.documentNumber,
    this.email,
    this.phone,
    this.contractSignedAt,
    this.contractExpiresAt,
    this.contractFileUrl,
    this.contractFileName,
    this.contractNotes,
    this.daysToExpire,
  });

  final int id;
  final String code;
  final String name;
  final String? documentNumber;
  final String? email;
  final String? phone;
  final String status;
  final bool active;
  final String? contractSignedAt;
  final String? contractExpiresAt;
  final String? contractFileUrl;
  final String? contractFileName;
  final String? contractNotes;
  final int? daysToExpire;
  final String attentionLevel;

  factory CompanyContract.fromJson(Map<String, dynamic> json) {
    return CompanyContract(
      id: json['id'] as int,
      code: json['code'].toString(),
      name: json['name'].toString(),
      documentNumber: json['document_number']?.toString(),
      email: json['email']?.toString(),
      phone: json['phone']?.toString(),
      status: json['status'].toString(),
      active: json['active'] as bool? ?? true,
      contractSignedAt: json['contract_signed_at']?.toString(),
      contractExpiresAt: json['contract_expires_at']?.toString(),
      contractFileUrl: json['contract_file_url']?.toString(),
      contractFileName: json['contract_file_name']?.toString(),
      contractNotes: json['contract_notes']?.toString(),
      daysToExpire: json['days_to_expire'] as int?,
      attentionLevel: json['attention_level']?.toString() ?? 'sem_contrato',
    );
  }
}

class CompanyTaxProfileLookup {
  const CompanyTaxProfileLookup({
    required this.cnpj,
    required this.found,
    required this.status,
    this.source,
    this.message,
    this.legalName,
    this.tradeName,
    this.taxRegime,
    this.crt,
    this.isMei,
    this.isSimples,
    this.cnaeMain,
    this.cnaeDescription,
    this.legalNature,
    this.companySize,
    this.statusReason,
    this.openedAt,
    this.email,
    this.phone,
    this.zipCode,
    this.state,
    this.city,
    this.cityCode,
    this.neighborhood,
    this.addressLine,
    this.addressNumber,
    this.addressComplement,
  });

  final String cnpj;
  final bool found;
  final String status;
  final String? source;
  final String? message;
  final String? legalName;
  final String? tradeName;
  final String? taxRegime;
  final String? crt;
  final bool? isMei;
  final bool? isSimples;
  final String? cnaeMain;
  final String? cnaeDescription;
  final String? legalNature;
  final String? companySize;
  final String? statusReason;
  final String? openedAt;
  final String? email;
  final String? phone;
  final String? zipCode;
  final String? state;
  final String? city;
  final String? cityCode;
  final String? neighborhood;
  final String? addressLine;
  final String? addressNumber;
  final String? addressComplement;

  factory CompanyTaxProfileLookup.fromJson(Map<String, dynamic> json) {
    return CompanyTaxProfileLookup(
      cnpj: json['cnpj'] as String? ?? '',
      found: json['found'] as bool? ?? false,
      status: json['status'] as String? ?? 'not_found',
      source: json['source'] as String?,
      message: json['message'] as String?,
      legalName: json['legal_name'] as String?,
      tradeName: json['trade_name'] as String?,
      taxRegime: json['tax_regime'] as String?,
      crt: json['crt'] as String?,
      isMei: json['is_mei'] as bool?,
      isSimples: json['is_simples'] as bool?,
      cnaeMain: json['cnae_main'] as String?,
      cnaeDescription: json['cnae_description'] as String?,
      legalNature: json['legal_nature'] as String?,
      companySize: json['company_size'] as String?,
      statusReason: json['status_reason'] as String?,
      openedAt: json['opened_at'] as String?,
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      zipCode: json['zip_code'] as String?,
      state: json['state'] as String?,
      city: json['city'] as String?,
      cityCode: json['city_code'] as String?,
      neighborhood: json['neighborhood'] as String?,
      addressLine: json['address_line'] as String?,
      addressNumber: json['address_number'] as String?,
      addressComplement: json['address_complement'] as String?,
    );
  }
}
