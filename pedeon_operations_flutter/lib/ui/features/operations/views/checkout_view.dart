import 'package:flutter/material.dart';

import '../../../../domain/models/operation_order.dart';
import '../view_models/operations_view_model.dart';

class CheckoutView extends StatelessWidget {
  const CheckoutView({super.key, required this.viewModel});
  final OperationsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final orders = viewModel.orders
        .where(
          (order) =>
              order.status == 'ready' &&
              order.paymentStatus != 'confirmed',
        )
        .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Caixa', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  viewModel.cashSession == null
                      ? 'Abra o caixa para começar os recebimentos.'
                      : 'Caixa ${viewModel.cashSession!['cash_register_number']} • '
                            '${viewModel.cashSession!['operator_name']}',
                ),
              ),
              if (viewModel.cashSession == null)
                FilledButton.icon(
                  onPressed: () => _openCash(context),
                  icon: const Icon(Icons.lock_open_outlined),
                  label: const Text('Abrir caixa'),
                )
              else
                OutlinedButton.icon(
                  onPressed: () => _closeCash(context),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Fechar caixa'),
                ),
            ],
          ),
          const SizedBox(height: 18),
          Expanded(
            child: orders.isEmpty
                ? const Center(
                    child: Text(
                      'Nenhuma conta ou pedido pendente para receber.',
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth >= 1100
                            ? 3
                            : constraints.maxWidth >= 680
                            ? 2
                            : 1,
                        mainAxisExtent: 238,
                        crossAxisSpacing: 14,
                        mainAxisSpacing: 14,
                      ),
                      itemCount: orders.length,
                      itemBuilder: (_, index) => _OrderCheckoutCard(
                        order: orders[index],
                        onReceive: viewModel.cashSession == null
                            ? null
                            : () => _receive(context, orders[index]),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _receive(BuildContext context, OperationOrder order) async {
    final result = await showDialog<_CheckoutInput>(
      context: context,
      builder: (_) => _CheckoutDialog(order: order),
    );
    if (result == null || !context.mounted) return;
    final receipt = await viewModel.checkout(
      order,
      method: result.method,
      amountPaid: result.amount,
      authorizationCode: result.authorization,
    );
    if (!context.mounted) return;
    if (receipt != null) {
      final change = double.tryParse('${receipt['change_amount'] ?? 0}') ?? 0;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            change > 0
                ? 'Recebido localmente. Troco: R\$ ${change.toStringAsFixed(2)}'
                : 'Pagamento registrado. A sincronização seguirá automaticamente.',
          ),
        ),
      );
    }
  }

  Future<void> _openCash(BuildContext context) async {
    final input = await showDialog<CashOpeningInput>(
      context: context,
      builder: (_) => const CashOpeningDialog(),
    );
    if (input == null || !context.mounted) return;
    final opened = await viewModel.openCash(
      register: '01',
      openingAmount: input.openingAmount,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          opened
              ? 'Caixa aberto e pronto para operar.'
              : viewModel.error ?? 'Falha ao abrir caixa.',
        ),
      ),
    );
  }

  Future<void> _closeCash(BuildContext context) async {
    final input = await showDialog<_CashClosingInput>(
      context: context,
      builder: (_) => const _CashClosingDialog(),
    );
    if (input == null || !context.mounted) return;
    final closed = await viewModel.closeCash(
      code: input.code,
      pin: input.pin,
      countedCashAmount: input.countedCashAmount,
      notes: input.notes,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          closed
              ? 'Caixa fechado localmente. A tesouraria será atualizada automaticamente.'
              : viewModel.error ?? 'Falha ao fechar caixa.',
        ),
      ),
    );
  }
}

class _OrderCheckoutCard extends StatelessWidget {
  const _OrderCheckoutCard({required this.order, required this.onReceive});
  final OperationOrder order;
  final VoidCallback? onReceive;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  order.number,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Text(
                'R\$ ${order.total.toStringAsFixed(2)}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            [
              if (order.tableLabel?.isNotEmpty == true)
                'Mesa ${order.tableLabel}',
              if (order.commandLabel?.isNotEmpty == true)
                'Comanda ${order.commandLabel}',
              order.customerName,
            ].join(' • '),
          ),
          const Divider(height: 24),
          Expanded(
            child: ListView(
              children: [
                for (final item in order.items)
                  Text('${item.quantity}× ${item.name}'),
              ],
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onReceive,
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text('Receber pedido'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CheckoutDialog extends StatefulWidget {
  const _CheckoutDialog({required this.order});
  final OperationOrder order;
  @override
  State<_CheckoutDialog> createState() => _CheckoutDialogState();
}

class _CheckoutDialogState extends State<_CheckoutDialog> {
  String method = 'dinheiro';
  final amount = TextEditingController();
  final authorization = TextEditingController();
  @override
  void initState() {
    super.initState();
    amount.text = widget.order.total.toStringAsFixed(2).replaceAll('.', ',');
  }

  @override
  void dispose() {
    amount.dispose();
    authorization.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('Receber ${widget.order.number}'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Forma de pagamento'),
            items: const [
              DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
              DropdownMenuItem(value: 'pix', child: Text('Pix')),
              DropdownMenuItem(
                value: 'debito',
                child: Text('Cartão de débito'),
              ),
              DropdownMenuItem(
                value: 'credito',
                child: Text('Cartão de crédito'),
              ),
            ],
            onChanged: (value) => setState(() => method = value ?? method),
          ),
          const SizedBox(height: 12),
          TextFormField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: method == 'dinheiro' ? 'Valor recebido' : 'Valor',
              prefixText: 'R\$ ',
            ),
          ),
          if (method == 'debito' || method == 'credito') ...[
            const SizedBox(height: 12),
            TextFormField(
              controller: authorization,
              decoration: const InputDecoration(
                labelText: 'NSU/autorização (opcional)',
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final paid = double.tryParse(amount.text.replaceAll(',', '.'));
          if (paid == null || paid <= 0) {
            return;
          }
          Navigator.pop(
            context,
            _CheckoutInput(
              method,
              paid,
              authorization.text.trim().isEmpty
                  ? null
                  : authorization.text.trim(),
            ),
          );
        },
        child: const Text('Confirmar recebimento'),
      ),
    ],
  );
}

class _CheckoutInput {
  const _CheckoutInput(this.method, this.amount, this.authorization);
  final String method;
  final double amount;
  final String? authorization;
}

class CashOpeningDialog extends StatefulWidget {
  const CashOpeningDialog({super.key});
  @override
  State<CashOpeningDialog> createState() => _CashOpeningDialogState();
}

class _CashOpeningDialogState extends State<CashOpeningDialog> {
  final opening = TextEditingController(text: '0,00');
  @override
  void dispose() {
    opening.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Abrir caixa'),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Align(
            alignment: Alignment.centerLeft,
            child: Text('Usuário atualmente logado será vinculado ao caixa.'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: opening,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Fundo inicial',
              prefixText: 'R\$ ',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final value = double.tryParse(opening.text.replaceAll(',', '.'));
          if (value == null || value < 0) {
            return;
          }
          Navigator.pop(
            context,
            CashOpeningInput(
              value,
            ),
          );
        },
        child: const Text('Abrir caixa'),
      ),
    ],
  );
}

class CashOpeningInput {
  const CashOpeningInput(this.openingAmount);
  final double openingAmount;
}

class _CashClosingDialog extends StatefulWidget {
  const _CashClosingDialog();
  @override
  State<_CashClosingDialog> createState() => _CashClosingDialogState();
}

class _CashClosingDialogState extends State<_CashClosingDialog> {
  final code = TextEditingController();
  final pin = TextEditingController();
  final counted = TextEditingController(text: '0,00');
  final notes = TextEditingController();

  @override
  void dispose() {
    code.dispose();
    pin.dispose();
    counted.dispose();
    notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Fechar caixa'),
    content: SizedBox(
      width: 480,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Informe a conferência em dinheiro. O fechamento seguirá para a tesouraria, mesmo se a internet estiver indisponível.',
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: code,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Código do fiscal',
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: pin,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'PIN'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: counted,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Dinheiro contado (sem o fundo inicial)',
              prefixText: 'R\$ ',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observação (opcional)',
            ),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final value = double.tryParse(counted.text.replaceAll(',', '.'));
          if (code.text.trim().isEmpty ||
              pin.text.isEmpty ||
              value == null ||
              value < 0) {
            return;
          }
          Navigator.pop(
            context,
            _CashClosingInput(
              code.text.trim(),
              pin.text,
              value,
              notes.text.trim().isEmpty ? null : notes.text.trim(),
            ),
          );
        },
        child: const Text('Confirmar fechamento'),
      ),
    ],
  );
}

class _CashClosingInput {
  const _CashClosingInput(
    this.code,
    this.pin,
    this.countedCashAmount,
    this.notes,
  );
  final String code;
  final String pin;
  final double countedCashAmount;
  final String? notes;
}
