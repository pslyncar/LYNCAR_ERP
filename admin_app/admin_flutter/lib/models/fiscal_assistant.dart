class FiscalAssistantResponse {
  const FiscalAssistantResponse({
    required this.legalNotice,
    required this.suggestions,
    required this.ncmOfficialSuggestions,
    required this.alerts,
  });

  final String legalNotice;
  final List<FiscalSuggestion> suggestions;
  final List<FiscalNcmOfficialSuggestion> ncmOfficialSuggestions;
  final List<FiscalAlert> alerts;

  factory FiscalAssistantResponse.fromJson(Map<String, dynamic> json) {
    return FiscalAssistantResponse(
      legalNotice: json['legal_notice']?.toString() ?? '',
      suggestions: (json['suggestions'] as List<dynamic>? ?? [])
          .map(
            (item) => FiscalSuggestion.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      ncmOfficialSuggestions:
          (json['ncm_official_suggestions'] as List<dynamic>? ?? [])
              .map(
                (item) => FiscalNcmOfficialSuggestion.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList(),
      alerts: (json['alerts'] as List<dynamic>? ?? [])
          .map((item) => FiscalAlert.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class FiscalNcmOfficialSuggestion {
  const FiscalNcmOfficialSuggestion({
    required this.code,
    required this.description,
    required this.source,
  });

  final String code;
  final String description;
  final String source;

  factory FiscalNcmOfficialSuggestion.fromJson(Map<String, dynamic> json) {
    return FiscalNcmOfficialSuggestion(
      code: json['code']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      source: json['source']?.toString() ?? 'siscomex_classif',
    );
  }
}

class FiscalSuggestion {
  const FiscalSuggestion({
    required this.id,
    required this.normalizedDescription,
    required this.source,
    required this.usageCount,
    this.originalDescription,
    this.barcode,
    this.unit,
    this.ncm,
    this.cest,
    this.cfop,
    this.origin,
    this.cst,
    this.csosn,
    this.icmsRate,
    this.pisRate,
    this.cofinsRate,
    this.ipiRate,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
    this.selectiveTaxRate,
  });

  final int id;
  final String normalizedDescription;
  final String? originalDescription;
  final String? barcode;
  final String? unit;
  final String? ncm;
  final String? cest;
  final String? cfop;
  final String? origin;
  final String? cst;
  final String? csosn;
  final double? icmsRate;
  final double? pisRate;
  final double? cofinsRate;
  final double? ipiRate;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;
  final double? selectiveTaxRate;
  final String source;
  final int usageCount;

  factory FiscalSuggestion.fromJson(Map<String, dynamic> json) {
    return FiscalSuggestion(
      id: _toInt(json['id']),
      normalizedDescription: json['normalized_description']?.toString() ?? '',
      originalDescription: json['original_description']?.toString(),
      barcode: json['barcode']?.toString(),
      unit: json['unit']?.toString(),
      ncm: json['ncm']?.toString(),
      cest: json['cest']?.toString(),
      cfop: json['cfop']?.toString(),
      origin: json['origin']?.toString(),
      cst: json['cst']?.toString(),
      csosn: json['csosn']?.toString(),
      icmsRate: _toNullableDouble(json['icms_rate']),
      pisRate: _toNullableDouble(json['pis_rate']),
      cofinsRate: _toNullableDouble(json['cofins_rate']),
      ipiRate: _toNullableDouble(json['ipi_rate']),
      ibsCbsCst: json['ibs_cbs_cst']?.toString(),
      ibsCbsClassification: json['ibs_cbs_classification']?.toString(),
      cbsRate: _toNullableDouble(json['cbs_rate']),
      ibsStateRate: _toNullableDouble(json['ibs_state_rate']),
      ibsCityRate: _toNullableDouble(json['ibs_city_rate']),
      selectiveTaxCst: json['selective_tax_cst']?.toString(),
      selectiveTaxClassification: json['selective_tax_classification']
          ?.toString(),
      selectiveTaxRate: _toNullableDouble(json['selective_tax_rate']),
      source: json['source']?.toString() ?? '',
      usageCount: _toInt(json['usage_count']),
    );
  }
}

class FiscalAlert {
  const FiscalAlert({
    required this.severity,
    this.field,
    required this.message,
  });

  final String severity;
  final String? field;
  final String message;

  factory FiscalAlert.fromJson(Map<String, dynamic> json) {
    return FiscalAlert(
      severity: json['severity']?.toString() ?? 'info',
      field: json['field']?.toString(),
      message: json['message']?.toString() ?? '',
    );
  }
}

int _toInt(dynamic value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

double? _toNullableDouble(dynamic value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
