import 'dart:convert';
import 'dart:typed_data';

import 'package:http_parser/http_parser.dart';

import '../../../services/http_facade.dart' as http;

import '../../../models/session.dart';
import '../domain/pedeon_settings.dart';
import '../domain/pedeon_order.dart';

abstract interface class PedeOnRepository {
  Future<PedeOnSettings> load();
  Future<PedeOnSettings> saveStore(PedeOnStoreSettings settings);
  Future<PedeOnSettings> uploadStoreMedia({
    required String mediaType,
    required Uint8List bytes,
    required String filename,
  });
  Future<PedeOnSettings> saveManualPix(PedeOnManualPixSettings settings);
  Future<PedeOnSettings> saveInfinitePay(PedeOnInfinitePaySettings settings);
  Future<PedeOnSettings> saveDeliveryCard(PedeOnDeliveryCardSettings settings);
  Future<PedeOnSettings> savePickupPayment(
    PedeOnPickupPaymentSettings settings,
  );
  Future<PedeOnSettings> saveDeliveryOperation(
    PedeOnDeliveryOperation settings,
  );
  Future<PedeOnSettings> saveTerminal(PedeOnTerminalSettings terminal);
  Future<PedeOnDeliveryZone> saveDeliveryZone(PedeOnDeliveryZone zone);
  Future<PedeOnSettings> saveStation(PedeOnFulfillmentStation station);
  Future<void> deleteDeliveryZone(int zoneId);
  Future<PedeOnCatalogPage> loadCatalog({String search = '', int page = 1});
  Future<List<PedeOnCatalogProduct>> searchCatalogProducts(String search);
  Future<PedeOnCategory> createCategory(String name, String description);
  Future<PedeOnCategory> updateCategory(PedeOnCategory category);
  Future<List<PedeOnCategory>> reorderCategories(List<int> categoryIds);
  Future<void> deleteCategory(int categoryId);
  Future<PedeOnCatalogProduct> savePublication(PedeOnCatalogProduct product);
  Future<PedeOnModifierGroup> saveModifierGroup(PedeOnModifierGroup group);
  Future<void> deleteModifierGroup(int groupId);
  Future<PedeOnOrderPage> loadOrders({
    String? status,
    String? source,
    int page = 1,
  });
  Future<PedeOnOrderDetail> loadOrder(int orderId);
  Future<PedeOnOrderDetail> updateOrderStatus(int orderId, String status);
  Future<PedeOnOrderDetail> confirmPayment(int orderId);
}

class HttpPedeOnRepository implements PedeOnRepository {
  HttpPedeOnRepository(this.session);

  final Session session;

  Map<String, String> get _headers => {
    if (session.token.isNotEmpty) 'Authorization': 'Bearer ${session.token}',
    'Content-Type': 'application/json',
  };

  String get _baseUrl {
    final parsed = Uri.parse(session.apiBaseUrl);
    if ((parsed.host == 'localhost' || parsed.host == '127.0.0.1') &&
        parsed.port == 5000) {
      return parsed.replace(port: 8000).toString();
    }
    return session.apiBaseUrl.endsWith('/')
        ? session.apiBaseUrl.substring(0, session.apiBaseUrl.length - 1)
        : session.apiBaseUrl;
  }

  @override
  Future<PedeOnSettings> load() => _send('GET', '/pedeon/settings');

  @override
  Future<PedeOnSettings> saveStore(PedeOnStoreSettings settings) =>
      _send('PUT', '/pedeon/settings/store', settings.toJson());

  @override
  Future<PedeOnSettings> uploadStoreMedia({
    required String mediaType,
    required Uint8List bytes,
    required String filename,
  }) async {
    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_baseUrl/pedeon/settings/media/$mediaType'),
    );
    request.headers.addAll(_headers..remove('Content-Type'));
    final lowerName = filename.toLowerCase();
    final contentType = lowerName.endsWith('.png')
        ? MediaType('image', 'png')
        : lowerName.endsWith('.webp')
        ? MediaType('image', 'webp')
        : lowerName.endsWith('.gif')
        ? MediaType('image', 'gif')
        : MediaType('image', 'jpeg');
    request.files.add(
      http.MultipartFile.fromBytes(
        'file',
        bytes,
        filename: filename,
        contentType: contentType,
      ),
    );
    final response = await http.Response.fromStream(
      await http.sendMultipart(request),
    );
    return PedeOnSettings.fromJson(_decode(response));
  }

  @override
  Future<PedeOnSettings> saveManualPix(PedeOnManualPixSettings settings) =>
      _send('PUT', '/pedeon/settings/payments/manual-pix', settings.toJson());

  @override
  Future<PedeOnSettings> saveInfinitePay(PedeOnInfinitePaySettings settings) =>
      _send('PUT', '/pedeon/settings/payments/infinitepay', settings.toJson());

  @override
  Future<PedeOnSettings> saveDeliveryCard(
    PedeOnDeliveryCardSettings settings,
  ) => _send(
    'PUT',
    '/pedeon/settings/payments/delivery-card',
    settings.toJson(),
  );

  @override
  Future<PedeOnSettings> savePickupPayment(
    PedeOnPickupPaymentSettings settings,
  ) => _send(
    'PUT',
    '/pedeon/settings/payments/pickup-payment',
    settings.toJson(),
  );

  @override
  Future<PedeOnSettings> saveDeliveryOperation(
    PedeOnDeliveryOperation settings,
  ) => _send('PUT', '/pedeon/settings/delivery', settings.toJson());

  @override
  Future<PedeOnSettings> saveTerminal(PedeOnTerminalSettings terminal) => _send(
    'PUT',
    '/pedeon/settings/terminals/${terminal.terminalId}',
    terminal.toJson(),
  );

  @override
  Future<PedeOnDeliveryZone> saveDeliveryZone(PedeOnDeliveryZone zone) async {
    final id = zone.id;
    final response = await (id == null
        ? http.post(
            Uri.parse('$_baseUrl/pedeon/settings/delivery-zones'),
            headers: _headers,
            body: jsonEncode(zone.toJson()),
          )
        : http.put(
            Uri.parse('$_baseUrl/pedeon/settings/delivery-zones/$id'),
            headers: _headers,
            body: jsonEncode(zone.toJson()),
          ));
    return PedeOnDeliveryZone.fromJson(_decode(response));
  }

  @override
  Future<PedeOnSettings> saveStation(PedeOnFulfillmentStation station) async {
    final uri = Uri.parse(
      station.id == null
          ? '$_baseUrl/pedeon/settings/stations'
          : '$_baseUrl/pedeon/settings/stations/${station.id}',
    );
    final response = await (station.id == null
        ? http.post(uri, headers: _headers, body: jsonEncode(station.toJson()))
        : http.put(uri, headers: _headers, body: jsonEncode(station.toJson())));
    _decode(response);
    return load();
  }

  @override
  Future<void> deleteDeliveryZone(int zoneId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/pedeon/settings/delivery-zones/$zoneId'),
      headers: _headers,
    );
    if (response.statusCode != 204) _decode(response);
  }

  @override
  Future<PedeOnCatalogPage> loadCatalog({
    String search = '',
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/pedeon/catalog').replace(
      queryParameters: {'search': search, 'page': '$page', 'page_size': '20'},
    );
    return PedeOnCatalogPage.fromJson(
      _decode(await http.get(uri, headers: _headers)),
    );
  }

  @override
  Future<List<PedeOnCatalogProduct>> searchCatalogProducts(
    String search,
  ) async {
    final uri = Uri.parse('$_baseUrl/pedeon/catalog').replace(
      queryParameters: {
        'search': search.trim(),
        'page': '1',
        'page_size': '50',
      },
    );
    return PedeOnCatalogPage.fromJson(
      _decode(await http.get(uri, headers: _headers)),
    ).items;
  }

  @override
  Future<PedeOnCategory> createCategory(String name, String description) async {
    final response = await http.post(
      Uri.parse('$_baseUrl/pedeon/catalog/categories'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'description': description.trim().isEmpty ? null : description.trim(),
        'active': true,
      }),
    );
    return PedeOnCategory.fromJson(_decode(response));
  }

  @override
  Future<PedeOnCategory> updateCategory(PedeOnCategory category) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/pedeon/catalog/categories/${category.id}'),
      headers: _headers,
      body: jsonEncode(category.toJson()),
    );
    return PedeOnCategory.fromJson(_decode(response));
  }

  @override
  Future<List<PedeOnCategory>> reorderCategories(List<int> categoryIds) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/pedeon/catalog/categories-order'),
      headers: _headers,
      body: jsonEncode({'category_ids': categoryIds}),
    );
    return _decodeList(response)
        .map((item) => PedeOnCategory.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> deleteCategory(int categoryId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/pedeon/catalog/categories/$categoryId'),
      headers: _headers,
    );
    if (response.statusCode != 204) _decode(response);
  }

  @override
  Future<PedeOnCatalogProduct> savePublication(
    PedeOnCatalogProduct product,
  ) async {
    final response = await http.put(
      Uri.parse('$_baseUrl/pedeon/catalog/products/${product.productId}'),
      headers: _headers,
      body: jsonEncode(product.toJson()),
    );
    return PedeOnCatalogProduct.fromJson(_decode(response));
  }

  @override
  Future<PedeOnModifierGroup> saveModifierGroup(
    PedeOnModifierGroup group,
  ) async {
    final uri = Uri.parse(
      group.id == null
          ? '$_baseUrl/pedeon/catalog/modifier-groups'
          : '$_baseUrl/pedeon/catalog/modifier-groups/${group.id}',
    );
    final response = group.id == null
        ? await http.post(
            uri,
            headers: _headers,
            body: jsonEncode(group.toJson()),
          )
        : await http.put(
            uri,
            headers: _headers,
            body: jsonEncode(group.toJson()),
          );
    return PedeOnModifierGroup.fromJson(_decode(response));
  }

  @override
  Future<void> deleteModifierGroup(int groupId) async {
    final response = await http.delete(
      Uri.parse('$_baseUrl/pedeon/catalog/modifier-groups/$groupId'),
      headers: _headers,
    );
    if (response.statusCode != 204) _decode(response);
  }

  @override
  Future<PedeOnOrderPage> loadOrders({
    String? status,
    String? source,
    int page = 1,
  }) async {
    final uri = Uri.parse('$_baseUrl/pedeon/orders').replace(
      queryParameters: {
        'page': '$page',
        'page_size': '20',
        if (status != null && status.isNotEmpty) 'status': status,
        if (source != null && source.isNotEmpty) 'source': source,
      },
    );
    return PedeOnOrderPage.fromJson(
      _decode(await http.get(uri, headers: _headers)),
    );
  }

  @override
  Future<PedeOnOrderDetail> loadOrder(int orderId) async =>
      PedeOnOrderDetail.fromJson(
        _decode(
          await http.get(
            Uri.parse('$_baseUrl/pedeon/orders/$orderId'),
            headers: _headers,
          ),
        ),
      );

  @override
  Future<PedeOnOrderDetail> updateOrderStatus(
    int orderId,
    String status,
  ) async => PedeOnOrderDetail.fromJson(
    _decode(
      await http.patch(
        Uri.parse('$_baseUrl/pedeon/orders/$orderId/status'),
        headers: _headers,
        body: jsonEncode({'status': status}),
      ),
    ),
  );

  @override
  Future<PedeOnOrderDetail> confirmPayment(int orderId) async =>
      PedeOnOrderDetail.fromJson(
        _decode(
          await http.post(
            Uri.parse('$_baseUrl/pedeon/orders/$orderId/payments/confirm'),
            headers: _headers,
          ),
        ),
      );

  Future<PedeOnSettings> _send(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final uri = Uri.parse('$_baseUrl$path');
    final response = method == 'GET'
        ? await http.get(uri, headers: _headers)
        : await http.put(uri, headers: _headers, body: jsonEncode(body));
    return PedeOnSettings.fromJson(_decode(response));
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      var message = 'Não foi possível concluir a operação.';
      try {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        message = data['detail']?.toString() ?? message;
      } catch (_) {}
      throw StateError(message);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  List<dynamic> _decodeList(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      _decode(response);
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as List<dynamic>;
  }
}
