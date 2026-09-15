import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/features/pedeon/domain/pedeon_settings.dart';
import 'package:papezzosync_admin/features/pedeon/presentation/modifier_group_editor_dialog.dart';

void main() {
  testWidgets('guia o cadastro do ponto da carne com respostas gratuitas', (
    tester,
  ) async {
    PedeOnModifierGroup? saved;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: FilledButton(
              onPressed: () async {
                saved = await showModifierGroupEditor(
                  context,
                  products: const [],
                  searchProducts: (_) async => const [],
                );
              },
              child: const Text('Novo grupo'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Novo grupo'));
    await tester.pumpAndSettle();
    expect(find.text('Preparo'), findsOneWidget);
    expect(find.text('Adicionais'), findsOneWidget);
    expect(find.text('Produto do estoque'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'Qual o ponto da carne?',
    );
    await tester.scrollUntilVisible(
      find.byKey(const Key('modifier-add-manual')),
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.byKey(const Key('modifier-add-manual')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField).last,
      'Bem passado',
    );
    await tester.tap(find.text('Adicionar').last);
    await tester.pumpAndSettle();
    expect(find.text('Bem passado'), findsOneWidget);
    expect(find.text('Resposta sem acréscimo'), findsOneWidget);

    await tester.tap(find.text('Salvar pergunta'));
    await tester.pumpAndSettle();
    expect(saved?.minimumSelections, 1);
    expect(saved?.maximumSelections, 1);
    expect(saved?.options.single.priceDelta, 0);
  });
}
