class Payable {
  const Payable({
    required this.id,
    required this.description,
    required this.originalAmount,
    required this.paidAmount,
    required this.balanceAmount,
    required this.status,
    required this.createdAt,
    required this.payments,
    this.number,
    this.supplierId,
    this.supplierName,
    this.stockEntryId,
    this.stockEntryNumber,
    this.documentNumber,
    this.category,
    this.issueDate,
    this.dueDate,
    this.competenceDate,
    this.settledAt,
    this.notes,
  });

  final int id;
  final String? number;
  final int? supplierId;
  final String? supplierName;
  final int? stockEntryId;
  final String? stockEntryNumber;
  final String description;
  final String? documentNumber;
  final String? category;
  final double originalAmount;
  final double paidAmount;
  final double balanceAmount;
  final String status;
  final DateTime? issueDate;
  final DateTime? dueDate;
  final DateTime? competenceDate;
  final DateTime createdAt;
  final DateTime? settledAt;
  final String? notes;
  final List<PayablePayment> payments;

  factory Payable.fromJson(Map<String, dynamic> json) {
    return Payable(
      id: json['id'] as int,
      number: json['number'] as String?,
      supplierId: json['supplier_id'] as int?,
      supplierName: json['supplier_name'] as String?,
      stockEntryId: json['stock_entry_id'] as int?,
      stockEntryNumber: json['stock_entry_number'] as String?,
      description: json['description'] as String,
      documentNumber: json['document_number'] as String?,
      category: json['category'] as String?,
      originalAmount: _toDouble(json['original_amount']),
      paidAmount: _toDouble(json['paid_amount']),
      balanceAmount: _toDouble(json['balance_amount']),
      status: json['status'] as String? ?? 'open',
      issueDate: _date(json['issue_date']),
      dueDate: _date(json['due_date']),
      competenceDate: _date(json['competence_date']),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      settledAt: _date(json['settled_at']),
      notes: json['notes'] as String?,
      payments: ((json['payments'] as List<dynamic>?) ?? [])
          .map((item) => PayablePayment.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class PayablePayment {
  const PayablePayment({
    required this.id,
    required this.payableId,
    required this.amount,
    required this.method,
    required this.paidAt,
    this.userId,
    this.notes,
  });

  final int id;
  final int payableId;
  final int? userId;
  final double amount;
  final String method;
  final String? notes;
  final DateTime paidAt;

  factory PayablePayment.fromJson(Map<String, dynamic> json) {
    return PayablePayment(
      id: json['id'] as int,
      payableId: json['payable_id'] as int,
      userId: json['user_id'] as int?,
      amount: _toDouble(json['amount']),
      method: json['method'] as String? ?? 'dinheiro',
      notes: json['notes'] as String?,
      paidAt: DateTime.parse(json['paid_at'] as String).toLocal(),
    );
  }
}

class PayablePayload {
  const PayablePayload({
    this.supplierId,
    this.stockEntryId,
    required this.description,
    this.documentNumber,
    this.category,
    required this.originalAmount,
    this.dueDate,
    this.issueDate,
    this.competenceDate,
    this.notes,
  });

  final int? supplierId;
  final int? stockEntryId;
  final String description;
  final String? documentNumber;
  final String? category;
  final double originalAmount;
  final DateTime? dueDate;
  final DateTime? issueDate;
  final DateTime? competenceDate;
  final String? notes;

  Map<String, dynamic> toJson() => {
    'supplier_id': supplierId,
    'stock_entry_id': stockEntryId,
    'description': description.trim(),
    'document_number': _emptyToNull(documentNumber),
    'category': _emptyToNull(category),
    'original_amount': originalAmount,
    'due_date': dueDate?.toIso8601String(),
    'issue_date': issueDate?.toIso8601String(),
    'competence_date': competenceDate?.toIso8601String(),
    'notes': _emptyToNull(notes),
  };
}

class PayablePaymentPayload {
  const PayablePaymentPayload({
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
    'notes': _emptyToNull(notes),
  };
}

DateTime? _date(Object? value) {
  if (value == null) return null;
  return DateTime.parse(value as String).toLocal();
}

double _toDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

String? _emptyToNull(String? value) {
  final text = value?.trim() ?? '';
  return text.isEmpty ? null : text;
}
