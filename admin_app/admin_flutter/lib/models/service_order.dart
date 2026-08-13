class ServiceOrder {
  const ServiceOrder({
    required this.id,
    required this.clientId,
    required this.title,
    required this.status,
    required this.priority,
    required this.requestDescription,
    required this.laborAmount,
    required this.itemsAmount,
    required this.discountAmount,
    required this.totalAmount,
    required this.openedAt,
    required this.createdAt,
    required this.items,
    required this.events,
    this.equipmentId,
    this.ticketId,
    this.assignedUserId,
    this.openedByUserId,
    this.soldByUserId,
    this.number,
    this.serviceType,
    this.receivedEquipment,
    this.waitingReason,
    this.technicalDiagnosis,
    this.servicePerformed,
    this.internalNotes,
    this.scheduledAt,
    this.closedAt,
  });

  final int id;
  final int clientId;
  final int? equipmentId;
  final int? ticketId;
  final int? assignedUserId;
  final int? openedByUserId;
  final int? soldByUserId;
  final String? number;
  final String title;
  final String status;
  final String priority;
  final String? serviceType;
  final String? receivedEquipment;
  final String? waitingReason;
  final String requestDescription;
  final String? technicalDiagnosis;
  final String? servicePerformed;
  final String? internalNotes;
  final double laborAmount;
  final double itemsAmount;
  final double discountAmount;
  final double totalAmount;
  final DateTime openedAt;
  final DateTime? scheduledAt;
  final DateTime? closedAt;
  final DateTime createdAt;
  final List<ServiceOrderItem> items;
  final List<ServiceOrderEvent> events;

  factory ServiceOrder.fromJson(Map<String, dynamic> json) {
    return ServiceOrder(
      id: json['id'] as int,
      clientId: json['client_id'] as int,
      equipmentId: json['equipment_id'] as int?,
      ticketId: json['ticket_id'] as int?,
      assignedUserId: json['assigned_user_id'] as int?,
      openedByUserId: json['opened_by_user_id'] as int?,
      soldByUserId: json['sold_by_user_id'] as int?,
      number: json['number'] as String?,
      title: json['title'] as String,
      status: json['status'] as String,
      priority: json['priority'] as String,
      serviceType: json['service_type'] as String?,
      receivedEquipment: json['received_equipment'] as String?,
      waitingReason: json['waiting_reason'] as String?,
      requestDescription: json['request_description'] as String,
      technicalDiagnosis: json['technical_diagnosis'] as String?,
      servicePerformed: json['service_performed'] as String?,
      internalNotes: json['internal_notes'] as String?,
      laborAmount: _toDouble(json['labor_amount']),
      itemsAmount: _toDouble(json['items_amount']),
      discountAmount: _toDouble(json['discount_amount']),
      totalAmount: _toDouble(json['total_amount']),
      openedAt: DateTime.parse(json['opened_at'] as String),
      scheduledAt: json['scheduled_at'] == null
          ? null
          : DateTime.parse(json['scheduled_at'] as String),
      closedAt: json['closed_at'] == null
          ? null
          : DateTime.parse(json['closed_at'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
      items: (json['items'] as List<dynamic>? ?? [])
          .map(
            (item) => ServiceOrderItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      events: (json['events'] as List<dynamic>? ?? [])
          .map(
            (item) => ServiceOrderEvent.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
    );
  }

  static double _toDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }
}

class ServiceOrderEvent {
  const ServiceOrderEvent({
    required this.id,
    required this.serviceOrderId,
    required this.eventType,
    required this.createdAt,
    this.userId,
    this.userName,
    this.statusFrom,
    this.statusTo,
    this.assignedUserId,
    this.assignedUserName,
    this.assignedUserCode,
    this.notes,
  });

  final int id;
  final int serviceOrderId;
  final int? userId;
  final String? userName;
  final String eventType;
  final String? statusFrom;
  final String? statusTo;
  final int? assignedUserId;
  final String? assignedUserName;
  final String? assignedUserCode;
  final String? notes;
  final DateTime createdAt;

  factory ServiceOrderEvent.fromJson(Map<String, dynamic> json) {
    return ServiceOrderEvent(
      id: json['id'] as int,
      serviceOrderId: json['service_order_id'] as int,
      userId: json['user_id'] as int?,
      userName: json['user_name'] as String?,
      eventType: json['event_type'] as String,
      statusFrom: json['status_from'] as String?,
      statusTo: json['status_to'] as String?,
      assignedUserId: json['assigned_user_id'] as int?,
      assignedUserName: json['assigned_user_name'] as String?,
      assignedUserCode: json['assigned_user_code'] as String?,
      notes: json['notes'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ServiceOrderItem {
  const ServiceOrderItem({
    required this.id,
    required this.serviceOrderId,
    required this.description,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    required this.createdAt,
    this.productId,
  });

  final int id;
  final int serviceOrderId;
  final int? productId;
  final String description;
  final double quantity;
  final double unitPrice;
  final double totalPrice;
  final DateTime createdAt;

  factory ServiceOrderItem.fromJson(Map<String, dynamic> json) {
    return ServiceOrderItem(
      id: json['id'] as int,
      serviceOrderId: json['service_order_id'] as int,
      productId: json['product_id'] as int?,
      description: json['description'] as String,
      quantity: ServiceOrder._toDouble(json['quantity']),
      unitPrice: ServiceOrder._toDouble(json['unit_price']),
      totalPrice: ServiceOrder._toDouble(json['total_price']),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ServiceOrderPayload {
  const ServiceOrderPayload({
    required this.clientId,
    required this.title,
    required this.status,
    required this.priority,
    required this.requestDescription,
    required this.laborAmount,
    required this.discountAmount,
    this.equipmentId,
    this.number,
    this.serviceType,
    this.receivedEquipment,
    this.waitingReason,
    this.technicalDiagnosis,
    this.servicePerformed,
    this.internalNotes,
    this.scheduledAt,
  });

  final int clientId;
  final int? equipmentId;
  final String? number;
  final String title;
  final String status;
  final String priority;
  final String? serviceType;
  final String? receivedEquipment;
  final String? waitingReason;
  final String requestDescription;
  final String? technicalDiagnosis;
  final String? servicePerformed;
  final String? internalNotes;
  final double laborAmount;
  final double discountAmount;
  final DateTime? scheduledAt;

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'equipment_id': equipmentId,
      'number': _emptyToNull(number),
      'title': title.trim(),
      'status': status,
      'priority': priority,
      'service_type': _emptyToNull(serviceType),
      'received_equipment': _emptyToNull(receivedEquipment),
      'waiting_reason': _emptyToNull(waitingReason),
      'request_description': requestDescription.trim(),
      'technical_diagnosis': _emptyToNull(technicalDiagnosis),
      'service_performed': _emptyToNull(servicePerformed),
      'internal_notes': _emptyToNull(internalNotes),
      'labor_amount': laborAmount,
      'discount_amount': discountAmount,
      'scheduled_at': scheduledAt?.toUtc().toIso8601String(),
    };
  }
}

class ServiceOrderItemPayload {
  const ServiceOrderItemPayload({
    required this.description,
    required this.quantity,
    required this.unitPrice,
    this.productId,
  });

  final int? productId;
  final String description;
  final double quantity;
  final double unitPrice;

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'description': description.trim(),
      'quantity': quantity,
      'unit_price': unitPrice,
    };
  }
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
