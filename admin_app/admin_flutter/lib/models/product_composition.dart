class ProductCompositionItem {
  const ProductCompositionItem({
    required this.id,
    required this.productId,
    required this.componentProductId,
    required this.componentName,
    required this.componentUnit,
    required this.quantity,
    required this.unit,
    required this.wastePercent,
    required this.createdAt,
    this.componentInternalCode,
    this.componentCostPrice,
    this.notes,
  });

  final int id;
  final int productId;
  final int componentProductId;
  final String componentName;
  final String? componentInternalCode;
  final String componentUnit;
  final double? componentCostPrice;
  final double quantity;
  final String unit;
  final double wastePercent;
  final String? notes;
  final DateTime createdAt;

  factory ProductCompositionItem.fromJson(Map<String, dynamic> json) {
    return ProductCompositionItem(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      componentProductId: json['component_product_id'] as int,
      componentName: json['component_name'] as String,
      componentInternalCode: json['component_internal_code'] as String?,
      componentUnit: json['component_unit'] as String? ?? 'un',
      componentCostPrice: _toNullableDouble(json['component_unit_cost']),
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      wastePercent: _toDouble(json['waste_percent']),
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ProductCompositionPayload {
  const ProductCompositionPayload({
    required this.componentProductId,
    required this.quantity,
    required this.unit,
    required this.wastePercent,
    this.notes,
  });

  final int componentProductId;
  final double quantity;
  final String unit;
  final double wastePercent;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'component_product_id': componentProductId,
      'quantity': quantity,
      'unit': unit,
      'waste_percent': wastePercent,
      'notes': _emptyToNull(notes),
    };
  }
}

double _toDouble(Object? value) => _toNullableDouble(value) ?? 0;

double? _toNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
