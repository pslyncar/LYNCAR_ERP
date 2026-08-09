class ServiceContract {
  const ServiceContract({
    required this.id,
    required this.clientId,
    required this.description,
    required this.valuePerPerson,
    required this.defaultPeopleQuantity,
    required this.billingPeriodicity,
    required this.startDate,
    required this.status,
    required this.active,
    required this.rules,
    required this.consumptionItems,
    this.number,
    this.clientName,
    this.notes,
  });

  final int id;
  final String? number;
  final int clientId;
  final String? clientName;
  final String description;
  final double valuePerPerson;
  final double defaultPeopleQuantity;
  final String billingPeriodicity;
  final String startDate;
  final String status;
  final bool active;
  final String? notes;
  final List<ServiceContractRule> rules;
  final List<ServiceContractConsumptionItem> consumptionItems;

  factory ServiceContract.fromJson(Map<String, dynamic> json) {
    return ServiceContract(
      id: json['id'] as int,
      number: json['number'] as String?,
      clientId: json['client_id'] as int,
      clientName: json['client_name'] as String?,
      description: json['description'] as String,
      valuePerPerson: _toDouble(json['value_per_person']),
      defaultPeopleQuantity: _toDouble(json['default_people_quantity']),
      billingPeriodicity: json['billing_periodicity'] as String? ?? 'quinzenal',
      startDate: json['start_date']?.toString() ?? '',
      status: json['status'] as String? ?? 'active',
      active: json['active'] as bool? ?? true,
      notes: json['notes'] as String?,
      rules: (json['rules'] as List<dynamic>? ?? const [])
          .map((item) => ServiceContractRule.fromJson(item as Map<String, dynamic>))
          .toList(),
      consumptionItems:
          (json['consumption_items'] as List<dynamic>? ?? const [])
              .map(
                (item) => ServiceContractConsumptionItem.fromJson(
                  item as Map<String, dynamic>,
                ),
              )
              .toList(),
    );
  }
}

class ServiceContractRule {
  const ServiceContractRule({
    required this.dayType,
    required this.attends,
    required this.charges,
    required this.multiplier,
    this.id,
    this.notes,
  });

  final int? id;
  final String dayType;
  final bool attends;
  final bool charges;
  final double multiplier;
  final String? notes;

  factory ServiceContractRule.fromJson(Map<String, dynamic> json) {
    return ServiceContractRule(
      id: json['id'] as int?,
      dayType: json['day_type'] as String,
      attends: json['attends'] as bool? ?? true,
      charges: json['charges'] as bool? ?? true,
      multiplier: _toDouble(json['multiplier']),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'day_type': dayType,
      'attends': attends,
      'charges': charges,
      'multiplier': multiplier,
      'notes': _emptyToNull(notes),
    };
  }
}

class ServiceContractConsumptionItem {
  const ServiceContractConsumptionItem({
    required this.productId,
    required this.quantityPerPerson,
    required this.unit,
    required this.wastePercent,
    required this.active,
    this.id,
    this.productName,
    this.notes,
  });

  final int? id;
  final int productId;
  final String? productName;
  final double quantityPerPerson;
  final String unit;
  final double wastePercent;
  final bool active;
  final String? notes;

  factory ServiceContractConsumptionItem.fromJson(Map<String, dynamic> json) {
    return ServiceContractConsumptionItem(
      id: json['id'] as int?,
      productId: json['product_id'] as int,
      productName: json['product_name'] as String?,
      quantityPerPerson: _toDouble(json['quantity_per_person']),
      unit: json['unit'] as String? ?? 'un',
      wastePercent: _toDouble(json['waste_percent']),
      active: json['active'] as bool? ?? true,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'product_id': productId,
      'quantity_per_person': quantityPerPerson,
      'unit': unit,
      'waste_percent': wastePercent,
      'active': active,
      'notes': _emptyToNull(notes),
    };
  }
}

class ServiceAppointment {
  const ServiceAppointment({
    required this.id,
    required this.contractId,
    required this.appointmentDate,
    required this.dayType,
    required this.peopleQuantity,
    required this.valuePerPerson,
    required this.multiplier,
    required this.totalAmount,
    required this.status,
    required this.stockPosted,
    required this.items,
    this.clientName,
    this.notes,
  });

  final int id;
  final int contractId;
  final String? clientName;
  final String appointmentDate;
  final String dayType;
  final double peopleQuantity;
  final double valuePerPerson;
  final double multiplier;
  final double totalAmount;
  final String status;
  final bool stockPosted;
  final String? notes;
  final List<ServiceAppointmentConsumptionItem> items;

  factory ServiceAppointment.fromJson(Map<String, dynamic> json) {
    return ServiceAppointment(
      id: json['id'] as int,
      contractId: json['contract_id'] as int,
      clientName: json['client_name'] as String?,
      appointmentDate: json['appointment_date']?.toString() ?? '',
      dayType: json['day_type'] as String? ?? 'weekday',
      peopleQuantity: _toDouble(json['people_quantity']),
      valuePerPerson: _toDouble(json['value_per_person']),
      multiplier: _toDouble(json['multiplier']),
      totalAmount: _toDouble(json['total_amount']),
      status: json['status'] as String? ?? 'previsto',
      stockPosted: json['stock_posted'] as bool? ?? false,
      notes: json['notes'] as String?,
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => ServiceAppointmentConsumptionItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ServiceAppointmentConsumptionItem {
  const ServiceAppointmentConsumptionItem({
    required this.productId,
    required this.quantityPlanned,
    required this.quantityConfirmed,
    required this.unit,
    this.id,
    this.productName,
    this.notes,
  });

  final int? id;
  final int productId;
  final String? productName;
  final double quantityPlanned;
  final double quantityConfirmed;
  final String unit;
  final String? notes;

  factory ServiceAppointmentConsumptionItem.fromJson(Map<String, dynamic> json) {
    return ServiceAppointmentConsumptionItem(
      id: json['id'] as int?,
      productId: json['product_id'] as int,
      productName: json['product_name'] as String?,
      quantityPlanned: _toDouble(json['quantity_planned']),
      quantityConfirmed: _toDouble(json['quantity_confirmed']),
      unit: json['unit'] as String? ?? 'un',
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'product_id': productId,
      'quantity_planned': quantityPlanned,
      'quantity_confirmed': quantityConfirmed,
      'unit': unit,
      'notes': _emptyToNull(notes),
    };
  }
}

class ServiceBilling {
  const ServiceBilling({
    required this.id,
    required this.contractId,
    required this.periodStart,
    required this.periodEnd,
    required this.totalAmount,
    required this.status,
    required this.generatedAt,
    required this.items,
    this.number,
    this.receivableId,
  });

  final int id;
  final String? number;
  final int contractId;
  final int? receivableId;
  final String periodStart;
  final String periodEnd;
  final double totalAmount;
  final String status;
  final String generatedAt;
  final List<ServiceBillingItem> items;

  factory ServiceBilling.fromJson(Map<String, dynamic> json) {
    return ServiceBilling(
      id: json['id'] as int,
      number: json['number'] as String?,
      contractId: json['contract_id'] as int,
      receivableId: json['receivable_id'] as int?,
      periodStart: json['period_start']?.toString() ?? '',
      periodEnd: json['period_end']?.toString() ?? '',
      totalAmount: _toDouble(json['total_amount']),
      status: json['status'] as String? ?? 'generated',
      generatedAt: json['generated_at']?.toString() ?? '',
      items: (json['items'] as List<dynamic>? ?? const [])
          .map((item) => ServiceBillingItem.fromJson(item as Map<String, dynamic>))
          .toList(),
    );
  }
}

class ServiceBillingItem {
  const ServiceBillingItem({
    required this.id,
    required this.itemDate,
    required this.description,
    required this.peopleQuantity,
    required this.unitPrice,
    required this.multiplier,
    required this.totalAmount,
    this.appointmentId,
  });

  final int id;
  final int? appointmentId;
  final String itemDate;
  final String description;
  final double peopleQuantity;
  final double unitPrice;
  final double multiplier;
  final double totalAmount;

  factory ServiceBillingItem.fromJson(Map<String, dynamic> json) {
    return ServiceBillingItem(
      id: json['id'] as int,
      appointmentId: json['appointment_id'] as int?,
      itemDate: json['item_date']?.toString() ?? '',
      description: json['description']?.toString() ?? '',
      peopleQuantity: _toDouble(json['people_quantity']),
      unitPrice: _toDouble(json['unit_price']),
      multiplier: _toDouble(json['multiplier']),
      totalAmount: _toDouble(json['total_amount']),
    );
  }
}

class ServiceContractPayload {
  ServiceContractPayload({
    required this.clientId,
    required this.description,
    required this.valuePerPerson,
    required this.defaultPeopleQuantity,
    required this.startDate,
    required this.active,
    required this.rules,
    required this.consumptionItems,
    this.status = 'active',
    this.notes,
  });

  final int clientId;
  final String description;
  final double valuePerPerson;
  final double defaultPeopleQuantity;
  final String startDate;
  final String status;
  final bool active;
  final String? notes;
  final List<ServiceContractRule> rules;
  final List<ServiceContractConsumptionItem> consumptionItems;

  Map<String, dynamic> toJson() {
    return {
      'client_id': clientId,
      'description': description.trim(),
      'value_per_person': valuePerPerson,
      'default_people_quantity': defaultPeopleQuantity,
      'billing_periodicity': 'quinzenal',
      'start_date': startDate,
      'status': status,
      'active': active,
      'notes': _emptyToNull(notes),
      'rules': rules.map((rule) => rule.toJson()).toList(),
      'consumption_items': consumptionItems.map((item) => item.toJson()).toList(),
    };
  }
}

double _toDouble(Object? value) {
  if (value == null) return 0;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString()) ?? 0;
}

String? _emptyToNull(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  return trimmed;
}
