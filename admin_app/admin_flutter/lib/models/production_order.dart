class ProductionOrder {
  const ProductionOrder({
    required this.id,
    required this.productId,
    required this.productName,
    required this.status,
    required this.quantity,
    required this.producedQuantity,
    required this.unit,
    required this.producedAt,
    this.number,
    this.userId,
    this.completedByUserId,
    this.canceledByUserId,
    this.unitCost,
    this.totalCost,
    this.estimatedUnitCost,
    this.estimatedTotalCost,
    this.dueDate,
    this.notes,
    this.cancellationReason,
    this.startedAt,
    this.completedAt,
    this.canceledAt,
    this.components = const [],
  });

  final int id;
  final String? number;
  final int productId;
  final String productName;
  final int? userId;
  final int? completedByUserId;
  final int? canceledByUserId;
  final String status;
  final double quantity;
  final double producedQuantity;
  final String unit;
  final double? unitCost;
  final double? totalCost;
  final double? estimatedUnitCost;
  final double? estimatedTotalCost;
  final String? dueDate;
  final String? notes;
  final String? cancellationReason;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final DateTime? canceledAt;
  final DateTime producedAt;
  final List<ProductionOrderComponent> components;

  factory ProductionOrder.fromJson(Map<String, dynamic> json) {
    return ProductionOrder(
      id: json['id'] as int,
      number: json['number'] as String?,
      productId: json['product_id'] as int,
      productName: json['product_name'] as String,
      userId: json['user_id'] as int?,
      completedByUserId: json['completed_by_user_id'] as int?,
      canceledByUserId: json['canceled_by_user_id'] as int?,
      status: json['status'] as String? ?? 'concluida',
      quantity: _toDouble(json['quantity']),
      producedQuantity: _toDouble(json['produced_quantity']),
      unit: json['unit'] as String? ?? 'un',
      unitCost: _toNullableDouble(json['unit_cost']),
      totalCost: _toNullableDouble(json['total_cost']),
      estimatedUnitCost: _toNullableDouble(json['estimated_unit_cost']),
      estimatedTotalCost: _toNullableDouble(json['estimated_total_cost']),
      dueDate: json['due_date'] as String?,
      notes: json['notes'] as String?,
      cancellationReason: json['cancellation_reason'] as String?,
      startedAt: _toDateTime(json['started_at']),
      completedAt: _toDateTime(json['completed_at']),
      canceledAt: _toDateTime(json['canceled_at']),
      producedAt: DateTime.parse(json['produced_at'] as String).toLocal(),
      components: (json['components'] as List<dynamic>? ?? [])
          .map(
            (item) =>
                ProductionOrderComponent.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class ProductionOrderComponent {
  const ProductionOrderComponent({
    required this.id,
    required this.componentProductId,
    required this.componentName,
    required this.quantity,
    required this.unit,
    required this.wastePercent,
    this.unitCost,
    this.totalCost,
  });

  final int id;
  final int componentProductId;
  final String componentName;
  final double quantity;
  final String unit;
  final double wastePercent;
  final double? unitCost;
  final double? totalCost;

  factory ProductionOrderComponent.fromJson(Map<String, dynamic> json) {
    return ProductionOrderComponent(
      id: json['id'] as int,
      componentProductId: json['component_product_id'] as int,
      componentName: json['component_name'] as String,
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      wastePercent: _toDouble(json['waste_percent']),
      unitCost: _toNullableDouble(json['unit_cost']),
      totalCost: _toNullableDouble(json['total_cost']),
    );
  }
}

class ProductionOrderPayload {
  const ProductionOrderPayload({
    required this.productId,
    required this.quantity,
    this.dueDate,
    this.notes,
  });

  final int productId;
  final double quantity;
  final String? dueDate;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'quantity': quantity,
      'due_date': _emptyToNull(dueDate),
      'notes': _emptyToNull(notes),
    };
  }
}

class ProductionOrderPreview {
  const ProductionOrderPreview({
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.components,
    this.estimatedUnitCost,
    this.estimatedTotalCost,
  });

  final int productId;
  final double quantity;
  final String unit;
  final double? estimatedUnitCost;
  final double? estimatedTotalCost;
  final List<ProductionOrderComponentPreview> components;

  factory ProductionOrderPreview.fromJson(Map<String, dynamic> json) {
    return ProductionOrderPreview(
      productId: json['product_id'] as int,
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      estimatedUnitCost: _toNullableDouble(json['estimated_unit_cost']),
      estimatedTotalCost: _toNullableDouble(json['estimated_total_cost']),
      components: (json['components'] as List<dynamic>? ?? [])
          .map(
            (item) => ProductionOrderComponentPreview.fromJson(
              item as Map<String, dynamic>,
            ),
          )
          .toList(),
    );
  }
}

class ProductionOrderComponentPreview {
  const ProductionOrderComponentPreview({
    required this.componentProductId,
    required this.componentName,
    required this.requestedQuantity,
    required this.requestedUnit,
    required this.requiredQuantity,
    required this.stockQuantity,
    required this.unit,
    required this.wastePercent,
    required this.enoughStock,
    this.unitCost,
    this.totalCost,
  });

  final int componentProductId;
  final String componentName;
  final double requestedQuantity;
  final String requestedUnit;
  final double requiredQuantity;
  final double stockQuantity;
  final String unit;
  final double wastePercent;
  final double? unitCost;
  final double? totalCost;
  final bool enoughStock;

  factory ProductionOrderComponentPreview.fromJson(Map<String, dynamic> json) {
    return ProductionOrderComponentPreview(
      componentProductId: json['component_product_id'] as int,
      componentName: json['component_name'] as String,
      requestedQuantity: _toDouble(json['requested_quantity']),
      requestedUnit: json['requested_unit'] as String? ?? 'un',
      requiredQuantity: _toDouble(json['required_quantity']),
      stockQuantity: _toDouble(json['stock_quantity']),
      unit: json['unit'] as String? ?? 'un',
      wastePercent: _toDouble(json['waste_percent']),
      unitCost: _toNullableDouble(json['unit_cost']),
      totalCost: _toNullableDouble(json['total_cost']),
      enoughStock: json['enough_stock'] as bool? ?? false,
    );
  }
}

class ProductionOrderCompletePayload {
  const ProductionOrderCompletePayload({this.producedQuantity, this.notes});

  final double? producedQuantity;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'produced_quantity': producedQuantity,
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

DateTime? _toDateTime(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString())?.toLocal();
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
