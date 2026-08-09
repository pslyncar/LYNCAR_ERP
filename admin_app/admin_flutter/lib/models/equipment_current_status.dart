class EquipmentCurrentStatus {
  const EquipmentCurrentStatus({
    required this.equipmentId,
    required this.cpuUsagePercent,
    required this.memoryUsagePercent,
    required this.diskUsagePercent,
    required this.storageVolumes,
    required this.healthStatus,
    required this.collectedAt,
    this.temperatureCelsius,
  });

  final int equipmentId;
  final String cpuUsagePercent;
  final String memoryUsagePercent;
  final String diskUsagePercent;
  final List<StorageVolume> storageVolumes;
  final String healthStatus;
  final DateTime collectedAt;
  final String? temperatureCelsius;

  factory EquipmentCurrentStatus.fromJson(Map<String, dynamic> json) {
    return EquipmentCurrentStatus(
      equipmentId: json['equipment_id'] as int,
      cpuUsagePercent: json['cpu_usage_percent'].toString(),
      memoryUsagePercent: json['memory_usage_percent'].toString(),
      diskUsagePercent: json['disk_usage_percent'].toString(),
      storageVolumes: (json['storage_volumes'] as List<dynamic>? ?? [])
          .map((item) => StorageVolume.fromJson(item as Map<String, dynamic>))
          .toList(),
      temperatureCelsius: json['temperature_celsius']?.toString(),
      healthStatus: json['health_status'] as String,
      collectedAt: DateTime.parse(json['collected_at'] as String),
    );
  }
}

class StorageVolume {
  const StorageVolume({
    required this.mountpoint,
    required this.totalGb,
    required this.usedGb,
    required this.freeGb,
    required this.usagePercent,
    this.device,
    this.filesystem,
  });

  final String? device;
  final String mountpoint;
  final String? filesystem;
  final String totalGb;
  final String usedGb;
  final String freeGb;
  final String usagePercent;

  factory StorageVolume.fromJson(Map<String, dynamic> json) {
    return StorageVolume(
      device: json['device']?.toString(),
      mountpoint: json['mountpoint']?.toString() ?? '-',
      filesystem: json['filesystem']?.toString(),
      totalGb: json['total_gb'].toString(),
      usedGb: json['used_gb'].toString(),
      freeGb: json['free_gb'].toString(),
      usagePercent: json['usage_percent'].toString(),
    );
  }
}

class EquipmentAlert {
  const EquipmentAlert({
    required this.id,
    required this.equipmentId,
    required this.type,
    required this.severity,
    required this.message,
    required this.metricValue,
    required this.createdAt,
  });

  final int id;
  final int equipmentId;
  final String type;
  final String severity;
  final String message;
  final String metricValue;
  final DateTime createdAt;

  factory EquipmentAlert.fromJson(Map<String, dynamic> json) {
    return EquipmentAlert(
      id: json['id'] as int,
      equipmentId: json['equipment_id'] as int,
      type: json['type'] as String,
      severity: json['severity'] as String,
      message: json['message'] as String,
      metricValue: json['metric_value'].toString(),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
