class PdvOperator {
  const PdvOperator({
    required this.id,
    required this.name,
    required this.code,
    required this.role,
    required this.canOpenCash,
    required this.canAuthorizeWithdrawal,
    required this.canAuthorizeCancel,
    required this.canAuthorizeDiscount,
    required this.active,
    required this.createdAt,
    this.notes,
  });

  final int id;
  final String name;
  final String code;
  final String role;
  final bool canOpenCash;
  final bool canAuthorizeWithdrawal;
  final bool canAuthorizeCancel;
  final bool canAuthorizeDiscount;
  final bool active;
  final String? notes;
  final DateTime createdAt;

  bool get isFiscal => role == 'fiscal';

  factory PdvOperator.fromJson(Map<String, dynamic> json) {
    return PdvOperator(
      id: json['id'] as int,
      name: json['name'] as String,
      code: json['code'] as String,
      role: json['role'] as String,
      canOpenCash: json['can_open_cash'] as bool? ?? true,
      canAuthorizeWithdrawal:
          json['can_authorize_withdrawal'] as bool? ?? false,
      canAuthorizeCancel: json['can_authorize_cancel'] as bool? ?? false,
      canAuthorizeDiscount: json['can_authorize_discount'] as bool? ?? false,
      active: json['active'] as bool? ?? true,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class PdvOperatorPayload {
  const PdvOperatorPayload({
    required this.name,
    required this.code,
    required this.role,
    required this.canOpenCash,
    required this.canAuthorizeWithdrawal,
    required this.canAuthorizeCancel,
    required this.canAuthorizeDiscount,
    required this.active,
    this.pin,
    this.notes,
  });

  final String name;
  final String code;
  final String? pin;
  final String role;
  final bool canOpenCash;
  final bool canAuthorizeWithdrawal;
  final bool canAuthorizeCancel;
  final bool canAuthorizeDiscount;
  final bool active;
  final String? notes;

  Map<String, dynamic> toCreateJson() {
    return {
      'name': name.trim(),
      'code': code.trim(),
      'pin': pin,
      'role': role,
      'can_open_cash': canOpenCash,
      'can_authorize_withdrawal': canAuthorizeWithdrawal,
      'can_authorize_cancel': canAuthorizeCancel,
      'can_authorize_discount': canAuthorizeDiscount,
      'active': active,
      'notes': notes,
    };
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name.trim(),
      'code': code.trim(),
      if (pin != null && pin!.isNotEmpty) 'pin': pin,
      'role': role,
      'can_open_cash': canOpenCash,
      'can_authorize_withdrawal': canAuthorizeWithdrawal,
      'can_authorize_cancel': canAuthorizeCancel,
      'can_authorize_discount': canAuthorizeDiscount,
      'active': active,
      'notes': notes,
    };
  }
}

class PdvAuthorization {
  const PdvAuthorization({
    required this.operatorId,
    required this.operatorName,
    required this.role,
    required this.message,
  });

  final int operatorId;
  final String operatorName;
  final String role;
  final String message;

  factory PdvAuthorization.fromJson(Map<String, dynamic> json) {
    return PdvAuthorization(
      operatorId: json['operator_id'] as int,
      operatorName: json['operator_name'] as String,
      role: json['role'] as String,
      message: json['message'] as String,
    );
  }
}
