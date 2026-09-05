class CompanyFiscalSetting {
  const CompanyFiscalSetting({
    required this.id,
    required this.environment,
    required this.nfceEnabled,
    required this.pdvNfceEnabled,
    required this.nfeEnabled,
    required this.hasCertificate,
    required this.nfceSeries,
    required this.nfceNextNumber,
    required this.nfeSeries,
    required this.nfeNextNumber,
    required this.hasNfceCsc,
    this.legalName,
    this.tradeName,
    this.cnpj,
    this.stateRegistration,
    this.municipalRegistration,
    this.crt,
    this.taxRegime,
    this.uf,
    this.cityCode,
    this.addressLine,
    this.addressNumber,
    this.neighborhood,
    this.city,
    this.zipCode,
    this.certificateName,
    this.certificateFileSha256,
    this.nfceCscId,
    this.certificateExpiresAt,
    this.logoUrl,
    this.notes,
  });

  final int id;
  final String environment;
  final bool nfceEnabled;
  final bool pdvNfceEnabled;
  final bool nfeEnabled;
  final bool hasCertificate;
  final int nfceSeries;
  final int nfceNextNumber;
  final int nfeSeries;
  final int nfeNextNumber;
  final bool hasNfceCsc;
  final String? legalName;
  final String? tradeName;
  final String? cnpj;
  final String? stateRegistration;
  final String? municipalRegistration;
  final String? crt;
  final String? taxRegime;
  final String? uf;
  final String? cityCode;
  final String? addressLine;
  final String? addressNumber;
  final String? neighborhood;
  final String? city;
  final String? zipCode;
  final String? certificateName;
  final String? certificateFileSha256;
  final String? nfceCscId;
  final DateTime? certificateExpiresAt;
  final String? logoUrl;
  final String? notes;

  factory CompanyFiscalSetting.fromJson(Map<String, dynamic> json) {
    return CompanyFiscalSetting(
      id: json['id'] as int,
      environment: json['environment'] as String? ?? 'homologacao',
      nfceEnabled: json['nfce_enabled'] as bool? ?? false,
      pdvNfceEnabled: json['pdv_nfce_enabled'] as bool? ?? false,
      nfeEnabled: json['nfe_enabled'] as bool? ?? false,
      hasCertificate: json['has_certificate'] as bool? ?? false,
      nfceSeries: json['nfce_series'] as int? ?? 1,
      nfceNextNumber: json['nfce_next_number'] as int? ?? 1,
      nfeSeries: json['nfe_series'] as int? ?? 1,
      nfeNextNumber: json['nfe_next_number'] as int? ?? 1,
      hasNfceCsc: json['has_nfce_csc'] as bool? ?? false,
      legalName: json['legal_name'] as String?,
      tradeName: json['trade_name'] as String?,
      cnpj: json['cnpj'] as String?,
      stateRegistration: json['state_registration'] as String?,
      municipalRegistration: json['municipal_registration'] as String?,
      crt: json['crt'] as String?,
      taxRegime: json['tax_regime'] as String?,
      uf: json['uf'] as String?,
      cityCode: json['city_code'] as String?,
      addressLine: json['address_line'] as String?,
      addressNumber: json['address_number'] as String?,
      neighborhood: json['neighborhood'] as String?,
      city: json['city'] as String?,
      zipCode: json['zip_code'] as String?,
      certificateName: json['certificate_name'] as String?,
      certificateFileSha256: json['certificate_file_sha256'] as String?,
      nfceCscId: json['nfce_csc_id'] as String?,
      certificateExpiresAt: json['certificate_expires_at'] == null
          ? null
          : DateTime.parse(json['certificate_expires_at'] as String),
      logoUrl:
          json['pdv_logo_url'] as String? ??
          json['receipt_logo_url'] as String? ??
          json['company_logo_url'] as String? ??
          json['logo_url'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

class NfceNumberingSyncResult {
  const NfceNumberingSyncResult({
    required this.environment,
    required this.series,
    required this.currentNextNumber,
    required this.suggestedNextNumber,
    required this.updatedNextNumber,
    required this.keysCount,
    required this.incomplete,
    this.highestAuthorizedNumber,
    this.statusCode,
    this.message,
  });

  final String environment;
  final int series;
  final int currentNextNumber;
  final int? highestAuthorizedNumber;
  final int suggestedNextNumber;
  final int updatedNextNumber;
  final int keysCount;
  final bool incomplete;
  final String? statusCode;
  final String? message;

  factory NfceNumberingSyncResult.fromJson(Map<String, dynamic> json) {
    return NfceNumberingSyncResult(
      environment: json['environment'] as String? ?? 'homologacao',
      series: json['series'] as int? ?? 1,
      currentNextNumber: json['current_next_number'] as int? ?? 1,
      highestAuthorizedNumber: json['highest_authorized_number'] as int?,
      suggestedNextNumber: json['suggested_next_number'] as int? ?? 1,
      updatedNextNumber: json['updated_next_number'] as int? ?? 1,
      keysCount: json['keys_count'] as int? ?? 0,
      incomplete: json['incomplete'] as bool? ?? false,
      statusCode: json['status_code'] as String?,
      message: json['message'] as String?,
    );
  }
}

class FiscalNumberingStatus {
  const FiscalNumberingStatus({
    required this.environment,
    required this.nfceSeries,
    required this.nfceNextNumber,
    required this.nfeSeries,
    required this.nfeNextNumber,
    this.nfceLastAuthorizedNumber,
    this.nfeLastAuthorizedNumber,
  });

  final String environment;
  final int nfceSeries;
  final int? nfceLastAuthorizedNumber;
  final int nfceNextNumber;
  final int nfeSeries;
  final int? nfeLastAuthorizedNumber;
  final int nfeNextNumber;

  factory FiscalNumberingStatus.fromJson(Map<String, dynamic> json) {
    return FiscalNumberingStatus(
      environment: json['environment'] as String? ?? 'homologacao',
      nfceSeries: json['nfce_series'] as int? ?? 1,
      nfceLastAuthorizedNumber: json['nfce_last_authorized_number'] as int?,
      nfceNextNumber: json['nfce_next_number'] as int? ?? 1,
      nfeSeries: json['nfe_series'] as int? ?? 1,
      nfeLastAuthorizedNumber: json['nfe_last_authorized_number'] as int?,
      nfeNextNumber: json['nfe_next_number'] as int? ?? 1,
    );
  }
}

class FiscalSetupChecklist {
  const FiscalSetupChecklist({
    required this.readyForNfe,
    required this.readyForNfce,
    required this.environment,
    required this.items,
    this.crt,
    this.taxRegime,
  });

  final bool readyForNfe;
  final bool readyForNfce;
  final String environment;
  final String? crt;
  final String? taxRegime;
  final List<FiscalSetupChecklistItem> items;

  factory FiscalSetupChecklist.fromJson(Map<String, dynamic> json) {
    return FiscalSetupChecklist(
      readyForNfe: json['ready_for_nfe'] as bool? ?? false,
      readyForNfce: json['ready_for_nfce'] as bool? ?? false,
      environment: json['environment'] as String? ?? 'homologacao',
      crt: json['crt'] as String?,
      taxRegime: json['tax_regime'] as String?,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                FiscalSetupChecklistItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class FiscalSetupChecklistItem {
  const FiscalSetupChecklistItem({
    required this.code,
    required this.title,
    required this.status,
    required this.owner,
    required this.message,
    required this.blocksNfe,
    required this.blocksNfce,
  });

  final String code;
  final String title;
  final String status;
  final String owner;
  final String message;
  final bool blocksNfe;
  final bool blocksNfce;

  factory FiscalSetupChecklistItem.fromJson(Map<String, dynamic> json) {
    return FiscalSetupChecklistItem(
      code: json['code'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      owner: json['owner'] as String? ?? 'contador',
      message: json['message'] as String? ?? '',
      blocksNfe: json['blocks_nfe'] as bool? ?? false,
      blocksNfce: json['blocks_nfce'] as bool? ?? false,
    );
  }
}

class RtcIncompleteProduct {
  const RtcIncompleteProduct({
    required this.id,
    required this.name,
    required this.missingFields,
    required this.issues,
    this.internalCode,
    this.ncm,
    this.status,
    this.ruleSource,
    this.ruleId,
    this.ruleName,
  });

  final int id;
  final String name;
  final String? internalCode;
  final String? ncm;
  final String? status;
  final String? ruleSource;
  final int? ruleId;
  final String? ruleName;
  final List<String> missingFields;
  final List<FiscalProductIssue> issues;

  factory RtcIncompleteProduct.fromJson(Map<String, dynamic> json) {
    return RtcIncompleteProduct(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Produto sem nome',
      internalCode: json['internal_code'] as String?,
      ncm: json['ncm'] as String?,
      status: json['status'] as String?,
      ruleSource: json['rule_source'] as String?,
      ruleId: json['rule_id'] as int?,
      ruleName: json['rule_name'] as String?,
      missingFields: (json['missing_fields'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      issues: (json['issues'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(FiscalProductIssue.fromJson)
          .toList(growable: false),
    );
  }
}

class FiscalProductIssue {
  const FiscalProductIssue({
    required this.field,
    required this.message,
    required this.severity,
    required this.owner,
    required this.blocksNfe,
    required this.blocksNfce,
  });

  final String field;
  final String message;
  final String severity;
  final String owner;
  final bool blocksNfe;
  final bool blocksNfce;

  factory FiscalProductIssue.fromJson(Map<String, dynamic> json) {
    return FiscalProductIssue(
      field: json['field'] as String? ?? '',
      message: json['message'] as String? ?? '',
      severity: json['severity'] as String? ?? 'error',
      owner: json['owner'] as String? ?? 'contador',
      blocksNfe: json['blocks_nfe'] as bool? ?? false,
      blocksNfce: json['blocks_nfce'] as bool? ?? false,
    );
  }
}

class RtcCompliance {
  const RtcCompliance({
    required this.effectiveCrt,
    required this.mandatory,
    required this.ready,
    required this.message,
    required this.documentModel,
    required this.productsTotal,
    required this.productsIncomplete,
    required this.incompleteProducts,
    this.mandatoryFrom,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
  });

  final String effectiveCrt;
  final bool mandatory;
  final DateTime? mandatoryFrom;
  final bool ready;
  final String message;
  final String documentModel;
  final int productsTotal;
  final int productsIncomplete;
  final List<RtcIncompleteProduct> incompleteProducts;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;

  factory RtcCompliance.fromJson(Map<String, dynamic> json) {
    final rates = json['rates'] as Map<String, dynamic>?;
    return RtcCompliance(
      effectiveCrt: json['effective_crt']?.toString() ?? '',
      mandatory: json['mandatory'] as bool? ?? false,
      mandatoryFrom: json['mandatory_from'] == null
          ? null
          : DateTime.parse(json['mandatory_from'] as String),
      ready: json['ready'] as bool? ?? false,
      message: json['message'] as String? ?? '',
      documentModel: json['document_model']?.toString() ?? '65',
      productsTotal: json['products_total'] as int? ?? 0,
      productsIncomplete: json['products_incomplete'] as int? ?? 0,
      incompleteProducts:
          (json['incomplete_products'] as List<dynamic>? ?? const [])
              .map(
                (item) =>
                    RtcIncompleteProduct.fromJson(item as Map<String, dynamic>),
              )
              .toList(growable: false),
      cbsRate: _toDoubleOrNull(rates?['cbs']),
      ibsStateRate: _toDoubleOrNull(rates?['ibs_uf']),
      ibsCityRate: _toDoubleOrNull(rates?['ibs_mun']),
    );
  }
}

class FiscalOutputRule {
  const FiscalOutputRule({
    required this.id,
    required this.name,
    required this.active,
    required this.priority,
    required this.operationType,
    required this.createdAt,
    required this.updatedAt,
    this.documentModel,
    this.taxRegime,
    this.crt,
    this.ufOrigin,
    this.ufDestination,
    this.productId,
    this.productName,
    this.ncm,
    this.ncmPrefix,
    this.cest,
    this.cfop,
    this.origin,
    this.cst,
    this.csosn,
    this.pisCst,
    this.cofinsCst,
    this.icmsRate,
    this.pisRate,
    this.cofinsRate,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
    this.selectiveTaxRate,
    this.effectiveFrom,
    this.effectiveTo,
    this.notes,
  });

  final int id;
  final String name;
  final bool active;
  final int priority;
  final String operationType;
  final String? documentModel;
  final String? taxRegime;
  final String? crt;
  final String? ufOrigin;
  final String? ufDestination;
  final int? productId;
  final String? productName;
  final String? ncm;
  final String? ncmPrefix;
  final String? cest;
  final String? cfop;
  final String? origin;
  final String? cst;
  final String? csosn;
  final String? pisCst;
  final String? cofinsCst;
  final double? icmsRate;
  final double? pisRate;
  final double? cofinsRate;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;
  final double? selectiveTaxRate;
  final DateTime? effectiveFrom;
  final DateTime? effectiveTo;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory FiscalOutputRule.fromJson(Map<String, dynamic> json) {
    return FiscalOutputRule(
      id: json['id'] as int,
      name: json['name'] as String? ?? 'Regra fiscal',
      active: json['active'] as bool? ?? true,
      priority: json['priority'] as int? ?? 100,
      operationType: json['operation_type'] as String? ?? 'sale',
      documentModel: json['document_model'] as String?,
      taxRegime: json['tax_regime'] as String?,
      crt: json['crt'] as String?,
      ufOrigin: json['uf_origin'] as String?,
      ufDestination: json['uf_destination'] as String?,
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String?,
      ncm: json['ncm'] as String?,
      ncmPrefix: json['ncm_prefix'] as String?,
      cest: json['cest'] as String?,
      cfop: json['cfop'] as String?,
      origin: json['origin'] as String?,
      cst: json['cst'] as String?,
      csosn: json['csosn'] as String?,
      pisCst: json['pis_cst'] as String?,
      cofinsCst: json['cofins_cst'] as String?,
      icmsRate: _toDoubleOrNull(json['icms_rate']),
      pisRate: _toDoubleOrNull(json['pis_rate']),
      cofinsRate: _toDoubleOrNull(json['cofins_rate']),
      ibsCbsCst: json['ibs_cbs_cst'] as String?,
      ibsCbsClassification: json['ibs_cbs_classification'] as String?,
      cbsRate: _toDoubleOrNull(json['cbs_rate']),
      ibsStateRate: _toDoubleOrNull(json['ibs_state_rate']),
      ibsCityRate: _toDoubleOrNull(json['ibs_city_rate']),
      selectiveTaxCst: json['selective_tax_cst'] as String?,
      selectiveTaxClassification:
          json['selective_tax_classification'] as String?,
      selectiveTaxRate: _toDoubleOrNull(json['selective_tax_rate']),
      effectiveFrom: json['effective_from'] == null
          ? null
          : DateTime.parse(json['effective_from'] as String),
      effectiveTo: json['effective_to'] == null
          ? null
          : DateTime.parse(json['effective_to'] as String),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class FiscalOutputRulePreview {
  const FiscalOutputRulePreview({
    required this.documentModel,
    required this.operationType,
    required this.interstate,
    required this.documentAllowed,
    required this.ruleSource,
    required this.warnings,
    this.productId,
    this.productName,
    this.originUf,
    this.destinationUf,
    this.documentWarning,
    this.ruleId,
    this.ruleName,
    this.cfop,
    this.origin,
    this.cst,
    this.csosn,
    this.pisCst,
    this.cofinsCst,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
  });

  final int? productId;
  final String? productName;
  final String documentModel;
  final String operationType;
  final String? originUf;
  final String? destinationUf;
  final bool interstate;
  final bool documentAllowed;
  final String? documentWarning;
  final String ruleSource;
  final int? ruleId;
  final String? ruleName;
  final String? cfop;
  final String? origin;
  final String? cst;
  final String? csosn;
  final String? pisCst;
  final String? cofinsCst;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final List<String> warnings;

  factory FiscalOutputRulePreview.fromJson(Map<String, dynamic> json) {
    return FiscalOutputRulePreview(
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String?,
      documentModel: json['document_model'] as String? ?? '65',
      operationType: json['operation_type'] as String? ?? 'sale',
      originUf: json['origin_uf'] as String?,
      destinationUf: json['destination_uf'] as String?,
      interstate: json['interstate'] as bool? ?? false,
      documentAllowed: json['document_allowed'] as bool? ?? true,
      documentWarning: json['document_warning'] as String?,
      ruleSource: json['rule_source'] as String? ?? 'automatic',
      ruleId: json['rule_id'] as int?,
      ruleName: json['rule_name'] as String?,
      cfop: json['cfop'] as String?,
      origin: json['origin'] as String?,
      cst: json['cst'] as String?,
      csosn: json['csosn'] as String?,
      pisCst: json['pis_cst'] as String?,
      cofinsCst: json['cofins_cst'] as String?,
      ibsCbsCst: json['ibs_cbs_cst'] as String?,
      ibsCbsClassification: json['ibs_cbs_classification'] as String?,
      cbsRate: _toDoubleOrNull(json['cbs_rate']),
      ibsStateRate: _toDoubleOrNull(json['ibs_state_rate']),
      ibsCityRate: _toDoubleOrNull(json['ibs_city_rate']),
      warnings: (json['warnings'] as List<dynamic>? ?? [])
          .map((item) => item.toString())
          .toList(growable: false),
    );
  }
}

class FiscalDocument {
  const FiscalDocument({
    required this.id,
    required this.documentType,
    required this.model,
    required this.status,
    required this.environment,
    required this.createdAt,
    required this.updatedAt,
    this.saleId,
    this.fiscalClientId,
    this.series,
    this.number,
    this.accessKey,
    this.consumerCpf,
    this.recipientDocument,
    this.recipientName,
    this.operationNature,
    this.finality = '1',
    this.paymentCondition,
    this.fiscalNotes,
    this.freightMode,
    this.freightAmount = 0,
    this.insuranceAmount = 0,
    this.otherExpensesAmount = 0,
    this.carrierName,
    this.carrierDocument,
    this.carrierStateRegistration,
    this.carrierAddress,
    this.carrierCity,
    this.carrierUf,
    this.volumeQuantity,
    this.netWeight,
    this.grossWeight,
    this.volumeSpecies,
    this.volumeBrand,
    this.volumeNumbering,
    this.sefazStatusCode,
    this.sefazMessage,
    this.sefazProtocol,
    this.danfeUrl,
    this.issuedAt,
    this.authorizedAt,
    this.cancelledAt,
    this.cancellationReason,
    this.cancellationProtocol,
    this.cancellationStatusCode,
    this.cancellationMessage,
    this.fiscalItems = const [],
  });

  final int id;
  final int? saleId;
  final int? fiscalClientId;
  final String documentType;
  final String model;
  final int? series;
  final int? number;
  final String? accessKey;
  final String status;
  final String environment;
  final String? consumerCpf;
  final String? recipientDocument;
  final String? recipientName;
  final String? operationNature;
  final String finality;
  final String? paymentCondition;
  final String? fiscalNotes;
  final String? freightMode;
  final double freightAmount;
  final double insuranceAmount;
  final double otherExpensesAmount;
  final String? carrierName;
  final String? carrierDocument;
  final String? carrierStateRegistration;
  final String? carrierAddress;
  final String? carrierCity;
  final String? carrierUf;
  final double? volumeQuantity;
  final double? netWeight;
  final double? grossWeight;
  final String? volumeSpecies;
  final String? volumeBrand;
  final String? volumeNumbering;
  final String? sefazStatusCode;
  final String? sefazMessage;
  final String? sefazProtocol;
  final String? danfeUrl;
  final DateTime? issuedAt;
  final DateTime? authorizedAt;
  final DateTime? cancelledAt;
  final String? cancellationReason;
  final String? cancellationProtocol;
  final String? cancellationStatusCode;
  final String? cancellationMessage;
  final List<FiscalDraftItem> fiscalItems;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory FiscalDocument.fromJson(Map<String, dynamic> json) {
    return FiscalDocument(
      id: json['id'] as int,
      saleId: json['sale_id'] as int?,
      fiscalClientId: json['fiscal_client_id'] as int?,
      documentType: json['document_type'] as String? ?? 'nfce',
      model: json['model'] as String? ?? '65',
      series: json['series'] as int?,
      number: json['number'] as int?,
      accessKey: json['access_key'] as String?,
      status: json['status'] as String? ?? 'draft',
      environment: json['environment'] as String? ?? 'homologacao',
      consumerCpf: json['consumer_cpf'] as String?,
      recipientDocument: json['recipient_document'] as String?,
      recipientName: json['recipient_name'] as String?,
      operationNature: json['operation_nature'] as String?,
      finality: json['finality'] as String? ?? '1',
      paymentCondition: json['payment_condition'] as String?,
      fiscalNotes: json['fiscal_notes'] as String?,
      freightMode: json['freight_mode'] as String?,
      freightAmount: _toDouble(json['freight_amount']),
      insuranceAmount: _toDouble(json['insurance_amount']),
      otherExpensesAmount: _toDouble(json['other_expenses_amount']),
      carrierName: json['carrier_name'] as String?,
      carrierDocument: json['carrier_document'] as String?,
      carrierStateRegistration: json['carrier_state_registration'] as String?,
      carrierAddress: json['carrier_address'] as String?,
      carrierCity: json['carrier_city'] as String?,
      carrierUf: json['carrier_uf'] as String?,
      volumeQuantity: _toDoubleOrNull(json['volume_quantity']),
      netWeight: _toDoubleOrNull(json['net_weight']),
      grossWeight: _toDoubleOrNull(json['gross_weight']),
      volumeSpecies: json['volume_species'] as String?,
      volumeBrand: json['volume_brand'] as String?,
      volumeNumbering: json['volume_numbering'] as String?,
      sefazStatusCode: json['sefaz_status_code'] as String?,
      sefazMessage: json['sefaz_message'] as String?,
      sefazProtocol: json['sefaz_protocol'] as String?,
      danfeUrl: json['danfe_url'] as String?,
      issuedAt: json['issued_at'] == null
          ? null
          : DateTime.parse(json['issued_at'] as String),
      authorizedAt: json['authorized_at'] == null
          ? null
          : DateTime.parse(json['authorized_at'] as String),
      cancelledAt: json['cancelled_at'] == null
          ? null
          : DateTime.parse(json['cancelled_at'] as String),
      cancellationReason: json['cancellation_reason'] as String?,
      cancellationProtocol: json['cancellation_protocol'] as String?,
      cancellationStatusCode: json['cancellation_status_code'] as String?,
      cancellationMessage: json['cancellation_message'] as String?,
      fiscalItems: (json['fiscal_items'] as List<dynamic>? ?? [])
          .map((item) => FiscalDraftItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}

class FiscalDraftItem {
  const FiscalDraftItem({
    this.id,
    this.saleItemId,
    this.originalProductId,
    this.originalProductName,
    this.fiscalProductId,
    this.fiscalProductName,
    this.originalDescription,
    required this.fiscalDescription,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.discountAmount,
    required this.totalPrice,
    this.barcode,
    this.included = true,
    this.adjustmentReason,
    this.ncm,
    this.cest,
    this.cfop,
    this.origin,
    this.cst,
    this.csosn,
    this.pisCst,
    this.cofinsCst,
    this.cbenef,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
  });

  final int? id;
  final int? saleItemId;
  final int? originalProductId;
  final String? originalProductName;
  final int? fiscalProductId;
  final String? fiscalProductName;
  final String? originalDescription;
  final String fiscalDescription;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double discountAmount;
  final double totalPrice;
  final String? barcode;
  final bool included;
  final String? adjustmentReason;
  final String? ncm;
  final String? cest;
  final String? cfop;
  final String? origin;
  final String? cst;
  final String? csosn;
  final String? pisCst;
  final String? cofinsCst;
  final String? cbenef;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;

  factory FiscalDraftItem.fromJson(Map<String, dynamic> json) {
    return FiscalDraftItem(
      id: json['id'] as int?,
      saleItemId: json['sale_item_id'] as int?,
      originalProductId: json['original_product_id'] as int?,
      originalProductName: json['original_product_name'] as String?,
      fiscalProductId: json['fiscal_product_id'] as int?,
      fiscalProductName: json['fiscal_product_name'] as String?,
      originalDescription: json['original_description'] as String?,
      fiscalDescription: json['fiscal_description'] as String? ?? '',
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      unitPrice: _toDouble(json['unit_price']),
      discountAmount: _toDouble(json['discount_amount']),
      totalPrice: _toDouble(json['total_price']),
      barcode: json['barcode'] as String?,
      included: json['included'] as bool? ?? true,
      adjustmentReason: json['adjustment_reason'] as String?,
      ncm: json['ncm'] as String?,
      cest: json['cest'] as String?,
      cfop: json['cfop'] as String?,
      origin: json['origin'] as String?,
      cst: json['cst'] as String?,
      csosn: json['csosn'] as String?,
      pisCst: json['pis_cst'] as String?,
      cofinsCst: json['cofins_cst'] as String?,
      cbenef: json['cbenef'] as String?,
      ibsCbsCst: json['ibs_cbs_cst'] as String?,
      ibsCbsClassification: json['ibs_cbs_classification'] as String?,
      selectiveTaxCst: json['selective_tax_cst'] as String?,
      selectiveTaxClassification:
          json['selective_tax_classification'] as String?,
    );
  }

  FiscalDraftItem copyWith({
    int? fiscalProductId,
    String? fiscalProductName,
    String? fiscalDescription,
    String? barcode,
    String? unit,
    double? quantity,
    double? unitPrice,
    double? discountAmount,
    double? totalPrice,
    bool? included,
    String? adjustmentReason,
    String? ncm,
    String? cest,
    String? cfop,
    String? origin,
    String? cst,
    String? csosn,
    String? pisCst,
    String? cofinsCst,
    String? cbenef,
    String? ibsCbsCst,
    String? ibsCbsClassification,
    String? selectiveTaxCst,
    String? selectiveTaxClassification,
  }) {
    return FiscalDraftItem(
      id: id,
      saleItemId: saleItemId,
      originalProductId: originalProductId,
      originalProductName: originalProductName,
      fiscalProductId: fiscalProductId ?? this.fiscalProductId,
      fiscalProductName: fiscalProductName ?? this.fiscalProductName,
      originalDescription: originalDescription,
      fiscalDescription: fiscalDescription ?? this.fiscalDescription,
      quantity: quantity ?? this.quantity,
      unit: unit ?? this.unit,
      unitPrice: unitPrice ?? this.unitPrice,
      discountAmount: discountAmount ?? this.discountAmount,
      totalPrice: totalPrice ?? this.totalPrice,
      barcode: barcode ?? this.barcode,
      included: included ?? this.included,
      adjustmentReason: adjustmentReason ?? this.adjustmentReason,
      ncm: ncm ?? this.ncm,
      cest: cest ?? this.cest,
      cfop: cfop ?? this.cfop,
      origin: origin ?? this.origin,
      cst: cst ?? this.cst,
      csosn: csosn ?? this.csosn,
      pisCst: pisCst ?? this.pisCst,
      cofinsCst: cofinsCst ?? this.cofinsCst,
      cbenef: cbenef ?? this.cbenef,
      ibsCbsCst: ibsCbsCst ?? this.ibsCbsCst,
      ibsCbsClassification: ibsCbsClassification ?? this.ibsCbsClassification,
      selectiveTaxCst: selectiveTaxCst ?? this.selectiveTaxCst,
      selectiveTaxClassification:
          selectiveTaxClassification ?? this.selectiveTaxClassification,
    );
  }

  Map<String, dynamic> toOverrideJson() => {
    'sale_item_id': saleItemId,
    'fiscal_product_id': fiscalProductId,
    'fiscal_description': fiscalDescription,
    'quantity': quantity,
    'unit': unit,
    'unit_price': unitPrice,
    'discount_amount': discountAmount,
    'total_price': totalPrice,
    'included': included,
    'adjustment_reason': adjustmentReason,
    'ncm': ncm,
    'cest': cest,
    'cfop': cfop,
    'origin': origin,
    'cst': cst,
    'csosn': csosn,
    'pis_cst': pisCst,
    'cofins_cst': cofinsCst,
    'cbenef': cbenef,
    'ibs_cbs_cst': ibsCbsCst,
    'ibs_cbs_classification': ibsCbsClassification,
    'selective_tax_cst': selectiveTaxCst,
    'selective_tax_classification': selectiveTaxClassification,
  };
}

class FiscalSaleDraft {
  const FiscalSaleDraft({
    required this.saleId,
    this.saleNumber,
    required this.saleTotal,
    required this.fiscalTotal,
    this.consumerCpf,
    required this.items,
  });

  final int saleId;
  final String? saleNumber;
  final double saleTotal;
  final double fiscalTotal;
  final String? consumerCpf;
  final List<FiscalDraftItem> items;

  factory FiscalSaleDraft.fromJson(Map<String, dynamic> json) {
    return FiscalSaleDraft(
      saleId: json['sale_id'] as int,
      saleNumber: json['sale_number'] as String?,
      saleTotal: _toDouble(json['sale_total']),
      fiscalTotal: _toDouble(json['fiscal_total']),
      consumerCpf: json['consumer_cpf'] as String?,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => FiscalDraftItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FiscalProductLookup {
  const FiscalProductLookup({
    required this.id,
    required this.name,
    this.internalCode,
    this.barcode,
    required this.unit,
    required this.stockQuantity,
    required this.fiscalReceivedQuantity,
    required this.fiscalIssuedQuantity,
    required this.fiscalAvailableQuantity,
    required this.fiscalEntryCount,
    required this.salePrice,
  });

  final int id;
  final String name;
  final String? internalCode;
  final String? barcode;
  final String unit;
  final double stockQuantity;
  final double fiscalReceivedQuantity;
  final double fiscalIssuedQuantity;
  final double fiscalAvailableQuantity;
  final int fiscalEntryCount;
  final double salePrice;

  factory FiscalProductLookup.fromJson(Map<String, dynamic> json) {
    return FiscalProductLookup(
      id: json['id'] as int,
      name: json['name'] as String,
      internalCode: json['internal_code'] as String?,
      barcode: json['barcode'] as String?,
      unit: json['unit'] as String? ?? 'un',
      stockQuantity: _toDouble(json['stock_quantity']),
      fiscalReceivedQuantity: _toDouble(json['fiscal_received_quantity']),
      fiscalIssuedQuantity: _toDouble(json['fiscal_issued_quantity']),
      fiscalAvailableQuantity: _toDouble(json['fiscal_available_quantity']),
      fiscalEntryCount: json['fiscal_entry_count'] as int? ?? 0,
      salePrice: _toDouble(json['sale_price']),
    );
  }
}

double _toDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

double? _toDoubleOrNull(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
