class MonitoringSnapshot {
  const MonitoringSnapshot({
    required this.equipmentId,
    required this.cpuUsagePercent,
    required this.memoryUsagePercent,
    required this.diskUsagePercent,
    required this.collectedAt,
    this.temperatureCelsius,
  });

  final int equipmentId;
  final String cpuUsagePercent;
  final String memoryUsagePercent;
  final String diskUsagePercent;
  final String? temperatureCelsius;
  final DateTime collectedAt;

  factory MonitoringSnapshot.fromJson(Map<String, dynamic> json) {
    return MonitoringSnapshot(
      equipmentId: json['equipment_id'] as int,
      cpuUsagePercent: json['cpu_usage_percent'].toString(),
      memoryUsagePercent: json['memory_usage_percent'].toString(),
      diskUsagePercent: json['disk_usage_percent'].toString(),
      temperatureCelsius: json['temperature_celsius']?.toString(),
      collectedAt: DateTime.parse(json['collected_at'] as String),
    );
  }
}
