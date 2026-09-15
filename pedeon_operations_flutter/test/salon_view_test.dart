import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_operations/data/repositories/operations_repository.dart';
import 'package:pedeon_operations/data/services/edge_api_service.dart';
import 'package:pedeon_operations/data/services/terminal_credentials_store.dart';
import 'package:pedeon_operations/domain/models/local_catalog.dart';
import 'package:pedeon_operations/ui/features/operations/view_models/operations_view_model.dart';
import 'package:pedeon_operations/ui/features/operations/views/salon_view.dart';

void main() {
  test('catálogo respeita o canal habilitado no produto', () {
    final product = CatalogProduct.fromJson({
      'id': 2,
      'name': 'X-Burger',
      'description': '',
      'price': 20,
      'available': true,
      'enabled_channels': ['pdv_counter'],
      'modifier_groups': <dynamic>[],
    });

    expect(product.isEnabledFor('pdv_counter'), isTrue);
    expect(product.isEnabledFor('onsite_waiter'), isFalse);
  });

  testWidgets('celular escolhe categoria antes de mostrar produtos', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel = _viewModelWithCatalog();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SalonView(viewModel: viewModel, initialTable: '1'),
        ),
      ),
    );

    expect(find.text('Lanches'), findsOneWidget);
    expect(find.text('X-Burger'), findsNothing);
    await tester.tap(find.text('Lanches'));
    await tester.pump();
    expect(find.text('X-Burger'), findsOneWidget);
  });

  testWidgets('salão configura adicional e quantidade antes de incluir', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final viewModel =
        OperationsViewModel(
            OperationsRepository(
              edgeApi: EdgeApiService(baseUrl: Uri.parse('http://edge.local')),
              credentials: TerminalCredentialsStore(),
            ),
          )
    ..catalog = const LocalCatalog(
      storeName: 'Loja',
      publicSlug: 'drikapadaria',
            categories: [CatalogCategory(id: 1, name: 'Lanches')],
            products: [
              CatalogProduct(
                id: 2,
                categoryId: 1,
                name: 'X-Burger',
                description: 'Artesanal',
                price: 20,
                available: true,
                enabledChannels: {'onsite_waiter'},
                modifierGroups: [
                  ModifierGroup(
                    name: 'Adicionais',
                    minimum: 0,
                    maximum: 2,
                    options: [ModifierOption(id: 3, name: 'Bacon', price: 3)],
                  ),
                ],
              ),
            ],
          );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: SalonView(viewModel: viewModel)),
      ),
    );
    await tester.tap(find.text('X-Burger'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bacon'));
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump();

    expect(find.text('Adicionar 2 • R\$ 46,00'), findsOneWidget);
    await tester.tap(find.text('Adicionar 2 • R\$ 46,00'));
    await tester.pumpAndSettle();
    expect(viewModel.cart.single.quantity, 2);
    expect(viewModel.cart.single.total, 46);
  });
}

OperationsViewModel _viewModelWithCatalog() =>
    OperationsViewModel(
        OperationsRepository(
          edgeApi: EdgeApiService(baseUrl: Uri.parse('http://edge.local')),
          credentials: TerminalCredentialsStore(),
        ),
      )
    ..catalog = const LocalCatalog(
      storeName: 'Loja',
      publicSlug: 'drikapadaria',
        categories: [CatalogCategory(id: 1, name: 'Lanches')],
        products: [
          CatalogProduct(
            id: 2,
            categoryId: 1,
            name: 'X-Burger',
            description: 'Artesanal',
            price: 20,
            available: true,
            enabledChannels: {'onsite_waiter'},
            modifierGroups: [],
          ),
        ],
      );
