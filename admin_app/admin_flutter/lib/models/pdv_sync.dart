import 'client.dart';
import 'product.dart';

class PdvSyncBatch {
  const PdvSyncBatch({
    required this.cursor,
    required this.serverTime,
    required this.products,
    required this.clients,
    required this.deletedProductIds,
    required this.deletedClientIds,
    required this.resetRequired,
    required this.hasMore,
  });

  final int cursor;
  final DateTime serverTime;
  final List<Product> products;
  final List<Client> clients;
  final List<int> deletedProductIds;
  final List<int> deletedClientIds;
  final bool resetRequired;
  final bool hasMore;

  factory PdvSyncBatch.fromJson(Map<String, dynamic> json) {
    return PdvSyncBatch(
      cursor: (json['cursor'] as num?)?.toInt() ?? 0,
      serverTime:
          DateTime.tryParse(json['server_time']?.toString() ?? '') ??
          DateTime.now().toUtc(),
      products: (json['products'] as List<dynamic>? ?? const [])
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      clients: (json['clients'] as List<dynamic>? ?? const [])
          .map((item) => Client.fromJson(item as Map<String, dynamic>))
          .toList(growable: false),
      deletedProductIds:
          (json['deleted_product_ids'] as List<dynamic>? ?? const [])
              .map((value) => (value as num).toInt())
              .toList(growable: false),
      deletedClientIds:
          (json['deleted_client_ids'] as List<dynamic>? ?? const [])
              .map((value) => (value as num).toInt())
              .toList(growable: false),
      resetRequired: json['reset_required'] as bool? ?? false,
      hasMore: json['has_more'] as bool? ?? false,
    );
  }
}

class PdvCatalogState {
  const PdvCatalogState({
    required this.cursor,
    required this.products,
    required this.clients,
  });

  final int cursor;
  final List<Product> products;
  final List<Client> clients;

  PdvCatalogState apply(PdvSyncBatch batch, {required bool replace}) {
    if (replace) {
      return PdvCatalogState(
        cursor: batch.cursor,
        products: _sortedProducts(batch.products),
        clients: _sortedClients(batch.clients),
      );
    }
    final productsById = {for (final item in products) item.id: item};
    for (final id in batch.deletedProductIds) {
      productsById.remove(id);
    }
    for (final item in batch.products) {
      if (item.active) productsById[item.id] = item;
    }
    final clientsById = {for (final item in clients) item.id: item};
    for (final id in batch.deletedClientIds) {
      clientsById.remove(id);
    }
    for (final item in batch.clients) {
      clientsById[item.id] = item;
    }
    return PdvCatalogState(
      cursor: batch.cursor,
      products: _sortedProducts(productsById.values),
      clients: _sortedClients(clientsById.values),
    );
  }
}

List<Product> _sortedProducts(Iterable<Product> values) {
  return values.where((item) => item.active).toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}

List<Client> _sortedClients(Iterable<Client> values) {
  return values.toList()
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
}
