class PedeOnOrderSummary {
  const PedeOnOrderSummary({
    required this.id,
    required this.publicId,
    required this.displayNumber,
    required this.sourceChannel,
    required this.status,
    required this.paymentStatus,
    required this.fulfillmentType,
    required this.customerName,
    required this.customerPhone,
    required this.total,
    required this.createdAt,
    this.externalOrderId,
  });

  factory PedeOnOrderSummary.fromJson(Map<String, dynamic> json) =>
      PedeOnOrderSummary(
        id: json['id'] as int,
        publicId: json['public_id'] as String,
        displayNumber: json['display_number'] as String,
        sourceChannel: json['source_channel'] as String? ?? 'pedeon',
        externalOrderId: json['external_order_id'] as String?,
        status: json['status'] as String,
        paymentStatus: json['payment_status'] as String,
        fulfillmentType: json['fulfillment_type'] as String,
        customerName: json['customer_name'] as String,
        customerPhone: json['customer_phone'] as String,
        total: _money(json['total']),
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  final int id;
  final String publicId;
  final String displayNumber;
  final String sourceChannel;
  final String? externalOrderId;
  final String status;
  final String paymentStatus;
  final String fulfillmentType;
  final String customerName;
  final String customerPhone;
  final double total;
  final DateTime createdAt;
}

class PedeOnOrderItem {
  const PedeOnOrderItem({
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.total,
    required this.modifiers,
    this.customerNotes,
    this.stationCode,
    this.stationName,
  });
  factory PedeOnOrderItem.fromJson(Map<String, dynamic> json) =>
      PedeOnOrderItem(
        description: json['description'] as String,
        quantity: _money(json['quantity']),
        unit: json['unit'] as String,
        unitPrice: _money(json['unit_price']),
        total: _money(json['total']),
        customerNotes: json['customer_notes'] as String?,
        stationCode: json['station_code'] as String?,
        stationName: json['station_name'] as String?,
        modifiers: (json['modifiers'] as List? ?? const [])
            .cast<Map<String, dynamic>>()
            .map(PedeOnOrderItemModifier.fromJson)
            .toList(growable: false),
      );
  final String description;
  final double quantity;
  final String unit;
  final double unitPrice;
  final double total;
  final String? customerNotes;
  final String? stationCode;
  final String? stationName;
  final List<PedeOnOrderItemModifier> modifiers;
}

class PedeOnOrderItemModifier {
  const PedeOnOrderItemModifier({
    required this.groupName,
    required this.optionName,
    required this.quantity,
    required this.unitPrice,
    required this.total,
  });

  factory PedeOnOrderItemModifier.fromJson(Map<String, dynamic> json) =>
      PedeOnOrderItemModifier(
        groupName: json['group_name'] as String,
        optionName: json['option_name'] as String,
        quantity: _money(json['quantity']),
        unitPrice: _money(json['unit_price']),
        total: _money(json['total']),
      );

  final String groupName;
  final String optionName;
  final double quantity;
  final double unitPrice;
  final double total;
}

class PedeOnOrderDetail extends PedeOnOrderSummary {
  const PedeOnOrderDetail({
    required super.id,
    required super.publicId,
    required super.displayNumber,
    required super.sourceChannel,
    required super.status,
    required super.paymentStatus,
    required super.fulfillmentType,
    required super.customerName,
    required super.customerPhone,
    required super.total,
    required super.createdAt,
    required this.subtotal,
    required this.discount,
    required this.deliveryFee,
    required this.items,
    super.externalOrderId,
    this.customerEmail,
    this.customerDocument,
    this.deliveryAddress,
    this.customerNotes,
    this.paymentMethod,
    this.localPaymentMethod,
  });
  factory PedeOnOrderDetail.fromJson(Map<String, dynamic> json) =>
      PedeOnOrderDetail(
        id: json['id'] as int,
        publicId: json['public_id'] as String,
        displayNumber: json['display_number'] as String,
        sourceChannel: json['source_channel'] as String? ?? 'pedeon',
        externalOrderId: json['external_order_id'] as String?,
        status: json['status'] as String,
        paymentStatus: json['payment_status'] as String,
        fulfillmentType: json['fulfillment_type'] as String,
        customerName: json['customer_name'] as String,
        customerPhone: json['customer_phone'] as String,
        total: _money(json['total']),
        createdAt: DateTime.parse(json['created_at'] as String),
        subtotal: _money(json['subtotal']),
        discount: _money(json['discount']),
        deliveryFee: _money(json['delivery_fee']),
        customerEmail: json['customer_email'] as String?,
        customerDocument: json['customer_document'] as String?,
        deliveryAddress: (json['delivery_address'] as Map?)
            ?.cast<String, dynamic>(),
        customerNotes: json['customer_notes'] as String?,
        paymentMethod: json['payment_method'] as String?,
        localPaymentMethod: json['local_payment_method'] as String?,
        items: (json['items'] as List)
            .cast<Map<String, dynamic>>()
            .map(PedeOnOrderItem.fromJson)
            .toList(growable: false),
      );
  final double subtotal;
  final double discount;
  final double deliveryFee;
  final String? customerEmail;
  final String? customerDocument;
  final Map<String, dynamic>? deliveryAddress;
  final String? customerNotes;
  final String? paymentMethod;
  final String? localPaymentMethod;
  final List<PedeOnOrderItem> items;
}

class PedeOnOrderPage {
  const PedeOnOrderPage({
    required this.items,
    required this.page,
    required this.total,
    required this.totalPages,
  });
  factory PedeOnOrderPage.fromJson(Map<String, dynamic> json) =>
      PedeOnOrderPage(
        items: (json['items'] as List)
            .cast<Map<String, dynamic>>()
            .map(PedeOnOrderSummary.fromJson)
            .toList(growable: false),
        page: json['page'] as int,
        total: json['total'] as int,
        totalPages: json['total_pages'] as int,
      );
  final List<PedeOnOrderSummary> items;
  final int page;
  final int total;
  final int totalPages;
}

double _money(Object? value) => double.parse(value.toString());
