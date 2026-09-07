class MasterFinanceSetting {
  const MasterFinanceSetting({
    required this.enabled,
    required this.feePercent,
    required this.dailyInterestPercent,
    required this.graceDays,
    required this.monetaryCorrectionEnabled,
    required this.monetaryIndex,
    required this.automaticIndexUpdate,
  });
  final bool enabled;
  final double feePercent;
  final double dailyInterestPercent;
  final int graceDays;
  final bool monetaryCorrectionEnabled;
  final String monetaryIndex;
  final bool automaticIndexUpdate;
  factory MasterFinanceSetting.fromJson(Map<String, dynamic> j) =>
      MasterFinanceSetting(
        enabled: j['late_charges_enabled'] == true,
        feePercent: (j['late_fee_percent'] as num?)?.toDouble() ?? 0,
        dailyInterestPercent:
            (j['late_interest_daily_percent'] as num?)?.toDouble() ?? 0,
        graceDays: (j['late_grace_days'] as num?)?.toInt() ?? 0,
        monetaryCorrectionEnabled: j['monetary_correction_enabled'] != false,
        monetaryIndex: j['monetary_index'] as String? ?? 'IPCA',
        automaticIndexUpdate: j['automatic_index_update'] != false,
      );
  Map<String, dynamic> toJson() => {
    'late_charges_enabled': enabled,
    'late_fee_percent': feePercent,
    'late_interest_daily_percent': dailyInterestPercent,
    'late_grace_days': graceDays,
    'monetary_correction_enabled': monetaryCorrectionEnabled,
    'monetary_index': monetaryIndex,
    'automatic_index_update': automaticIndexUpdate,
  };
}
