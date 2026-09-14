import '../domain/catalog_models.dart';
import '../domain/customer_auth.dart';
import 'catalog_api_service.dart';

abstract interface class CatalogRepository {
  Future<CatalogPage> load(
    String slug, {
    String search,
    String? category,
    int page,
  });
  Future<CatalogProduct?> loadProduct(String slug, int productId);
  Future<CartQuote> quote(
    String slug,
    List<CartLine> lines, {
    String fulfillmentType,
    DeliveryAddress? deliveryAddress,
  });
  Future<PublicOrder> createOrder(
    String slug,
    CheckoutInput input,
    List<CartLine> lines, {
    String? customerToken,
  });
  Future<CustomerSession> registerCustomer(
    String slug, {
    required String name,
    required String email,
    required String password,
    String? phone,
  });
  Future<CustomerSession> loginCustomer(
    String slug, {
    required String email,
    required String password,
  });
  Future<String> startGoogleLogin(String slug);
  Future<CustomerSession> exchangeGoogleCode(String slug, String code);
  Future<CustomerSession> updateCustomerProfile(
    String slug, {
    required String token,
    String? document,
    DeliveryAddress? deliveryAddress,
  });
  Future<PublicOrder> trackOrder(String slug, String trackingToken);
  String imageUrl(String? value);
}

class HttpCatalogRepository implements CatalogRepository {
  const HttpCatalogRepository(this._service);
  final CatalogApiService _service;

  @override
  Future<CatalogPage> load(
    String slug, {
    String search = '',
    String? category,
    int page = 1,
  }) async => CatalogPage.fromJson(
    await _service.fetchCatalog(
      slug,
      search: search,
      category: category,
      page: page,
    ),
  );

  @override
  Future<CartQuote> quote(
    String slug,
    List<CartLine> lines, {
    String fulfillmentType = 'pickup',
    DeliveryAddress? deliveryAddress,
  }) async => CartQuote.fromJson(
    await _service.quote(
      slug,
      lines,
      fulfillmentType: fulfillmentType,
      deliveryAddress: deliveryAddress,
    ),
  );

  @override
  Future<PublicOrder> createOrder(
    String slug,
    CheckoutInput input,
    List<CartLine> lines, {
    String? customerToken,
  }) async => PublicOrder.fromJson(
    await _service.createOrder(slug, {
      'idempotency_key': input.idempotencyKey,
      'items': lines
          .map((line) => line.toRequestJson())
          .toList(growable: false),
      'customer_name': input.customerName,
      'customer_phone': input.customerPhone,
      'customer_email': input.customerEmail,
      'customer_document': input.customerDocument,
      'fulfillment_type': input.fulfillmentType,
      'delivery_address': input.deliveryAddress?.toJson(),
      'payment_method': input.paymentMethod,
      'local_payment_method': input.localPaymentMethod,
      'cash_change_for': input.cashChangeFor,
      'customer_notes': input.customerNotes,
    }, token: customerToken),
  );

  @override
  Future<CustomerSession> registerCustomer(
    String slug, {
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async => CustomerSession.fromJson(
    await _service.registerCustomer(
      slug,
      name: name,
      email: email,
      password: password,
      phone: phone,
    ),
  );

  @override
  Future<CustomerSession> loginCustomer(
    String slug, {
    required String email,
    required String password,
  }) async => CustomerSession.fromJson(
    await _service.loginCustomer(slug, email: email, password: password),
  );

  @override
  Future<String> startGoogleLogin(String slug) =>
      _service.startGoogleLogin(slug);

  @override
  Future<CustomerSession> exchangeGoogleCode(String slug, String code) async =>
      CustomerSession.fromJson(await _service.exchangeGoogleCode(slug, code));

  @override
  Future<CustomerSession> updateCustomerProfile(
    String slug, {
    required String token,
    String? document,
    DeliveryAddress? deliveryAddress,
  }) async => CustomerSession.fromJson(
    await _service.updateCustomerProfile(
      slug,
      token: token,
      document: document,
      deliveryAddress: deliveryAddress,
    ),
  );

  @override
  String imageUrl(String? value) => _service.resolveImage(value);

  @override
  Future<CatalogProduct?> loadProduct(String slug, int productId) async {
    final page = CatalogPage.fromJson(
      await _service.fetchCatalog(slug, productId: productId),
    );
    return page.items.firstOrNull;
  }

  @override
  Future<PublicOrder> trackOrder(String slug, String trackingToken) async =>
      PublicOrder.fromJson(await _service.trackOrder(slug, trackingToken));
}
