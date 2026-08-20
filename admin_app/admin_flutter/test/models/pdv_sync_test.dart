import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/models/pdv_sync.dart';

Map<String, dynamic> _product(int id, String name, {bool active = true}) {
  return {
    'id': id,
    'name': name,
    'product_type': 'produto',
    'sale_price': '10.00',
    'stock_quantity': '1',
    'minimum_stock': '0',
    'active': active,
  };
}

Map<String, dynamic> _client(int id, String name) {
  return {
    'id': id,
    'name': name,
    'person_type': 'PF',
    'contract_type': 'avulso',
    'active': true,
    'created_at': '2026-08-20T12:00:00Z',
    'allow_credit': false,
    'credit_limit': '0',
    'credit_status': 'liberado',
    'monthly_fee': '0',
  };
}

PdvSyncBatch _batch({
  required int cursor,
  List<Map<String, dynamic>> products = const [],
  List<Map<String, dynamic>> clients = const [],
  List<int> deletedProducts = const [],
  List<int> deletedClients = const [],
}) {
  return PdvSyncBatch.fromJson({
    'cursor': cursor,
    'server_time': '2026-08-20T12:00:00Z',
    'products': products,
    'clients': clients,
    'deleted_product_ids': deletedProducts,
    'deleted_client_ids': deletedClients,
    'reset_required': false,
    'has_more': false,
  });
}

void main() {
  group('PdvCatalogState', () {
    test('carga completa substitui catalogo e ordena dados', () {
      const initial = PdvCatalogState(cursor: 0, products: [], clients: []);
      final result = initial.apply(
        _batch(
          cursor: 10,
          products: [_product(2, 'Z'), _product(1, 'A')],
          clients: [_client(2, 'Z'), _client(1, 'A')],
        ),
        replace: true,
      );

      expect(result.cursor, 10);
      expect(result.products.map((item) => item.id), [1, 2]);
      expect(result.clients.map((item) => item.id), [1, 2]);
    });

    test('delta atualiza, inclui e remove sem duplicar', () {
      final initial = PdvCatalogState(
        cursor: 10,
        products: _batch(
          cursor: 10,
          products: [_product(1, 'Antigo'), _product(2, 'Remover')],
        ).products,
        clients: _batch(
          cursor: 10,
          clients: [_client(1, 'Antigo'), _client(2, 'Remover')],
        ).clients,
      );
      final result = initial.apply(
        _batch(
          cursor: 15,
          products: [_product(1, 'Novo'), _product(3, 'Incluido')],
          clients: [_client(1, 'Novo'), _client(3, 'Incluido')],
          deletedProducts: [2],
          deletedClients: [2],
        ),
        replace: false,
      );

      expect(result.cursor, 15);
      expect(result.products.map((item) => item.id).toSet(), {1, 3});
      expect(result.products.firstWhere((item) => item.id == 1).name, 'Novo');
      expect(result.clients.map((item) => item.id).toSet(), {1, 3});
      expect(result.clients.firstWhere((item) => item.id == 1).name, 'Novo');
    });
  });
}
