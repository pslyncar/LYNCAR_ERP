import 'package:flutter/material.dart';

import '../../../../domain/models/operation_order.dart';
import '../view_models/operations_view_model.dart';
import 'counter_sale_view.dart';
import 'checkout_view.dart';
import 'salon_qr_dialog.dart';
import 'salon_view.dart';

class TableCommandView extends StatefulWidget {
  const TableCommandView({super.key, required this.viewModel});

  final OperationsViewModel viewModel;

  @override
  State<TableCommandView> createState() => _TableCommandViewState();
}

class _TableCommandViewState extends State<TableCommandView> {
  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 700;
        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 14 : 24,
                compact ? 12 : 20,
                compact ? 14 : 24,
                8,
              ),
              child: compact
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'Escolha onde atender',
                          style: Theme.of(context).textTheme.headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Selecione uma mesa ou inicie uma venda direta no balcão.',
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: _openSalonQr,
                              icon: const Icon(Icons.qr_code_2_outlined),
                              label: const Text('QR do salão'),
                            ),
                            FilledButton.icon(
                              onPressed: _openOrder,
                              icon: const Icon(Icons.storefront_outlined),
                              label: const Text('Venda de balcão'),
                            ),
                          ],
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'PDV • Vendas',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const Text(
                                'Mesas, balcão e contas em um único fluxo de vendas.',
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _openSalonQr,
                          icon: const Icon(Icons.qr_code_2_outlined),
                          label: const Text('QR do salão'),
                        ),
                        const SizedBox(width: 12),
                        FilledButton.icon(
                          onPressed: _openOrder,
                          icon: const Icon(Icons.add),
                          label: const Text('Venda de balcão'),
                        ),
                      ],
                    ),
            ),
            Expanded(
              child: _LocationGrid(
                prefix: 'Mesa',
                count: 20,
                orders: widget.viewModel.orders,
                labelOf: (order) => order.tableLabel,
                onTap: (label, orders) => orders.isEmpty
                    ? _openOrder(table: label)
                    : _openAccount(label: label, orders: orders),
              ),
            ),
          ],
        );
      },
    );
  }

  void _openSalonQr() {
    final slug = widget.viewModel.catalog?.publicSlug ?? '';
    if (slug.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'O endereço público da loja ainda não foi sincronizado.',
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (_) => SalonQrDialog(slug: slug),
    );
  }

  Future<void> _openOrder({String table = ''}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(
            title: Text(
              table.isNotEmpty ? 'Mesa $table' : 'Venda rápida no balcão',
            ),
          ),
          body: table.isEmpty
              ? CounterSaleView(viewModel: widget.viewModel)
              : SalonView(viewModel: widget.viewModel, initialTable: table),
        ),
      ),
    );
    if (mounted) await widget.viewModel.refresh();
  }

  Future<void> _openAccount({
    required String label,
    required List<OperationOrder> orders,
  }) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => _AccountView(viewModel: widget.viewModel, label: label),
      ),
    );
    if (mounted) await widget.viewModel.refresh();
  }
}

class _LocationGrid extends StatelessWidget {
  const _LocationGrid({
    required this.prefix,
    required this.count,
    required this.orders,
    required this.labelOf,
    required this.onTap,
  });

  final String prefix;
  final int count;
  final List<OperationOrder> orders;
  final String? Function(OperationOrder) labelOf;
  final void Function(String label, List<OperationOrder> orders) onTap;

  @override
  Widget build(BuildContext context) {
    final active = <String, List<OperationOrder>>{};
    for (final order in orders.where(
      (item) =>
          item.status != 'completed' &&
          item.status != 'cancelled' &&
          item.paymentStatus != 'confirmed',
    )) {
      final label = labelOf(order)?.trim();
      if (label != null && label.isNotEmpty) {
        active.putIfAbsent(label, () => []).add(order);
      }
    }
    final labels =
        <String>{
          for (var index = 1; index <= count; index++) '$index',
          ...active.keys,
        }.toList()..sort((a, b) {
          final left = int.tryParse(a);
          final right = int.tryParse(b);
          return left != null && right != null
              ? left.compareTo(right)
              : a.compareTo(b);
        });
    return LayoutBuilder(
      builder: (context, constraints) => GridView.builder(
        padding: EdgeInsets.all(constraints.maxWidth < 700 ? 12 : 24),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: constraints.maxWidth < 700 ? 150 : 190,
          mainAxisExtent: constraints.maxWidth < 700 ? 112 : 138,
          crossAxisSpacing: constraints.maxWidth < 700 ? 8 : 14,
          mainAxisSpacing: constraints.maxWidth < 700 ? 8 : 14,
        ),
        itemCount: labels.length,
        itemBuilder: (_, index) {
          final label = labels[index];
          final linked = active[label] ?? const <OperationOrder>[];
          final occupied = linked.isNotEmpty;
          final total = linked.fold<double>(
            0,
            (sum, order) => sum + order.total,
          );
          return Card(
            color: occupied
                ? const Color(0xFFE6F7EF)
                : Theme.of(context).colorScheme.surfaceContainerLowest,
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => onTap(label, linked),
              child: Padding(
                padding: EdgeInsets.all(constraints.maxWidth < 700 ? 12 : 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          occupied
                              ? Icons.people_alt_outlined
                              : Icons.event_seat_outlined,
                        ),
                        const Spacer(),
                        Text(
                          occupied ? 'OCUPADA' : 'LIVRE',
                          style: TextStyle(
                            color: occupied
                                ? const Color(0xFF087A55)
                                : Colors.black54,
                            fontWeight: FontWeight.w800,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      '$prefix $label',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (occupied)
                      Text('${linked.length} pedido(s) • ${_money(total)}'),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

class _AccountView extends StatelessWidget {
  const _AccountView({required this.viewModel, required this.label});

  final OperationsViewModel viewModel;
  final String label;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: viewModel,
    builder: (context, _) {
      final orders = viewModel.orders
          .where(
            (order) =>
                order.status != 'completed' &&
                order.status != 'cancelled' &&
                order.paymentStatus != 'confirmed' &&
                order.tableLabel?.trim() == label,
          )
          .toList(growable: false);
      final total = orders.fold<double>(0, (sum, order) => sum + order.total);
      return Scaffold(
        appBar: AppBar(
          title: Text('Mesa $label'),
          actions: [
            TextButton.icon(
              onPressed: () => _addItems(context),
              icon: const Icon(Icons.add),
              label: const Text('Novo lançamento'),
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Conta em aberto',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                  ),
                  Text(
                    _money(total),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Receba a conta quando necessário. Itens em preparo continuam na cozinha.',
              ),
              const SizedBox(height: 18),
              Expanded(
                child: ListView.separated(
                  itemCount: orders.length,
                  separatorBuilder: (_, _) => const Divider(),
                  itemBuilder: (_, index) {
                    final order = orders[index];
                    return ListTile(
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: Text(order.number),
                      subtitle: Text(
                        order.items
                            .map((item) => '${item.quantity}× ${item.name}')
                            .join(' • '),
                      ),
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(_money(order.total)),
                          Text(_statusLabel(order.status)),
                        ],
                      ),
                    );
                  },
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: orders.isEmpty
                      ? null
                      : () => _receiveAccount(context, orders, total),
                  icon: const Icon(Icons.point_of_sale_outlined),
                  label: Text(
                    viewModel.cashSession == null
                        ? 'Abrir caixa e receber conta'
                        : 'Receber e fechar conta',
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );

  Future<void> _addItems(BuildContext context) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text('Novo lançamento • $label')),
          body: SalonView(viewModel: viewModel, initialTable: label),
        ),
      ),
    );
    await viewModel.refresh();
  }

  Future<void> _receiveAccount(
    BuildContext context,
    List<OperationOrder> orders,
    double total,
  ) async {
    if (viewModel.cashSession == null) {
      final opening = await showDialog<CashOpeningInput>(
        context: context,
        builder: (_) => const CashOpeningDialog(),
      );
      if (opening == null || !context.mounted) return;
      final opened = await viewModel.openCash(
        register: '01',
        openingAmount: opening.openingAmount,
      );
      if (!opened || !context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Caixa aberto. Escolha o pagamento da mesa.'),
        ),
      );
    }
    final input = await showDialog<_AccountPayment>(
      context: context,
      builder: (_) => _AccountPaymentDialog(total: total),
    );
    if (input == null || !context.mounted) return;
    final success = await viewModel.checkoutAccount(
      orders,
      method: input.method,
      amountPaid: input.amount,
      authorizationCode: input.authorization,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? 'Conta recebida e mesa liberada.'
              : viewModel.error ?? 'Não foi possível receber a conta.',
        ),
      ),
    );
    if (success) Navigator.pop(context);
  }
}

class _AccountPaymentDialog extends StatefulWidget {
  const _AccountPaymentDialog({required this.total});
  final double total;

  @override
  State<_AccountPaymentDialog> createState() => _AccountPaymentDialogState();
}

class _AccountPaymentDialogState extends State<_AccountPaymentDialog> {
  String method = 'dinheiro';
  late final TextEditingController amount;
  final authorization = TextEditingController();

  @override
  void initState() {
    super.initState();
    amount = TextEditingController(
      text: widget.total.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    amount.dispose();
    authorization.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Receber conta'),
    content: SizedBox(
      width: 460,
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
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(
              labelText: 'Valor recebido',
              prefixText: 'R\$ ',
            ),
          ),
          if (method == 'debito' || method == 'credito') ...[
            const SizedBox(height: 12),
            TextField(
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
          if (paid == null || paid <= 0) return;
          Navigator.pop(
            context,
            _AccountPayment(
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

class _AccountPayment {
  const _AccountPayment(this.method, this.amount, this.authorization);
  final String method;
  final double amount;
  final String? authorization;
}

String _statusLabel(String status) => switch (status) {
  'pending' => 'Pendente',
  'accepted' => 'Aceito',
  'in_preparation' => 'Em preparo',
  'ready' => 'Pronto',
  'out_for_delivery' => 'Em entrega',
  _ => status,
};
