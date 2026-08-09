class ProductBatch {
  const ProductBatch({
    required this.id,
    required this.productId,
    required this.quantity,
    required this.unit,
    required this.active,
    required this.createdAt,
    required this.updatedAt,
    this.batchNumber,
    this.expirationDate,
    this.sourceType,
    this.sourceId,
    this.sourceNumber,
    this.supplierName,
    this.invoiceNumber,
    this.invoiceSeries,
    this.notes,
  });

  final int id;
  final int productId;
  final String? batchNumber;
  final String? expirationDate;
  final double quantity;
  final String unit;
  final String? sourceType;
  final int? sourceId;
  final String? sourceNumber;
  final String? supplierName;
  final String? invoiceNumber;
  final String? invoiceSeries;
  final String? notes;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory ProductBatch.fromJson(Map<String, dynamic> json) {
    return ProductBatch(
      id: json['id'] as int,
      productId: json['product_id'] as int,
      batchNumber: json['batch_number'] as String?,
      expirationDate: json['expiration_date'] as String?,
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      sourceType: json['source_type'] as String?,
      sourceId: json['source_id'] as int?,
      sourceNumber: json['source_number'] as String?,
      supplierName: json['supplier_name'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceSeries: json['invoice_series'] as String?,
      notes: json['notes'] as String?,
      active: json['active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  static double _toDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}
