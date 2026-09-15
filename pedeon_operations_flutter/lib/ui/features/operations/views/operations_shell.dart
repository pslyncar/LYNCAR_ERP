import 'package:flutter/material.dart';
import '../../../../domain/models/operation_order.dart';
import '../../../../domain/models/sync_issue.dart';
import '../view_models/operations_view_model.dart';
import 'order_board.dart';
import 'checkout_view.dart';
import 'printer_settings_view.dart';
import 'table_command_view.dart';

class OperationsShell extends StatefulWidget {
  const OperationsShell({super.key, required this.viewModel});
  final OperationsViewModel viewModel;
  @override
  State<OperationsShell> createState() => _OperationsShellState();
}

class _OperationsShellState extends State<OperationsShell> {
  int selected = 0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 820;
        final session = widget.viewModel.session!;
        final destinations = <_Destination>[
          if (session.can('accept'))
            _Destination(
              wide ? 'PDV • Vendas' : 'Vendas',
              Icons.table_restaurant_outlined,
              [],
              null,
              isSalon: true,
            ),
          if (session.can('accept'))
            const _Destination(
              'Novos pedidos',
              Icons.notifications_active_outlined,
              [
                'pending',
                'awaiting_payment',
                'awaiting_acceptance',
              ],
              'accepted',
            ),
          if (session.can('prepare'))
            const _Destination('Cozinha', Icons.soup_kitchen_outlined, [
              'accepted',
              'in_preparation',
            ], 'ready'),
          if (session.can('dispatch'))
            const _Destination('Expedição', Icons.delivery_dining_outlined, [
              'ready',
              'out_for_delivery',
            ], 'completed', fulfillments: ['delivery']),
          if (session.can('checkout'))
            const _Destination(
              'Caixa',
              Icons.point_of_sale_outlined,
              ['ready'],
              null,
              isCheckout: true,
            ),
          if (session.can('print'))
            const _Destination(
              'Impressoras',
              Icons.print_outlined,
              [],
              null,
              isPrinters: true,
            ),
          if (!session.can('accept') &&
              !session.can('prepare') &&
              !session.can('dispatch'))
            const _Destination(
              'Pedidos',
              Icons.receipt_long_outlined,
              [],
              null,
            ),
        ];
        if (selected >= destinations.length) selected = 0;
        final destination = destinations[selected];
        final content = destination.isSalon
            ? TableCommandView(viewModel: widget.viewModel)
            : destination.isPrinters
            ? PrinterSettingsView(viewModel: widget.viewModel)
            : destination.isCheckout
            ? CheckoutView(viewModel: widget.viewModel)
            : OrderBoard(
                title: destination.label,
                orders: _filter(
                  widget.viewModel.orders,
                  destination.statuses,
                  fulfillments: destination.fulfillments,
                ),
                actionStatus: destination.actionStatus,
                onTransition: widget.viewModel.transition,
              );

        final body = Column(
          children: [
            _Header(viewModel: widget.viewModel),
            if (widget.viewModel.error case final error?)
              MaterialBanner(
                content: Text('Operação local mantida. Sincronização: $error'),
                leading: const Icon(Icons.cloud_off_outlined),
                actions: [
                  TextButton(
                    onPressed: widget.viewModel.refresh,
                    child: const Text('Tentar agora'),
                  ),
                ],
              ),
            Expanded(child: content),
          ],
        );
        if (wide) {
          return Scaffold(
            body: Row(
              children: [
                NavigationRail(
                  selectedIndex: selected,
                  onDestinationSelected: (value) =>
                      setState(() => selected = value),
                  labelType: NavigationRailLabelType.all,
                  destinations: [
                    for (final item in destinations)
                      NavigationRailDestination(
                        icon: Icon(item.icon),
                        label: Text(item.label),
                      ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: body),
              ],
            ),
          );
        }
        return Scaffold(
          body: body,
          bottomNavigationBar: NavigationBar(
            selectedIndex: selected,
            onDestinationSelected: (value) => setState(() => selected = value),
            destinations: [
              for (final item in destinations)
                NavigationDestination(icon: Icon(item.icon), label: item.label),
            ],
          ),
        );
      },
    );
  }

  List<OperationOrder> _filter(
    List<OperationOrder> orders,
    List<String> statuses,
    {
    List<String> fulfillments = const [],
  }
  ) => orders
      .where(
        (order) =>
            (statuses.isEmpty || statuses.contains(order.status)) &&
            (fulfillments.isEmpty || fulfillments.contains(order.fulfillment)),
      )
      .toList(growable: false);
}

class _Destination {
  const _Destination(
    this.label,
    this.icon,
    this.statuses,
    this.actionStatus, {
    this.fulfillments = const [],
    this.isSalon = false,
    this.isCheckout = false,
    this.isPrinters = false,
  });
  final String label;
  final IconData icon;
  final List<String> statuses;
  final String? actionStatus;
  final List<String> fulfillments;
  final bool isSalon;
  final bool isCheckout;
  final bool isPrinters;
}

class _Header extends StatelessWidget {
  const _Header({required this.viewModel});
  final OperationsViewModel viewModel;
  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF0C2538),
    child: SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF1ED6B4),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.shopping_bag_outlined,
                color: Color(0xFF0C2538),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PedeOn',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    viewModel.session!.deviceLabel,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: viewModel.refresh,
              tooltip: 'Atualizar agora',
              color: Colors.white,
              icon: const Icon(Icons.refresh),
            ),
            if (viewModel.syncIssues.isNotEmpty)
              IconButton(
                tooltip:
                    '${_uniqueIssues.length} pedido(s) com pendência de sincronização',
                color: const Color(0xFFFFCC66),
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Pendências de sincronização'),
                    content: SizedBox(
                      width: 520,
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final issue in _uniqueIssues)
                            ListTile(
                              leading: const Icon(Icons.warning_amber_rounded),
                              title: Text(issue.aggregateId),
                              subtitle: Text(issue.message),
                            ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Fechar'),
                      ),
                    ],
                  ),
                ),
                icon: Badge(
                  label: Text('${_uniqueIssues.length}'),
                  child: const Icon(Icons.cloud_off_outlined),
                ),
              ),
            IconButton(
              onPressed: viewModel.logout,
              tooltip: 'Sair',
              color: Colors.white,
              icon: const Icon(Icons.logout_rounded),
            ),
            PopupMenuButton<String>(
              color: Colors.white,
              onSelected: (_) => viewModel.logout(),
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'logout',
                  child: Text('Sair e voltar ao login'),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  List<SyncIssue> get _uniqueIssues {
    final byOrder = <String, SyncIssue>{};
    for (final issue in viewModel.syncIssues) {
      byOrder[issue.aggregateId] = issue;
    }
    return byOrder.values.toList(growable: false);
  }
}
