import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/models/fiscal.dart';
import 'package:papezzosync_admin/widgets/fiscal_numbering_dialog.dart';

void main() {
  testWidgets('mostra os dois modelos e só fecha pelo comando do usuário', (
    tester,
  ) async {
    const status = FiscalNumberingStatus(
      environment: 'homologacao',
      nfceSeries: 1,
      nfceLastAuthorizedNumber: 69,
      nfceNextNumber: 72,
      nfeSeries: 1,
      nfeLastAuthorizedNumber: 12,
      nfeNextNumber: 13,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => showDialog<void>(
              context: context,
              barrierDismissible: false,
              builder: (_) => FiscalNumberingDialog(
                initialStatus: status,
                onSynchronize: () async => status,
              ),
            ),
            child: const Text('Abrir'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('nfce-numbering-card')), findsOneWidget);
    expect(find.byKey(const Key('nfe-numbering-card')), findsOneWidget);
    expect(find.text('NFC-e • Modelo 65 • Série 1'), findsOneWidget);
    expect(find.text('NF-e • Modelo 55 • Série 1'), findsOneWidget);
    expect(find.text('69'), findsOneWidget);
    expect(find.text('72'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.text('13'), findsOneWidget);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('Conferir numeração fiscal'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, 'Fechar'));
    await tester.pumpAndSettle();
    expect(find.text('Conferir numeração fiscal'), findsNothing);
  });
}
