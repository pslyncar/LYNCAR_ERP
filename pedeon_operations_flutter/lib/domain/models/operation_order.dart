class OperationOrder {
  const OperationOrder({
    required this.publicId,
    required this.number,
    required this.status,
    required this.paymentStatus,
    required this.source,
    required this.fulfillment,
    required this.customerName,
    required this.createdAt,
    required this.notes,
    required this.items,
    this.total = 0,
    this.tableLabel,
    this.commandLabel,
  });

  factory OperationOrder.fromJson(Map<String, dynamic> json) {
    final customer = json['customer'] as Map<String, dynamic>?;
    final rawItems = json['items'] as List<dynamic>? ?? const [];
    final metadata = json['source_metadata'] as Map<String, dynamic>?;
    return OperationOrder(
      publicId: '${json['public_id'] ?? json['id']}',
      number: '${json['display_number'] ?? json['number'] ?? 'Pedido'}',
      status: '${json['status'] ?? 'pending'}',
      paymentStatus: '${json['payment_status'] ?? 'pending'}',
      source: '${json['source_channel'] ?? 'pedeon'}',
      fulfillment: '${json['fulfillment_type'] ?? 'pickup'}',
      customerName:
          '${customer?['name'] ?? json['customer_name'] ?? 'Cliente'}',
      createdAt: DateTime.tryParse('${json['created_at'] ?? ''}')?.toLocal(),
      notes: '${json['notes'] ?? json['observation'] ?? ''}',
      items: List.unmodifiable(
        rawItems.whereType<Map<String, dynamic>>().map(
          OperationOrderItem.fromJson,
        ),
      ),
      total: _toDouble(json['total'] ?? json['total_amount']),
      tableLabel: metadata?['table_label']?.toString(),
      commandLabel: metadata?['command_label']?.toString(),
    );
  }

  final String publicId;
  final String number;
  final String status;
  final String paymentStatus;
  final String source;
  final String fulfillment;
  final String customerName;
  final DateTime? createdAt;
  final String notes;
  final List<OperationOrderItem> items;
  final double total;
  final String? tableLabel;
  final String? commandLabel;
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  if (value is String) {
    return double.tryParse(value.trim().replaceAll(',', '.')) ?? 0;
  }
  return 0;
}

class OperationOrderItem {
  const OperationOrderItem({
    required this.name,
    required this.quantity,
    required this.notes,
    required this.modifiers,
  });
  factory OperationOrderItem.fromJson(Map<String, dynamic> json) {
    final raw =
        json['modifiers'] as List<dynamic>? ??
        json['selected_options'] as List<dynamic>? ??
        const [];
    return OperationOrderItem(
      name:
          '${json['name'] ?? json['product_name'] ?? json['description'] ?? 'Item'}',
      quantity: (num.tryParse('${json['quantity'] ?? 1}') ?? 1).toInt(),
      notes:
          '${json['notes'] ?? json['observation'] ?? json['customer_notes'] ?? ''}',
      modifiers: List.unmodifiable(
        raw
            .map(
              (item) => item is Map<String, dynamic>
                  ? '${item['name'] ?? item['label'] ?? item['option_name'] ?? ''}'
                  : '$item',
            )
            .where((item) => item.trim().isNotEmpty),
      ),
    );
  }
  final String name;
  final int quantity;
  final String notes;
  final List<String> modifiers;
}
