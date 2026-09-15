import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_operations/domain/models/operation_order.dart';
import 'package:pedeon_operations/ui/features/operations/views/order_board.dart';

void main() {
  testWidgets('KDS mostra origem, itens, adicionais e avanca o pedido', (
    tester,
  ) async {
    String? transition;
    final order = OperationOrder(
      publicId: 'PED-1',
      number: '#101',
      status: 'in_preparation',
      paymentStatus: 'pending',
      source: 'ifood',
      fulfillment: 'delivery',
      customerName: 'Cliente',
      createdAt: DateTime(2026, 8, 24, 10, 30),
      notes: 'Sem talher',
      items: const [
        OperationOrderItem(
          name: 'X-Burger',
          quantity: 2,
          notes: 'Sem cebola',
          modifiers: ['Ao ponto', 'Bacon'],
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderBoard(
            title: 'Cozinha',
            orders: [order],
            actionStatus: 'ready',
            onTransition: (_, status) async => transition = status,
          ),
        ),
      ),
    );

    expect(find.text('IFOOD'), findsOneWidget);
    expect(find.text('2× X-Burger'), findsOneWidget);
    expect(find.text('Ao ponto • Bacon'), findsOneWidget);
    expect(find.text('Obs.: Sem cebola'), findsOneWidget);
    await tester.tap(find.text('Marcar como pronto'));
    await tester.pump();
    expect(transition, 'ready');
  });

  testWidgets('painel vazio informa que a operacao esta em dia', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: OrderBoard(
            title: 'Cozinha',
            orders: const [],
            actionStatus: 'ready',
            onTransition: (_, _) async {},
          ),
        ),
      ),
    );
    expect(find.text('Tudo em dia'), findsOneWidget);
  });
}
