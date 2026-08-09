class StockMovement {
  const StockMovement({
    required this.id,
    required this.productId,
    required this.movementType,
    required this.quantityDelta,
    required this.quantityBefore,
    required this.quantityAfter,
    required this.unit,
    required this.createdAt,
    this.userId,
    this.sourceType,
    this.sourceId,
    this.sourceNumber,
    this.unitPrice,
    this.totalValue,
    this.reason,
    this.notes,
    this.supplierName,
    this.supplierDocument,
    this.invoiceKey,
    this.invoiceNumber,
    this.invoiceSeries,
    this.batchNumber,
    this.expirationDate,
    this.receivedQuantity,
    this.checkStatus,
    this.checkNotes,
    this.productName,
    this.userName,
  });

  final int id;
  final int productId;
  final int? userId;
  final String movementType;
  final String? sourceType;
  final int? sourceId;
  final String? sourceNumber;
  final double quantityDelta;
  final double quantityBefore;
  final double quantityAfter;
  final String unit;
  final double? unitPrice;
  final double? totalValue;
  final String? reason;
  final String? notes;
  final String? supplierName;
  final String? supplierDocument;
  final String? invoiceKey;
  final String? invoiceNumber;
  final String? invoiceSeries;
  final String? batchNumber;
  final String? expirationDate;
  final double? receivedQuantity;
  final String? checkStatus;
  final String? checkNotes;
  final String? productName;
  final String? userName;
  final DateTime createdAt;

  factory StockMovement.fromJson(Map<String, dynamic> json) {
    return StockMovement(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      userId: json['user_id'] as int?,
      movementType: json['movement_type'] as String,
      sourceType: json['source_type'] as String?,
      sourceId: json['source_id'] as int?,
      sourceNumber: json['source_number'] as String?,
      quantityDelta: _toDouble(json['quantity_delta']),
      quantityBefore: _toDouble(json['quantity_before']),
      quantityAfter: _toDouble(json['quantity_after']),
      unit: json['unit'] as String? ?? 'un',
      unitPrice: _toNullableDouble(json['unit_price']),
      totalValue: _toNullableDouble(json['total_value']),
      reason: json['reason'] as String?,
      notes: json['notes'] as String?,
      supplierName: json['supplier_name'] as String?,
      supplierDocument: json['supplier_document'] as String?,
      invoiceKey: json['invoice_key'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceSeries: json['invoice_series'] as String?,
      batchNumber: json['batch_number'] as String?,
      expirationDate: json['expiration_date'] as String?,
      receivedQuantity: _toNullableDouble(json['received_quantity']),
      checkStatus: json['check_status'] as String?,
      checkNotes: json['check_notes'] as String?,
      productName: json['product_name'] as String?,
      userName: json['user_name'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    );
  }

  static double _toDouble(Object? value) => _toNullableDouble(value) ?? 0;

  static double? _toNullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
