class Sale {
  const Sale({
    required this.id,
    required this.source,
    required this.status,
    required this.subtotalAmount,
    required this.discountAmount,
    required this.totalAmount,
    required this.amountPaid,
    required this.changeAmount,
    required this.soldAt,
    required this.items,
    required this.payments,
    this.hasFiscalDocument = false,
    this.hasAuthorizedFiscalDocument = false,
    this.number,
    this.clientId,
    this.sellerUserId,
    this.sellerName,
    this.cashRegisterNumber,
    this.consumerCpf,
    this.offlineClientId,
    this.notes,
    this.canceledAt,
  });

  final int id;
  final String? number;
  final int? clientId;
  final int? sellerUserId;
  final String? sellerName;
  final String? cashRegisterNumber;
  final String? consumerCpf;
  final String? offlineClientId;
  final String source;
  final String status;
  final double subtotalAmount;
  final double discountAmount;
  final double totalAmount;
  final double amountPaid;
  final double changeAmount;
  final String? notes;
  final DateTime soldAt;
  final DateTime? canceledAt;
  final bool hasFiscalDocument;
  final bool hasAuthorizedFiscalDocument;
  final List<SaleItem> items;
  final List<SalePayment> payments;

  factory Sale.fromJson(Map<String, dynamic> json) {
    return Sale(
      id: json['id'] as int,
      number: json['number'] as String?,
      clientId: json['client_id'] as int?,
      sellerUserId: json['seller_user_id'] as int?,
      sellerName: json['seller_name'] as String?,
      cashRegisterNumber: json['cash_register_number'] as String?,
      consumerCpf: json['consumer_cpf'] as String?,
      offlineClientId: json['offline_client_id'] as String?,
      source: json['source'] as String? ?? 'pdv',
      status: json['status'] as String? ?? 'finalizada',
      subtotalAmount: _toDouble(json['subtotal_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      totalAmount: _toDouble(json['total_amount']),
      amountPaid: _toDouble(json['amount_paid']),
      changeAmount: _toDouble(json['change_amount']),
      notes: json['notes'] as String?,
      soldAt: DateTime.parse(json['sold_at'] as String),
      canceledAt: json['canceled_at'] == null
          ? null
          : DateTime.parse(json['canceled_at'] as String),
      hasFiscalDocument: json['has_fiscal_document'] as bool? ?? false,
      hasAuthorizedFiscalDocument:
          json['has_authorized_fiscal_document'] as bool? ?? false,
      items: ((json['items'] as List<dynamic>?) ?? [])
          .map((item) => SaleItem.fromJson(item as Map<String, dynamic>))
          .toList(),
      payments: ((json['payments'] as List<dynamic>?) ?? [])
          .map((item) => SalePayment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class SaleItem {
  const SaleItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.discountAmount,
    required this.totalPrice,
    this.productId,
    this.barcode,
  });

  final int id;
  final int? productId;
  final String? barcode;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double discountAmount;
  final double totalPrice;

  factory SaleItem.fromJson(Map<String, dynamic> json) {
    return SaleItem(
      id: json['id'] as int,
      productId: json['product_id'] as int?,
      barcode: json['barcode'] as String?,
      description: json['description'] as String,
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      unitPrice: _toDouble(json['unit_price']),
      discountAmount: _toDouble(json['discount_amount']),
      totalPrice: _toDouble(json['total_price']),
    );
  }
}

class SalePayment {
  const SalePayment({
    required this.id,
    required this.method,
    required this.amount,
    this.authorizationCode,
    this.notes,
  });

  final int id;
  final String method;
  final double amount;
  final String? authorizationCode;
  final String? notes;

  factory SalePayment.fromJson(Map<String, dynamic> json) {
    return SalePayment(
      id: json['id'] as int,
      method: json['method'] as String,
      amount: _toDouble(json['amount']),
      authorizationCode: json['authorization_code'] as String?,
      notes: json['notes'] as String?,
    );
  }
}

class SalePayload {
  const SalePayload({
    required this.clientId,
    this.sellerUserId,
    required this.source,
    this.cashRegisterNumber,
    required this.status,
    required this.discountAmount,
    this.consumerCpf,
    this.offlineClientId,
    required this.notes,
    required this.items,
    required this.payments,
  });

  final int? clientId;
  final int? sellerUserId;
  final String source;
  final String? cashRegisterNumber;
  final String status;
  final double discountAmount;
  final String? consumerCpf;
  final String? offlineClientId;
  final String notes;
  final List<SaleItemPayload> items;
  final List<SalePaymentPayload> payments;

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'seller_user_id': sellerUserId,
      'source': source,
      'cash_register_number': cashRegisterNumber,
      'status': status,
      'discount_amount': _moneyJson(discountAmount),
      'consumer_cpf': consumerCpf == null || consumerCpf!.trim().isEmpty
          ? null
          : consumerCpf!.trim(),
      'offline_client_id':
          offlineClientId == null || offlineClientId!.trim().isEmpty
          ? null
          : offlineClientId!.trim(),
      'notes': notes.trim().isEmpty ? null : notes.trim(),
      'items': items.map((item) => item.toJson()).toList(),
      'payments': payments.map((payment) => payment.toJson()).toList(),
    };
  }
}

class SaleSeller {
  const SaleSeller({
    required this.id,
    required this.name,
    required this.role,
    this.sellerCode,
  });

  final int id;
  final String name;
  final String role;
  final String? sellerCode;

  factory SaleSeller.fromJson(Map<String, dynamic> json) {
    return SaleSeller(
      id: json['id'] as int,
      name: json['name'] as String,
      role: json['role'] as String? ?? 'seller',
      sellerCode: json['seller_code'] as String?,
    );
  }
}

class SaleItemPayload {
  const SaleItemPayload({
    required this.productId,
    required this.barcode,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.discountAmount,
  });

  final int? productId;
  final String? barcode;
  final String description;
  final double quantity;
  final double unitPrice;
  final double discountAmount;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'barcode': barcode,
      'description': description,
      'quantity': quantity,
      'unit_price': _unitPriceJson(unitPrice),
      'discount_amount': _moneyJson(discountAmount),
    };
  }
}

class SalePaymentPayload {
  const SalePaymentPayload({
    required this.method,
    required this.amount,
    this.authorizationCode,
    this.notes,
  });

  final String method;
  final double amount;
  final String? authorizationCode;
  final String? notes;

  Map<String, dynamic> toJson() {
    return {
      'method': method,
      'amount': _moneyJson(amount),
      'authorization_code': authorizationCode,
      'notes': notes,
    };
  }
}

String _moneyJson(double value) => value.toStringAsFixed(2);
String _unitPriceJson(double value) => value.toStringAsFixed(4);

double _toDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
