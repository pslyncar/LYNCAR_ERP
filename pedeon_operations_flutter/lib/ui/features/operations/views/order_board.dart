import 'package:flutter/material.dart';
import '../../../../domain/models/operation_order.dart';

class OrderBoard extends StatelessWidget {
  const OrderBoard({
    super.key,
    required this.title,
    required this.orders,
    required this.actionStatus,
    required this.onTransition,
  });
  final String title;
  final List<OperationOrder> orders;
  final String? actionStatus;
  final Future<void> Function(OperationOrder, String) onTransition;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1500
          ? 4
          : constraints.maxWidth >= 1050
          ? 3
          : constraints.maxWidth >= 660
          ? 2
          : 1;
      return CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 22, 20, 12),
            sliver: SliverToBoxAdapter(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.headlineMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Badge(
                    label: Text('${orders.length}'),
                    child: const Icon(Icons.receipt_long_outlined),
                  ),
                ],
              ),
            ),
          ),
          if (orders.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyBoard(),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              sliver: SliverGrid.builder(
                itemCount: orders.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  mainAxisExtent: 390,
                ),
                itemBuilder: (context, index) => _OrderCard(
                  order: orders[index],
                  actionStatus: actionStatus,
                  onTransition: onTransition,
                ),
              ),
            ),
        ],
      );
    },
  );
}

class _OrderCard extends StatelessWidget {
  const _OrderCard({
    required this.order,
    required this.actionStatus,
    required this.onTransition,
  });
  final OperationOrder order;
  final String? actionStatus;
  final Future<void> Function(OperationOrder, String) onTransition;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          color: _sourceColor(order.source),
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  order.number,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                order.source.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: Row(
            children: [
              const Icon(Icons.person_outline, size: 19),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  order.customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                _time(order.createdAt),
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              Chip(
                avatar: Icon(_statusIcon(order.status), size: 18),
                label: Text(_statusLabel(order.status)),
              ),
              if (order.paymentStatus != 'confirmed')
                const Chip(
                  avatar: Icon(Icons.payments_outlined, size: 18),
                  label: Text('Pagamento pendente'),
                ),
            ],
          ),
        ),
        if ((order.tableLabel ?? '').isNotEmpty ||
            (order.commandLabel ?? '').isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(
              spacing: 8,
              children: [
                if ((order.tableLabel ?? '').isNotEmpty)
                  Chip(
                    avatar: const Icon(
                      Icons.table_restaurant_outlined,
                      size: 18,
                    ),
                    label: Text(order.tableLabel!),
                  ),
                if ((order.commandLabel ?? '').isNotEmpty)
                  Chip(
                    avatar: const Icon(
                      Icons.confirmation_number_outlined,
                      size: 18,
                    ),
                    label: Text(order.commandLabel!),
                  ),
              ],
            ),
          ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: order.items.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final item = order.items[index];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${item.quantity}× ${item.name}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 16,
                    ),
                  ),
                  if (item.modifiers.isNotEmpty)
                    Text(
                      item.modifiers.join(' • '),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  if (item.notes.trim().isNotEmpty)
                    Text(
                      'Obs.: ${item.notes}',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                ],
              );
            },
          ),
        ),
        if (order.notes.trim().isNotEmpty)
          Container(
            color: const Color(0xFFFFF3CD),
            padding: const EdgeInsets.all(10),
            child: Text('Pedido: ${order.notes}'),
          ),
        if (actionStatus != null && _canApplyAction(order, actionStatus!))
          Padding(
            padding: const EdgeInsets.all(12),
            child: FilledButton.icon(
              onPressed: () => onTransition(order, actionStatus!),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(_actionLabel(actionStatus!)),
              ),
            ),
          ),
      ],
    ),
  );
}

class _EmptyBoard extends StatelessWidget {
  const _EmptyBoard();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.task_alt_rounded, size: 70, color: Colors.black26),
        SizedBox(height: 14),
        Text(
          'Tudo em dia',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        Text('Novos pedidos aparecerão automaticamente.'),
      ],
    ),
  );
}

String _time(DateTime? value) => value == null
    ? '--:--'
    : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _actionLabel(String status) => switch (status) {
  'accepted' => 'Aceitar pedido',
  'ready' => 'Marcar como pronto',
  'completed' => 'Concluir entrega',
  _ => 'Avançar',
};
bool _canApplyAction(OperationOrder order, String actionStatus) =>
    actionStatus == 'accepted' &&
        (order.status == 'pending' || order.status == 'awaiting_acceptance') ||
    actionStatus == 'ready' &&
        (order.status == 'accepted' || order.status == 'in_preparation') ||
    actionStatus == 'completed' &&
        (order.status == 'ready' || order.status == 'out_for_delivery');
String _statusLabel(String status) => switch (status) {
  'pending' => 'Novo pedido',
  'awaiting_payment' => 'Aguardando pagamento',
  'awaiting_acceptance' => 'Aguardando aceite',
  'accepted' => 'Aceito',
  'in_preparation' => 'Em preparo',
  'ready' => 'Pronto',
  'out_for_delivery' => 'Saiu para entrega',
  'completed' => 'Concluído',
  'cancelled' => 'Cancelado',
  _ => status,
};
IconData _statusIcon(String status) => switch (status) {
  'awaiting_payment' => Icons.payments_outlined,
  'awaiting_acceptance' || 'pending' => Icons.notifications_active_outlined,
  'accepted' || 'in_preparation' => Icons.soup_kitchen_outlined,
  'ready' => Icons.check_circle_outline,
  _ => Icons.receipt_long_outlined,
};
Color _sourceColor(String source) => switch (source.toLowerCase()) {
  'ifood' => const Color(0xFFEA1D2C),
  '99food' => const Color(0xFFFFD400),
  'local' ||
  'salao' ||
  'onsite_waiter' ||
  'pdv_counter' => const Color(0xFF7048E8),
  _ => const Color(0xFF087681),
};
