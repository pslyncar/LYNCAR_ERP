class StockEntry {
  const StockEntry({
    required this.id,
    this.supplierId,
    required this.source,
    required this.status,
    this.invoiceKey,
    this.invoiceNumber,
    this.invoiceSeries,
    this.supplierName,
    this.supplierDocument,
    required this.totalAmount,
    this.notes,
    required this.items,
    this.createdAt,
    this.confirmedAt,
  });

  final int id;
  final int? supplierId;
  final String source;
  final String status;
  final String? invoiceKey;
  final String? invoiceNumber;
  final String? invoiceSeries;
  final String? supplierName;
  final String? supplierDocument;
  final double totalAmount;
  final String? notes;
  final List<StockEntryItem> items;
  final DateTime? createdAt;
  final DateTime? confirmedAt;

  factory StockEntry.fromJson(Map<String, dynamic> json) {
    return StockEntry(
      id: json['id'] as int,
      supplierId: json['supplier_id'] as int?,
      source: json['source'] as String? ?? 'manual',
      status: json['status'] as String? ?? 'confirmed',
      invoiceKey: json['invoice_key'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceSeries: json['invoice_series'] as String?,
      supplierName: json['supplier_name'] as String?,
      supplierDocument: json['supplier_document'] as String?,
      totalAmount: _toDouble(json['total_amount']),
      notes: json['notes'] as String?,
      items: (json['items'] as List<dynamic>? ?? [])
          .map((item) => StockEntryItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      confirmedAt: DateTime.tryParse(json['confirmed_at']?.toString() ?? ''),
    );
  }
}

class StockEntryItem {
  const StockEntryItem({
    this.productId,
    required this.description,
    this.barcode,
    this.invoiceQuantity,
    this.invoiceUnit,
    this.packageConversionFactor,
    required this.quantity,
    this.receivedQuantity,
    required this.unit,
    required this.unitCost,
    required this.totalCost,
    this.ncm,
    this.cfop,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
    this.selectiveTaxRate,
    this.batchNumber,
    this.expirationDate,
    this.checkStatus = 'accepted',
    this.checkNotes,
  });

  final int? productId;
  final String description;
  final String? barcode;
  final double? invoiceQuantity;
  final String? invoiceUnit;
  final double? packageConversionFactor;
  final double quantity;
  final double? receivedQuantity;
  final String unit;
  final double unitCost;
  final double totalCost;
  final String? ncm;
  final String? cfop;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;
  final double? selectiveTaxRate;
  final String? batchNumber;
  final String? expirationDate;
  final String checkStatus;
  final String? checkNotes;

  factory StockEntryItem.fromJson(Map<String, dynamic> json) {
    return StockEntryItem(
      productId: json['product_id'] as int?,
      description: json['description'] as String,
      barcode: json['barcode'] as String?,
      invoiceQuantity: _toNullableDouble(json['invoice_quantity']),
      invoiceUnit: json['invoice_unit'] as String?,
      packageConversionFactor: _toNullableDouble(
        json['package_conversion_factor'],
      ),
      quantity: _toDouble(json['quantity']),
      receivedQuantity: _toNullableDouble(json['received_quantity']),
      unit: json['unit'] as String? ?? 'un',
      unitCost: _toDouble(json['unit_cost']),
      totalCost: _toDouble(json['total_cost']),
      ncm: json['ncm'] as String?,
      cfop: json['cfop'] as String?,
      ibsCbsCst: json['ibs_cbs_cst'] as String?,
      ibsCbsClassification: json['ibs_cbs_classification'] as String?,
      cbsRate: _toNullableDouble(json['cbs_rate']),
      ibsStateRate: _toNullableDouble(json['ibs_state_rate']),
      ibsCityRate: _toNullableDouble(json['ibs_city_rate']),
      selectiveTaxCst: json['selective_tax_cst'] as String?,
      selectiveTaxClassification: json['selective_tax_classification'] as String?,
      selectiveTaxRate: _toNullableDouble(json['selective_tax_rate']),
      batchNumber: json['batch_number'] as String?,
      expirationDate: json['expiration_date'] as String?,
      checkStatus: json['check_status'] as String? ?? 'accepted',
      checkNotes: json['check_notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'description': description,
      'barcode': barcode,
      'invoice_quantity': invoiceQuantity,
      'invoice_unit': invoiceUnit,
      'package_conversion_factor': packageConversionFactor,
      'quantity': quantity,
      'received_quantity': receivedQuantity,
      'unit': unit,
      'unit_cost': unitCost,
      'total_cost': totalCost,
      'ncm': ncm,
      'cfop': cfop,
      'ibs_cbs_cst': ibsCbsCst,
      'ibs_cbs_classification': ibsCbsClassification,
      'cbs_rate': cbsRate,
      'ibs_state_rate': ibsStateRate,
      'ibs_city_rate': ibsCityRate,
      'selective_tax_cst': selectiveTaxCst,
      'selective_tax_classification': selectiveTaxClassification,
      'selective_tax_rate': selectiveTaxRate,
      'batch_number': batchNumber,
      'expiration_date': expirationDate,
      'check_status': checkStatus,
      'check_notes': checkNotes,
    };
  }
}

class StockEntryPayload {
  const StockEntryPayload({
    this.supplierId,
    this.supplierName,
    this.supplierDocument,
    required this.source,
    this.invoiceKey,
    this.invoiceNumber,
    this.invoiceSeries,
    this.notes,
    required this.items,
  });

  final int? supplierId;
  final String? supplierName;
  final String? supplierDocument;
  final String source;
  final String? invoiceKey;
  final String? invoiceNumber;
  final String? invoiceSeries;
  final String? notes;
  final List<StockEntryItem> items;

  Map<String, dynamic> toJson() {
    return {
      'supplier_id': supplierId,
      'supplier_name': supplierName,
      'supplier_document': supplierDocument,
      'source': source,
      'invoice_key': invoiceKey,
      'invoice_number': invoiceNumber,
      'invoice_series': invoiceSeries,
      'notes': notes,
      'items': items.map((item) => item.toJson()).toList(),
    };
  }
}

class StockEntryMobileItemPayload {
  const StockEntryMobileItemPayload({
    this.productId,
    required this.description,
    this.barcode,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    this.salePrice,
    this.ncm,
    this.cfop,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
    this.selectiveTaxRate,
    this.batchNumber,
    this.expirationDate,
    this.checkNotes,
  });

  final int? productId;
  final String description;
  final String? barcode;
  final double quantity;
  final String unit;
  final double unitCost;
  final double? salePrice;
  final String? ncm;
  final String? cfop;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;
  final double? selectiveTaxRate;
  final String? batchNumber;
  final String? expirationDate;
  final String? checkNotes;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'description': description,
      'barcode': barcode,
      'quantity': quantity,
      'unit': unit,
      'unit_cost': unitCost,
      'sale_price': salePrice,
      'ncm': ncm,
      'cfop': cfop,
      'ibs_cbs_cst': ibsCbsCst,
      'ibs_cbs_classification': ibsCbsClassification,
      'cbs_rate': cbsRate,
      'ibs_state_rate': ibsStateRate,
      'ibs_city_rate': ibsCityRate,
      'selective_tax_cst': selectiveTaxCst,
      'selective_tax_classification': selectiveTaxClassification,
      'selective_tax_rate': selectiveTaxRate,
      'batch_number': batchNumber,
      'expiration_date': expirationDate,
      'check_notes': checkNotes,
    };
  }
}

class NfeXmlPreview {
  const NfeXmlPreview({
    this.supplierId,
    this.supplierName,
    this.supplierDocument,
    this.invoiceKey,
    this.invoiceNumber,
    this.invoiceSeries,
    required this.items,
  });

  final int? supplierId;
  final String? supplierName;
  final String? supplierDocument;
  final String? invoiceKey;
  final String? invoiceNumber;
  final String? invoiceSeries;
  final List<NfeXmlPreviewItem> items;

  factory NfeXmlPreview.fromJson(Map<String, dynamic> json) {
    return NfeXmlPreview(
      supplierId: json['supplier_id'] as int?,
      supplierName: json['supplier_name'] as String?,
      supplierDocument: json['supplier_document'] as String?,
      invoiceKey: json['invoice_key'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      invoiceSeries: json['invoice_series'] as String?,
      items: (json['items'] as List<dynamic>? ?? [])
          .map(
            (item) => NfeXmlPreviewItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class NfeXmlPreviewItem {
  const NfeXmlPreviewItem({
    this.productId,
    this.productName,
    required this.description,
    this.barcode,
    required this.quantity,
    required this.unit,
    required this.unitCost,
    required this.totalCost,
    this.ncm,
    this.cfop,
    this.ibsCbsCst,
    this.ibsCbsClassification,
    this.cbsRate,
    this.ibsStateRate,
    this.ibsCityRate,
    this.selectiveTaxCst,
    this.selectiveTaxClassification,
    this.selectiveTaxRate,
    this.batchNumber,
    this.expirationDate,
  });

  final int? productId;
  final String? productName;
  final String description;
  final String? barcode;
  final double quantity;
  final String unit;
  final double unitCost;
  final double totalCost;
  final String? ncm;
  final String? cfop;
  final String? ibsCbsCst;
  final String? ibsCbsClassification;
  final double? cbsRate;
  final double? ibsStateRate;
  final double? ibsCityRate;
  final String? selectiveTaxCst;
  final String? selectiveTaxClassification;
  final double? selectiveTaxRate;
  final String? batchNumber;
  final String? expirationDate;

  factory NfeXmlPreviewItem.fromJson(Map<String, dynamic> json) {
    return NfeXmlPreviewItem(
      productId: json['product_id'] as int?,
      productName: json['product_name'] as String?,
      description: json['description'] as String,
      barcode: json['barcode'] as String?,
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      unitCost: _toDouble(json['unit_cost']),
      totalCost: _toDouble(json['total_cost']),
      ncm: json['ncm'] as String?,
      cfop: json['cfop'] as String?,
      ibsCbsCst: json['ibs_cbs_cst'] as String?,
      ibsCbsClassification: json['ibs_cbs_classification'] as String?,
      cbsRate: _toNullableDouble(json['cbs_rate']),
      ibsStateRate: _toNullableDouble(json['ibs_state_rate']),
      ibsCityRate: _toNullableDouble(json['ibs_city_rate']),
      selectiveTaxCst: json['selective_tax_cst'] as String?,
      selectiveTaxClassification: json['selective_tax_classification'] as String?,
      selectiveTaxRate: _toNullableDouble(json['selective_tax_rate']),
      batchNumber: json['batch_number'] as String?,
      expirationDate: json['expiration_date'] as String?,
    );
  }
}

double _toDouble(Object? value) {
  return _toNullableDouble(value) ?? 0;
}

double? _toNullableDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

class XmlInboxSettings {
  const XmlInboxSettings({required this.emailAddress, required this.enabled});

  final String emailAddress;
  final bool enabled;

  factory XmlInboxSettings.fromJson(Map<String, dynamic> json) {
    return XmlInboxSettings(
      emailAddress: json['email_address']?.toString() ?? '',
      enabled: json['enabled'] as bool? ?? false,
    );
  }
}

class XmlInboxMessage {
  const XmlInboxMessage({
    required this.id,
    this.stockEntryId,
    required this.status,
    this.senderEmail,
    this.subject,
    this.attachmentName,
    this.supplierName,
    this.supplierDocument,
    this.recipientDocument,
    this.invoiceKey,
    this.invoiceNumber,
    this.rejectionReason,
    this.receivedAt,
  });

  final int id;
  final int? stockEntryId;
  final String status;
  final String? senderEmail;
  final String? subject;
  final String? attachmentName;
  final String? supplierName;
  final String? supplierDocument;
  final String? recipientDocument;
  final String? invoiceKey;
  final String? invoiceNumber;
  final String? rejectionReason;
  final DateTime? receivedAt;

  bool get imported => status == 'imported';
  bool get pendingReceipt => status == 'pending_receipt';

  factory XmlInboxMessage.fromJson(Map<String, dynamic> json) {
    return XmlInboxMessage(
      id: json['id'] as int,
      stockEntryId: json['stock_entry_id'] as int?,
      status: json['status']?.toString() ?? 'unknown',
      senderEmail: json['sender_email'] as String?,
      subject: json['subject'] as String?,
      attachmentName: json['attachment_name'] as String?,
      supplierName: json['supplier_name'] as String?,
      supplierDocument: json['supplier_document'] as String?,
      recipientDocument: json['recipient_document'] as String?,
      invoiceKey: json['invoice_key'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      rejectionReason: json['rejection_reason'] as String?,
      receivedAt: DateTime.tryParse(json['received_at']?.toString() ?? ''),
    );
  }
}
