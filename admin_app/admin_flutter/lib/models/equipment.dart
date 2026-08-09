class Equipment {
  const Equipment({
    required this.id,
    required this.clientId,
    required this.hostname,
    required this.status,
    required this.createdAt,
    this.assetTag,
    this.location,
    this.responsibleUser,
    this.operatingSystem,
    this.processor,
    this.ramTotalGb,
    this.storageTotalGb,
    this.technicalNotes,
    this.agentVersion,
    this.lastIpAddress,
    this.lastLoggedUser,
    this.lastSeenAt,
  });

  final int id;
  final int clientId;
  final String hostname;
  final String status;
  final DateTime createdAt;
  final String? assetTag;
  final String? location;
  final String? responsibleUser;
  final String? operatingSystem;
  final String? processor;
  final String? ramTotalGb;
  final String? storageTotalGb;
  final String? technicalNotes;
  final String? agentVersion;
  final String? lastIpAddress;
  final String? lastLoggedUser;
  final DateTime? lastSeenAt;

  factory Equipment.fromJson(Map<String, dynamic> json) {
    return Equipment(
      id: json['id'] as int,
      clientId: json['client_id'] as int,
      hostname: json['hostname'] as String,
      status: json['status'] as String? ?? 'ativo',
      createdAt: DateTime.parse(json['created_at'] as String),
      assetTag: json['asset_tag'] as String?,
      location: json['location'] as String?,
      responsibleUser: json['responsible_user'] as String?,
      operatingSystem: json['operating_system'] as String?,
      processor: json['processor'] as String?,
      ramTotalGb: json['ram_total_gb']?.toString(),
      storageTotalGb: json['storage_total_gb']?.toString(),
      technicalNotes: json['technical_notes'] as String?,
      agentVersion: json['agent_version'] as String?,
      lastIpAddress: json['last_ip_address'] as String?,
      lastLoggedUser: json['last_logged_user'] as String?,
      lastSeenAt: json['last_seen_at'] == null
          ? null
          : DateTime.parse(json['last_seen_at'] as String),
    );
  }
}

class EquipmentCreate {
  const EquipmentCreate({
    required this.clientId,
    required this.hostname,
    this.assetTag,
    this.location,
    this.responsibleUser,
    this.operatingSystem,
    this.processor,
    this.ramTotalGb,
    this.storageTotalGb,
    this.technicalNotes,
  });

  final int clientId;
  final String hostname;
  final String? assetTag;
  final String? location;
  final String? responsibleUser;
  final String? operatingSystem;
  final String? processor;
  final String? ramTotalGb;
  final String? storageTotalGb;
  final String? technicalNotes;

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'hostname': hostname.trim(),
      'asset_tag': _emptyToNull(assetTag),
      'location': _emptyToNull(location),
      'responsible_user': _emptyToNull(responsibleUser),
      'operating_system': _emptyToNull(operatingSystem),
      'processor': _emptyToNull(processor),
      'ram_total_gb': _numberOrNull(ramTotalGb),
      'storage_total_gb': _numberOrNull(storageTotalGb),
      'status': 'ativo',
      'technical_notes': _emptyToNull(technicalNotes),
    };
  }

  static String? _emptyToNull(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return trimmed;
  }

  static num? _numberOrNull(String? value) {
    final trimmed = value?.replaceAll(',', '.').trim();
    if (trimmed == null || trimmed.isEmpty) {
      return null;
    }
    return num.tryParse(trimmed);
  }
}

class EquipmentAgentToken {
  const EquipmentAgentToken({
    required this.equipmentId,
    required this.token,
    required this.message,
  });

  final int equipmentId;
  final String token;
  final String message;

  factory EquipmentAgentToken.fromJson(Map<String, dynamic> json) {
    return EquipmentAgentToken(
      equipmentId: json['equipment_id'] as int,
      token: json['token'] as String,
      message: json['message'] as String,
    );
  }
}
