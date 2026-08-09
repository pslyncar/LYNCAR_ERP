class CashClosing {
  const CashClosing({
    required this.id,
    required this.status,
    required this.closedAt,
    required this.openingAmount,
    required this.expectedCashAmount,
    required this.countedCashAmount,
    required this.cashDifferenceAmount,
    required this.totalSalesAmount,
    required this.totalSalesCount,
    required this.totalWithdrawalAmount,
    required this.totalSupplyAmount,
    this.authorizedByOperatorId,
    this.authorizedByOperatorName,
    required this.payments,
    required this.movements,
    this.number,
    this.cashRegisterNumber,
    this.operatorName,
    this.openedAt,
    this.notes,
    this.treasuryNotes,
    this.treasuryCheckedAt,
    this.businessDate,
    this.crossedBusinessDay = false,
    this.businessDayCutoffMinutes = 180,
  });

  final int id;
  final String? number;
  final String? cashRegisterNumber;
  final String? operatorName;
  final DateTime? openedAt;
  final DateTime closedAt;
  final double openingAmount;
  final double expectedCashAmount;
  final double countedCashAmount;
  final double cashDifferenceAmount;
  final double totalSalesAmount;
  final int totalSalesCount;
  final double totalWithdrawalAmount;
  final double totalSupplyAmount;
  final int? authorizedByOperatorId;
  final String? authorizedByOperatorName;
  final String status;
  final String? notes;
  final String? treasuryNotes;
  final DateTime? treasuryCheckedAt;
  final DateTime? businessDate;
  final bool crossedBusinessDay;
  final int businessDayCutoffMinutes;
  final List<CashClosingPayment> payments;
  final List<CashClosingMovement> movements;

  factory CashClosing.fromJson(Map<String, dynamic> json) {
    return CashClosing(
      id: json['id'] as int,
      number: json['number'] as String?,
      cashRegisterNumber: json['cash_register_number'] as String?,
      operatorName: json['operator_name'] as String?,
      openedAt: json['opened_at'] == null
          ? null
          : DateTime.parse(json['opened_at'] as String).toLocal(),
      closedAt: DateTime.parse(json['closed_at'] as String).toLocal(),
      openingAmount: _toDouble(json['opening_amount']),
      expectedCashAmount: _toDouble(json['expected_cash_amount']),
      countedCashAmount: _toDouble(json['counted_cash_amount']),
      cashDifferenceAmount: _toDouble(json['cash_difference_amount']),
      totalSalesAmount: _toDouble(json['total_sales_amount']),
      totalSalesCount: json['total_sales_count'] as int? ?? 0,
      totalWithdrawalAmount: _toDouble(json['total_withdrawal_amount']),
      totalSupplyAmount: _toDouble(json['total_supply_amount']),
      authorizedByOperatorId: json['authorized_by_operator_id'] as int?,
      authorizedByOperatorName: json['authorized_by_operator_name'] as String?,
      status: json['status'] as String? ?? 'pending_treasury',
      notes: json['notes'] as String?,
      treasuryNotes: json['treasury_notes'] as String?,
      treasuryCheckedAt: json['treasury_checked_at'] == null
          ? null
          : DateTime.parse(json['treasury_checked_at'] as String).toLocal(),
      businessDate: json['business_date'] == null
          ? null
          : DateTime.parse(json['business_date'] as String),
      crossedBusinessDay: json['crossed_business_day'] as bool? ?? false,
      businessDayCutoffMinutes:
          json['business_day_cutoff_minutes'] as int? ?? 180,
      payments: ((json['payments'] as List<dynamic>?) ?? [])
          .map(
            (item) => CashClosingPayment.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      movements: ((json['movements'] as List<dynamic>?) ?? [])
          .map(
            (item) =>
                CashClosingMovement.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }
}

class CashClosingReviewPayload {
  const CashClosingReviewPayload({
    required this.status,
    this.notes,
    this.countedCashAmount,
  });

  final String status;
  final String? notes;
  final double? countedCashAmount;

  Map<String, dynamic> toJson() {
    return {
      'status': status,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      if (countedCashAmount != null) 'counted_cash_amount': countedCashAmount,
    };
  }
}

class CashClosingPayload {
  const CashClosingPayload({
    required this.operatorName,
    this.cashRegisterNumber,
    required this.openedAt,
    required this.openingAmount,
    required this.expectedCashAmount,
    required this.countedCashAmount,
    required this.totalSalesAmount,
    required this.totalSalesCount,
    required this.totalWithdrawalAmount,
    required this.totalSupplyAmount,
    required this.payments,
    required this.movements,
    this.authorizedByOperatorId,
    this.authorizedByOperatorName,
    this.notes,
  });

  final String? operatorName;
  final String? cashRegisterNumber;
  final DateTime? openedAt;
  final double openingAmount;
  final double expectedCashAmount;
  final double countedCashAmount;
  final double totalSalesAmount;
  final int totalSalesCount;
  final double totalWithdrawalAmount;
  final double totalSupplyAmount;
  final int? authorizedByOperatorId;
  final String? authorizedByOperatorName;
  final String? notes;
  final List<CashClosingPaymentPayload> payments;
  final List<CashClosingMovementPayload> movements;

  Map<String, dynamic> toJson() {
    return {
      'operator_name': operatorName,
      'cash_register_number': cashRegisterNumber,
      'opened_at': openedAt?.toIso8601String(),
      'opening_amount': openingAmount,
      'expected_cash_amount': expectedCashAmount,
      'counted_cash_amount': countedCashAmount,
      'total_sales_amount': totalSalesAmount,
      'total_sales_count': totalSalesCount,
      'total_withdrawal_amount': totalWithdrawalAmount,
      'total_supply_amount': totalSupplyAmount,
      'authorized_by_operator_id': authorizedByOperatorId,
      'authorized_by_operator_name': authorizedByOperatorName,
      'notes': notes?.trim().isEmpty == true ? null : notes?.trim(),
      'payments': payments.map((payment) => payment.toJson()).toList(),
      'movements': movements.map((movement) => movement.toJson()).toList(),
    };
  }
}

class CashClosingPayment {
  const CashClosingPayment({
    required this.id,
    required this.method,
    required this.amount,
  });

  final int id;
  final String method;
  final double amount;

  factory CashClosingPayment.fromJson(Map<String, dynamic> json) {
    return CashClosingPayment(
      id: json['id'] as int,
      method: json['method'] as String,
      amount: _toDouble(json['amount']),
    );
  }
}

class CashClosingPaymentPayload {
  const CashClosingPaymentPayload({required this.method, required this.amount});

  final String method;
  final double amount;

  Map<String, dynamic> toJson() => {'method': method, 'amount': amount};
}

class CashClosingMovement {
  const CashClosingMovement({
    required this.id,
    required this.movementType,
    required this.amount,
    this.reason,
    this.createdAt,
    this.authorizedByOperatorId,
    this.authorizedByOperatorName,
  });

  final int id;
  final String movementType;
  final double amount;
  final String? reason;
  final DateTime? createdAt;
  final int? authorizedByOperatorId;
  final String? authorizedByOperatorName;

  factory CashClosingMovement.fromJson(Map<String, dynamic> json) {
    return CashClosingMovement(
      id: json['id'] as int,
      movementType: json['movement_type'] as String,
      amount: _toDouble(json['amount']),
      reason: json['reason'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String).toLocal(),
      authorizedByOperatorId: json['authorized_by_operator_id'] as int?,
      authorizedByOperatorName: json['authorized_by_operator_name'] as String?,
    );
  }
}

class CashClosingMovementPayload {
  const CashClosingMovementPayload({
    required this.movementType,
    required this.amount,
    this.reason,
    this.createdAt,
    this.authorizedByOperatorId,
    this.authorizedByOperatorName,
  });

  final String movementType;
  final double amount;
  final String? reason;
  final DateTime? createdAt;
  final int? authorizedByOperatorId;
  final String? authorizedByOperatorName;

  Map<String, dynamic> toJson() {
    return {
      'movement_type': movementType,
      'amount': amount,
      'reason': reason,
      'created_at': createdAt?.toIso8601String(),
      'authorized_by_operator_id': authorizedByOperatorId,
      'authorized_by_operator_name': authorizedByOperatorName,
    };
  }
}

double _toDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}
