import 'package:flutter/material.dart';

import '../domain/pedeon_order.dart';
import 'pedeon_settings_view_model.dart';

class PedeOnOrdersPanel extends StatelessWidget {
  const PedeOnOrdersPanel({super.key, required this.viewModel});
  final PedeOnSettingsViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final page = viewModel.orders;
    return RefreshIndicator(
      onRefresh: () => viewModel.loadOrders(page: 1),
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1380),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _OrdersHeader(viewModel: viewModel),
                  const SizedBox(height: 18),
                  if (viewModel.ordersLoading && page == null)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(48),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else if (page == null || page.items.isEmpty)
                    const _EmptyOrders()
                  else ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cards = page.items
                            .map(
                              (order) => _OrderCard(
                                order: order,
                                onOpen: () => _openOrder(context, order.id),
                              ),
                            )
                            .toList(growable: false);
                        if (constraints.maxWidth < 760) {
                          return Column(
                            children: [
                              for (final card in cards) ...[
                                card,
                                const SizedBox(height: 12),
                              ],
                            ],
                          );
                        }
                        return Wrap(
                          spacing: 14,
                          runSpacing: 14,
                          children: cards
                              .map(
                                (card) => SizedBox(
                                  width: (constraints.maxWidth - 14) / 2,
                                  child: card,
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _Pagination(viewModel: viewModel, page: page),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openOrder(BuildContext context, int orderId) async {
    final order = await viewModel.loadOrder(orderId);
    if (!context.mounted || order == null) return;
    await showDialog<void>(
      context: context,
      builder: (_) => _OrderDetailDialog(order: order, viewModel: viewModel),
    );
  }
}

class _OrdersHeader extends StatelessWidget {
  const _OrdersHeader({required this.viewModel});
  final PedeOnSettingsViewModel viewModel;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 14,
      runSpacing: 12,
      children: [
        const SizedBox(
          width: 460,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Central de Pedidos',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
              ),
              SizedBox(height: 4),
              Text(
                'Confira pagamento, aceite e acompanhe o preparo sem misturar pedido com venda.',
                style: TextStyle(color: Color(0xFF667085)),
              ),
            ],
          ),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            DropdownButton<String>(
              value: viewModel.orderSourceFilter ?? '',
              items: const [
                DropdownMenuItem(value: '', child: Text('Todos os canais')),
                DropdownMenuItem(value: 'pedeon', child: Text('PedeOn')),
                DropdownMenuItem(
                  value: 'onsite_waiter',
                  child: Text('Salão • atendente'),
                ),
                DropdownMenuItem(
                  value: 'onsite_qr',
                  child: Text('Salão • QR da mesa'),
                ),
                DropdownMenuItem(
                  value: 'pdv_counter',
                  child: Text('Balcão / PDV'),
                ),
                DropdownMenuItem(value: 'ifood', child: Text('iFood')),
                DropdownMenuItem(value: 'food99', child: Text('99Food')),
              ],
              onChanged: viewModel.ordersLoading
                  ? null
                  : (value) =>
                        viewModel.loadOrders(source: value ?? '', page: 1),
            ),
            DropdownButton<String>(
              value: viewModel.orderStatusFilter ?? '',
              items: const [
                DropdownMenuItem(value: '', child: Text('Todos')),
                DropdownMenuItem(
                  value: 'awaiting_payment',
                  child: Text('Aguardando pagamento'),
                ),
                DropdownMenuItem(
                  value: 'awaiting_acceptance',
                  child: Text('Aguardando aceite'),
                ),
                DropdownMenuItem(value: 'accepted', child: Text('Aceitos')),
                DropdownMenuItem(
                  value: 'in_preparation',
                  child: Text('Em preparo'),
                ),
                DropdownMenuItem(value: 'ready', child: Text('Prontos')),
                DropdownMenuItem(
                  value: 'out_for_delivery',
                  child: Text('Em entrega'),
                ),
                DropdownMenuItem(value: 'completed', child: Text('Concluídos')),
                DropdownMenuItem(value: 'cancelled', child: Text('Cancelados')),
              ],
              onChanged: viewModel.ordersLoading
                  ? null
                  : (value) =>
                        viewModel.loadOrders(status: value ?? '', page: 1),
            ),
            IconButton.outlined(
              tooltip: 'Atualizar pedidos',
              onPressed: viewModel.ordersLoading
                  ? null
                  : () => viewModel.loadOrders(),
              icon: viewModel.ordersLoading
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
      ],
    ),
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({required this.order, required this.onOpen});
  final PedeOnOrderSummary order;
  final VoidCallback onOpen;
  @override
  Widget build(BuildContext context) => Card(
    child: InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    order.displayNumber,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _StatusChip(status: order.status),
              ],
            ),
            const SizedBox(height: 8),
            _SourceChip(
              source: order.sourceChannel,
              externalOrderId: order.externalOrderId,
            ),
            const SizedBox(height: 12),
            Text(
              order.customerName,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            Text(
              order.customerPhone,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
            const Divider(height: 24),
            Row(
              children: [
                Icon(
                  order.fulfillmentType == 'delivery'
                      ? Icons.delivery_dining_outlined
                      : Icons.storefront_outlined,
                  size: 20,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    order.fulfillmentType == 'delivery'
                        ? 'Entrega'
                        : 'Retirada',
                  ),
                ),
                Text(
                  _currency(order.total),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const SizedBox(width: 6),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _OrderDetailDialog extends StatefulWidget {
  const _OrderDetailDialog({required this.order, required this.viewModel});
  final PedeOnOrderDetail order;
  final PedeOnSettingsViewModel viewModel;
  @override
  State<_OrderDetailDialog> createState() => _OrderDetailDialogState();
}

class _OrderDetailDialogState extends State<_OrderDetailDialog> {
  late PedeOnOrderDetail order = widget.order;
  bool working = false;

  @override
  Widget build(BuildContext context) => Dialog(
    insetPadding: const EdgeInsets.all(18),
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        order.displayNumber,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        order.customerName,
                        style: const TextStyle(color: Color(0xFF667085)),
                      ),
                    ],
                  ),
                ),
                _StatusChip(status: order.status),
                IconButton(
                  onPressed: working ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(22),
              children: [
                _DetailLine(label: 'Contato', value: order.customerPhone),
                _DetailLine(
                  label: 'Canal',
                  value:
                      _sourceLabel(order.sourceChannel) +
                      (order.externalOrderId == null
                          ? ''
                          : ' • ${order.externalOrderId}'),
                ),
                _DetailLine(
                  label: 'Recebimento',
                  value: order.fulfillmentType == 'delivery'
                      ? 'Entrega'
                      : 'Retirada',
                ),
                _DetailLine(label: 'Pagamento', value: _paymentLabel(order)),
                if (order.deliveryAddress case final address?)
                  _DetailLine(label: 'Endereço', value: _address(address)),
                if ((order.customerNotes ?? '').isNotEmpty)
                  _DetailLine(
                    label: 'Observações',
                    value: order.customerNotes!,
                  ),
                const SizedBox(height: 18),
                const Text(
                  'Itens',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 8),
                ...order.items.map(
                  (item) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(item.description),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_quantity(item.quantity)} ${item.unit} × ${_currency(item.unitPrice)}',
                        ),
                        if ((item.stationName ?? '').isNotEmpty)
                          Text(
                            'Destino: ${item.stationName}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        for (final modifier in item.modifiers)
                          Text(
                            '${modifier.groupName}: ${modifier.optionName}'
                            '${modifier.total > 0 ? ' (+${_currency(modifier.total)})' : ''}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        if ((item.customerNotes ?? '').isNotEmpty)
                          Text(
                            'Observação: ${item.customerNotes}',
                            style: const TextStyle(fontStyle: FontStyle.italic),
                          ),
                      ],
                    ),
                    trailing: Text(
                      _currency(item.total),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerRight,
                  child: Text(
                    'Total ${_currency(order.total)}',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
          _OrderActions(order: order, working: working, onAction: _action),
        ],
      ),
    ),
  );

  Future<void> _action(String action) async {
    setState(() => working = true);
    final success = action == 'confirm_payment'
        ? await widget.viewModel.confirmPayment(order.id)
        : await widget.viewModel.updateOrderStatus(order.id, action);
    if (success) {
      final refreshed = await widget.viewModel.loadOrder(order.id);
      if (refreshed != null && mounted) setState(() => order = refreshed);
    }
    if (mounted) setState(() => working = false);
  }
}

class _OrderActions extends StatelessWidget {
  const _OrderActions({
    required this.order,
    required this.working,
    required this.onAction,
  });
  final PedeOnOrderDetail order;
  final bool working;
  final ValueChanged<String> onAction;
  @override
  Widget build(BuildContext context) {
    final deliveryPaymentPending =
        order.paymentStatus != 'confirmed' &&
        {
          'credit_card_on_delivery',
          'debit_card_on_delivery',
        }.contains(order.paymentMethod);
    final primary = switch (order.status) {
      'awaiting_payment' when order.paymentMethod == 'manual_pix' => (
        'confirm_payment',
        'Confirmar Pix',
      ),
      'awaiting_acceptance' => ('accepted', 'Aceitar e enviar à cozinha'),
      'accepted' => ('in_preparation', 'Enviar para produção'),
      'in_preparation' => ('ready', 'Marcar como pronto'),
      'ready' when order.fulfillmentType == 'delivery' => (
        'out_for_delivery',
        'Saiu para entrega',
      ),
      'ready' => ('completed', 'Concluir retirada'),
      'out_for_delivery' => ('completed', 'Concluir entrega'),
      _ => null,
    };
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          if (deliveryPaymentPending)
            OutlinedButton.icon(
              onPressed: working ? null : () => onAction('confirm_payment'),
              icon: const Icon(Icons.price_check_outlined),
              label: const Text('Confirmar recebimento'),
            ),
          if (!['completed', 'cancelled', 'expired'].contains(order.status))
            TextButton(
              onPressed: working ? null : () => onAction('cancelled'),
              child: const Text('Cancelar pedido'),
            ),
          if (primary != null) ...[
            const SizedBox(width: 10),
            FilledButton(
              onPressed: working ? null : () => onAction(primary.$1),
              child: Text(primary.$2),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'awaiting_payment' => ('Aguardando pagamento', const Color(0xFFB54708)),
      'awaiting_acceptance' => ('Novo pedido', const Color(0xFF175CD3)),
      'accepted' => ('Aceito', const Color(0xFF026AA2)),
      'in_preparation' => ('Em preparo', const Color(0xFF7A5AF8)),
      'ready' => ('Pronto', const Color(0xFF067647)),
      'out_for_delivery' => ('Em entrega', const Color(0xFF027A48)),
      'completed' => ('Concluído', const Color(0xFF344054)),
      'cancelled' => ('Cancelado', const Color(0xFFB42318)),
      _ => (status, const Color(0xFF475467)),
    };
    return Chip(
      label: Text(label),
      side: BorderSide(color: color.withValues(alpha: .25)),
      backgroundColor: color.withValues(alpha: .08),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
    );
  }
}

class _SourceChip extends StatelessWidget {
  const _SourceChip({required this.source, this.externalOrderId});
  final String source;
  final String? externalOrderId;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(_sourceIcon(source), size: 17),
    label: Text(
      externalOrderId == null
          ? _sourceLabel(source)
          : '${_sourceLabel(source)} • $externalOrderId',
    ),
    side: const BorderSide(color: Color(0xFFD0D5DD)),
    backgroundColor: const Color(0xFFF9FAFB),
    labelStyle: const TextStyle(fontWeight: FontWeight.w800),
    visualDensity: VisualDensity.compact,
  );
}

class _Pagination extends StatelessWidget {
  const _Pagination({required this.viewModel, required this.page});
  final PedeOnSettingsViewModel viewModel;
  final PedeOnOrderPage page;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      IconButton.outlined(
        onPressed: page.page > 1
            ? () => viewModel.loadOrders(page: page.page - 1)
            : null,
        icon: const Icon(Icons.chevron_left),
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Text('Página ${page.page} de ${page.totalPages}'),
      ),
      IconButton.outlined(
        onPressed: page.page < page.totalPages
            ? () => viewModel.loadOrders(page: page.page + 1)
            : null,
        icon: const Icon(Icons.chevron_right),
      ),
    ],
  );
}

class _EmptyOrders extends StatelessWidget {
  const _EmptyOrders();
  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(52),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 54,
              color: Color(0xFF98A2B3),
            ),
            SizedBox(height: 12),
            Text(
              'Nenhum pedido nesta fila.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 120,
          child: Text(label, style: const TextStyle(color: Color(0xFF667085))),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ],
    ),
  );
}

String _paymentLabel(PedeOnOrderDetail order) {
  final method = order.localPaymentMethod != null
      ? 'Pagar no local • ${_localPaymentLabel(order.localPaymentMethod!)}'
      : switch (order.paymentMethod) {
          'manual_pix' => 'Pix manual',
          'infinitepay_pix' => 'InfinitePay',
          'credit_card_on_delivery' => 'Crédito na entrega',
          'debit_card_on_delivery' => 'Débito na entrega',
          _ => 'Não informado',
        };
  final state = order.paymentStatus == 'confirmed'
      ? 'confirmado'
      : 'aguardando confirmação';
  return '$method • $state';
}

String _localPaymentLabel(String method) => switch (method) {
  'cash' => 'dinheiro',
  'pix' => 'Pix',
  'credit_card' => 'crédito',
  'debit_card' => 'débito',
  _ => method,
};

String _sourceLabel(String source) => switch (source) {
  'pedeon' => 'PedeOn',
  'onsite_waiter' => 'Salão • atendente',
  'onsite_qr' => 'Salão • QR da mesa',
  'pdv_counter' => 'Balcão / PDV',
  'ifood' => 'iFood',
  'food99' => '99Food',
  _ => source,
};

IconData _sourceIcon(String source) => switch (source) {
  'pedeon' => Icons.shopping_bag_outlined,
  'onsite_waiter' => Icons.room_service_outlined,
  'onsite_qr' => Icons.qr_code_2_outlined,
  'pdv_counter' => Icons.point_of_sale_outlined,
  'ifood' || 'food99' => Icons.delivery_dining_outlined,
  _ => Icons.hub_outlined,
};

String _address(Map<String, dynamic> value) =>
    [
          '${value['street'] ?? ''}, ${value['number'] ?? ''}',
          value['complement'],
          value['neighborhood'],
          '${value['city'] ?? ''}/${value['state'] ?? ''}',
          'CEP ${value['postal_code'] ?? ''}',
        ]
        .where((item) => item != null && item.toString().trim().isNotEmpty)
        .join(' • ');
String _quantity(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(3);
String _currency(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
