class LynaReply {
  const LynaReply({
    required this.message,
    required this.source,
    this.model,
    this.canExecuteActions = false,
  });

  factory LynaReply.fromJson(Map<String, dynamic> json) => LynaReply(
    message: json['message']?.toString() ?? 'Não consegui responder agora.',
    source: json['source']?.toString() ?? 'fallback',
    model: json['model']?.toString(),
    canExecuteActions: json['can_execute_actions'] as bool? ?? false,
  );

  final String message;
  final String source;
  final String? model;
  final bool canExecuteActions;
}
