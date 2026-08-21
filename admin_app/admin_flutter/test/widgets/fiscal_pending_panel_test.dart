import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:papezzosync_admin/models/fiscal.dart';
import 'package:papezzosync_admin/models/session.dart';
import 'package:papezzosync_admin/screens/fiscal_screen.dart';

void main() {
  test('fiscal can be enabled by a company-specific module override', () {
    const session = Session(
      apiBaseUrl: 'http://localhost',
      token: 'token',
      userId: 1,
      role: 'admin',
      companyCode: 'cliente',
      companyName: 'Cliente',
      businessType: 'custom',
      planCode: 'start',
      enabledModules: ['fiscal'],
      permissions: ['fiscal:view'],
    );

    expect(session.canUseFiscal, isTrue);
  });

  testWidgets('shows fiscal gaps and opens rule configuration', (tester) async {
    var configureCalls = 0;
    int? configuredProductId;
    int? editedProductId;
    final compliance = RtcCompliance(
      effectiveCrt: '3',
      mandatory: true,
      ready: false,
      message: 'Existem produtos com dados fiscais pendentes.',
      documentModel: '65',
      productsTotal: 2,
      productsIncomplete: 1,
      incompleteProducts: const [
        RtcIncompleteProduct(
          id: 7,
          name: 'Produto sem classificação',
          internalCode: 'PRD-7',
          ncm: '19059090',
          missingFields: ['CST IBS/CBS deve ter 3 dígitos'],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FiscalPendingPanel(
              compliance: compliance,
              canManage: true,
              onConfigureRule: () => configureCalls++,
              onConfigureProductRule: (product) =>
                  configuredProductId = product.id,
              onEditProduct: (product) => editedProductId = product.id,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pendências fiscais'), findsOneWidget);
    expect(find.textContaining('Produto sem classificação'), findsOneWidget);
    expect(find.textContaining('CST IBS/CBS'), findsOneWidget);

    await tester.tap(find.text('Criar regra em massa'));
    await tester.pumpAndSettle();
    expect(configureCalls, 1);

    await tester.tap(find.text('Regra deste produto'));
    await tester.pumpAndSettle();
    expect(configuredProductId, 7);

    await tester.tap(find.text('Editar produto'));
    await tester.pumpAndSettle();
    expect(editedProductId, 7);
  });

  testWidgets('paginates fiscal products in groups of five', (tester) async {
    final products = List.generate(
      12,
      (index) => RtcIncompleteProduct(
        id: index + 1,
        name: 'Produto ${index + 1}',
        internalCode: 'P${index + 1}',
        missingFields: const ['NCM deve ter 8 dígitos'],
      ),
    );
    final compliance = RtcCompliance(
      effectiveCrt: '4',
      mandatory: false,
      ready: false,
      message: 'Produtos pendentes.',
      documentModel: '65',
      productsTotal: 12,
      productsIncomplete: 12,
      incompleteProducts: products,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: FiscalPendingPanel(
              compliance: compliance,
              canManage: true,
              onConfigureRule: () {},
              onConfigureProductRule: (_) {},
              onEditProduct: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Editar produto'), findsNWidgets(5));
    expect(find.text('P1 - Produto 1'), findsOneWidget);
    expect(find.text('P6 - Produto 6'), findsNothing);
    expect(find.byKey(const Key('pending-products-page-3')), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const Key('pending-products-page-2')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('pending-products-page-2')));
    await tester.pumpAndSettle();

    expect(find.text('Editar produto'), findsNWidgets(5));
    expect(find.text('P1 - Produto 1'), findsNothing);
    expect(find.text('P6 - Produto 6'), findsOneWidget);
    expect(find.text('Mostrando 6–10 de 12 produtos'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
