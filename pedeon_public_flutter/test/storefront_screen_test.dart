import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_public/src/data/catalog_repository.dart';
import 'package:pedeon_public/src/domain/catalog_models.dart';
import 'package:pedeon_public/src/domain/customer_auth.dart';
import 'package:pedeon_public/src/presentation/storefront_screen.dart';

const _testCustomer = CustomerSession(
  token: 'test-token',
  id: 1,
  name: 'Cliente teste',
  email: 'cliente@example.com',
);

void main() {
  testWidgets('exibe catálogo e adiciona item no desktop', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialCustomer: _testCustomer,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Padaria Drika'), findsOneWidget);
    expect(find.text('Pães'), findsWidgets);
    expect(find.text('Pão francês'), findsOneWidget);
    expect(find.text('Seu pedido'), findsNothing);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();

    expect(find.text('Pão francês foi adicionado.'), findsOneWidget);
    expect(find.text('Seu pedido'), findsNothing);
    expect(find.byKey(const Key('open-cart-floating')), findsOneWidget);

    await tester.pump(const Duration(seconds: 3));
    expect(find.text('Pão francês foi adicionado.'), findsNothing);

    await tester.tap(find.byKey(const Key('open-cart-header')));
    await tester.pumpAndSettle();

    expect(find.text('Seu pedido'), findsOneWidget);
    expect(find.text('R\$ 1,20'), findsWidgets);
  });

  testWidgets('adapta para celular e abre carrinho inferior', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialCustomer: _testCustomer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-product-1')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();

    expect(find.text('Ver pedido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('detalhe ocupa a tela do celular sem esconder o conteúdo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(selectedProduct: _FakeRepository.burger),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const Key('add-product-2')),
      300,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).first,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-2')));
    await tester.pumpAndSettle();

    expect(find.byType(Dialog), findsOneWidget);
    expect(find.text('X-Burger').hitTestable(), findsWidgets);
    expect(
      find.byKey(const Key('add-configured-product')).hitTestable(),
      findsOneWidget,
    );
    await tester.scrollUntilVisible(
      find.text('Quer adicionar uma bebida?'),
      240,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView).last,
            matching: find.byType(Scrollable),
          )
          .first,
    );
    expect(
      find.text('Quer adicionar uma bebida?').hitTestable(),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('categorias formam seções e acompanham a rolagem', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _SectionedRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pães'), findsWidgets);
    expect(find.text('Bebidas'), findsWidgets);
    expect(find.text('Tudo'), findsNothing);
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Pães'))
          .selected,
      isTrue,
    );
    await tester.tap(find.widgetWithText(ChoiceChip, 'Bebidas'));
    await tester.pumpAndSettle();

    final bebidasChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Bebidas'),
    );
    expect(bebidasChip.selected, isTrue);
    expect(find.text('Refrigerante').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('finaliza checkout sem duplicar a venda no cliente', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialCustomer: _testCustomer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add-product-1')));
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-cart-header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-cart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-checkout')));
    await tester.pumpAndSettle();
    await _selectPickup(tester);

    expect(find.text('Finalizar pedido'), findsOneWidget);
    await tester.enterText(
      find.byKey(const Key('checkout-name')),
      'Cliente Teste',
    );
    await tester.enterText(
      find.byKey(const Key('checkout-phone')),
      '11999999999',
    );
    await tester.tap(find.byKey(const Key('submit-order')));
    await tester.pumpAndSettle();

    expect(find.text('Pedido recebido!'), findsOneWidget);
    expect(find.text('PED-000001'), findsOneWidget);
    expect(find.text('Copiar chave Pix'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('maquininha aparece apenas quando o cliente escolhe entrega', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialCustomer: _testCustomer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-cart-header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-cart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-checkout')));
    await tester.pumpAndSettle();

    expect(find.text('Crédito na entrega'), findsNothing);
    expect(find.text('Débito na entrega'), findsNothing);

    await tester.tap(find.text('Entrega'));
    await tester.pumpAndSettle();

    expect(find.text('Crédito'), findsOneWidget);
    expect(find.text('Débito'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('entrega calcula automaticamente antes de criar o pedido', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final repository = _FakeRepository();
    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: repository,
          initialCustomer: _testCustomer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-cart-header')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-cart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-checkout')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Entrega'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('checkout-name')), 'Cliente');
    await tester.enterText(
      find.byKey(const Key('checkout-phone')),
      '11999999999',
    );
    await tester.enterText(
      find.byKey(const Key('checkout-postal-code')),
      '01001000',
    );
    await tester.enterText(
      find.byKey(const Key('checkout-street')),
      'Praça da Sé',
    );
    await tester.enterText(find.byKey(const Key('checkout-number')), '1');
    await tester.enterText(
      find.byKey(const Key('checkout-neighborhood')),
      'Sé',
    );
    await tester.enterText(find.byKey(const Key('checkout-city')), 'São Paulo');
    await tester.enterText(find.byKey(const Key('checkout-state')), 'SP');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    expect(repository.deliveryQuoteCalls, 1);
    expect(find.text('Pedido recebido!'), findsNothing);
    expect(find.text('Área teste'), findsOneWidget);
    expect(find.text('R\$ 6,20'), findsWidgets);
    expect(find.textContaining('Fazer pedido'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('checkout mobile usa uma rolagem única até o resumo', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialCustomer: _testCustomer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('add-product-1')));
    await tester.drag(
      find.byType(CustomScrollView).first,
      const Offset(0, -100),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ver pedido'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-cart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-checkout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkout-scroll')), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('checkout-phone')));
    await tester.enterText(
      find.byKey(const Key('checkout-phone')),
      '11999999999',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('checkout-mobile-summary')),
      350,
      scrollable: find
          .descendant(
            of: find.byKey(const Key('checkout-scroll')),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Resumo'), findsOneWidget);
    expect(find.byKey(const Key('submit-order')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('resumo desktop exibe os itens mesmo em janela baixa', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 650);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialCustomer: _testCustomer,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -420));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-cart-floating')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('review-cart')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('continue-checkout')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('checkout-summary-product-1')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('produto exige opção obrigatória antes de adicionar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(selectedProduct: _FakeRepository.burger),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();

    final productScroll = tester.state<ScrollableState>(
      find.byType(Scrollable).last,
    );
    productScroll.position.jumpTo(productScroll.position.maxScrollExtent);
    await tester.pumpAndSettle();

    expect(find.textContaining('Escolha 1 opção'), findsOneWidget);
    expect(find.text('Coca-Cola'), findsOneWidget);
    await tester.tap(find.text('Coca-Cola'));
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('open-cart-floating')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'adiciona várias unidades preservando opções e observação em uma linha',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        MaterialApp(
          home: StorefrontScreen(
            slug: 'padaria-drika',
            repository: _FakeRepository(
              selectedProduct: _FakeRepository.burger,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('add-product-2')));
      await tester.pumpAndSettle();

      final productScroll = tester.state<ScrollableState>(
        find.byType(Scrollable).last,
      );
      productScroll.position.jumpTo(productScroll.position.maxScrollExtent);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coca-Cola'));
      await tester.enterText(
        find.byKey(const Key('product-notes')),
        'Sem cebola',
      );
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('increase-product-quantity')));
      await tester.tap(find.byKey(const Key('increase-product-quantity')));
      await tester.pump();

      expect(
        tester.widget<Text>(find.byKey(const Key('product-quantity'))).data,
        '3',
      );
      expect(find.text('Adicionar 3 itens • R\$ 99,00'), findsOneWidget);

      await tester.tap(find.byKey(const Key('add-configured-product')));
      await tester.pumpAndSettle();
      expect(
        find.text('3× X-Burger foram adicionados com a mesma configuração.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('open-cart-floating')));
      await tester.pumpAndSettle();
      expect(
        find.text('Quer adicionar uma bebida?: Coca-Cola'),
        findsOneWidget,
      );
      expect(find.text('Obs.: Sem cebola'), findsOneWidget);
      expect(find.text('R\$ 99,00'), findsWidgets);
      expect(find.text('3'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('abre produto compartilhado diretamente pelo link', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialProductId: 2,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('X-Burger'), findsWidgets);
    expect(find.text('Quer adicionar uma bebida?'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('compartilhamento local copia o link exato do produto', (
    tester,
  ) async {
    String? copiedText;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          copiedText =
              (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
          initialProductId: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Compartilhar'));
    await tester.pumpAndSettle();

    expect(copiedText, contains('/padaria-drika?produto=1'));
    expect(find.text('Link do produto copiado.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('puxar o catálogo para baixo atualiza os dados', (tester) async {
    tester.view.physicalSize = const Size(390, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _FakeRepository();

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(slug: 'padaria-drika', repository: repository),
      ),
    );
    await tester.pumpAndSettle();
    expect(repository.loadCalls, 1);

    await tester.drag(
      find.byKey(const Key('catalog-scroll')),
      const Offset(0, 340),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(repository.loadCalls, 2);
    expect(tester.takeException(), isNull);
  });

  testWidgets('duplica configuração existente pelo carrinho', (tester) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-cart-floating')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ações deste item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adicionar outro igual'));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsWidgets);
    expect(find.text('R\$ 2,40'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('edita item do carrinho preservando a personalização', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StorefrontScreen(
          slug: 'padaria-drika',
          repository: _FakeRepository(selectedProduct: _FakeRepository.burger),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('add-product-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Coca-Cola'));
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open-cart-floating')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ações deste item'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Editar personalização'));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.radio_button_checked_rounded), findsOneWidget);
    await tester.tap(find.byKey(const Key('increase-product-quantity')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('add-configured-product')));
    await tester.pumpAndSettle();

    expect(find.text('R\$ 66,00'), findsWidgets);
    expect(find.text('2'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}

Future<void> _selectPickup(WidgetTester tester) async {
  await tester.tap(find.text('Retirar'));
  await tester.pumpAndSettle();
  await tester.tap(
    find.widgetWithText(FilledButton, 'Confirmar retirada').last,
  );
  await tester.pumpAndSettle();
  final pix = find.text('Pix manual');
  if (pix.evaluate().isNotEmpty) {
    await tester.tap(pix.first);
    await tester.pumpAndSettle();
  }
}

class _FakeRepository implements CatalogRepository {
  _FakeRepository({this.selectedProduct = product});

  final CatalogProduct selectedProduct;
  int loadCalls = 0;
  int deliveryQuoteCalls = 0;
  static const product = CatalogProduct(
    id: 1,
    categoryId: 1,
    name: 'Pão francês',
    price: 1.2,
    normalPrice: 1.2,
    onOffer: false,
    available: true,
    unit: 'un',
  );
  static const burger = CatalogProduct(
    id: 2,
    categoryId: 1,
    name: 'X-Burger',
    price: 25,
    normalPrice: 25,
    onOffer: false,
    available: true,
    unit: 'un',
    modifierGroups: [
      ModifierGroup(
        id: 10,
        name: 'Quer adicionar uma bebida?',
        minimumSelections: 1,
        maximumSelections: 1,
        options: [ModifierOption(id: 100, name: 'Coca-Cola', priceDelta: 8)],
      ),
    ],
  );

  @override
  Future<PublicOrder> createOrder(
    String slug,
    CheckoutInput input,
    List<CartLine> lines, {
    String? customerToken,
  }) async => PublicOrder(
    orderId: 'order-1',
    trackingToken: 'tracking-token',
    displayNumber: 'PED-000001',
    status: 'awaiting_payment',
    paymentStatus: 'awaiting_manual_confirmation',
    fulfillmentType: input.fulfillmentType,
    customerName: input.customerName,
    subtotal: 1.2,
    deliveryFee: 0,
    total: 1.2,
    createdAt: DateTime(2026, 8, 22),
    payment: const PublicPayment(
      method: 'manual_pix',
      status: 'awaiting_manual_confirmation',
      displayName: 'Pix manual',
      pixKey: 'pix@padaria.test',
      recipientName: 'Padaria Drika',
    ),
  );

  @override
  Future<CustomerSession> registerCustomer(
    String slug, {
    required String name,
    required String email,
    required String password,
    String? phone,
  }) async => const CustomerSession(
    token: 'test-token',
    id: 1,
    name: 'Cliente teste',
    email: 'cliente@example.com',
  );

  @override
  Future<CustomerSession> loginCustomer(
    String slug, {
    required String email,
    required String password,
  }) async => const CustomerSession(
    token: 'test-token',
    id: 1,
    name: 'Cliente teste',
    email: 'cliente@example.com',
  );

  @override
  Future<CustomerSession?> currentCustomer(
    String slug, {
    String? token,
  }) async => null;

  @override
  Future<void> logoutCustomer(String slug, {String? token}) async {}

  @override
  Future<String> startSocialLogin(String slug, String provider) async =>
      'https://accounts.google.com';

  @override
  Future<CustomerSession> exchangeSocialCode(
    String slug,
    String provider,
    String code,
  ) async =>
      const CustomerSession(
        token: 'google-test-token',
        id: 1,
        name: 'Cliente Google',
        email: 'cliente@example.com',
      );

  @override
  Future<CustomerSession> updateCustomerProfile(
    String slug, {
    required String token,
    String? document,
    DeliveryAddress? deliveryAddress,
  }) async => CustomerSession(
    token: token,
    id: 1,
    name: 'Cliente teste',
    email: 'cliente@example.com',
    document: document,
    deliveryAddress: deliveryAddress,
  );

  @override
  Future<CatalogPage> load(
    String slug, {
    String search = '',
    String? category,
    int page = 1,
  }) async {
    loadCalls++;
    return CatalogPage(
      store: Storefront(
        slug: 'padaria-drika',
        displayName: 'Padaria Drika',
        description: 'Pães fresquinhos todos os dias.',
        acceptingOrders: true,
        fulfillmentOptions: ['pickup', 'delivery'],
        minimumOrderAmount: 0,
        paymentMethods: [
          PaymentOption(method: 'manual_pix', displayName: 'Pix manual'),
          PaymentOption(
            method: 'credit_card_on_delivery',
            displayName: 'Crédito na entrega',
          ),
          PaymentOption(
            method: 'debit_card_on_delivery',
            displayName: 'Débito na entrega',
          ),
        ],
      ),
      categories: [CatalogCategory(id: 1, name: 'Pães', slug: 'paes')],
      items: [selectedProduct],
      page: 1,
      totalPages: 1,
    );
  }

  @override
  Future<CartQuote> quote(
    String slug,
    List<CartLine> lines, {
    String fulfillmentType = 'pickup',
    DeliveryAddress? deliveryAddress,
  }) async {
    if (fulfillmentType == 'delivery') deliveryQuoteCalls++;
    return fulfillmentType == 'delivery'
        ? const CartQuote(
            subtotal: 1.2,
            minimumOrderAmount: 0,
            minimumOrderReached: true,
            deliveryFee: 5,
            total: 6.2,
            deliveryZoneName: 'Área teste',
            estimatedMinutesMin: 30,
            estimatedMinutesMax: 45,
          )
        : const CartQuote(
            subtotal: 1.2,
            minimumOrderAmount: 0,
            minimumOrderReached: true,
            deliveryFee: 0,
            total: 1.2,
          );
  }

  @override
  Future<PublicOrder> trackOrder(String slug, String trackingToken) async =>
      PublicOrder(
        orderId: 'order-1',
        trackingToken: trackingToken,
        displayNumber: 'PED-000001',
        status: 'awaiting_acceptance',
        paymentStatus: 'paid',
        fulfillmentType: 'pickup',
        customerName: 'Cliente teste',
        subtotal: 1.2,
        deliveryFee: 0,
        total: 1.2,
        createdAt: DateTime(2026, 8, 22),
        payment: const PublicPayment(
          method: 'manual_pix',
          status: 'paid',
          displayName: 'Pix manual',
        ),
      );

  @override
  String imageUrl(String? value) => '';

  @override
  Future<CatalogProduct?> loadProduct(String slug, int productId) async =>
      productId == burger.id
      ? burger
      : productId == product.id
      ? product
      : null;
}

class _SectionedRepository extends _FakeRepository {
  static const drink = CatalogProduct(
    id: 3,
    categoryId: 2,
    name: 'Refrigerante',
    price: 8,
    normalPrice: 8,
    onOffer: false,
    available: true,
    unit: 'un',
  );

  @override
  Future<CatalogPage> load(
    String slug, {
    String search = '',
    String? category,
    int page = 1,
  }) async => CatalogPage(
    store: Storefront(
      slug: slug,
      displayName: 'Padaria Drika',
      acceptingOrders: true,
      fulfillmentOptions: const ['pickup'],
      minimumOrderAmount: 0,
    ),
    categories: const [
      CatalogCategory(id: 1, name: 'Pães', slug: 'paes'),
      CatalogCategory(id: 2, name: 'Bebidas', slug: 'bebidas'),
    ],
    items: const [_FakeRepository.product, drink],
    page: 1,
    totalPages: 1,
  );
}
