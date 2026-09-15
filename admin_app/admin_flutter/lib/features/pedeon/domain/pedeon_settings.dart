class PedeOnStoreSettings {
  const PedeOnStoreSettings({
    required this.id,
    required this.publicSlug,
    required this.displayName,
    required this.description,
    this.logoUrl,
    this.coverUrl,
    this.accentColor = '#075E6F',
    this.darkMode = false,
    required this.active,
    required this.acceptingOrders,
    required this.acceptanceMode,
    this.experienceMode = 'food_service',
    this.businessSegment = 'other',
    this.defaultFulfillmentMode = 'preparation',
    this.productionPrintPolicy = 'manual',
    this.inventoryPolicy = 'warn_allow',
    required this.fulfillmentOptions,
    required this.minimumOrderAmount,
  });

  final int id;
  final String publicSlug;
  final String displayName;
  final String description;
  final String? logoUrl;
  final String? coverUrl;
  final String accentColor;
  final bool darkMode;
  final bool active;
  final bool acceptingOrders;
  final String acceptanceMode;
  final String experienceMode;
  final String businessSegment;
  final String defaultFulfillmentMode;
  final String productionPrintPolicy;
  final String inventoryPolicy;
  final List<String> fulfillmentOptions;
  final double minimumOrderAmount;

  factory PedeOnStoreSettings.fromJson(Map<String, dynamic> json) =>
      PedeOnStoreSettings(
        id: json['id'] as int,
        publicSlug: json['public_slug'] as String,
        displayName: json['display_name'] as String,
        description: json['description']?.toString() ?? '',
        logoUrl: json['logo_url']?.toString(),
        coverUrl: json['cover_url']?.toString(),
        accentColor: json['accent_color']?.toString() ?? '#075E6F',
        darkMode: json['dark_mode'] as bool? ?? false,
        active: json['active'] as bool? ?? false,
        acceptingOrders: json['accepting_orders'] as bool? ?? false,
        acceptanceMode: json['acceptance_mode']?.toString() ?? 'manual',
        experienceMode: json['experience_mode']?.toString() ?? 'food_service',
        businessSegment: json['business_segment']?.toString() ?? 'other',
        defaultFulfillmentMode:
            json['default_fulfillment_mode']?.toString() ?? 'preparation',
        productionPrintPolicy:
            json['production_print_policy']?.toString() ?? 'manual',
        inventoryPolicy: json['inventory_policy']?.toString() ?? 'warn_allow',
        fulfillmentOptions: (json['fulfillment_options'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        minimumOrderAmount:
            double.tryParse(json['minimum_order_amount'].toString()) ?? 0,
      );

  Map<String, dynamic> toJson() => {
    'public_slug': publicSlug,
    'display_name': displayName,
    'description': description.trim().isEmpty ? null : description.trim(),
    'logo_url': logoUrl,
    'cover_url': coverUrl,
    'accent_color': accentColor,
    'dark_mode': darkMode,
    'active': active,
    'accepting_orders': acceptingOrders,
    'acceptance_mode': acceptanceMode,
    'experience_mode': experienceMode,
    'business_segment': businessSegment,
    'default_fulfillment_mode': defaultFulfillmentMode,
    'production_print_policy': productionPrintPolicy,
    'inventory_policy': inventoryPolicy,
    'fulfillment_options': fulfillmentOptions,
    'minimum_order_amount': minimumOrderAmount,
  };

  PedeOnStoreSettings copyWith({
    String? publicSlug,
    String? displayName,
    String? description,
    String? logoUrl,
    String? coverUrl,
    String? accentColor,
    bool? darkMode,
    bool? active,
    bool? acceptingOrders,
    String? acceptanceMode,
    String? experienceMode,
    String? businessSegment,
    String? defaultFulfillmentMode,
    String? productionPrintPolicy,
    String? inventoryPolicy,
    List<String>? fulfillmentOptions,
    double? minimumOrderAmount,
  }) => PedeOnStoreSettings(
    id: id,
    publicSlug: publicSlug ?? this.publicSlug,
    displayName: displayName ?? this.displayName,
    description: description ?? this.description,
    logoUrl: logoUrl ?? this.logoUrl,
    coverUrl: coverUrl ?? this.coverUrl,
    accentColor: accentColor ?? this.accentColor,
    darkMode: darkMode ?? this.darkMode,
    active: active ?? this.active,
    acceptingOrders: acceptingOrders ?? this.acceptingOrders,
    acceptanceMode: acceptanceMode ?? this.acceptanceMode,
    experienceMode: experienceMode ?? this.experienceMode,
    businessSegment: businessSegment ?? this.businessSegment,
    defaultFulfillmentMode:
        defaultFulfillmentMode ?? this.defaultFulfillmentMode,
    productionPrintPolicy: productionPrintPolicy ?? this.productionPrintPolicy,
    inventoryPolicy: inventoryPolicy ?? this.inventoryPolicy,
    fulfillmentOptions: fulfillmentOptions ?? this.fulfillmentOptions,
    minimumOrderAmount: minimumOrderAmount ?? this.minimumOrderAmount,
  );
}

class PedeOnManualPixSettings {
  const PedeOnManualPixSettings({
    required this.enabled,
    required this.pickupEnabled,
    required this.deliveryEnabled,
    required this.keyType,
    required this.pixKey,
    required this.recipientName,
    required this.instructions,
  });

  final bool enabled;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final String keyType;
  final String pixKey;
  final String recipientName;
  final String instructions;

  factory PedeOnManualPixSettings.fromJson(Map<String, dynamic> json) =>
      PedeOnManualPixSettings(
        enabled: json['enabled'] as bool? ?? false,
        pickupEnabled: json['pickup_enabled'] as bool? ?? true,
        deliveryEnabled: json['delivery_enabled'] as bool? ?? true,
        keyType: json['key_type']?.toString() ?? 'random',
        pixKey: json['pix_key']?.toString() ?? '',
        recipientName: json['recipient_name']?.toString() ?? '',
        instructions: json['instructions']?.toString() ?? '',
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'pickup_enabled': pickupEnabled,
    'delivery_enabled': deliveryEnabled,
    'key_type': keyType,
    'pix_key': pixKey,
    'recipient_name': recipientName,
    'instructions': instructions.trim().isEmpty ? null : instructions.trim(),
  };

  PedeOnManualPixSettings copyWith({
    bool? enabled,
    bool? pickupEnabled,
    bool? deliveryEnabled,
    String? keyType,
    String? pixKey,
    String? recipientName,
    String? instructions,
  }) => PedeOnManualPixSettings(
    enabled: enabled ?? this.enabled,
    pickupEnabled: pickupEnabled ?? this.pickupEnabled,
    deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
    keyType: keyType ?? this.keyType,
    pixKey: pixKey ?? this.pixKey,
    recipientName: recipientName ?? this.recipientName,
    instructions: instructions ?? this.instructions,
  );
}

class PedeOnInfinitePaySettings {
  const PedeOnInfinitePaySettings({
    required this.enabled,
    required this.pickupEnabled,
    required this.deliveryEnabled,
    required this.handle,
    required this.autoAcceptAfterConfirmation,
  });

  final bool enabled;
  final bool pickupEnabled;
  final bool deliveryEnabled;
  final String handle;
  final bool autoAcceptAfterConfirmation;

  factory PedeOnInfinitePaySettings.fromJson(Map<String, dynamic> json) =>
      PedeOnInfinitePaySettings(
        enabled: json['enabled'] as bool? ?? false,
        pickupEnabled: json['pickup_enabled'] as bool? ?? true,
        deliveryEnabled: json['delivery_enabled'] as bool? ?? true,
        handle: json['handle']?.toString() ?? '',
        autoAcceptAfterConfirmation:
            json['auto_accept_after_confirmation'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'pickup_enabled': pickupEnabled,
    'delivery_enabled': deliveryEnabled,
    'handle': handle,
    'auto_accept_after_confirmation': autoAcceptAfterConfirmation,
  };

  PedeOnInfinitePaySettings copyWith({
    bool? enabled,
    bool? pickupEnabled,
    bool? deliveryEnabled,
    String? handle,
    bool? autoAcceptAfterConfirmation,
  }) => PedeOnInfinitePaySettings(
    enabled: enabled ?? this.enabled,
    pickupEnabled: pickupEnabled ?? this.pickupEnabled,
    deliveryEnabled: deliveryEnabled ?? this.deliveryEnabled,
    handle: handle ?? this.handle,
    autoAcceptAfterConfirmation:
        autoAcceptAfterConfirmation ?? this.autoAcceptAfterConfirmation,
  );
}

class PedeOnDeliveryCardSettings {
  const PedeOnDeliveryCardSettings({
    required this.cashEnabled,
    required this.pixEnabled,
    required this.creditEnabled,
    required this.debitEnabled,
  });
  factory PedeOnDeliveryCardSettings.fromJson(Map<String, dynamic> json) =>
      PedeOnDeliveryCardSettings(
        cashEnabled: json['cash_enabled'] as bool? ?? false,
        pixEnabled: json['pix_enabled'] as bool? ?? false,
        creditEnabled: json['credit_enabled'] as bool? ?? false,
        debitEnabled: json['debit_enabled'] as bool? ?? false,
      );
  final bool cashEnabled;
  final bool pixEnabled;
  final bool creditEnabled;
  final bool debitEnabled;
  Map<String, dynamic> toJson() => {
    'cash_enabled': cashEnabled,
    'pix_enabled': pixEnabled,
    'credit_enabled': creditEnabled,
    'debit_enabled': debitEnabled,
  };
  PedeOnDeliveryCardSettings copyWith({
    bool? cashEnabled,
    bool? pixEnabled,
    bool? creditEnabled,
    bool? debitEnabled,
  }) => PedeOnDeliveryCardSettings(
    cashEnabled: cashEnabled ?? this.cashEnabled,
    pixEnabled: pixEnabled ?? this.pixEnabled,
    creditEnabled: creditEnabled ?? this.creditEnabled,
    debitEnabled: debitEnabled ?? this.debitEnabled,
  );
}

class PedeOnPickupPaymentSettings {
  const PedeOnPickupPaymentSettings({
    required this.enabled,
    required this.acceptedMethods,
  });

  final bool enabled;
  final List<String> acceptedMethods;

  factory PedeOnPickupPaymentSettings.fromJson(Map<String, dynamic> json) =>
      PedeOnPickupPaymentSettings(
        enabled: json['enabled'] as bool? ?? false,
        acceptedMethods:
            (json['accepted_methods'] as List<dynamic>? ??
                    const ['cash', 'pix', 'credit_card', 'debit_card'])
                .map((e) => '$e')
                .toList(growable: false),
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'accepted_methods': acceptedMethods,
  };

  PedeOnPickupPaymentSettings copyWith({
    bool? enabled,
    List<String>? acceptedMethods,
  }) => PedeOnPickupPaymentSettings(
    enabled: enabled ?? this.enabled,
    acceptedMethods: acceptedMethods ?? this.acceptedMethods,
  );
}

class PedeOnTerminalSettings {
  const PedeOnTerminalSettings({
    required this.terminalId,
    required this.cashRegisterNumber,
    required this.deviceLabel,
    required this.appVersion,
    required this.terminalActive,
    required this.enabled,
    required this.capabilities,
    required this.notificationMode,
    required this.priority,
  });

  final int terminalId;
  final String cashRegisterNumber;
  final String deviceLabel;
  final String appVersion;
  final bool terminalActive;
  final bool enabled;
  final List<String> capabilities;
  final String notificationMode;
  final int priority;

  factory PedeOnTerminalSettings.fromJson(Map<String, dynamic> json) =>
      PedeOnTerminalSettings(
        terminalId: json['terminal_id'] as int,
        cashRegisterNumber: json['cash_register_number']?.toString() ?? '-',
        deviceLabel: json['device_label']?.toString() ?? 'Terminal sem nome',
        appVersion: json['app_version']?.toString() ?? '-',
        terminalActive: json['terminal_active'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? false,
        capabilities: (json['capabilities'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        notificationMode: json['notification_mode']?.toString() ?? 'badge',
        priority: json['priority'] as int? ?? 100,
      );

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'capabilities': capabilities,
    'notification_mode': notificationMode,
    'priority': priority,
  };

  PedeOnTerminalSettings copyWith({
    bool? enabled,
    List<String>? capabilities,
    String? notificationMode,
    int? priority,
  }) => PedeOnTerminalSettings(
    terminalId: terminalId,
    cashRegisterNumber: cashRegisterNumber,
    deviceLabel: deviceLabel,
    appVersion: appVersion,
    terminalActive: terminalActive,
    enabled: enabled ?? this.enabled,
    capabilities: capabilities ?? this.capabilities,
    notificationMode: notificationMode ?? this.notificationMode,
    priority: priority ?? this.priority,
  );
}

class PedeOnDeliveryZone {
  const PedeOnDeliveryZone({
    this.id,
    required this.name,
    required this.matchType,
    this.postalCodePrefix = '',
    this.neighborhood = '',
    this.city = '',
    this.state = '',
    this.centerLatitude,
    this.centerLongitude,
    this.radiusKm,
    this.feeAmount = 0,
    this.minimumOrderAmount = 0,
    this.freeDeliveryThreshold,
    this.estimatedMinutesMin,
    this.estimatedMinutesMax,
    this.sortOrder = 0,
    this.active = true,
  });

  final int? id;
  final String name;
  final String matchType;
  final String postalCodePrefix;
  final String neighborhood;
  final String city;
  final String state;
  final double? centerLatitude;
  final double? centerLongitude;
  final double? radiusKm;
  final double feeAmount;
  final double minimumOrderAmount;
  final double? freeDeliveryThreshold;
  final int? estimatedMinutesMin;
  final int? estimatedMinutesMax;
  final int sortOrder;
  final bool active;

  factory PedeOnDeliveryZone.fromJson(Map<String, dynamic> json) =>
      PedeOnDeliveryZone(
        id: json['id'] as int?,
        name: json['name']?.toString() ?? '',
        matchType: json['match_type']?.toString() ?? 'postal_code_prefix',
        postalCodePrefix: json['postal_code_prefix']?.toString() ?? '',
        neighborhood: json['neighborhood']?.toString() ?? '',
        city: json['city']?.toString() ?? '',
        state: json['state']?.toString() ?? '',
        centerLatitude: json['center_latitude'] == null
            ? null
            : double.tryParse(json['center_latitude'].toString()),
        centerLongitude: json['center_longitude'] == null
            ? null
            : double.tryParse(json['center_longitude'].toString()),
        radiusKm: json['radius_km'] == null
            ? null
            : double.tryParse(json['radius_km'].toString()),
        feeAmount: double.tryParse(json['fee_amount'].toString()) ?? 0,
        minimumOrderAmount:
            double.tryParse(json['minimum_order_amount'].toString()) ?? 0,
        freeDeliveryThreshold: json['free_delivery_threshold'] == null
            ? null
            : double.tryParse(json['free_delivery_threshold'].toString()),
        estimatedMinutesMin: json['estimated_minutes_min'] as int?,
        estimatedMinutesMax: json['estimated_minutes_max'] as int?,
        sortOrder: json['sort_order'] as int? ?? 0,
        active: json['active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'name': name.trim(),
    'match_type': matchType,
    'postal_code_prefix': matchType == 'postal_code_prefix'
        ? postalCodePrefix.replaceAll(RegExp(r'\D'), '')
        : null,
    'neighborhood': matchType == 'neighborhood' ? neighborhood.trim() : null,
    'city': city.trim().isEmpty ? null : city.trim(),
    'state': state.trim().isEmpty ? null : state.trim().toUpperCase(),
    'center_latitude': matchType == 'radius' ? centerLatitude : null,
    'center_longitude': matchType == 'radius' ? centerLongitude : null,
    'radius_km': matchType == 'radius' ? radiusKm : null,
    'fee_amount': feeAmount,
    'minimum_order_amount': minimumOrderAmount,
    'free_delivery_threshold': freeDeliveryThreshold,
    'estimated_minutes_min': estimatedMinutesMin,
    'estimated_minutes_max': estimatedMinutesMax,
    'sort_order': sortOrder,
    'active': active,
  };
}

class PedeOnSettings {
  const PedeOnSettings({
    required this.store,
    required this.manualPix,
    required this.infinitePay,
    required this.deliveryCard,
    required this.pickupPayment,
    required this.terminals,
    this.deliveryZones = const [],
    this.fulfillmentStations = const [],
    required this.deliveryOperation,
  });

  final PedeOnStoreSettings store;
  final PedeOnManualPixSettings manualPix;
  final PedeOnInfinitePaySettings infinitePay;
  final PedeOnDeliveryCardSettings deliveryCard;
  final PedeOnPickupPaymentSettings pickupPayment;
  final List<PedeOnTerminalSettings> terminals;
  final List<PedeOnDeliveryZone> deliveryZones;
  final List<PedeOnFulfillmentStation> fulfillmentStations;
  final PedeOnDeliveryOperation deliveryOperation;

  factory PedeOnSettings.fromJson(Map<String, dynamic> json) {
    final payments = json['payments'] as Map<String, dynamic>;
    return PedeOnSettings(
      store: PedeOnStoreSettings.fromJson(
        json['store'] as Map<String, dynamic>,
      ),
      manualPix: PedeOnManualPixSettings.fromJson(
        payments['manual_pix'] as Map<String, dynamic>,
      ),
      infinitePay: PedeOnInfinitePaySettings.fromJson(
        payments['infinitepay'] as Map<String, dynamic>,
      ),
      deliveryCard: PedeOnDeliveryCardSettings.fromJson(
        (payments['delivery_card'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      pickupPayment: PedeOnPickupPaymentSettings.fromJson(
        (payments['pickup_payment'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
      terminals: (json['terminals'] as List? ?? const [])
          .map(
            (item) =>
                PedeOnTerminalSettings.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      deliveryZones: (json['delivery_zones'] as List? ?? const [])
          .map(
            (item) => PedeOnDeliveryZone.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      fulfillmentStations: (json['fulfillment_stations'] as List? ?? const [])
          .map(
            (item) =>
                PedeOnFulfillmentStation.fromJson(item as Map<String, dynamic>),
          )
          .toList(),
      deliveryOperation: PedeOnDeliveryOperation.fromJson(
        (json['delivery_operation'] as Map?)?.cast<String, dynamic>() ??
            const {},
      ),
    );
  }
}

class PedeOnFulfillmentStation {
  const PedeOnFulfillmentStation({
    this.id,
    required this.code,
    required this.name,
    this.stationType = 'preparation',
    this.sortOrder = 0,
    this.active = true,
  });

  final int? id;
  final String code;
  final String name;
  final String stationType;
  final int sortOrder;
  final bool active;

  factory PedeOnFulfillmentStation.fromJson(Map<String, dynamic> json) =>
      PedeOnFulfillmentStation(
        id: json['id'] as int?,
        code: json['code']?.toString() ?? '',
        name: json['name']?.toString() ?? '',
        stationType: json['station_type']?.toString() ?? 'preparation',
        sortOrder: json['sort_order'] as int? ?? 0,
        active: json['active'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
    'code': code,
    'name': name,
    'station_type': stationType,
    'sort_order': sortOrder,
    'active': active,
  };

  PedeOnFulfillmentStation copyWith({
    String? code,
    String? name,
    String? stationType,
    int? sortOrder,
    bool? active,
  }) => PedeOnFulfillmentStation(
    id: id,
    code: code ?? this.code,
    name: name ?? this.name,
    stationType: stationType ?? this.stationType,
    sortOrder: sortOrder ?? this.sortOrder,
    active: active ?? this.active,
  );
}

class PedeOnBusinessHoursDay {
  const PedeOnBusinessHoursDay({
    this.enabled = false,
    this.openTime = '08:00',
    this.closeTime = '18:00',
  });
  final bool enabled;
  final String openTime;
  final String closeTime;
  factory PedeOnBusinessHoursDay.fromJson(Map<String, dynamic> json) =>
      PedeOnBusinessHoursDay(
        enabled: json['enabled'] as bool? ?? false,
        openTime: json['open_time']?.toString() ?? '08:00',
        closeTime: json['close_time']?.toString() ?? '18:00',
      );
  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'open_time': openTime,
    'close_time': closeTime,
  };
  PedeOnBusinessHoursDay copyWith({
    bool? enabled,
    String? openTime,
    String? closeTime,
  }) => PedeOnBusinessHoursDay(
    enabled: enabled ?? this.enabled,
    openTime: openTime ?? this.openTime,
    closeTime: closeTime ?? this.closeTime,
  );
}

class PedeOnDeliveryOperation {
  PedeOnDeliveryOperation({
    this.pricingMode = 'zones',
    this.fixedFeeAmount = 0,
    this.fixedMinimumOrderAmount = 0,
    this.fixedFreeDeliveryThreshold,
    this.preparationMinutesMin = 20,
    this.preparationMinutesMax = 35,
    this.openingMode = 'manual',
    Map<String, PedeOnBusinessHoursDay>? weeklyHours,
  }) : weeklyHours =
           weeklyHours ??
           {for (final day in weekDays) day: const PedeOnBusinessHoursDay()};

  static const weekDays = [
    'monday',
    'tuesday',
    'wednesday',
    'thursday',
    'friday',
    'saturday',
    'sunday',
  ];
  final String pricingMode;
  final double fixedFeeAmount;
  final double fixedMinimumOrderAmount;
  final double? fixedFreeDeliveryThreshold;
  final int preparationMinutesMin;
  final int preparationMinutesMax;
  final String openingMode;
  final Map<String, PedeOnBusinessHoursDay> weeklyHours;

  factory PedeOnDeliveryOperation.fromJson(Map<String, dynamic> json) {
    final raw =
        (json['weekly_hours'] as Map?)?.cast<String, dynamic>() ?? const {};
    return PedeOnDeliveryOperation(
      pricingMode: json['pricing_mode']?.toString() ?? 'zones',
      fixedFeeAmount: double.tryParse('${json['fixed_fee_amount'] ?? 0}') ?? 0,
      fixedMinimumOrderAmount:
          double.tryParse('${json['fixed_minimum_order_amount'] ?? 0}') ?? 0,
      fixedFreeDeliveryThreshold: json['fixed_free_delivery_threshold'] == null
          ? null
          : double.tryParse('${json['fixed_free_delivery_threshold']}'),
      preparationMinutesMin: json['preparation_minutes_min'] as int? ?? 20,
      preparationMinutesMax: json['preparation_minutes_max'] as int? ?? 35,
      openingMode: json['opening_mode']?.toString() ?? 'manual',
      weeklyHours: {
        for (final day in weekDays)
          day: PedeOnBusinessHoursDay.fromJson(
            (raw[day] as Map?)?.cast<String, dynamic>() ?? const {},
          ),
      },
    );
  }
  Map<String, dynamic> toJson() => {
    'pricing_mode': pricingMode,
    'fixed_fee_amount': fixedFeeAmount,
    'fixed_minimum_order_amount': fixedMinimumOrderAmount,
    'fixed_free_delivery_threshold': fixedFreeDeliveryThreshold,
    'preparation_minutes_min': preparationMinutesMin,
    'preparation_minutes_max': preparationMinutesMax,
    'opening_mode': openingMode,
    'weekly_hours': weeklyHours.map(
      (key, value) => MapEntry(key, value.toJson()),
    ),
  };
  PedeOnDeliveryOperation copyWith({
    String? pricingMode,
    double? fixedFeeAmount,
    double? fixedMinimumOrderAmount,
    double? fixedFreeDeliveryThreshold,
    bool clearFreeThreshold = false,
    int? preparationMinutesMin,
    int? preparationMinutesMax,
    String? openingMode,
    Map<String, PedeOnBusinessHoursDay>? weeklyHours,
  }) => PedeOnDeliveryOperation(
    pricingMode: pricingMode ?? this.pricingMode,
    fixedFeeAmount: fixedFeeAmount ?? this.fixedFeeAmount,
    fixedMinimumOrderAmount:
        fixedMinimumOrderAmount ?? this.fixedMinimumOrderAmount,
    fixedFreeDeliveryThreshold: clearFreeThreshold
        ? null
        : fixedFreeDeliveryThreshold ?? this.fixedFreeDeliveryThreshold,
    preparationMinutesMin: preparationMinutesMin ?? this.preparationMinutesMin,
    preparationMinutesMax: preparationMinutesMax ?? this.preparationMinutesMax,
    openingMode: openingMode ?? this.openingMode,
    weeklyHours: weeklyHours ?? this.weeklyHours,
  );
}

class PedeOnCategory {
  const PedeOnCategory({
    required this.id,
    required this.name,
    required this.slug,
    required this.description,
    required this.active,
    required this.sortOrder,
    this.channel = 'shared',
  });
  final int id;
  final String name;
  final String slug;
  final String description;
  final bool active;
  final int sortOrder;
  final String channel;

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description.trim().isEmpty ? null : description.trim(),
    'active': active,
    'sort_order': sortOrder,
    'channel': channel,
  };

  PedeOnCategory copyWith({
    String? name,
    String? description,
    bool? active,
    String? channel,
  }) => PedeOnCategory(
    id: id,
    name: name ?? this.name,
    slug: slug,
    description: description ?? this.description,
    active: active ?? this.active,
    sortOrder: sortOrder,
    channel: channel ?? this.channel,
  );

  factory PedeOnCategory.fromJson(Map<String, dynamic> json) => PedeOnCategory(
    id: json['id'] as int,
    name: json['name']?.toString() ?? '',
    slug: json['slug']?.toString() ?? '',
    description: json['description']?.toString() ?? '',
    active: json['active'] as bool? ?? true,
    sortOrder: json['sort_order'] as int? ?? 0,
    channel: json['channel']?.toString() ?? 'shared',
  );
}

class PedeOnModifierOption {
  const PedeOnModifierOption({
    this.id,
    required this.name,
    required this.priceDelta,
    this.productId,
    this.active = true,
    this.minimumQuantity = 1,
    this.maximumQuantity = 1,
  });
  final int? id;
  final String name;
  final double priceDelta;
  final int? productId;
  final bool active;
  final int minimumQuantity;
  final int? maximumQuantity;

  factory PedeOnModifierOption.fromJson(Map<String, dynamic> json) =>
      PedeOnModifierOption(
        id: json['id'] as int?,
        name: json['name']?.toString() ?? '',
        priceDelta: double.tryParse(json['price_delta'].toString()) ?? 0,
        productId: json['product_id'] as int?,
        active: json['active'] as bool? ?? true,
        minimumQuantity: json['minimum_quantity'] as int? ?? 1,
        maximumQuantity: json['maximum_quantity'] as int?,
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'price_delta': priceDelta,
    'product_id': productId,
    'active': active,
    'minimum_quantity': minimumQuantity,
    'maximum_quantity': maximumQuantity,
  };
}

class PedeOnModifierGroup {
  const PedeOnModifierGroup({
    this.id,
    required this.name,
    required this.minimumSelections,
    required this.maximumSelections,
    required this.options,
    this.description = '',
    this.active = true,
    this.channel = 'shared',
    this.kind = 'complement',
  });
  final int? id;
  final String name;
  final String description;
  final int minimumSelections;
  final int? maximumSelections;
  final bool active;
  final List<PedeOnModifierOption> options;
  final String channel;
  final String kind;

  PedeOnModifierGroup copyWith({String? channel, String? kind}) =>
      PedeOnModifierGroup(
        id: id,
        name: name,
        description: description,
        minimumSelections: minimumSelections,
        maximumSelections: maximumSelections,
        options: options,
        active: active,
        channel: channel ?? this.channel,
        kind: kind ?? this.kind,
      );

  factory PedeOnModifierGroup.fromJson(Map<String, dynamic> json) =>
      PedeOnModifierGroup(
        id: json['id'] as int?,
        name: json['name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        minimumSelections: json['minimum_selections'] as int? ?? 0,
        maximumSelections: json['maximum_selections'] as int?,
        active: json['active'] as bool? ?? true,
        channel: json['channel']?.toString() ?? 'shared',
        kind: json['kind']?.toString() ?? 'complement',
        options: (json['options'] as List? ?? const [])
            .map(
              (item) =>
                  PedeOnModifierOption.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
      );

  Map<String, dynamic> toJson() => {
    'name': name,
    'description': description.trim().isEmpty ? null : description.trim(),
    'minimum_selections': minimumSelections,
    'maximum_selections': maximumSelections,
    'active': active,
    'options': options.map((option) => option.toJson()).toList(),
    'channel': channel,
    'kind': kind,
  };
}

class PedeOnCatalogProduct {
  const PedeOnCatalogProduct({
    required this.productId,
    required this.publicationId,
    required this.productName,
    required this.internalCode,
    required this.barcode,
    required this.productImageUrl,
    required this.productDescription,
    required this.salePrice,
    required this.offerPrice,
    required this.stockQuantity,
    required this.unit,
    required this.categoryId,
    required this.displayName,
    required this.description,
    required this.imageUrl,
    required this.onlinePrice,
    required this.published,
    required this.available,
    required this.useProductOffer,
    this.fulfillmentMode = 'inherit',
    this.printPolicy = 'inherit',
    this.enabledChannels = const ['pedeon_online'],
    this.publishedChannels = const [],
    this.availableChannels = const [],
    this.productionStationCode = '',
    required this.sortOrder,
    this.modifierGroupIds = const [],
    this.onlineCategoryId,
    this.salonCategoryId,
    this.onlineModifierGroupIds = const [],
    this.salonModifierGroupIds = const [],
  });
  final int productId;
  final int? publicationId;
  final String productName;
  final String internalCode;
  final String barcode;
  final String productImageUrl;
  final String productDescription;
  final double salePrice;
  final double? offerPrice;
  final double stockQuantity;
  final String unit;
  final int? categoryId;
  final String displayName;
  final String description;
  final String imageUrl;
  final double? onlinePrice;
  final bool published;
  final bool available;
  final bool useProductOffer;
  final String fulfillmentMode;
  final String printPolicy;
  final List<String> enabledChannels;
  final List<String> publishedChannels;
  final List<String> availableChannels;
  final String productionStationCode;
  final int sortOrder;
  final List<int> modifierGroupIds;
  final int? onlineCategoryId;
  final int? salonCategoryId;
  final List<int> onlineModifierGroupIds;
  final List<int> salonModifierGroupIds;

  double get effectivePrice =>
      onlinePrice ??
      (useProductOffer && offerPrice != null ? offerPrice! : salePrice);
  String get effectiveName =>
      displayName.trim().isEmpty ? productName : displayName;
  String get effectiveImage =>
      imageUrl.trim().isEmpty ? productImageUrl : imageUrl;

  factory PedeOnCatalogProduct.fromJson(Map<String, dynamic> json) =>
      PedeOnCatalogProduct(
        productId: json['product_id'] as int,
        publicationId: json['publication_id'] as int?,
        productName: json['product_name']?.toString() ?? '',
        internalCode: json['internal_code']?.toString() ?? '',
        barcode: json['barcode']?.toString() ?? '',
        productImageUrl: json['product_image_url']?.toString() ?? '',
        productDescription: json['product_description']?.toString() ?? '',
        salePrice: double.tryParse(json['sale_price'].toString()) ?? 0,
        offerPrice: json['offer_price'] == null
            ? null
            : double.tryParse(json['offer_price'].toString()),
        stockQuantity: double.tryParse(json['stock_quantity'].toString()) ?? 0,
        unit: json['unit']?.toString() ?? 'un',
        categoryId: json['category_id'] as int?,
        onlineCategoryId: json['online_category_id'] as int?,
        salonCategoryId: json['salon_category_id'] as int?,
        displayName: json['display_name']?.toString() ?? '',
        description: json['description']?.toString() ?? '',
        imageUrl: json['image_url']?.toString() ?? '',
        onlinePrice: json['online_price'] == null
            ? null
            : double.tryParse(json['online_price'].toString()),
        published: json['published'] as bool? ?? false,
        available: json['available'] as bool? ?? true,
        useProductOffer: json['use_product_offer'] as bool? ?? true,
        fulfillmentMode: json['fulfillment_mode']?.toString() ?? 'inherit',
        printPolicy: json['print_policy']?.toString() ?? 'inherit',
        enabledChannels:
            (json['enabled_channels'] as List? ?? const ['pedeon_online'])
                .map((item) => item.toString())
                .toList(),
        publishedChannels: (json['published_channels'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        availableChannels: (json['available_channels'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(),
        productionStationCode:
            json['production_station_code']?.toString() ?? '',
        sortOrder: json['sort_order'] as int? ?? 0,
        modifierGroupIds: (json['modifier_group_ids'] as List? ?? const [])
            .whereType<int>()
            .toList(),
        onlineModifierGroupIds:
            (json['online_modifier_group_ids'] as List? ?? const [])
                .whereType<int>()
                .toList(),
        salonModifierGroupIds:
            (json['salon_modifier_group_ids'] as List? ?? const [])
                .whereType<int>()
                .toList(),
      );

  Map<String, dynamic> toJson() => {
    'category_id': categoryId,
    'online_category_id': onlineCategoryId,
    'salon_category_id': salonCategoryId,
    'display_name': displayName.trim().isEmpty ? null : displayName.trim(),
    'description': description.trim().isEmpty ? null : description.trim(),
    'image_url': imageUrl.trim().isEmpty ? null : imageUrl.trim(),
    'online_price': onlinePrice,
    'published': published,
    'available': available,
    'use_product_offer': useProductOffer,
    'fulfillment_mode': fulfillmentMode,
    'print_policy': printPolicy,
    'enabled_channels': enabledChannels,
    'published_channels': publishedChannels,
    'available_channels': availableChannels,
    'production_station_code': productionStationCode.trim().isEmpty
        ? null
        : productionStationCode.trim(),
    'sort_order': sortOrder,
    'modifier_group_ids': modifierGroupIds,
    'online_modifier_group_ids': onlineModifierGroupIds,
    'salon_modifier_group_ids': salonModifierGroupIds,
  };

  PedeOnCatalogProduct copyWith({
    int? categoryId,
    bool clearCategory = false,
    String? displayName,
    String? description,
    String? imageUrl,
    double? onlinePrice,
    bool clearOnlinePrice = false,
    bool? published,
    bool? available,
    bool? useProductOffer,
    String? fulfillmentMode,
    String? printPolicy,
    List<String>? enabledChannels,
    List<String>? publishedChannels,
    List<String>? availableChannels,
    String? productionStationCode,
    int? sortOrder,
    List<int>? modifierGroupIds,
    int? onlineCategoryId,
    int? salonCategoryId,
    List<int>? onlineModifierGroupIds,
    List<int>? salonModifierGroupIds,
  }) => PedeOnCatalogProduct(
    productId: productId,
    publicationId: publicationId,
    productName: productName,
    internalCode: internalCode,
    barcode: barcode,
    productImageUrl: productImageUrl,
    productDescription: productDescription,
    salePrice: salePrice,
    offerPrice: offerPrice,
    stockQuantity: stockQuantity,
    unit: unit,
    categoryId: clearCategory ? null : categoryId ?? this.categoryId,
    displayName: displayName ?? this.displayName,
    description: description ?? this.description,
    imageUrl: imageUrl ?? this.imageUrl,
    onlinePrice: clearOnlinePrice ? null : onlinePrice ?? this.onlinePrice,
    published: published ?? this.published,
    available: available ?? this.available,
    useProductOffer: useProductOffer ?? this.useProductOffer,
    fulfillmentMode: fulfillmentMode ?? this.fulfillmentMode,
    printPolicy: printPolicy ?? this.printPolicy,
    enabledChannels: enabledChannels ?? this.enabledChannels,
    publishedChannels: publishedChannels ?? this.publishedChannels,
    availableChannels: availableChannels ?? this.availableChannels,
    productionStationCode: productionStationCode ?? this.productionStationCode,
    sortOrder: sortOrder ?? this.sortOrder,
    modifierGroupIds: modifierGroupIds ?? this.modifierGroupIds,
    onlineCategoryId: onlineCategoryId ?? this.onlineCategoryId,
    salonCategoryId: salonCategoryId ?? this.salonCategoryId,
    onlineModifierGroupIds:
        onlineModifierGroupIds ?? this.onlineModifierGroupIds,
    salonModifierGroupIds: salonModifierGroupIds ?? this.salonModifierGroupIds,
  );
}

class PedeOnCatalogPage {
  const PedeOnCatalogPage({
    required this.items,
    required this.categories,
    required this.modifierGroups,
    required this.page,
    required this.pageSize,
    required this.total,
    required this.totalPages,
  });
  final List<PedeOnCatalogProduct> items;
  final List<PedeOnCategory> categories;
  final List<PedeOnModifierGroup> modifierGroups;
  final int page;
  final int pageSize;
  final int total;
  final int totalPages;

  factory PedeOnCatalogPage.fromJson(Map<String, dynamic> json) =>
      PedeOnCatalogPage(
        items: (json['items'] as List? ?? const [])
            .map(
              (item) =>
                  PedeOnCatalogProduct.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        categories: (json['categories'] as List? ?? const [])
            .map(
              (item) => PedeOnCategory.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        modifierGroups: (json['modifier_groups'] as List? ?? const [])
            .map(
              (item) =>
                  PedeOnModifierGroup.fromJson(item as Map<String, dynamic>),
            )
            .toList(),
        page: json['page'] as int? ?? 1,
        pageSize: json['page_size'] as int? ?? 20,
        total: json['total'] as int? ?? 0,
        totalPages: json['total_pages'] as int? ?? 1,
      );

  PedeOnCatalogPage copyWith({List<PedeOnCategory>? categories}) =>
      PedeOnCatalogPage(
        items: items,
        categories: categories ?? this.categories,
        modifierGroups: modifierGroups,
        page: page,
        pageSize: pageSize,
        total: total,
        totalPages: totalPages,
      );
}
