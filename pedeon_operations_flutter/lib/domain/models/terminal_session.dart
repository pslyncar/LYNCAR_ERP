class TerminalSession {
  const TerminalSession({
    required this.terminalId,
    required this.deviceLabel,
    required this.capabilities,
    required this.stationIds,
    required this.userId,
    required this.userName,
    required this.userType,
  });

  factory TerminalSession.fromJson(Map<String, dynamic> json) =>
      TerminalSession(
        terminalId: json['terminal_id'].toString(),
        deviceLabel:
            (json['device_label'] as String?)?.trim().isNotEmpty == true
            ? json['device_label'] as String
            : 'Terminal PedeOn',
        capabilities: Set.unmodifiable(
          (json['capabilities'] as List<dynamic>? ?? const []).map((e) => '$e'),
        ),
        stationIds: List.unmodifiable(
          (json['station_ids'] as List<dynamic>? ?? const [])
              .map((e) => int.tryParse('$e'))
              .whereType<int>(),
        ),
        userId: (json['user'] as Map<String, dynamic>?)?['id'] as int?,
        userName: ((json['user'] as Map<String, dynamic>?)?['name'] as String?)?.trim(),
        userType: (json['user'] as Map<String, dynamic>?)?['type'] as String? ?? 'erp_owner',
      );

  final String terminalId;
  final String deviceLabel;
  final Set<String> capabilities;
  final List<int> stationIds;
  final int? userId;
  final String? userName;
  final String userType;
  bool can(String capability) => capabilities.contains(capability);
}
