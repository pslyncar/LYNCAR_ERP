import 'package:flutter/material.dart';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/features/pedeon/data/pedeon_repository.dart';
import 'package:papezzosync_admin/features/pedeon/domain/pedeon_settings.dart';
import 'package:papezzosync_admin/features/pedeon/domain/pedeon_order.dart';
import 'package:papezzosync_admin/features/pedeon/presentation/pedeon_settings_screen.dart';
import 'package:papezzosync_admin/features/pedeon/presentation/pedeon_settings_view_model.dart';
import 'package:papezzosync_admin/models/session.dart';

void main() {
  testWidgets('exibe configuração responsiva e separa pagamentos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final viewModel = PedeOnSettingsViewModel(_FakePedeOnRepository());
    await tester.pumpWidget(
      MaterialApp(
        home: PedeOnSettingsScreen(session: _session, viewModel: viewModel),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    expect(find.text('PedeOn'), findsOneWidget);
    expect(find.text('Central de Pedidos'), findsOneWidget);
    expect(find.text('Tipo: Cardápio / Alimentação'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('pedeon-configure-experience')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Identidade da loja'), findsOneWidget);
    expect(find.text('Cardápio / Alimentação'), findsOneWidget);
    expect(find.text('Loja online'), findsOneWidget);
    expect(find.textContaining('Híbr'), findsNothing);
    expect(
      find.text('.lyncar.com.br/cardapio'),
      findsOneWidget,
    );
    expect(find.text('PDVs autorizados'), findsOneWidget);
    expect(find.text('Estações operacionais'), findsOneWidget);

    await tester.tap(find.text('Cardápio'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Categorias do cardápio'), findsOneWidget);
    expect(find.text('Produto Teste'), findsOneWidget);
    expect(find.text('Posição 1 no cardápio'), findsOneWidget);
    expect(find.text('Posição 2 no cardápio'), findsOneWidget);

    final firstHandle = find.byType(ReorderableDragStartListener).first;
    await tester.drag(firstHandle, const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.text('Bebidas')).dy,
      lessThan(tester.getTopLeft(find.text('Lanches')).dy),
    );
    expect(find.text('Pagamentos'), findsOneWidget);
    expect(find.text('Pix manual'), findsNothing);

    expect(find.text('PedeOn'), findsOneWidget);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    expect(find.text('PedeOn'), findsNothing);
    await tester.drag(
      find.byType(SingleChildScrollView).first,
      const Offset(0, 500),
    );
    await tester.pumpAndSettle();
    expect(find.text('PedeOn'), findsOneWidget);

    tester.view.physicalSize = const Size(560, 900);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Pagamentos'));
    await tester.pumpAndSettle();

    expect(find.text('Pix manual'), findsOneWidget);
    expect(find.text('Pix InfinitePay'), findsOneWidget);
    expect(find.text('Pagamento na entrega'), findsOneWidget);
    expect(find.text('Aceitar crédito na entrega'), findsOneWidget);
    expect(find.text('Aceitar débito na entrega'), findsOneWidget);
    expect(find.textContaining('Nunca será marcado como pago'), findsOneWidget);
  });
}

const _session = Session(
  apiBaseUrl: 'http://127.0.0.1:8000',
  token: 'test',
  userId: 1,
  role: 'admin',
  companyCode: 'test',
  companyName: 'Teste',
  businessType: 'market',
  planCode: 'pro',
  enabledModules: ['pedeon'],
  permissions: [
    'pedeon:view',
    'pedeon:settings',
    'pedeon:payments',
    'pedeon:terminals',
  ],
);

class _FakePedeOnRepository implements PedeOnRepository {
  @override
  Future<PedeOnOrderPage> loadOrders({
    String? status,
    String? source,
    int page = 1,
  }) async =>
      PedeOnOrderPage(items: const [], page: page, total: 0, totalPages: 1);

  @override
  Future<PedeOnOrderDetail> loadOrder(int orderId) =>
      throw UnimplementedError();

  @override
  Future<PedeOnOrderDetail> updateOrderStatus(int orderId, String status) =>
      throw UnimplementedError();

  @override
  Future<PedeOnOrderDetail> confirmPayment(int orderId) =>
      throw UnimplementedError();

  final settings = PedeOnSettings(
    store: PedeOnStoreSettings(
      id: 1,
      publicSlug: 'loja-teste',
      displayName: 'Loja Teste',
      description: 'Descrição',
      active: true,
      acceptingOrders: true,
      acceptanceMode: 'manual',
      fulfillmentOptions: ['pickup'],
      minimumOrderAmount: 0,
    ),
    manualPix: PedeOnManualPixSettings(
      enabled: false,
      pickupEnabled: true,
      deliveryEnabled: true,
      keyType: 'random',
      pixKey: '',
      recipientName: '',
      instructions: '',
    ),
    infinitePay: PedeOnInfinitePaySettings(
      enabled: false,
      pickupEnabled: true,
      deliveryEnabled: true,
      handle: '',
      autoAcceptAfterConfirmation: true,
    ),
    deliveryCard: PedeOnDeliveryCardSettings(
      cashEnabled: false,
      pixEnabled: false,
      creditEnabled: false,
      debitEnabled: false,
    ),
    pickupPayment: PedeOnPickupPaymentSettings(
      enabled: false,
      acceptedMethods: const [],
    ),
    deliveryOperation: PedeOnDeliveryOperation(),
    terminals: [],
    fulfillmentStations: const [
      PedeOnFulfillmentStation(id: 1, code: 'cozinha', name: 'Cozinha'),
    ],
  );

  final catalog = const PedeOnCatalogPage(
    items: [
      PedeOnCatalogProduct(
        productId: 10,
        publicationId: null,
        productName: 'Produto Teste',
        internalCode: 'PRD-10',
        barcode: '',
        productImageUrl: '',
        productDescription: '',
        salePrice: 12.5,
        offerPrice: null,
        stockQuantity: 3,
        unit: 'un',
        categoryId: null,
        displayName: '',
        description: '',
        imageUrl: '',
        onlinePrice: null,
        published: false,
        available: true,
        useProductOffer: true,
        sortOrder: 0,
      ),
    ],
    categories: [
      PedeOnCategory(
        id: 1,
        name: 'Lanches',
        slug: 'lanches',
        description: '',
        active: true,
        sortOrder: 10,
      ),
      PedeOnCategory(
        id: 2,
        name: 'Bebidas',
        slug: 'bebidas',
        description: '',
        active: true,
        sortOrder: 20,
      ),
    ],
    modifierGroups: [],
    page: 1,
    pageSize: 20,
    total: 1,
    totalPages: 1,
  );

  @override
  Future<PedeOnSettings> load() async => settings;
  @override
  Future<PedeOnCatalogPage> loadCatalog({
    String search = '',
    int page = 1,
  }) async => catalog;
  @override
  Future<List<PedeOnCatalogProduct>> searchCatalogProducts(
    String search,
  ) async => catalog.items;
  @override
  Future<PedeOnCategory> createCategory(
    String name,
    String description,
  ) async => const PedeOnCategory(
    id: 1,
    name: 'Nova',
    slug: 'nova',
    description: '',
    active: true,
    sortOrder: 10,
  );
  @override
  Future<PedeOnCategory> updateCategory(PedeOnCategory category) async =>
      category;
  @override
  Future<void> deleteCategory(int categoryId) async {}
  @override
  Future<PedeOnCatalogProduct> savePublication(
    PedeOnCatalogProduct product,
  ) async => product;
  @override
  Future<List<PedeOnCategory>> reorderCategories(List<int> categoryIds) async {
    final byId = {
      for (final category in catalog.categories) category.id: category,
    };
    return categoryIds.map((id) => byId[id]!).toList();
  }

  @override
  Future<PedeOnModifierGroup> saveModifierGroup(
    PedeOnModifierGroup group,
  ) async => group;
  @override
  Future<void> deleteModifierGroup(int groupId) async {}
  @override
  Future<PedeOnSettings> saveInfinitePay(
    PedeOnInfinitePaySettings value,
  ) async => settings;
  @override
  Future<PedeOnSettings> saveDeliveryCard(
    PedeOnDeliveryCardSettings value,
  ) async => settings;
  @override
  Future<PedeOnSettings> savePickupPayment(
    PedeOnPickupPaymentSettings value,
  ) async => settings;
  @override
  Future<PedeOnSettings> saveDeliveryOperation(
    PedeOnDeliveryOperation value,
  ) async => settings;
  @override
  Future<PedeOnSettings> saveManualPix(PedeOnManualPixSettings value) async =>
      settings;
  @override
  Future<PedeOnSettings> saveStore(PedeOnStoreSettings value) async => settings;

  @override
  Future<PedeOnSettings> uploadStoreMedia({
    required String mediaType,
    required Uint8List bytes,
    required String filename,
  }) async => settings;
  @override
  Future<PedeOnSettings> saveTerminal(PedeOnTerminalSettings terminal) async =>
      settings;

  @override
  Future<PedeOnSettings> saveStation(PedeOnFulfillmentStation station) async =>
      settings;

  @override
  Future<PedeOnDeliveryZone> saveDeliveryZone(PedeOnDeliveryZone zone) async =>
      zone;

  @override
  Future<void> deleteDeliveryZone(int zoneId) async {}
}
