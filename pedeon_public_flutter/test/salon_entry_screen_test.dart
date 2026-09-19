import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_public/src/presentation/salon_entry_screen.dart';

void main() {
  testWidgets('tocar em mesa abre imediatamente a conta selecionada', (
    tester,
  ) async {
    ({String type, int number})? selected;
    await tester.pumpWidget(
      MaterialApp(
        home: SalonEntryScreen(
          slug: 'padaria-drika',
          onAccountSelected: (type, number) =>
              selected = (type: type, number: number),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('salon-account-3')));

    expect(selected, (type: 'mesa', number: 3));
    expect(find.text('Comandas'), findsNothing);
    expect(
      find.textContaining('selecionada para este atendimento'),
      findsNothing,
    );
  });
}
