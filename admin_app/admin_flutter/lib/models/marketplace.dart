class MercadoLivreStatus {
  const MercadoLivreStatus({
    required this.configured,
    required this.connected,
    required this.message,
    this.accountId,
    this.nickname,
    this.siteId,
    this.expiresAt,
    this.lastSyncAt,
    this.listingLimit,
    required this.enabledListings,
    this.remainingListings,
    required this.pendingJobs,
  });

  final bool configured;
  final bool connected;
  final String message;
  final String? accountId;
  final String? nickname;
  final String? siteId;
  final DateTime? expiresAt;
  final DateTime? lastSyncAt;
  final int? listingLimit;
  final int enabledListings;
  final int? remainingListings;
  final int pendingJobs;

  factory MercadoLivreStatus.fromJson(Map<String, dynamic> json) {
    return MercadoLivreStatus(
      configured: json['configured'] == true,
      connected: json['connected'] == true,
      message: json['message'] as String? ?? '',
      accountId: json['account_id'] as String?,
      nickname: json['nickname'] as String?,
      siteId: json['site_id'] as String?,
      expiresAt: _parseDate(json['expires_at']),
      lastSyncAt: _parseDate(json['last_sync_at']),
      listingLimit: json['listing_limit'] as int?,
      enabledListings: json['enabled_listings'] as int? ?? 0,
      remainingListings: json['remaining_listings'] as int?,
      pendingJobs: json['pending_jobs'] as int? ?? 0,
    );
  }
}

class MercadoLivreAuthUrl {
  const MercadoLivreAuthUrl({required this.authUrl, required this.state});

  final String authUrl;
  final String state;

  factory MercadoLivreAuthUrl.fromJson(Map<String, dynamic> json) {
    return MercadoLivreAuthUrl(
      authUrl: json['auth_url'] as String? ?? '',
      state: json['state'] as String? ?? '',
    );
  }
}

class MarketplaceProduct {
  const MarketplaceProduct({
    required this.productId,
    required this.name,
    required this.salePrice,
    required this.stockQuantity,
    required this.active,
    required this.listing,
    this.internalCode,
    this.barcode,
  });

  final int productId;
  final String name;
  final String? internalCode;
  final String? barcode;
  final double salePrice;
  final double stockQuantity;
  final bool active;
  final ProductMarketplaceListing listing;

  factory MarketplaceProduct.fromJson(Map<String, dynamic> json) {
    return MarketplaceProduct(
      productId: json['product_id'] as int,
      name: json['name'] as String? ?? '',
      internalCode: json['internal_code'] as String?,
      barcode: json['barcode'] as String?,
      salePrice: _toDouble(json['sale_price']),
      stockQuantity: _toDouble(json['stock_quantity']),
      active: json['active'] != false,
      listing: ProductMarketplaceListing.fromJson(
        json['listing'] as Map<String, dynamic>? ?? const {},
      ),
    );
  }
}

class ProductMarketplaceListing {
  const ProductMarketplaceListing({
    required this.productId,
    required this.provider,
    required this.enabled,
    required this.syncStock,
    required this.syncPrice,
    required this.status,
    required this.condition,
    this.id,
    this.listingId,
    this.title,
    this.categoryId,
    this.listingTypeId,
    this.permalink,
    this.lastError,
    this.lastSyncedAt,
  });

  final int? id;
  final int productId;
  final String provider;
  final String? listingId;
  final bool enabled;
  final bool syncStock;
  final bool syncPrice;
  final String status;
  final String? title;
  final String? categoryId;
  final String? listingTypeId;
  final String condition;
  final String? permalink;
  final String? lastError;
  final DateTime? lastSyncedAt;

  factory ProductMarketplaceListing.fromJson(Map<String, dynamic> json) {
    return ProductMarketplaceListing(
      id: json['id'] as int?,
      productId: json['product_id'] as int? ?? 0,
      provider: json['provider'] as String? ?? 'mercado_livre',
      listingId: json['listing_id'] as String?,
      enabled: json['enabled'] == true,
      syncStock: json['sync_stock'] != false,
      syncPrice: json['sync_price'] != false,
      status: json['status'] as String? ?? 'not_configured',
      title: json['title'] as String?,
      categoryId: json['category_id'] as String?,
      listingTypeId: json['listing_type_id'] as String?,
      condition: json['condition'] as String? ?? 'new',
      permalink: json['permalink'] as String?,
      lastError: json['last_error'] as String?,
      lastSyncedAt: _parseDate(json['last_synced_at']),
    );
  }

  Map<String, dynamic> toUpdateJson({
    bool? enabled,
    bool? syncStock,
    bool? syncPrice,
  }) {
    return {
      'enabled': enabled ?? this.enabled,
      'sync_stock': syncStock ?? this.syncStock,
      'sync_price': syncPrice ?? this.syncPrice,
      'title': title,
      'category_id': categoryId,
      'listing_type_id': listingTypeId,
      'condition': condition,
    };
  }
}

class MercadoLivreImportPreview {
  const MercadoLivreImportPreview({
    required this.total,
    required this.offset,
    required this.limit,
    required this.results,
  });

  final int total;
  final int offset;
  final int limit;
  final List<MercadoLivreImportItem> results;

  factory MercadoLivreImportPreview.fromJson(Map<String, dynamic> json) {
    return MercadoLivreImportPreview(
      total: json['total'] as int? ?? 0,
      offset: json['offset'] as int? ?? 0,
      limit: json['limit'] as int? ?? 0,
      results: (json['results'] as List<dynamic>? ?? const [])
          .map(
            (item) =>
                MercadoLivreImportItem.fromJson(item as Map<String, dynamic>),
          )
          .toList(growable: false),
    );
  }
}

class MercadoLivreImportItem {
  const MercadoLivreImportItem({
    required this.listingId,
    required this.title,
    required this.price,
    required this.alreadyLinked,
    this.status,
    this.availableQuantity,
    this.permalink,
    this.thumbnail,
    this.categoryId,
    this.listingTypeId,
    this.condition,
    this.sellerCustomField,
    this.localProductId,
    this.localProductName,
  });

  final String listingId;
  final String title;
  final String? status;
  final double? price;
  final int? availableQuantity;
  final String? permalink;
  final String? thumbnail;
  final String? categoryId;
  final String? listingTypeId;
  final String? condition;
  final String? sellerCustomField;
  final int? localProductId;
  final String? localProductName;
  final bool alreadyLinked;

  factory MercadoLivreImportItem.fromJson(Map<String, dynamic> json) {
    return MercadoLivreImportItem(
      listingId: json['listing_id'] as String? ?? '',
      title: json['title'] as String? ?? '',
      status: json['status'] as String?,
      price: json['price'] == null ? null : _toDouble(json['price']),
      availableQuantity: json['available_quantity'] as int?,
      permalink: json['permalink'] as String?,
      thumbnail: json['thumbnail'] as String?,
      categoryId: json['category_id'] as String?,
      listingTypeId: json['listing_type_id'] as String?,
      condition: json['condition'] as String?,
      sellerCustomField: json['seller_custom_field'] as String?,
      localProductId: json['local_product_id'] as int?,
      localProductName: json['local_product_name'] as String?,
      alreadyLinked: json['already_linked'] == true,
    );
  }
}

double _toDouble(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '') ?? 0;
}

DateTime? _parseDate(Object? value) {
  if (value == null) return null;
  return DateTime.tryParse(value.toString());
}
