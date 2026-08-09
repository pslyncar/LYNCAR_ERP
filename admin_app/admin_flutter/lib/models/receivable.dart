class Receivable {
  const Receivable({
    required this.id,
    required this.description,
    required this.originalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    required this.createdAt,
    required this.saleItems,
    required this.payments,
    this.number,
    this.saleId,
    this.clientId,
    this.clientName,
    this.saleNumber,
    this.saleSoldAt,
    this.dueDate,
    this.settledAt,
    this.notes,
  });

  final int id;
  final String? number;
  final int? saleId;
  final int? clientId;
  final String? clientName;
  final String? saleNumber;
  final DateTime? saleSoldAt;
  final String description;
  final double originalAmount;
  final double paidAmount;
  final double balanceAmount;
  final String status;
  final DateTime? dueDate;
  final DateTime createdAt;
  final DateTime? settledAt;
  final String? notes;
  final List<ReceivableSaleItem> saleItems;
  final List<ReceivablePayment> payments;

  factory Receivable.fromJson(Map<String, dynamic> json) {
    return Receivable(
      id: json['id'] as int,
      number: json['number'] as String?,
      saleId: json['sale_id'] as int?,
      clientId: json['client_id'] as int?,
      clientName: json['client_name'] as String?,
      saleNumber: json['sale_number'] as String?,
      saleSoldAt: json['sale_sold_at'] == null
          ? null
          : DateTime.parse(json['sale_sold_at'] as String).toLocal(),
      description: json['description'] as String,
      originalAmount: _toDouble(json['original_amount']),
      paidAmount: _toDouble(json['paid_amount']),
      balanceAmount: _toDouble(json['balance_amount']),
      status: json['status'] as String? ?? 'open',
      dueDate: json['due_date'] == null
          ? null
          : DateTime.parse(json['due_date'] as String).toLocal(),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      settledAt: json['settled_at'] == null
          ? null
          : DateTime.parse(json['settled_at'] as String).toLocal(),
      notes: json['notes'] as String?,
      saleItems: ((json['sale_items'] as List<dynamic>?) ?? [])
          .map(
            (item) => ReceivableSaleItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      payments: ((json['payments'] as List<dynamic>?) ?? [])
          .map(
            (item) => ReceivablePayment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class ReceivableSaleItem {
  const ReceivableSaleItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.totalPrice,
  });

  final int id;
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double totalPrice;

  factory ReceivableSaleItem.fromJson(Map<String, dynamic> json) {
    return ReceivableSaleItem(
      id: json['id'] as int,
      description: json['description'] as String? ?? '-',
      quantity: _toDouble(json['quantity']),
      unit: json['unit'] as String? ?? 'un',
      unitPrice: _toDouble(json['unit_price']),
      totalPrice: _toDouble(json['total_price']),
    );
  }
}

class ReceivablePayment {
  const ReceivablePayment({
    required this.id,
    required this.receivableId,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.userId,
    this.notes,
  });

  final int id;
  final int receivableId;
  final int? userId;
  final double amount;
  final String method;
  final String? notes;
  final DateTime paidAt;

  factory ReceivablePayment.fromJson(Map<String, dynamic> json) {
    return ReceivablePayment(
      id: json['id'] as int,
      receivableId: json['receivable_id'] as int,
      userId: json['user_id'] as int?,
      amount: _toDouble(json['amount']),
      method: json['method'] as String? ?? 'dinheiro',
      notes: json['notes'] as String?,
      paidAt: DateTime.parse(json['paid_at'] as String).toLocal(),
    );
  }
}

class ReceivablePaymentPayload {
  const ReceivablePaymentPayload({
    required this.amount,
    required this.method,
    this.notes,
  });

  final double amount;
  final String method;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'amount': amount,
    'method': method,
    'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
  };
}

class ReceivableManualPayload {
  const ReceivableManualPayload({
    required this.clientId,
    required this.amount,
    required this.description,
    this.dueDate,
    this.notes,
  });

  final int clientId;
  final double amount;
  final String description;
  final DateTime? dueDate;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'client_id': clientId,
    'amount': amount,
    'description': description.trim().isEmpty
        ? 'Lançamento manual de crediário'
        : description.trim(),
    'due_date': dueDate?.toIso8601String(),
    'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
  };
}

double _toDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
