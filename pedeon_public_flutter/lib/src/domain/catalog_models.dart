class Storefront {
  const Storefront({
    required this.slug,
    required this.displayName,
    required this.acceptingOrders,
    this.experienceMode = 'food_service',
    required this.fulfillmentOptions,
    required this.minimumOrderAmount,
    this.paymentMethods = const [],
    this.description,
    this.logoUrl,
    this.coverUrl,
    this.accentColor = '#075E6F',
    this.darkMode = false,
    this.deliveryFee,
    this.deliveryMinutesMin,
    this.deliveryMinutesMax,
  });
  factory Storefront.fromJson(Map<String, dynamic> json) => Storefront(
    slug: json['slug'] as String,
    displayName: json['display_name'] as String,
    description: json['description'] as String?,
    logoUrl: json['logo_url'] as String?,
    coverUrl: json['cover_url'] as String?,
    accentColor: json['accent_color']?.toString() ?? '#075E6F',
    darkMode: json['dark_mode'] as bool? ?? false,
    deliveryFee: _nullableMoney(json['delivery_fee']),
    deliveryMinutesMin: json['delivery_minutes_min'] as int?,
    deliveryMinutesMax: json['delivery_minutes_max'] as int?,
    acceptingOrders: json['accepting_orders'] as bool? ?? false,
    experienceMode: json['experience_mode']?.toString() ?? 'food_service',
    fulfillmentOptions: (json['fulfillment_options'] as List? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    minimumOrderAmount: _money(json['minimum_order_amount']),
    paymentMethods: (json['payment_methods'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(PaymentOption.fromJson)
        .toList(growable: false),
  );
  final String slug;
  final String displayName;
  final String? description;
  final String? logoUrl;
  final String? coverUrl;
  final String accentColor;
  final bool darkMode;
  final double? deliveryFee;
  final int? deliveryMinutesMin;
  final int? deliveryMinutesMax;
  final bool acceptingOrders;
  final String experienceMode;
  final List<String> fulfillmentOptions;
  final double minimumOrderAmount;
  final List<PaymentOption> paymentMethods;
}

class PaymentOption {
  const PaymentOption({
    required this.method,
    required this.displayName,
    this.fulfillmentTypes = const [],
    this.localMethods = const [],
  });
  factory PaymentOption.fromJson(Map<String, dynamic> json) => PaymentOption(
    method: json['method'] as String,
    displayName: json['display_name'] as String,
    fulfillmentTypes: (json['fulfillment_types'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
    localMethods: (json['local_methods'] as List<dynamic>? ?? const [])
        .whereType<String>()
        .toList(growable: false),
  );
  final String method;
  final String displayName;
  final List<String> fulfillmentTypes;
  final List<String> localMethods;
}

class CatalogCategory {
  const CatalogCategory({
    required this.id,
    required this.name,
    required this.slug,
  });
  factory CatalogCategory.fromJson(Map<String, dynamic> json) =>
      CatalogCategory(
        id: json['id'] as int,
        name: json['name'] as String,
        slug: json['slug'] as String,
      );
  final int id;
  final String name;
  final String slug;
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.name,
    required this.price,
    required this.normalPrice,
    required this.onOffer,
    required this.available,
    required this.unit,
    this.categoryId,
    this.description,
    this.imageUrl,
    this.modifierGroups = const [],
  });
  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: json['product_id'] as int,
    categoryId: json['category_id'] as int?,
    name: json['name'] as String,
    description: json['description'] as String?,
    imageUrl: json['image_url'] as String?,
    price: _money(json['price']),
    normalPrice: _money(json['normal_price']),
    onOffer: json['on_offer'] as bool? ?? false,
    available: json['available'] as bool? ?? false,
    unit: json['unit'] as String? ?? 'un',
    modifierGroups: (json['modifier_groups'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ModifierGroup.fromJson)
        .toList(growable: false),
  );
  final int id;
  final int? categoryId;
  final String name;
  final String? description;
  final String? imageUrl;
  final double price;
  final double normalPrice;
  final bool onOffer;
  final bool available;
  final String unit;
  final List<ModifierGroup> modifierGroups;
}

class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.name,
    required this.priceDelta,
    this.availableQuantity,
    this.minimumQuantity = 1,
    this.maximumQuantity = 1,
  });

  factory ModifierOption.fromJson(Map<String, dynamic> json) => ModifierOption(
    id: json['id'] as int,
    name: json['name'] as String,
    priceDelta: _money(json['price_delta']),
    availableQuantity: json['available_quantity'] as int?,
    minimumQuantity: json['minimum_quantity'] as int? ?? 1,
    maximumQuantity: json['maximum_quantity'] as int?,
  );

  final int id;
  final String name;
  final double priceDelta;
  final int? availableQuantity;
  final int minimumQuantity;
  final int? maximumQuantity;
}

class ModifierGroup {
  const ModifierGroup({
    required this.id,
    required this.name,
    required this.minimumSelections,
    required this.maximumSelections,
    required this.options,
    this.description,
    this.kind = 'complement',
  });

  factory ModifierGroup.fromJson(Map<String, dynamic> json) => ModifierGroup(
    id: json['id'] as int,
    name: json['name'] as String,
    description: json['description'] as String?,
    minimumSelections: json['minimum_selections'] as int? ?? 0,
    maximumSelections: json['maximum_selections'] as int?,
    options: (json['options'] as List? ?? const [])
        .cast<Map<String, dynamic>>()
        .map(ModifierOption.fromJson)
        .toList(growable: false),
    kind: json['kind']?.toString() ?? 'complement',
  );

  final int id;
  final String name;
  final String? description;
  final int minimumSelections;
  final int? maximumSelections;
  final List<ModifierOption> options;
  final String kind;
}

class CatalogPage {
  const CatalogPage({
    required this.store,
    required this.categories,
    required this.items,
    required this.page,
    required this.totalPages,
  });
  factory CatalogPage.fromJson(Map<String, dynamic> json) => CatalogPage(
    store: Storefront.fromJson(json['store'] as Map<String, dynamic>),
    categories: (json['categories'] as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogCategory.fromJson)
        .toList(growable: false),
    items: (json['items'] as List)
        .cast<Map<String, dynamic>>()
        .map(CatalogProduct.fromJson)
        .toList(growable: false),
    page: json['page'] as int,
    totalPages: json['total_pages'] as int,
  );
  final Storefront store;
  final List<CatalogCategory> categories;
  final List<CatalogProduct> items;
  final int page;
  final int totalPages;
}

class CartLine {
  const CartLine({
    required this.id,
    required this.product,
    required this.quantity,
    this.selectedOptions = const {},
    this.customerNotes,
  });

  final String id;
  final CatalogProduct product;
  final int quantity;
  final Map<int, int> selectedOptions;
  final String? customerNotes;

  double get modifiersUnitTotal =>
      selectedOptions.entries.fold(0, (total, entry) {
        for (final group in product.modifierGroups) {
          for (final option in group.options) {
            if (option.id == entry.key) {
              return total + option.priceDelta * entry.value;
            }
          }
        }
        return total;
      });
  double get unitTotal => product.price + modifiersUnitTotal;
  double get total => unitTotal * quantity;

  Map<String, dynamic> toRequestJson() => {
    'line_id': id,
    'product_id': product.id,
    'quantity': quantity,
    'customer_notes': customerNotes,
    'modifiers': selectedOptions.entries
        .map((entry) => {'option_id': entry.key, 'quantity': entry.value})
        .toList(growable: false),
  };

  List<String> get modifierLabels => [
    for (final group in product.modifierGroups)
      for (final option in group.options)
        if (selectedOptions.containsKey(option.id))
          '${group.name}: ${option.name}'
              '${selectedOptions[option.id] == 1 ? '' : ' × ${selectedOptions[option.id]}'}',
  ];
}

class CartQuote {
  const CartQuote({
    required this.subtotal,
    required this.minimumOrderAmount,
    required this.minimumOrderReached,
    required this.deliveryFee,
    required this.total,
    this.deliveryZoneName,
    this.estimatedMinutesMin,
    this.estimatedMinutesMax,
  });
  factory CartQuote.fromJson(Map<String, dynamic> json) => CartQuote(
    subtotal: _money(json['subtotal']),
    minimumOrderAmount: _money(json['minimum_order_amount']),
    minimumOrderReached: json['minimum_order_reached'] as bool,
    deliveryFee: _money(json['delivery_fee'] ?? 0),
    total: _money(json['total'] ?? json['subtotal']),
    deliveryZoneName: json['delivery_zone_name'] as String?,
    estimatedMinutesMin: json['estimated_minutes_min'] as int?,
    estimatedMinutesMax: json['estimated_minutes_max'] as int?,
  );
  final double subtotal;
  final double minimumOrderAmount;
  final bool minimumOrderReached;
  final double deliveryFee;
  final double total;
  final String? deliveryZoneName;
  final int? estimatedMinutesMin;
  final int? estimatedMinutesMax;
}

class DeliveryAddress {
  const DeliveryAddress({
    required this.postalCode,
    required this.street,
    required this.number,
    required this.neighborhood,
    required this.city,
    required this.state,
    this.complement,
    this.reference,
  });
  final String postalCode;
  final String street;
  final String number;
  final String? complement;
  final String neighborhood;
  final String city;
  final String state;
  final String? reference;

  factory DeliveryAddress.fromJson(Map<String, dynamic> json) =>
      DeliveryAddress(
        postalCode: json['postal_code'] as String? ?? '',
        street: json['street'] as String? ?? '',
        number: json['number'] as String? ?? '',
        complement: json['complement'] as String?,
        neighborhood: json['neighborhood'] as String? ?? '',
        city: json['city'] as String? ?? '',
        state: json['state'] as String? ?? '',
        reference: json['reference'] as String?,
      );
  Map<String, dynamic> toJson() => {
    'postal_code': postalCode,
    'street': street,
    'number': number,
    'complement': complement,
    'neighborhood': neighborhood,
    'city': city,
    'state': state,
    'reference': reference,
  };
}

class CheckoutInput {
  const CheckoutInput({
    required this.idempotencyKey,
    required this.customerName,
    required this.customerPhone,
    required this.fulfillmentType,
    required this.paymentMethod,
    this.customerEmail,
    this.customerDocument,
    this.deliveryAddress,
    this.customerNotes,
    this.localPaymentMethod,
    this.cashChangeFor,
  });
  final String idempotencyKey;
  final String customerName;
  final String customerPhone;
  final String? customerEmail;
  final String? customerDocument;
  final String fulfillmentType;
  final String paymentMethod;
  final DeliveryAddress? deliveryAddress;
  final String? customerNotes;
  final String? localPaymentMethod;
  final String? cashChangeFor;
}

class PublicPayment {
  const PublicPayment({
    required this.method,
    required this.status,
    required this.displayName,
    this.checkoutUrl,
    this.pixKey,
    this.pixKeyType,
    this.recipientName,
    this.instructions,
  });
  factory PublicPayment.fromJson(Map<String, dynamic> json) => PublicPayment(
    method: json['method'] as String,
    status: json['status'] as String,
    displayName: json['display_name'] as String,
    checkoutUrl: json['checkout_url'] as String?,
    pixKey: json['pix_key'] as String?,
    pixKeyType: json['pix_key_type'] as String?,
    recipientName: json['recipient_name'] as String?,
    instructions: json['instructions'] as String?,
  );
  final String method;
  final String status;
  final String displayName;
  final String? checkoutUrl;
  final String? pixKey;
  final String? pixKeyType;
  final String? recipientName;
  final String? instructions;
}

class PublicOrder {
  const PublicOrder({
    required this.orderId,
    required this.trackingToken,
    required this.displayNumber,
    required this.status,
    required this.paymentStatus,
    required this.fulfillmentType,
    required this.customerName,
    required this.subtotal,
    required this.deliveryFee,
    required this.total,
    required this.createdAt,
    required this.payment,
    this.deliveryZoneName,
    this.estimatedMinutesMin,
    this.estimatedMinutesMax,
  });
  factory PublicOrder.fromJson(Map<String, dynamic> json) => PublicOrder(
    orderId: json['order_id'] as String,
    trackingToken: json['tracking_token'] as String,
    displayNumber: json['display_number'] as String,
    status: json['status'] as String,
    paymentStatus: json['payment_status'] as String,
    fulfillmentType: json['fulfillment_type'] as String,
    customerName: json['customer_name'] as String,
    subtotal: _money(json['subtotal']),
    deliveryFee: _money(json['delivery_fee']),
    total: _money(json['total']),
    deliveryZoneName: json['delivery_zone_name'] as String?,
    estimatedMinutesMin: json['estimated_minutes_min'] as int?,
    estimatedMinutesMax: json['estimated_minutes_max'] as int?,
    createdAt: DateTime.parse(json['created_at'] as String),
    payment: PublicPayment.fromJson(json['payment'] as Map<String, dynamic>),
  );
  final String orderId;
  final String trackingToken;
  final String displayNumber;
  final String status;
  final String paymentStatus;
  final String fulfillmentType;
  final String customerName;
  final double subtotal;
  final double deliveryFee;
  final double total;
  final String? deliveryZoneName;
  final int? estimatedMinutesMin;
  final int? estimatedMinutesMax;
  final DateTime createdAt;
  final PublicPayment payment;
}

double _money(Object? value) => double.parse(value.toString());

double? _nullableMoney(Object? value) =>
    value == null ? null : double.tryParse(value.toString());
