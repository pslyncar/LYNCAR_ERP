class Product {
  const Product({
    required this.id,
    required this.name,
    required this.productType,
    required this.salePrice,
    this.offerPrice,
    this.offerStartAt,
    this.offerEndAt,
    required this.stockQuantity,
    this.fiscalReceivedQuantity = 0,
    this.fiscalIssuedQuantity = 0,
    this.fiscalAvailableQuantity = 0,
    this.fiscalEntryCount = 0,
    required this.minimumStock,
    required this.active,
    this.internalCode,
    this.barcode,
    this.imageUrl,
    this.description,
    this.brand,
    this.model,
    this.category,
    this.stockLocation,
    this.tracksBatch = false,
    this.initialBatchNumber,
    this.initialExpirationDate,
    this.purchaseTotalCost,
    this.purchaseQuantity,
    this.averageCost,
    this.purchaseConversionEnabled = false,
    this.purchaseInvoiceUnit,
    this.purchasePackageFactor,
    this.purchasePackageBarcode,
    this.stockValue = 0,
    this.marginPercent,
    this.unit = 'un',
    this.ncm,
    this.cest,
    this.cfopSale,
    this.origin,
    this.cst,
    this.csosn,
    this.icmsRate,
    this.pisRate,
    this.cofinsRate,
    this.ipiRate,
    this.issRate,
    this.municipalServiceCode,
    this.taxRate,
    this.fiscalNotes,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
    this.selectiveTaxRate,
    this.newTaxSystem = false,
    this.oldTaxSystemNotes,
    this.newTaxSystemNotes,
    this.nearestBatchNumber,
    this.nearestExpirationDate,
    this.lastReceiptSupplierName,
    this.lastReceiptInvoiceNumber,
  });

  final int id;
  final String name;
  final String productType;
  final String? internalCode;
  final String? barcode;
  final String? imageUrl;
  final String? description;
  final String? brand;
  final String? model;
  final String? category;
  final String? stockLocation;
  final bool tracksBatch;
  final String? initialBatchNumber;
  final String? initialExpirationDate;
  final double salePrice;
  final double? offerPrice;
  final DateTime? offerStartAt;
  final DateTime? offerEndAt;
  final double? purchaseTotalCost;
  final double? purchaseQuantity;
  final double? averageCost;
  final bool purchaseConversionEnabled;
  final String? purchaseInvoiceUnit;
  final double? purchasePackageFactor;
  final String? purchasePackageBarcode;
  final double stockValue;
  final double? marginPercent;
  final double stockQuantity;
  final double fiscalReceivedQuantity;
  final double fiscalIssuedQuantity;
  final double fiscalAvailableQuantity;
  final int fiscalEntryCount;
  final double minimumStock;
  final String unit;
  final String? ncm;
  final String? cest;
  final String? cfopSale;
  final String? origin;
  final String? cst;
  final String? csosn;
  final double? icmsRate;
  final double? pisRate;
  final double? cofinsRate;
  final double? ipiRate;
  final double? issRate;
  final String? municipalServiceCode;
  final double? taxRate;
  final String? fiscalNotes;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;
  final double? selectiveTaxRate;
  final bool newTaxSystem;
  final String? oldTaxSystemNotes;
  final String? newTaxSystemNotes;
  final String? nearestBatchNumber;
  final String? nearestExpirationDate;
  final String? lastReceiptSupplierName;
  final String? lastReceiptInvoiceNumber;
  final bool active;

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'] as int,
      name: json['name'] as String,
      productType: json['product_type'] as String? ?? 'servico',
      internalCode: json['internal_code'] as String?,
      barcode: json['barcode'] as String?,
      imageUrl: json['image_url'] as String?,
      description: json['description'] as String?,
      brand: json['brand'] as String?,
      model: json['model'] as String?,
      category: json['category'] as String?,
      stockLocation: json['stock_location'] as String?,
      tracksBatch: json['tracks_batch'] as bool? ?? false,
      initialBatchNumber: json['initial_batch_number'] as String?,
      initialExpirationDate: json['initial_expiration_date'] as String?,
      salePrice: _toDouble(json['sale_price']),
      offerPrice: _toNullableDouble(json['offer_price']),
      offerStartAt: _toDateTime(json['offer_start_at']),
      offerEndAt: _toDateTime(json['offer_end_at']),
      purchaseTotalCost: _toNullableDouble(json['purchase_total_cost']),
      purchaseQuantity: _toNullableDouble(json['purchase_quantity']),
      purchaseConversionEnabled:
          json['purchase_conversion_enabled'] as bool? ?? false,
      purchaseInvoiceUnit: json['purchase_invoice_unit'] as String?,
      purchasePackageFactor: _toNullableDouble(json['purchase_package_factor']),
      purchasePackageBarcode: json['purchase_package_barcode'] as String?,
      averageCost: _toNullableDouble(json['average_cost']),
      stockValue: _toDouble(json['stock_value']),
      marginPercent: _toNullableDouble(json['margin_percent']),
      stockQuantity: _toDouble(json['stock_quantity']),
      fiscalReceivedQuantity: _toDouble(json['fiscal_received_quantity']),
      fiscalIssuedQuantity: _toDouble(json['fiscal_issued_quantity']),
      fiscalAvailableQuantity: _toDouble(json['fiscal_available_quantity']),
      fiscalEntryCount: json['fiscal_entry_count'] as int? ?? 0,
      minimumStock: _toDouble(json['minimum_stock']),
      unit: json['unit'] as String? ?? 'un',
      ncm: json['ncm'] as String?,
      cest: json['cest'] as String?,
      cfopSale: json['cfop_sale'] as String?,
      origin: json['origin'] as String?,
      cst: json['cst'] as String?,
      csosn: json['csosn'] as String?,
      icmsRate: _toNullableDouble(json['icms_rate']),
      pisRate: _toNullableDouble(json['pis_rate']),
      cofinsRate: _toNullableDouble(json['cofins_rate']),
      ipiRate: _toNullableDouble(json['ipi_rate']),
      issRate: _toNullableDouble(json['iss_rate']),
      municipalServiceCode: json['municipal_service_code'] as String?,
      taxRate: _toNullableDouble(json['tax_rate']),
      fiscalNotes: json['fiscal_notes'] as String?,
      ibsCbsCst: json['ibs_cbs_cst'] as String?,
      ibsCbsClassification: json['ibs_cbs_classification'] as String?,
      cbsRate: _toNullableDouble(json['cbs_rate']),
      ibsStateRate: _toNullableDouble(json['ibs_state_rate']),
      ibsCityRate: _toNullableDouble(json['ibs_city_rate']),
      selectiveTaxCst: json['selective_tax_cst'] as String?,
      selectiveTaxClassification:
          json['selective_tax_classification'] as String?,
      selectiveTaxRate: _toNullableDouble(json['selective_tax_rate']),
      newTaxSystem: json['new_tax_system'] as bool? ?? false,
      oldTaxSystemNotes: json['old_tax_system_notes'] as String?,
      newTaxSystemNotes: json['new_tax_system_notes'] as String?,
      nearestBatchNumber: json['nearest_batch_number'] as String?,
      nearestExpirationDate: json['nearest_expiration_date'] as String?,
      lastReceiptSupplierName: json['last_receipt_supplier_name'] as String?,
      lastReceiptInvoiceNumber: json['last_receipt_invoice_number'] as String?,
      active: json['active'] as bool? ?? true,
    );
  }

  static double _toDouble(Object? value) => _toNullableDouble(value) ?? 0;

  static double? _toNullableDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  static DateTime? _toDateTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }

  bool get hasActiveOffer {
    if (offerPrice == null || offerStartAt == null || offerEndAt == null) {
      return false;
    }
    final now = DateTime.now();
    return !now.isBefore(offerStartAt!) && !now.isAfter(offerEndAt!);
  }

  double get effectiveSalePrice => hasActiveOffer ? offerPrice! : salePrice;
}

class ProductPayload {
  ProductPayload({
    required this.name,
    required this.productType,
    required this.salePrice,
    this.offerPrice,
    this.offerStartAt,
    this.offerEndAt,
    required this.stockQuantity,
    required this.minimumStock,
    required this.unit,
    required this.active,
    this.internalCode,
    this.barcode,
    this.imageUrl,
    this.description,
    this.brand,
    this.model,
    this.category,
    this.stockLocation,
    this.tracksBatch = false,
    this.initialBatchNumber,
    this.initialExpirationDate,
    this.purchaseTotalCost,
    this.purchaseQuantity,
    this.averageCost,
    this.purchaseConversionEnabled = false,
    this.purchaseInvoiceUnit,
    this.purchasePackageFactor,
    this.purchasePackageBarcode,
    this.marginPercent,
    this.ncm,
    this.cest,
    this.cfopSale,
    this.origin,
    this.cst,
    this.csosn,
    this.icmsRate,
    this.pisRate,
    this.cofinsRate,
    this.ipiRate,
    this.issRate,
    this.municipalServiceCode,
    this.taxRate,
    this.fiscalNotes,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
    this.selectiveTaxRate,
    this.newTaxSystem = false,
    this.oldTaxSystemNotes,
    this.newTaxSystemNotes,
  });

  final String name;
  final String productType;
  final String? internalCode;
  final String? barcode;
  final String? imageUrl;
  final String? description;
  final String? brand;
  final String? model;
  final String? category;
  final String? stockLocation;
  final bool tracksBatch;
  final String? initialBatchNumber;
  final String? initialExpirationDate;
  final double salePrice;
  final double? offerPrice;
  final DateTime? offerStartAt;
  final DateTime? offerEndAt;
  final double? purchaseTotalCost;
  final double? purchaseQuantity;
  final double? averageCost;
  final bool purchaseConversionEnabled;
  final String? purchaseInvoiceUnit;
  final double? purchasePackageFactor;
  final String? purchasePackageBarcode;
  final double? marginPercent;
  final double stockQuantity;
  final double minimumStock;
  final String unit;
  final String? ncm;
  final String? cest;
  final String? cfopSale;
  final String? origin;
  final String? cst;
  final String? csosn;
  final double? icmsRate;
  final double? pisRate;
  final double? cofinsRate;
  final double? ipiRate;
  final double? issRate;
  final String? municipalServiceCode;
  final double? taxRate;
  final String? fiscalNotes;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;
  final double? selectiveTaxRate;
  final bool newTaxSystem;
  final String? oldTaxSystemNotes;
  final String? newTaxSystemNotes;
  final bool active;

  Map<String, dynamic> toJson() {
    return {
      'name': name.trim(),
      'product_type': productType,
      'internal_code': _emptyToNull(internalCode),
      'barcode': _emptyToNull(barcode),
      'image_url': _emptyToNull(imageUrl),
      'description': _emptyToNull(description),
      'brand': _emptyToNull(brand),
      'model': _emptyToNull(model),
      'category': _emptyToNull(category),
      'stock_location': _emptyToNull(stockLocation),
      'tracks_batch': tracksBatch,
      'initial_batch_number': _emptyToNull(initialBatchNumber),
      'initial_expiration_date': _emptyToNull(initialExpirationDate),
      'sale_price': _priceJson(salePrice),
      'offer_price': offerPrice == null ? null : _priceJson(offerPrice!),
      'offer_start_at': offerStartAt?.toIso8601String(),
      'offer_end_at': offerEndAt?.toIso8601String(),
      'purchase_total_cost': purchaseTotalCost,
      'purchase_quantity': purchaseQuantity,
      'average_cost': averageCost,
      'purchase_conversion_enabled': purchaseConversionEnabled,
      'purchase_invoice_unit': _emptyToNull(purchaseInvoiceUnit),
      'purchase_package_factor': purchasePackageFactor,
      'purchase_package_barcode': _emptyToNull(purchasePackageBarcode),
      'margin_percent': marginPercent,
      'stock_quantity': stockQuantity,
      'minimum_stock': minimumStock,
      'unit': unit.trim().isEmpty ? 'un' : unit.trim(),
      'ncm': _emptyToNull(ncm),
      'cest': _emptyToNull(cest),
      'cfop_sale': _emptyToNull(cfopSale),
      'origin': _emptyToNull(origin),
      'cst': _emptyToNull(cst),
      'csosn': _emptyToNull(csosn),
      'icms_rate': icmsRate,
      'pis_rate': pisRate,
      'cofins_rate': cofinsRate,
      'ipi_rate': ipiRate,
      'iss_rate': issRate,
      'municipal_service_code': _emptyToNull(municipalServiceCode),
      'tax_rate': taxRate,
      'fiscal_notes': _emptyToNull(fiscalNotes),
      'ibs_cbs_cst': _emptyToNull(ibsCbsCst),
      'ibs_cbs_classification': _emptyToNull(ibsCbsClassification),
      'cbs_rate': cbsRate,
      'ibs_state_rate': ibsStateRate,
      'ibs_city_rate': ibsCityRate,
      'selective_tax_cst': _emptyToNull(selectiveTaxCst),
      'selective_tax_classification': _emptyToNull(selectiveTaxClassification),
      'selective_tax_rate': selectiveTaxRate,
      'new_tax_system': newTaxSystem,
      'old_tax_system_notes': _emptyToNull(oldTaxSystemNotes),
      'new_tax_system_notes': _emptyToNull(newTaxSystemNotes),
      'active': active,
    };
  }
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}

String _priceJson(double value) => value.toStringAsFixed(4);
