class SyncIssue {
  const SyncIssue({
    required this.id,
    required this.type,
    required this.aggregateId,
    required this.message,
    required this.createdAt,
  });
  factory SyncIssue.fromJson(Map<String, dynamic> json) => SyncIssue(
    id: json['id'] as int,
    type: '${json['event_type']}',
    aggregateId: '${json['aggregate_id'] ?? ''}',
    message: '${json['last_error'] ?? 'Falha de sincronização'}',
    createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
  );
  final int id;
  final String type;
  final String aggregateId;
  final String message;
  final DateTime? createdAt;
}
