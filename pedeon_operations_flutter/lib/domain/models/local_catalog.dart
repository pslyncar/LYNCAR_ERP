class LocalCatalog {
  const LocalCatalog({
    required this.storeName,
    required this.publicSlug,
    required this.categories,
    required this.products,
  });
  factory LocalCatalog.fromJson(Map<String, dynamic> json) {
    final store = json['store'] as Map<String, dynamic>?;
    return LocalCatalog(
      storeName: '${store?['display_name'] ?? 'PedeOn'}',
      publicSlug: '${store?['slug'] ?? ''}',
      categories: (json['categories'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CatalogCategory.fromJson)
          .toList(growable: false),
      products: (json['items'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(CatalogProduct.fromJson)
          .where((item) => item.available)
          .toList(growable: false),
    );
  }
  final String storeName;
  final String publicSlug;
  final List<CatalogCategory> categories;
  final List<CatalogProduct> products;
}

class CatalogCategory {
  const CatalogCategory({required this.id, required this.name});
  factory CatalogCategory.fromJson(Map<String, dynamic> json) =>
      CatalogCategory(id: json['id'] as int, name: '${json['name']}');
  final int id;
  final String name;
}

class CatalogProduct {
  const CatalogProduct({
    required this.id,
    required this.categoryId,
    required this.name,
    required this.description,
    required this.price,
    required this.modifierGroups,
    required this.available,
    required this.enabledChannels,
  });
  factory CatalogProduct.fromJson(Map<String, dynamic> json) => CatalogProduct(
    id: (json['product_id'] ?? json['id']) as int,
    categoryId: json['category_id'] as int?,
    name: '${json['name']}',
    description: '${json['description'] ?? ''}',
    price: double.parse('${json['price']}'),
    available: json['available'] != false,
    enabledChannels: (json['enabled_channels'] as List<dynamic>? ?? const [])
        .map((item) => '$item')
        .toSet(),
    modifierGroups: (json['modifier_groups'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ModifierGroup.fromJson)
        .toList(growable: false),
  );
  final int id;
  final int? categoryId;
  final String name;
  final String description;
  final double price;
  final bool available;
  final Set<String> enabledChannels;
  final List<ModifierGroup> modifierGroups;

  bool isEnabledFor(String channel) =>
      available && enabledChannels.contains(channel);
}

class ModifierGroup {
  const ModifierGroup({
    required this.name,
    required this.minimum,
    required this.maximum,
    required this.options,
  });
  factory ModifierGroup.fromJson(Map<String, dynamic> json) => ModifierGroup(
    name: '${json['name']}',
    minimum: json['minimum_selections'] as int? ?? 0,
    maximum: json['maximum_selections'] as int?,
    options: (json['options'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ModifierOption.fromJson)
        .toList(growable: false),
  );
  final String name;
  final int minimum;
  final int? maximum;
  final List<ModifierOption> options;
}

class ModifierOption {
  const ModifierOption({
    required this.id,
    required this.name,
    required this.price,
  });
  factory ModifierOption.fromJson(Map<String, dynamic> json) => ModifierOption(
    id: json['id'] as int,
    name: '${json['name']}',
    price: double.parse('${json['price_delta']}'),
  );
  final int id;
  final String name;
  final double price;
}

class StaffCartLine {
  const StaffCartLine({
    required this.product,
    required this.quantity,
    required this.optionIds,
    this.notes = '',
  });
  final CatalogProduct product;
  final int quantity;
  final Set<int> optionIds;
  final String notes;
  double get total =>
      (product.price +
          product.modifierGroups
              .expand((g) => g.options)
              .where((o) => optionIds.contains(o.id))
              .fold<double>(0, (sum, o) => sum + o.price)) *
      quantity;
  Map<String, dynamic> toJson() => {
    'product_id': product.id,
    'quantity': quantity,
    'customer_notes': notes.isEmpty ? null : notes,
    'modifiers': [
      for (final id in optionIds) {'option_id': id, 'quantity': 1},
    ],
  };
}
