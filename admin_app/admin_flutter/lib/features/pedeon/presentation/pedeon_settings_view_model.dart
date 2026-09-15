import 'package:flutter/foundation.dart';

import '../data/pedeon_repository.dart';
import '../domain/pedeon_order.dart';
import '../domain/pedeon_settings.dart';

class PedeOnSettingsViewModel extends ChangeNotifier {
  PedeOnSettingsViewModel(this.repository);

  final PedeOnRepository repository;
  PedeOnSettings? settings;
  bool loading = false;
  bool saving = false;
  String? error;
  String? successMessage;
  PedeOnCatalogPage? catalog;
  bool catalogLoading = false;
  String catalogSearch = '';
  PedeOnOrderPage? orders;
  bool ordersLoading = false;
  String? orderStatusFilter;
  String? orderSourceFilter;

  Future<void> load() async {
    loading = true;
    error = null;
    notifyListeners();
    try {
      settings = await repository.load();
    } catch (exception) {
      error = _message(exception);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> saveStore(PedeOnStoreSettings value) =>
      _save(() => repository.saveStore(value), 'Loja atualizada.');

  Future<bool> uploadStoreMedia({
    required String mediaType,
    required Uint8List bytes,
    required String filename,
  }) => _save(
    () => repository.uploadStoreMedia(
      mediaType: mediaType,
      bytes: bytes,
      filename: filename,
    ),
    mediaType == 'logo' ? 'Logo atualizada.' : 'Foto de capa atualizada.',
  );

  Future<bool> saveManualPix(PedeOnManualPixSettings value) =>
      _save(() => repository.saveManualPix(value), 'Pix manual atualizado.');

  Future<bool> saveInfinitePay(PedeOnInfinitePaySettings value) =>
      _save(() => repository.saveInfinitePay(value), 'InfinitePay atualizada.');

  Future<bool> saveDeliveryCard(PedeOnDeliveryCardSettings value) => _save(
    () => repository.saveDeliveryCard(value),
    'Pagamentos na entrega atualizados.',
  );

  Future<bool> savePickupPayment(PedeOnPickupPaymentSettings value) => _save(
    () => repository.savePickupPayment(value),
    'Pagamento na retirada atualizado.',
  );

  Future<bool> saveDeliveryOperation(PedeOnDeliveryOperation value) => _save(
    () => repository.saveDeliveryOperation(value),
    'Entrega e horários atualizados.',
  );

  Future<bool> saveTerminal(PedeOnTerminalSettings value) => _save(
    () => repository.saveTerminal(value),
    'Permissões do PDV atualizadas.',
  );

  Future<bool> saveDeliveryZone(PedeOnDeliveryZone value) async {
    final result = await _catalogAction(
      () => repository.saveDeliveryZone(value),
      'Área de entrega salva.',
    );
    if (result) await load();
    return result;
  }

  Future<bool> saveStation(PedeOnFulfillmentStation value) =>
      _save(() => repository.saveStation(value), 'Estação operacional salva.');

  Future<bool> deleteDeliveryZone(int zoneId) async {
    final result = await _catalogAction(
      () => repository.deleteDeliveryZone(zoneId),
      'Área de entrega removida.',
    );
    if (result) await load();
    return result;
  }

  Future<void> loadCatalog({String? search, int? page}) async {
    catalogLoading = true;
    error = null;
    if (search != null) catalogSearch = search;
    notifyListeners();
    try {
      catalog = await repository.loadCatalog(
        search: catalogSearch,
        page: page ?? catalog?.page ?? 1,
      );
    } catch (exception) {
      error = _message(exception);
    } finally {
      catalogLoading = false;
      notifyListeners();
    }
  }

  Future<List<PedeOnCatalogProduct>> searchCatalogProducts(String search) =>
      repository.searchCatalogProducts(search);

  Future<bool> createCategory(String name, String description) async {
    final result = await _catalogAction(
      () => repository.createCategory(name, description),
      'Categoria criada.',
    );
    if (result) await loadCatalog(page: 1);
    return result;
  }

  Future<bool> updateCategory(PedeOnCategory category) async {
    final result = await _catalogAction(
      () => repository.updateCategory(category),
      'Categoria atualizada.',
    );
    if (result) await loadCatalog(page: 1);
    return result;
  }

  Future<bool> createCategoryWithProducts(
    String name,
    String description,
    List<PedeOnCatalogProduct> products, {
    String channel = 'shared',
  }) async {
    final result = await _catalogAction(
      () => repository.createCategory(name, description),
      'Categoria criada.',
    );
    if (!result) return false;
    await loadCatalog(page: 1);
    final category = catalog?.categories
        .where((item) => item.name == name && item.channel == 'shared')
        .firstOrNull;
    if (category == null) {
      return true;
    }
    final channelCategory = await repository.updateCategory(
      category.copyWith(channel: 'shared'),
    );
    for (final product in products) {
      await repository.savePublication(
        product.copyWith(categoryId: channelCategory.id),
      );
    }
    await loadCatalog(page: 1);
    return true;
  }

  Future<bool> deleteCategory(int categoryId) async {
    final result = await _catalogAction(
      () => repository.deleteCategory(categoryId),
      'Categoria removida.',
    );
    if (result) await loadCatalog(page: 1);
    return result;
  }

  Future<bool> reorderCategories(int oldIndex, int newIndex) async {
    final current = catalog;
    if (current == null || current.categories.length < 2) return false;
    final reordered = [...current.categories];
    final category = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, category);
    catalog = current.copyWith(categories: reordered);
    saving = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      final saved = await repository.reorderCategories(
        reordered.map((item) => item.id).toList(growable: false),
      );
      catalog = current.copyWith(categories: saved);
      successMessage = 'Ordem das categorias atualizada.';
      return true;
    } catch (exception) {
      catalog = current;
      error = _message(exception);
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> savePublication(PedeOnCatalogProduct product) async {
    final result = await _catalogAction(
      () => repository.savePublication(product),
      product.published ? 'Produto publicado.' : 'Produto atualizado.',
    );
    if (result) await loadCatalog(page: catalog?.page ?? 1);
    return result;
  }

  Future<bool> saveModifierGroup(PedeOnModifierGroup group) async {
    final result = await _catalogAction(
      () => repository.saveModifierGroup(group),
      'Grupo de opções salvo.',
    );
    if (result) await loadCatalog(page: catalog?.page ?? 1);
    return result;
  }

  Future<bool> deleteModifierGroup(int groupId) async {
    final result = await _catalogAction(
      () => repository.deleteModifierGroup(groupId),
      'Grupo removido.',
    );
    if (result) await loadCatalog(page: catalog?.page ?? 1);
    return result;
  }

  Future<void> loadOrders({String? status, String? source, int? page}) async {
    ordersLoading = true;
    error = null;
    if (status != null) orderStatusFilter = status.isEmpty ? null : status;
    if (source != null) orderSourceFilter = source.isEmpty ? null : source;
    notifyListeners();
    try {
      orders = await repository.loadOrders(
        status: orderStatusFilter,
        source: orderSourceFilter,
        page: page ?? orders?.page ?? 1,
      );
    } catch (exception) {
      error = _message(exception);
    } finally {
      ordersLoading = false;
      notifyListeners();
    }
  }

  Future<PedeOnOrderDetail?> loadOrder(int orderId) async {
    try {
      return await repository.loadOrder(orderId);
    } catch (exception) {
      error = _message(exception);
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateOrderStatus(int orderId, String status) async {
    final result = await _catalogAction(
      () => repository.updateOrderStatus(orderId, status),
      'Pedido atualizado.',
    );
    if (result) await loadOrders(page: orders?.page ?? 1);
    return result;
  }

  Future<bool> confirmPayment(int orderId) async {
    final result = await _catalogAction(
      () => repository.confirmPayment(orderId),
      'Pagamento confirmado.',
    );
    if (result) await loadOrders(page: orders?.page ?? 1);
    return result;
  }

  Future<bool> _catalogAction(
    Future<Object?> Function() action,
    String success,
  ) async {
    saving = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      await action();
      successMessage = success;
      return true;
    } catch (exception) {
      error = _message(exception);
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  Future<bool> _save(
    Future<PedeOnSettings> Function() action,
    String success,
  ) async {
    saving = true;
    error = null;
    successMessage = null;
    notifyListeners();
    try {
      settings = await action();
      successMessage = success;
      return true;
    } catch (exception) {
      error = _message(exception);
      return false;
    } finally {
      saving = false;
      notifyListeners();
    }
  }

  String _message(Object exception) => exception
      .toString()
      .replaceFirst('Bad state: ', '')
      .replaceFirst('StateError: ', '');
}
