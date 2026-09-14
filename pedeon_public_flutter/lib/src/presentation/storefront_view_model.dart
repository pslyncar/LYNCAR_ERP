import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalog_repository.dart';
import '../domain/catalog_models.dart';
import '../domain/customer_profile.dart';
import '../domain/customer_auth.dart';

class StorefrontViewModel extends ChangeNotifier {
  StorefrontViewModel({required this.slug, required this.repository});

  final String slug;
  final CatalogRepository repository;
  final Map<String, CartLine> _cart = {};
  Timer? _searchTimer;
  int _loadGeneration = 0;

  Storefront? store;
  List<CatalogCategory> categories = const [];
  List<CatalogProduct> products = const [];
  String search = '';
  String? selectedCategory;
  String? error;
  bool loading = false;
  bool loadingMore = false;
  int page = 1;
  int totalPages = 1;
  String? _checkoutIdempotencyKey;
  CustomerSession? customer;
  CustomerProfile? customerProfile;
  bool authLoading = false;
  String? authError;

  List<CartLine> get cart => List.unmodifiable(_cart.values);
  int get itemCount =>
      _cart.values.fold(0, (total, line) => total + line.quantity);
  double get subtotal =>
      _cart.values.fold(0, (total, line) => total + line.total);
  bool get canLoadMore => page < totalPages;
  bool get isAuthenticated => customer != null;
  String imageUrl(String? value) => repository.imageUrl(value);

  Future<void> load() async {
    final generation = ++_loadGeneration;
    loading = true;
    error = null;
    notifyListeners();
    try {
      final firstPage = await repository.load(slug, search: search);
      final loadedProducts = [...firstPage.items];
      for (var nextPage = 2; nextPage <= firstPage.totalPages; nextPage++) {
        final result = await repository.load(
          slug,
          search: search,
          page: nextPage,
        );
        if (generation != _loadGeneration) return;
        loadedProducts.addAll(result.items);
      }
      if (generation != _loadGeneration) return;
      store = firstPage.store;
      categories = firstPage.categories;
      products = loadedProducts;
      page = firstPage.totalPages;
      totalPages = firstPage.totalPages;
      selectedCategory = categories
          .where(
            (category) => loadedProducts.any(
              (product) => product.categoryId == category.id,
            ),
          )
          .firstOrNull
          ?.slug;
      await _restoreCart();
      await _restoreCustomer();
      await _restoreCustomerProfile();
    } catch (exception) {
      if (generation != _loadGeneration) return;
      error = exception.toString();
    } finally {
      if (generation == _loadGeneration) {
        loading = false;
        notifyListeners();
      }
    }
  }

  void setSearch(String value) {
    search = value;
    _searchTimer?.cancel();
    _searchTimer = Timer(const Duration(milliseconds: 350), load);
  }

  void selectCategory(String? value) {
    if (selectedCategory == value) return;
    selectedCategory = value;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!canLoadMore || loadingMore) return;
    loadingMore = true;
    notifyListeners();
    try {
      final result = await repository.load(
        slug,
        search: search,
        category: selectedCategory,
        page: page + 1,
      );
      products = [...products, ...result.items];
      page = result.page;
      totalPages = result.totalPages;
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  void addConfigured({
    required CatalogProduct product,
    required int quantity,
    Map<int, int> selectedOptions = const {},
    String? customerNotes,
  }) {
    if (!product.available) return;
    final normalizedNotes = (customerNotes ?? '').trim();
    final optionSignature = selectedOptions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final signature =
        '${product.id}|${optionSignature.map((e) => '${e.key}:${e.value}').join(',')}|$normalizedNotes';
    final current = _cart[signature];
    _cart[signature] = CartLine(
      id: signature,
      product: product,
      quantity: (current?.quantity ?? 0) + quantity,
      selectedOptions: Map.unmodifiable(selectedOptions),
      customerNotes: normalizedNotes.isEmpty ? null : normalizedNotes,
    );
    _persistCart();
    notifyListeners();
  }

  void add(CatalogProduct product) =>
      addConfigured(product: product, quantity: 1);

  void increaseLine(CartLine line) {
    _cart[line.id] = CartLine(
      id: line.id,
      product: line.product,
      quantity: line.quantity + 1,
      selectedOptions: line.selectedOptions,
      customerNotes: line.customerNotes,
    );
    _persistCart();
    notifyListeners();
  }

  void removeLine(CartLine line) {
    _cart.remove(line.id);
    _persistCart();
    notifyListeners();
  }

  void replaceConfigured({
    required CartLine original,
    required int quantity,
    required Map<int, int> selectedOptions,
    String? customerNotes,
  }) {
    _cart.remove(original.id);
    final normalizedNotes = (customerNotes ?? '').trim();
    final optionSignature = selectedOptions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final signature =
        '${original.product.id}|${optionSignature.map((e) => '${e.key}:${e.value}').join(',')}|$normalizedNotes';
    final current = _cart[signature];
    _cart[signature] = CartLine(
      id: signature,
      product: original.product,
      quantity: (current?.quantity ?? 0) + quantity,
      selectedOptions: Map.unmodifiable(selectedOptions),
      customerNotes: normalizedNotes.isEmpty ? null : normalizedNotes,
    );
    _persistCart();
    notifyListeners();
  }

  void decreaseLine(CartLine line) {
    if (line.quantity == 1) {
      _cart.remove(line.id);
    } else {
      _cart[line.id] = CartLine(
        id: line.id,
        product: line.product,
        quantity: line.quantity - 1,
        selectedOptions: line.selectedOptions,
        customerNotes: line.customerNotes,
      );
    }
    _persistCart();
    notifyListeners();
  }

  void decrease(CatalogProduct product) {
    final entry = _cart.entries
        .where((item) => item.value.product.id == product.id)
        .firstOrNull;
    final current = entry?.value;
    if (current == null) return;
    if (current.quantity == 1) {
      _cart.remove(entry!.key);
    } else {
      _cart[entry!.key] = CartLine(
        id: current.id,
        product: current.product,
        quantity: current.quantity - 1,
        selectedOptions: current.selectedOptions,
        customerNotes: current.customerNotes,
      );
    }
    _persistCart();
    notifyListeners();
  }

  Future<CartQuote> confirmQuote({
    String fulfillmentType = 'pickup',
    DeliveryAddress? deliveryAddress,
  }) => repository.quote(
    slug,
    cart,
    fulfillmentType: fulfillmentType,
    deliveryAddress: deliveryAddress,
  );

  Future<PublicOrder> trackOrder(String trackingToken) =>
      repository.trackOrder(slug, trackingToken);

  String checkoutIdempotencyKey() => _checkoutIdempotencyKey ??=
      '${DateTime.now().microsecondsSinceEpoch}-${Random.secure().nextInt(0x7fffffff)}';

  Future<PublicOrder> placeOrder(CheckoutInput input) async {
    final order = await repository.createOrder(
      slug,
      input,
      cart,
      customerToken: customer?.token,
    );
    _cart.clear();
    _persistCart();
    _checkoutIdempotencyKey = null;
    notifyListeners();
    return order;
  }

  String get _cartStorageKey => 'pedeon.cart.$slug';
  String get _customerStorageKey => 'pedeon.customer.$slug';
  String get _customerProfileStorageKey =>
      'pedeon.customer-profile.$slug.${customer?.id}';

  Future<CustomerSession> registerCustomer({
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async {
    authLoading = true;
    authError = null;
    notifyListeners();
    try {
      final session = await repository.registerCustomer(
        slug,
        name: name,
        email: email,
        password: password,
        phone: phone,
      );
      customer = session;
      await _persistCustomer();
      await _restoreCustomerProfile();
      return session;
    } catch (exception) {
      authError = exception.toString();
      rethrow;
    } finally {
      authLoading = false;
      notifyListeners();
    }
  }

  Future<CustomerSession> loginCustomer({
    required String email,
    required String password,
  }) async {
    authLoading = true;
    authError = null;
    notifyListeners();
    try {
      final session = await repository.loginCustomer(
        slug,
        email: email,
        password: password,
      );
      customer = session;
      await _persistCustomer();
      await _restoreCustomerProfile();
      return session;
    } catch (exception) {
      authError = exception.toString();
      rethrow;
    } finally {
      authLoading = false;
      notifyListeners();
    }
  }

  Future<String> startGoogleLogin() => repository.startGoogleLogin(slug);

  Future<void> exchangeGoogleCode(String code) async {
    authLoading = true;
    authError = null;
    notifyListeners();
    try {
      customer = await repository.exchangeGoogleCode(slug, code);
      await _persistCustomer();
      await _restoreCustomerProfile();
    } catch (exception) {
      authError = exception.toString();
      rethrow;
    } finally {
      authLoading = false;
      notifyListeners();
    }
  }

  Future<void> logoutCustomer() async {
    customer = null;
    customerProfile = null;
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_customerStorageKey);
    notifyListeners();
  }

  Future<void> saveCustomerProfile({
    String? document,
    DeliveryAddress? deliveryAddress,
  }) async {
    if (customer == null) return;
    final normalizedDocument = document?.trim();
    customerProfile = CustomerProfile(
      document: normalizedDocument?.isEmpty == true
          ? customerProfile?.document
          : normalizedDocument ?? customerProfile?.document,
      deliveryAddress: deliveryAddress ?? customerProfile?.deliveryAddress,
    );
    await _persistCustomerProfile();
    notifyListeners();
  }

  Future<void> _restoreCustomer() async {
    if (!kIsWeb) return;
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_customerStorageKey);
    if (encoded == null) return;
    try {
      final saved = (jsonDecode(encoded) as Map).cast<String, dynamic>();
      customer = CustomerSession(
        token: saved['token'] as String,
        id: saved['id'] as int,
        name: saved['name'] as String,
        email: saved['email'] as String,
        phone: saved['phone'] as String?,
      );
    } on Object {
      await preferences.remove(_customerStorageKey);
    }
  }

  Future<void> _persistCustomer() async {
    if (!kIsWeb || customer == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _customerStorageKey,
      jsonEncode({
        'token': customer!.token,
        'id': customer!.id,
        'name': customer!.name,
        'email': customer!.email,
        'phone': customer!.phone,
      }),
    );
  }

  Future<void> _restoreCustomerProfile() async {
    if (!kIsWeb || customer == null) return;
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_customerProfileStorageKey);
    if (encoded == null) return;
    try {
      final saved = (jsonDecode(encoded) as Map).cast<String, dynamic>();
      customerProfile = CustomerProfile.fromJson(saved);
    } on Object {
      await preferences.remove(_customerProfileStorageKey);
    }
  }

  Future<void> _persistCustomerProfile() async {
    if (!kIsWeb || customer == null || customerProfile == null) return;
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _customerProfileStorageKey,
      jsonEncode(customerProfile!.toJson()),
    );
  }

  Future<void> _restoreCart() async {
    if (!kIsWeb) return;
    final preferences = await SharedPreferences.getInstance();
    final encoded = preferences.getString(_cartStorageKey);
    if (encoded == null || products.isEmpty) return;
    try {
      final saved = (jsonDecode(encoded) as List).cast<Map<String, dynamic>>();
      for (final entry in saved) {
        final product = products
            .where((item) => item.id == entry['product_id'])
            .firstOrNull;
        if (product == null || !product.available) continue;
        final selectedOptions = <int, int>{
          for (final option in (entry['selected_options'] as Map).entries)
            int.parse(option.key.toString()): option.value as int,
        };
        final notes = (entry['customer_notes'] as String?)?.trim();
        final quantity = entry['quantity'] as int? ?? 1;
        final signature =
            '${product.id}|${selectedOptions.entries.map((e) => '${e.key}:${e.value}').join(',')}|${notes ?? ''}';
        _cart[signature] = CartLine(
          id: signature,
          product: product,
          quantity: quantity,
          selectedOptions: Map.unmodifiable(selectedOptions),
          customerNotes: notes?.isEmpty == true ? null : notes,
        );
      }
      notifyListeners();
    } on Object {
      await preferences.remove(_cartStorageKey);
    }
  }

  Future<void> _persistCart() async {
    if (!kIsWeb) return;
    final preferences = await SharedPreferences.getInstance();
    if (_cart.isEmpty) {
      await preferences.remove(_cartStorageKey);
      return;
    }
    await preferences.setString(
      _cartStorageKey,
      jsonEncode(
        _cart.values
            .map(
              (line) => {
                'product_id': line.product.id,
                'quantity': line.quantity,
                'selected_options': line.selectedOptions.map(
                  (key, value) => MapEntry('$key', value),
                ),
                'customer_notes': line.customerNotes,
              },
            )
            .toList(growable: false),
      ),
    );
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    super.dispose();
  }
}
