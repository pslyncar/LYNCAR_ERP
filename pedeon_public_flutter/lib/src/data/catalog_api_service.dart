import 'dart:convert';

import 'package:http/http.dart' as http;

import 'api_base_url.dart';
import '../domain/catalog_models.dart';
import 'http_client_factory.dart';

class CatalogApiService {
  CatalogApiService({http.Client? client, String? baseUrl})
    : _client = client ?? createCatalogHttpClient(),
      _baseUrl = resolvePedeOnApiBaseUrl(
        configured: baseUrl ?? const String.fromEnvironment('PEDEON_API_URL'),
      );

  final http.Client _client;
  final String _baseUrl;

  Future<Map<String, dynamic>> fetchCatalog(
    String slug, {
    String search = '',
    String? category,
    int? productId,
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/pedeon/public/$slug').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '24',
        if (search.trim().isNotEmpty) 'search': search.trim(),
        'category': ?category,
        if (productId != null) 'product_id': '$productId',
      },
    );
    return _decode(
      await _client.get(uri, headers: const {'Accept': 'application/json'}),
    );
  }

  Future<Map<String, dynamic>> quote(
    String slug,
    List<CartLine> lines, {
    String fulfillmentType = 'pickup',
    DeliveryAddress? deliveryAddress,
  }) async {
    final response = await _client.post(
      Uri.parse('$_baseUrl/pedeon/public/$slug/quote'),
      headers: const {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode({
        'items': lines
            .map((line) => line.toRequestJson())
            .toList(growable: false),
        'fulfillment_type': fulfillmentType,
        'delivery_address': deliveryAddress?.toJson(),
      }),
    );
    return _decode(response);
  }

  Future<Map<String, dynamic>> createOrder(
    String slug,
    Map<String, dynamic> payload, {
    String? token,
  }) async => _decode(
    await _client.post(
      Uri.parse('$_baseUrl/pedeon/public/$slug/orders'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: jsonEncode(payload),
    ),
  );

  Future<Map<String, dynamic>> registerCustomer(
    String slug, {
    required String name,
    required String email,
    required String password,
    String? phone,
  }) => _authRequest(slug, 'register', {
    'name': name,
    'email': email,
    'password': password,
    if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
  });

  Future<Map<String, dynamic>> loginCustomer(
    String slug, {
    required String email,
    required String password,
  }) => _authRequest(slug, 'login', {'email': email, 'password': password});

  Future<Map<String, dynamic>> currentCustomer(
    String slug, {
    String? token,
  }) async {
    final response = await _client.get(
      Uri.parse('$_baseUrl/pedeon/public/$slug/auth/me'),
      headers: {
        'Accept': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      },
    );
    return _decode(response);
  }

  Future<void> logoutCustomer(String slug, {String? token}) async {
    await _client.post(
      Uri.parse('$_baseUrl/pedeon/public/$slug/auth/logout'),
      headers: {if (token != null) 'Authorization': 'Bearer $token'},
    );
  }

  Future<String> startGoogleLogin(String slug) async {
    final result = _decode(
      await _client.get(
        Uri.parse('$_baseUrl/pedeon/public/$slug/auth/google/start'),
        headers: const {'Accept': 'application/json'},
      ),
    );
    return result['authorization_url'] as String;
  }

  Future<Map<String, dynamic>> exchangeGoogleCode(String slug, String code) =>
      _authRequest(slug, 'google/exchange', {'code': code});

  Future<Map<String, dynamic>> updateCustomerProfile(
    String slug, {
    required String token,
    String? document,
    DeliveryAddress? deliveryAddress,
  }) async => _decode(
    await _client.put(
      Uri.parse('$_baseUrl/pedeon/public/$slug/auth/profile'),
      headers: {
        'Content-Type': 'application/json; charset=UTF-8',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'document': document,
        'delivery_address': deliveryAddress?.toJson(),
      }),
    ),
  );

  Future<Map<String, dynamic>> _authRequest(
    String slug,
    String action,
    Map<String, dynamic> payload,
  ) async => _decode(
    await _client.post(
      Uri.parse('$_baseUrl/pedeon/public/$slug/auth/$action'),
      headers: const {'Content-Type': 'application/json; charset=UTF-8'},
      body: jsonEncode(payload),
    ),
  );

  Future<Map<String, dynamic>> trackOrder(
    String slug,
    String trackingToken,
  ) async => _decode(
    await _client.get(
      Uri.parse('$_baseUrl/pedeon/public/$slug/orders/$trackingToken'),
      headers: const {'Accept': 'application/json'},
    ),
  );

  Map<String, dynamic> _decode(http.Response response) {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded is Map ? decoded['detail'] : null;
      throw CatalogRequestException(
        detail?.toString() ?? 'Não foi possível carregar o cardápio.',
        statusCode: response.statusCode,
      );
    }
    return (decoded as Map).cast<String, dynamic>();
  }

  String resolveImage(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final uri = Uri.tryParse(value);
    if (uri != null && uri.hasScheme) return value;
    return '$_baseUrl${value.startsWith('/') ? '' : '/'}$value';
  }
}

class CatalogRequestException implements Exception {
  const CatalogRequestException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}
