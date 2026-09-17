import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/catalog_models.dart';

/// Gateway do terminal de salão. Este serviço fala apenas com o Lyncar Edge
/// local; ele nunca consulta o endpoint público do PedeOn.
class SalonEdgeService {
  SalonEdgeService({http.Client? client, String? baseUrl})
    : _client = client ?? http.Client(),
      _baseUrl = baseUrl ?? _defaultBaseUrl();

  final http.Client _client;
  final String _baseUrl;

  static String _defaultBaseUrl() {
    final base = Uri.base;
    return base
        .replace(port: 8765, path: '', query: null, fragment: null)
        .toString()
        .replaceFirst(RegExp(r'/$'), '');
  }

  Future<String> login(String code, String pin) async {
    final result = await _decode(
      await _client.post(
        Uri.parse('$_baseUrl/v1/salon/login'),
        headers: const {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code, 'pin': pin}),
      ),
    );
    return result['local_token'] as String;
  }

  Future<CatalogPage> catalog(String token) async {
    final result = await _decode(
      await _client.get(
        Uri.parse('$_baseUrl/v1/pedeon/catalog').replace(
          queryParameters: const {'channel': 'onsite_waiter'},
        ),
        headers: {'Accept': 'application/json', 'X-Lyncar-Waiter-Token': token},
      ),
    );
    final storeJson =
        (result['store'] as Map?)?.cast<String, dynamic>() ??
        const <String, dynamic>{};
    return CatalogPage(
      store: Storefront(
        slug: storeJson['slug']?.toString() ?? 'salao',
        displayName: storeJson['display_name']?.toString() ?? 'PedeOn Salão',
        acceptingOrders: true,
        fulfillmentOptions: const ['dine_in'],
        minimumOrderAmount: 0,
      ),
      categories: ((result['categories'] as List?) ?? const [])
          .cast<Map>()
          .map((item) => CatalogCategory.fromJson(item.cast<String, dynamic>()))
          .toList(),
      items: ((result['items'] as List?) ?? const [])
          .cast<Map>()
          .map((item) => CatalogProduct.fromJson(item.cast<String, dynamic>()))
          .toList(),
      page: 1,
      totalPages: 1,
    );
  }

  Future<void> sendOrder({
    required String token,
    required String accountType,
    required int accountNumber,
    required List<CartLine> lines,
  }) async {
    await _decode(
      await _client.post(
        Uri.parse('$_baseUrl/v1/staff/orders'),
        headers: {
          'Content-Type': 'application/json',
          'X-Lyncar-Waiter-Token': token,
        },
        body: jsonEncode({
          'idempotency_key':
              'salon-${DateTime.now().microsecondsSinceEpoch}-${accountNumber.toString().padLeft(4, '0')}',
          'source_channel': 'onsite_waiter',
          if (accountType == 'mesa') 'table_label': 'Mesa $accountNumber',
          if (accountType == 'comanda')
            'command_label': 'Comanda $accountNumber',
          'items': lines.map((line) => line.toRequestJson()).toList(),
        }),
      ),
    );
  }

  Future<Map<String, dynamic>> _decode(http.Response response) async {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SalonEdgeException(
        (decoded is Map ? decoded['detail'] : null)?.toString() ??
            'Não foi possível comunicar com o Lyncar Edge.',
      );
    }
    return (decoded as Map).cast<String, dynamic>();
  }
}

class SalonEdgeException implements Exception {
  const SalonEdgeException(this.message);
  final String message;
  @override
  String toString() => message;
}
