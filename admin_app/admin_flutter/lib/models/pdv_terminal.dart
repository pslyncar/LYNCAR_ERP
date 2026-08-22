class PdvTerminal {
  const PdvTerminal({
    required this.id,
    required this.cashRegisterNumber,
    required this.terminalKey,
    required this.active,
    this.appVersion,
    this.deviceLabel,
    this.activationStatus = 'active',
    this.activationCodeExpiresAt,
    this.activatedAt,
    this.machineName,
    this.windowsUser,
    this.windowsVersion,
    this.deviceFingerprint,
    this.currentStatus,
    this.currentOperatorName,
    this.cashOpenedAt,
    this.currentSessionTotalAmount,
    this.todaySalesCount = 0,
    this.todaySalesAmount = 0,
    this.lastSeenAt,
    this.crossedBusinessDay = false,
  });

  final int id;
  final String cashRegisterNumber;
  final String terminalKey;
  final String? appVersion;
  final String? deviceLabel;
  final String activationStatus;
  final DateTime? activationCodeExpiresAt;
  final DateTime? activatedAt;
  final String? machineName;
  final String? windowsUser;
  final String? windowsVersion;
  final String? deviceFingerprint;
  final bool active;
  final String? currentStatus;
  final String? currentOperatorName;
  final DateTime? cashOpenedAt;
  final double? currentSessionTotalAmount;
  final int todaySalesCount;
  final double todaySalesAmount;
  final DateTime? lastSeenAt;
  final bool crossedBusinessDay;

  factory PdvTerminal.fromJson(Map<String, dynamic> json) {
    return PdvTerminal(
      id: json['id'] as int,
      cashRegisterNumber: json['cash_register_number'] as String,
      terminalKey: json['terminal_key'] as String,
      appVersion: json['app_version'] as String?,
      deviceLabel: json['device_label'] as String?,
      activationStatus: json['activation_status'] as String? ?? 'active',
      activationCodeExpiresAt: json['activation_code_expires_at'] == null
          ? null
          : DateTime.parse(
              json['activation_code_expires_at'] as String,
            ).toLocal(),
      activatedAt: json['activated_at'] == null
          ? null
          : DateTime.parse(json['activated_at'] as String).toLocal(),
      machineName: json['machine_name'] as String?,
      windowsUser: json['windows_user'] as String?,
      windowsVersion: json['windows_version'] as String?,
      deviceFingerprint: json['device_fingerprint'] as String?,
      active: json['active'] as bool? ?? true,
      currentStatus: json['current_status'] as String?,
      currentOperatorName: json['current_operator_name'] as String?,
      cashOpenedAt: json['cash_opened_at'] == null
          ? null
          : DateTime.parse(json['cash_opened_at'] as String).toLocal(),
      currentSessionTotalAmount: _toDouble(
        json['current_session_total_amount'],
      ),
      todaySalesCount: json['today_sales_count'] as int? ?? 0,
      todaySalesAmount: _toDouble(json['today_sales_amount']) ?? 0,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String).toLocal(),
      crossedBusinessDay: json['crossed_business_day'] as bool? ?? false,
    );
  }

  static double? _toDouble(Object? value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class CompanyResourceQuota {
  const CompanyResourceQuota({
    required this.companyCode,
    required this.activeUsers,
    this.maxUsers,
    required this.pdvTerminals,
    this.maxPdvTerminals,
  });

  final String companyCode;
  final int activeUsers;
  final int? maxUsers;
  final int pdvTerminals;
  final int? maxPdvTerminals;

  bool get pdvLimitReached =>
      maxPdvTerminals != null && pdvTerminals >= maxPdvTerminals!;

  factory CompanyResourceQuota.fromJson(Map<String, dynamic> json) {
    return CompanyResourceQuota(
      companyCode: json['company_code'] as String,
      activeUsers: json['active_users'] as int? ?? 0,
      maxUsers: json['max_users'] as int?,
      pdvTerminals: json['pdv_terminals'] as int? ?? 0,
      maxPdvTerminals: json['max_pdv_terminals'] as int?,
    );
  }
}

class PdvBusinessDaySettings {
  const PdvBusinessDaySettings({required this.cutoffMinutes});

  final int cutoffMinutes;

  factory PdvBusinessDaySettings.fromJson(Map<String, dynamic> json) {
    return PdvBusinessDaySettings(
      cutoffMinutes: json['cutoff_minutes'] as int? ?? 180,
    );
  }
}

class PdvTerminalActivationCreatePayload {
  const PdvTerminalActivationCreatePayload({
    required this.cashRegisterNumber,
    this.deviceLabel,
    this.expiresHours = 24,
  });

  final String cashRegisterNumber;
  final String? deviceLabel;
  final int expiresHours;

  Map<String, dynamic> toJson() {
    return {
      'cash_register_number': cashRegisterNumber,
      'device_label': deviceLabel,
      'expires_hours': expiresHours,
    };
  }
}

class MasterPdvTerminalActivationCreatePayload
    extends PdvTerminalActivationCreatePayload {
  const MasterPdvTerminalActivationCreatePayload({
    required this.companyCode,
    required super.cashRegisterNumber,
    super.deviceLabel,
    super.expiresHours,
  });

  final String companyCode;

  @override
  Map<String, dynamic> toJson() {
    return {...super.toJson(), 'company_code': companyCode};
  }
}

class PdvTerminalActivationCode {
  const PdvTerminalActivationCode({
    required this.terminal,
    required this.activationCode,
    required this.expiresAt,
  });

  final PdvTerminal terminal;
  final String activationCode;
  final DateTime expiresAt;

  factory PdvTerminalActivationCode.fromJson(Map<String, dynamic> json) {
    return PdvTerminalActivationCode(
      terminal: PdvTerminal.fromJson(json['terminal'] as Map<String, dynamic>),
      activationCode: json['activation_code'] as String,
      expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    );
  }
}

class PdvTerminalRegisterPayload {
  const PdvTerminalRegisterPayload({
    required this.cashRegisterNumber,
    required this.terminalKey,
    this.appVersion,
    this.deviceLabel,
  });

  final String cashRegisterNumber;
  final String terminalKey;
  final String? appVersion;
  final String? deviceLabel;

  Map<String, dynamic> toJson() {
    return {
      'cash_register_number': cashRegisterNumber,
      'terminal_key': terminalKey,
      'app_version': appVersion,
      'device_label': deviceLabel,
    };
  }
}

class PdvTerminalHeartbeatPayload {
  const PdvTerminalHeartbeatPayload({
    required this.terminalKey,
    required this.currentStatus,
    this.appVersion,
    this.deviceLabel,
    this.currentOperatorName,
    this.cashOpenedAt,
    this.currentSessionTotalAmount,
  });

  final String terminalKey;
  final String currentStatus;
  final String? appVersion;
  final String? deviceLabel;
  final String? currentOperatorName;
  final DateTime? cashOpenedAt;
  final double? currentSessionTotalAmount;

  Map<String, dynamic> toJson() {
    return {
      'terminal_key': terminalKey,
      'app_version': appVersion,
      'device_label': deviceLabel,
      'current_status': currentStatus,
      'current_operator_name': currentOperatorName,
      'cash_opened_at': cashOpenedAt?.toIso8601String(),
      'current_session_total_amount': currentSessionTotalAmount,
    };
  }
}

class PdvTerminalCommand {
  const PdvTerminalCommand({
    required this.id,
    required this.terminalId,
    required this.action,
    required this.status,
    this.message,
    this.resultMessage,
    this.createdAt,
    this.deliveredAt,
    this.completedAt,
  });

  final int id;
  final int terminalId;
  final String action;
  final String status;
  final String? message;
  final String? resultMessage;
  final DateTime? createdAt;
  final DateTime? deliveredAt;
  final DateTime? completedAt;

  factory PdvTerminalCommand.fromJson(Map<String, dynamic> json) {
    return PdvTerminalCommand(
      id: json['id'] as int,
      terminalId: json['terminal_id'] as int,
      action: json['action'] as String,
      status: json['status'] as String,
      message: json['message'] as String?,
      resultMessage: json['result_message'] as String?,
      createdAt: json['created_at'] == null
          ? null
          : DateTime.parse(json['created_at'] as String).toLocal(),
      deliveredAt: json['delivered_at'] == null
          ? null
          : DateTime.parse(json['delivered_at'] as String).toLocal(),
      completedAt: json['completed_at'] == null
          ? null
          : DateTime.parse(json['completed_at'] as String).toLocal(),
    );
  }
}
