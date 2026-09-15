import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pedeon_operations/data/repositories/operations_repository.dart';
import 'package:pedeon_operations/data/services/edge_api_service.dart';
import 'package:pedeon_operations/data/services/terminal_credentials_store.dart';
import 'package:pedeon_operations/domain/models/operation_order.dart';
import 'package:pedeon_operations/ui/features/operations/view_models/operations_view_model.dart';
import 'package:pedeon_operations/ui/features/operations/views/checkout_view.dart';

void main() {
  testWidgets('caixa bloqueia recebimento ate existir sessao autenticada', (
    tester,
  ) async {
    final viewModel =
        OperationsViewModel(
            OperationsRepository(
              edgeApi: EdgeApiService(baseUrl: Uri.parse('http://edge.local')),
              credentials: TerminalCredentialsStore(),
            ),
          )
          ..orders = [
            OperationOrder(
              publicId: 'PED-1',
              number: '#101',
              status: 'ready',
              paymentStatus: 'pending',
              source: 'pedeon',
              fulfillment: 'pickup',
              customerName: 'Cliente',
              notes: '',
              createdAt: DateTime(2026, 8, 24),
              items: const [
                OperationOrderItem(
                  name: 'Pedido',
                  quantity: 1,
                  notes: '',
                  modifiers: [],
                ),
              ],
              total: 25,
            ),
          ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: CheckoutView(viewModel: viewModel)),
      ),
    );

    expect(
      find.text('Abra o caixa para começar os recebimentos.'),
      findsOneWidget,
    );
    expect(find.text('Abrir caixa'), findsOneWidget);
    final receive = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Receber pedido'),
    );
    expect(receive.onPressed, isNull);
  });
}
