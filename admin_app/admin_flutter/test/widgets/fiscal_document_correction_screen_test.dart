import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:papezzosync_admin/models/fiscal.dart';
import 'package:papezzosync_admin/screens/fiscal_document_correction_screen.dart';

void main() {
  FiscalDocument document({int? number}) {
    final now = DateTime(2026, 8, 21, 10);
    return FiscalDocument(
      id: 80,
      saleId: 48,
      documentType: 'nfe',
      model: '55',
      series: 1,
      number: number,
      status: number == null ? 'pending_configuration' : 'rejected',
      environment: 'homologacao',
      operationNature: '',
      sefazMessage: 'NCM obrigatório para o item 1.',
      fiscalItems: const [
        FiscalDraftItem(
          id: 1,
          fiscalProductId: 5,
          fiscalDescription: 'Produto para correção',
          quantity: 1,
          unit: 'UN',
          unitPrice: 10,
          discountAmount: 0,
          totalPrice: 10,
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  Future<void> pumpAtWidth(
    WidgetTester tester,
    double width,
    FiscalDocument fiscalDocument,
  ) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        home: FiscalDocumentCorrectionScreen(
          document: fiscalDocument,
          clients: const [],
          onBack: () {},
          onSave: (_, _, _) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('keeps a rejected number and exposes the complete editor', (
    tester,
  ) async {
    await pumpAtWidth(tester, 1400, document(number: 80));

    expect(find.textContaining('número 80 será preservado'), findsOneWidget);
    expect(find.text('Operação e destinatário'), findsOneWidget);
    expect(find.text('Produtos e tributação'), findsOneWidget);
    await tester.drag(
      find.byKey(const Key('fiscal-correction-scroll')),
      const Offset(0, -700),
    );
    await tester.pumpAndSettle();
    expect(find.text('Frete, transportadora e volumes'), findsOneWidget);
    expect(find.text('Salvar e reenviar nº 80'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'uses the no-number flow without overflowing on a narrow screen',
    (tester) async {
      await pumpAtWidth(tester, 680, document());

      expect(find.textContaining('Ainda sem número'), findsOneWidget);
      expect(find.byKey(const Key('save-resend')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
