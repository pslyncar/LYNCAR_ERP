class PlanChangeItem {
  const PlanChangeItem({
    required this.id,
    required this.label,
    this.detail,
    required this.active,
  });

  final int id;
  final String label;
  final String? detail;
  final bool active;

  factory PlanChangeItem.fromJson(Map<String, dynamic> json) {
    return PlanChangeItem(
      id: (json['id'] as num).toInt(),
      label: json['label'] as String? ?? '-',
      detail: json['detail'] as String?,
      active: json['active'] as bool? ?? true,
    );
  }
}

class PlanChangePreview {
  const PlanChangePreview({
    required this.companyCode,
    required this.currentPlan,
    required this.targetPlan,
    required this.currentModules,
    required this.targetModules,
    required this.removedModules,
    required this.users,
    required this.terminals,
    required this.maxUsers,
    required this.maxPdvTerminals,
    required this.activeUsers,
    required this.activeTerminals,
    required this.requiredUserSelections,
    required this.requiredTerminalSelections,
    required this.pdvWindowsWillBeRevoked,
  });

  final String companyCode;
  final String currentPlan;
  final String targetPlan;
  final List<String> currentModules;
  final List<String> targetModules;
  final List<String> removedModules;
  final List<PlanChangeItem> users;
  final List<PlanChangeItem> terminals;
  final int? maxUsers;
  final int? maxPdvTerminals;
  final int activeUsers;
  final int activeTerminals;
  final int requiredUserSelections;
  final int requiredTerminalSelections;
  final bool pdvWindowsWillBeRevoked;

  factory PlanChangePreview.fromJson(Map<String, dynamic> json) {
    List<String> strings(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .map((value) => value.toString())
            .toList();
    List<PlanChangeItem> items(String key) =>
        (json[key] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(PlanChangeItem.fromJson)
            .toList();
    int? integer(String key) => (json[key] as num?)?.toInt();

    return PlanChangePreview(
      companyCode: json['company_code'] as String? ?? '-',
      currentPlan: json['current_plan'] as String? ?? '-',
      targetPlan: json['target_plan'] as String? ?? '-',
      currentModules: strings('current_modules'),
      targetModules: strings('target_modules'),
      removedModules: strings('removed_modules'),
      users: items('users'),
      terminals: items('terminals'),
      maxUsers: integer('max_users'),
      maxPdvTerminals: integer('max_pdv_terminals'),
      activeUsers: (json['active_users'] as num?)?.toInt() ?? 0,
      activeTerminals: (json['active_terminals'] as num?)?.toInt() ?? 0,
      requiredUserSelections:
          (json['required_user_selections'] as num?)?.toInt() ?? 0,
      requiredTerminalSelections:
          (json['required_terminal_selections'] as num?)?.toInt() ?? 0,
      pdvWindowsWillBeRevoked:
          json['pdv_windows_will_be_revoked'] as bool? ?? false,
    );
  }
}

class PlanChangeResult {
  const PlanChangeResult({
    required this.inactivatedUserIds,
    required this.revokedTerminalIds,
    required this.targetPlan,
  });

  final List<int> inactivatedUserIds;
  final List<int> revokedTerminalIds;
  final String targetPlan;

  factory PlanChangeResult.fromJson(Map<String, dynamic> json) {
    return PlanChangeResult(
      inactivatedUserIds:
          ((json['inactivated_user_ids'] as List<dynamic>?) ?? const [])
              .map((value) => (value as num).toInt())
              .toList(),
      revokedTerminalIds:
          ((json['revoked_terminal_ids'] as List<dynamic>?) ?? const [])
              .map((value) => (value as num).toInt())
              .toList(),
      targetPlan: json['target_plan'] as String? ?? '-',
    );
  }
}
