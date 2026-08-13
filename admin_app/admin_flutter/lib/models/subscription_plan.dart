class SubscriptionPlan {
  const SubscriptionPlan({
    required this.id,
    required this.code,
    required this.name,
    this.monthlyPrice,
    this.annualPrice,
    this.maxUsers,
    required this.databaseLimitMb,
    required this.fileLimitMb,
    this.multiCompanyLimit,
    this.marketplaceListingLimit,
    required this.apiEnabled,
    required this.prioritySupport,
    required this.defaultModules,
    required this.active,
    required this.sortOrder,
  });

  final int id;
  final String code;
  final String name;
  final String? monthlyPrice;
  final String? annualPrice;
  final int? maxUsers;
  final int databaseLimitMb;
  final int fileLimitMb;
  final int? multiCompanyLimit;
  final int? marketplaceListingLimit;
  final bool apiEnabled;
  final bool prioritySupport;
  final List<String> defaultModules;
  final bool active;
  final int sortOrder;

  factory SubscriptionPlan.fromJson(Map<String, dynamic> json) {
    return SubscriptionPlan(
      id: json['id'] as int,
      code: json['code'] as String,
      name: json['name'] as String,
      monthlyPrice: json['monthly_price'] as String?,
      annualPrice: json['annual_price'] as String?,
      maxUsers: json['max_users'] as int?,
      databaseLimitMb: json['database_limit_mb'] as int,
      fileLimitMb: json['file_limit_mb'] as int,
      multiCompanyLimit: json['multi_company_limit'] as int?,
      marketplaceListingLimit: json['marketplace_listing_limit'] as int?,
      apiEnabled: json['api_enabled'] as bool? ?? false,
      prioritySupport: json['priority_support'] as bool? ?? false,
      defaultModules: (json['default_modules'] as List<dynamic>? ?? const [])
          .map((item) => item.toString())
          .toList(growable: false),
      active: json['active'] as bool? ?? true,
      sortOrder: json['sort_order'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toUpdateJson() {
    return {
      'name': name,
      'monthly_price': monthlyPrice,
      'annual_price': annualPrice,
      'max_users': maxUsers,
      'database_limit_mb': databaseLimitMb,
      'file_limit_mb': fileLimitMb,
      'multi_company_limit': multiCompanyLimit,
      'marketplace_listing_limit': marketplaceListingLimit,
      'api_enabled': apiEnabled,
      'priority_support': prioritySupport,
      'default_modules': defaultModules,
      'active': active,
      'sort_order': sortOrder,
    };
  }

  Map<String, dynamic> toCreateJson() {
    return {'code': code, ...toUpdateJson()};
  }
}
