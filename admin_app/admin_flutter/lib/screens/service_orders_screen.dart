import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/client.dart';
import '../models/equipment.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/service_order.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/receipt_print.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _statuses = {
  'aberta': 'Aberta',
  'em_diagnostico': 'Em diagnostico',
  'aguardando_aprovacao': 'Aguardando',
  'em_execucao': 'Em execucao',
  'concluida': 'Concluida',
  'cancelada': 'Cancelada',
};

const _priorities = {'baixa': 'Baixa', 'media': 'Media', 'alta': 'Alta'};

const _paymentMethods = {
  'dinheiro': 'Dinheiro',
  'pix': 'Pix',
  'debito': 'Debito',
  'credito': 'Credito',
  'boleto': 'Boleto',
  'transferencia': 'Transferencia',
  'crediario': 'Crediario',
  'outro': 'Outro',
};

const _workflowTabs = [
  _WorkflowTab('abertas', 'Aberto', ['aberta'], Icons.assignment_outlined),
  _WorkflowTab('andamento', 'Em andamento', [
    'em_diagnostico',
    'em_execucao',
  ], Icons.build_outlined),
  _WorkflowTab('aguardando', 'Aguardando', [
    'aguardando_aprovacao',
  ], Icons.hourglass_top_outlined),
  _WorkflowTab('concluidas', 'Concluido', [
    'concluida',
    'cancelada',
  ], Icons.check_circle_outline),
];

class ServiceOrdersScreen extends StatefulWidget {
  const ServiceOrdersScreen({super.key, required this.session});

  final Session session;

  @override
  State<ServiceOrdersScreen> createState() => _ServiceOrdersScreenState();
}

class _ServiceOrdersScreenState extends State<ServiceOrdersScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<ServiceOrder> _orders = [];
  List<Client> _clients = [];
  List<Equipment> _equipments = [];
  List<Product> _products = [];
  List<SaleSeller> _sellers = [];
  int _selectedStageIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listServiceOrders(widget.session.token),
        _api.listClients(widget.session.token),
        _api.listEquipments(widget.session.token),
        _api.listProducts(widget.session.token),
        if (widget.session.can('sales:create'))
          _api.listSaleSellers(widget.session.token)
        else
          Future.value(<SaleSeller>[]),
      ]);
      setState(() {
        _orders = results[0] as List<ServiceOrder>;
        _clients = results[1] as List<Client>;
        _equipments = results[2] as List<Equipment>;
        _products = results[3] as List<Product>;
        _sellers = results[4] as List<SaleSeller>;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar as OS.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([ServiceOrder? order]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ServiceOrderDialog(
        api: _api,
        token: widget.session.token,
        order: order,
        clients: _clients,
        equipments: _equipments,
        products: _products,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteOrder(ServiceOrder order) async {
    final label = order.number?.isNotEmpty == true
        ? order.number!
        : _serviceOrderCode(order);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir OS?'),
        content: Text('A OS $label será removida com seus itens.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _api.deleteServiceOrder(widget.session.token, order.id);
    await _load();
  }

  // ignore: unused_element
  void _sendToSales(ServiceOrder order) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'A OS ${order.number?.isNotEmpty == true ? order.number : _serviceOrderCode(order)} já está pronta para virar venda. A tela de Vendas será criada no próximo modulo.',
        ),
      ),
    );
  }

  Future<void> _openServiceOrderSale(ServiceOrder order) async {
    final sale = await showDialog<Sale>(
      context: context,
      builder: (context) => _ServiceOrderSaleDialog(
        api: _api,
        token: widget.session.token,
        order: order,
        client: _findClient(_clients, order.clientId),
        products: _products,
        sellers: _sellers,
      ),
    );
    if (sale == null || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Venda ${sale.number ?? sale.id} gerada da OS.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final clientById = {for (final client in _clients) client.id: client};
    final equipmentById = {
      for (final equipment in _equipments) equipment.id: equipment,
    };
    final selectedStage = _workflowTabs[_selectedStageIndex];
    final visibleOrders = _orders
        .where((order) => selectedStage.statuses.contains(order.status))
        .toList();

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            _Header(
              canCreate: widget.session.can('service_orders:create'),
              onRefresh: _load,
              onCreate: () => _openForm(),
            ),
            const SizedBox(height: 18),
            _SummaryStrip(orders: _orders),
            const SizedBox(height: 18),
            _WorkflowTabs(
              selectedIndex: _selectedStageIndex,
              orders: _orders,
              onSelected: (index) =>
                  setState(() => _selectedStageIndex = index),
            ),
            const SizedBox(height: 14),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: visibleOrders.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhuma OS encontrada.'),
                      )
                    : _ServiceOrdersTable(
                        orders: visibleOrders,
                        clientById: clientById,
                        equipmentById: equipmentById,
                        canUpdate: widget.session.can('service_orders:update'),
                        canDelete: widget.session.can('service_orders:finish'),
                        canSendToSales: widget.session.can('sales:create'),
                        onOpen: _openForm,
                        onDelete: _deleteOrder,
                        onSendToSales: _openServiceOrderSale,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canCreate,
    required this.onRefresh,
    required this.onCreate,
  });

  final bool canCreate;
  final VoidCallback onRefresh;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'OS',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'Ordens de servico, manutencoes, diagnosticos e valores',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          tooltip: 'Atualizar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
        if (canCreate)
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Nova OS'),
          ),
      ],
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.orders});

  final List<ServiceOrder> orders;

  @override
  Widget build(BuildContext context) {
    final open = orders.where((order) => order.status == 'aberta').length;
    final running = orders
        .where(
          (order) =>
              order.status == 'em_execucao' || order.status == 'em_diagnostico',
        )
        .length;
    final approval = orders
        .where((order) => order.status == 'aguardando_aprovacao')
        .length;
    final total = orders.fold<double>(
      0,
      (sum, order) => sum + order.totalAmount,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820 ? 4 : 2;
        final items = [
          _SummaryItem('Abertas', open, Icons.assignment_outlined),
          _SummaryItem('Em trabalho', running, Icons.build_outlined),
          _SummaryItem('Aguardando', approval, Icons.fact_check_outlined),
          _SummaryItem(
            'Total em OS',
            total,
            Icons.payments_outlined,
            currency: true,
          ),
        ];
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 98,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) => _SummaryTile(item: items[index]),
        );
      },
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.item});

  final _SummaryItem item;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(item.icon, color: const Color(0xFF2563EB)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.currency
                        ? _money(item.value as double)
                        : '${item.value}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkflowTabs extends StatelessWidget {
  const _WorkflowTabs({
    required this.selectedIndex,
    required this.orders,
    required this.onSelected,
  });

  final int selectedIndex;
  final List<ServiceOrder> orders;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 820
            ? (constraints.maxWidth - 36) / 4
            : constraints.maxWidth >= 520
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var index = 0; index < _workflowTabs.length; index++)
              SizedBox(
                width: itemWidth,
                child: _WorkflowTabButton(
                  tab: _workflowTabs[index],
                  count: orders
                      .where(
                        (order) => _workflowTabs[index].statuses.contains(
                          order.status,
                        ),
                      )
                      .length,
                  selected: selectedIndex == index,
                  onTap: () => onSelected(index),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _WorkflowTabButton extends StatelessWidget {
  const _WorkflowTabButton({
    required this.tab,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  final _WorkflowTab tab;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected ? const Color(0xFF2563EB) : const Color(0xFF475569);
    return Material(
      color: selected ? const Color(0xFFEFF6FF) : Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Container(
          height: 72,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected
                  ? const Color(0xFF93C5FD)
                  : const Color(0xFFE2E8F0),
            ),
          ),
          child: Row(
            children: [
              Icon(tab.icon, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  tab.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? const Color(0xFF1D4ED8) : color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                '$count',
                style: TextStyle(
                  color: selected ? const Color(0xFF1D4ED8) : color,
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ServiceOrdersTable extends StatelessWidget {
  const _ServiceOrdersTable({
    required this.orders,
    required this.clientById,
    required this.equipmentById,
    required this.canUpdate,
    required this.canDelete,
    required this.canSendToSales,
    required this.onOpen,
    required this.onDelete,
    required this.onSendToSales,
  });

  final List<ServiceOrder> orders;
  final Map<int, Client> clientById;
  final Map<int, Equipment> equipmentById;
  final bool canUpdate;
  final bool canDelete;
  final bool canSendToSales;
  final ValueChanged<ServiceOrder> onOpen;
  final ValueChanged<ServiceOrder> onDelete;
  final ValueChanged<ServiceOrder> onSendToSales;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: const Row(
            children: [
              SizedBox(width: 92, child: _HeaderCell('OS')),
              Expanded(flex: 3, child: _HeaderCell('Titulo / cliente')),
              Expanded(flex: 2, child: _HeaderCell('Equipamento')),
              SizedBox(width: 150, child: _HeaderCell('Status')),
              SizedBox(width: 120, child: _HeaderCell('Prioridade')),
              SizedBox(width: 120, child: _HeaderCell('Total')),
              SizedBox(width: 150, child: _HeaderCell('Acoes')),
            ],
          ),
        ),
        for (final order in orders)
          InkWell(
            onTap: canUpdate ? () => onOpen(order) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 76),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      order.number?.isNotEmpty == true
                          ? order.number!
                          : _serviceOrderCode(order),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _TwoLine(
                      primary: order.title,
                      secondary: _clientLine(order, clientById),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: _TwoLine(
                      primary: _equipmentLabel(order, equipmentById),
                      secondary: order.equipmentId == null
                          ? 'Avulso/recebido'
                          : 'Monitorado',
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: _StatusChip(status: order.status),
                  ),
                  SizedBox(
                    width: 120,
                    child: _PriorityChip(priority: order.priority),
                  ),
                  SizedBox(
                    width: 120,
                    child: Text(
                      _money(order.totalAmount),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (canSendToSales && order.status == 'concluida')
                          IconButton(
                            tooltip: 'Enviar para vendas',
                            onPressed: () => onSendToSales(order),
                            icon: const Icon(Icons.point_of_sale_outlined),
                          ),
                        if (canDelete)
                          IconButton(
                            tooltip: 'Excluir OS',
                            onPressed: () => onDelete(order),
                            icon: const Icon(Icons.delete_outline),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _ServiceOrderSaleDialog extends StatefulWidget {
  const _ServiceOrderSaleDialog({
    required this.api,
    required this.token,
    required this.order,
    required this.products,
    required this.sellers,
    this.client,
  });

  final ApiClient api;
  final String token;
  final ServiceOrder order;
  final Client? client;
  final List<Product> products;
  final List<SaleSeller> sellers;

  @override
  State<_ServiceOrderSaleDialog> createState() =>
      _ServiceOrderSaleDialogState();
}

class _ServiceOrderSaleDialogState extends State<_ServiceOrderSaleDialog> {
  final _sellerCode = TextEditingController();
  final _paymentAmount = TextEditingController();
  String _paymentMethod = 'dinheiro';
  int? _sellerUserId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _paymentAmount.text = formatBrazilianMoneyInput(_totalCents / 100);
  }

  @override
  void dispose() {
    _sellerCode.dispose();
    _paymentAmount.dispose();
    super.dispose();
  }

  int get _subtotalCents {
    final items = _moneyCents(widget.order.itemsAmount);
    final labor = _moneyCents(widget.order.laborAmount);
    return items + labor;
  }

  int get _discountCents => _moneyCents(widget.order.discountAmount);
  int get _totalCents => _nonNegativeCents(_subtotalCents - _discountCents);
  int get _paidCents => _moneyCents(parseBrazilianNumber(_paymentAmount.text));
  bool get _usesFinancialPayment =>
      _paymentMethod == 'boleto' || _paymentMethod == 'crediario';
  bool get _paymentCoversTotal => _paidCents + 1 >= _totalCents;

  SaleSeller? get _selectedSeller {
    if (_sellerUserId == null) return null;
    for (final seller in widget.sellers) {
      if (seller.id == _sellerUserId) return seller;
    }
    return null;
  }

  void _selectSellerByCode(String value) {
    final code = value.trim().toLowerCase();
    if (code.isEmpty) return;
    final matches = widget.sellers.where((seller) {
      final sellerCode = (seller.sellerCode ?? '').trim().toLowerCase();
      return sellerCode.isNotEmpty && sellerCode == code;
    }).toList();
    if (matches.isEmpty) {
      setState(
        () => _error = 'Vendedor com codigo ${value.trim()} nao encontrado.',
      );
      return;
    }
    setState(() {
      _sellerUserId = matches.first.id;
      _sellerCode.text = matches.first.sellerCode ?? '';
      _error = null;
    });
  }

  Future<void> _openSellerPicker() async {
    final codedSellers = widget.sellers
        .where((seller) => (seller.sellerCode ?? '').trim().isNotEmpty)
        .toList();
    final selected = await showDialog<SaleSeller>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Selecionar vendedor'),
        children: [
          if (codedSellers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nenhum vendedor com codigo cadastrado.'),
            )
          else
            for (final seller in codedSellers)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(seller),
                child: Text('${seller.sellerCode} - ${seller.name}'),
              ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() {
      _sellerUserId = selected.id;
      _sellerCode.text = selected.sellerCode ?? '';
      _error = null;
    });
  }

  Future<void> _createSale() async {
    if ((_selectedSeller?.sellerCode ?? '').trim().isEmpty) {
      setState(() => _error = 'Informe um vendedor com codigo cadastrado.');
      return;
    }
    if (_totalCents <= 0) {
      setState(() => _error = 'A OS precisa ter valor maior que zero.');
      return;
    }
    if (!_paymentCoversTotal) {
      setState(() => _error = 'Pagamento menor que o total.');
      return;
    }
    if (_usesFinancialPayment && widget.client == null) {
      setState(() => _error = 'Boleto e crediario exigem cliente cadastrado.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final label = widget.order.number?.isNotEmpty == true
          ? widget.order.number!
          : _serviceOrderCode(widget.order);
      final sale = await widget.api.createSale(
        widget.token,
        SalePayload(
          clientId: widget.order.clientId,
          sellerUserId: _sellerUserId,
          source: 'os',
          status: 'finalizada',
          discountAmount: _discountCents / 100,
          offlineClientId: 'os:${widget.order.id}',
          notes: 'Venda gerada pela OS $label.',
          items: [
            for (final item in widget.order.items)
              SaleItemPayload(
                productId: item.productId,
                barcode: _findProduct(widget.products, item.productId)?.barcode,
                description: item.description,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                discountAmount: 0,
              ),
            if (widget.order.laborAmount > 0)
              SaleItemPayload(
                productId: null,
                barcode: null,
                description: 'Mao de obra - OS $label',
                quantity: 1,
                unitPrice: widget.order.laborAmount,
                discountAmount: 0,
              ),
          ],
          payments: [
            SalePaymentPayload(
              method: _paymentMethod,
              amount: _paidCents / 100,
            ),
          ],
        ),
      );
      if (mounted) Navigator.of(context).pop(sale);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Nao foi possivel gerar a venda da OS.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.order.number?.isNotEmpty == true
        ? widget.order.number!
        : _serviceOrderCode(widget.order);
    final changeCents = _nonNegativeCents(_paidCents - _totalCents);
    return AlertDialog(
      title: Text('Gerar venda da OS $label'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SalePreviewLine(
                'Cliente',
                widget.client?.name ?? 'Cliente #${widget.order.clientId}',
              ),
              _SalePreviewLine('OS', widget.order.title),
              const Divider(height: 24),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 210,
                    child: TextField(
                      controller: _sellerCode,
                      textInputAction: TextInputAction.search,
                      onSubmitted: _selectSellerByCode,
                      decoration: InputDecoration(
                        labelText: 'Codigo vendedor',
                        prefixIcon: const Icon(Icons.badge_outlined),
                        suffixIcon: IconButton(
                          tooltip: 'Pesquisar vendedor',
                          onPressed: _openSellerPicker,
                          icon: const Icon(Icons.search),
                        ),
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Vendedor selecionado',
                        border: OutlineInputBorder(),
                      ),
                      child: Text(
                        _selectedSeller?.name ?? 'Nenhum vendedor selecionado',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Forma de pagamento',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final entry in _paymentMethods.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                ],
                onChanged: (value) => setState(() {
                  _paymentMethod = value ?? 'dinheiro';
                  _paymentAmount.text = formatBrazilianMoneyInput(
                    _totalCents / 100,
                  );
                }),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _paymentAmount,
                keyboardType: TextInputType.text,
                inputFormatters: const [BrazilianMoneyInputFormatter()],
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: 'Valor recebido',
                  border: OutlineInputBorder(),
                ),
              ),
              const Divider(height: 24),
              _MoneySummaryLine('Itens', _subtotalCents / 100),
              _MoneySummaryLine('Desconto da OS', _discountCents / 100),
              _MoneySummaryLine('Total', _totalCents / 100, strong: true),
              _MoneySummaryLine('Recebido', _paidCents / 100),
              _MoneySummaryLine('Troco', changeCents / 100),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _createSale,
          icon: const Icon(Icons.point_of_sale_outlined),
          label: Text(_saving ? 'Gerando...' : 'Gerar venda'),
        ),
      ],
    );
  }
}

class _SalePreviewLine extends StatelessWidget {
  const _SalePreviewLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _MoneySummaryLine extends StatelessWidget {
  const _MoneySummaryLine(this.label, this.value, {this.strong = false});

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: strong ? 20 : 15,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceOrderDialog extends StatefulWidget {
  const _ServiceOrderDialog({
    required this.api,
    required this.token,
    required this.clients,
    required this.equipments,
    required this.products,
    this.order,
  });

  final ApiClient api;
  final String token;
  final ServiceOrder? order;
  final List<Client> clients;
  final List<Equipment> equipments;
  final List<Product> products;

  @override
  State<_ServiceOrderDialog> createState() => _ServiceOrderDialogState();
}

class _ServiceOrderDialogState extends State<_ServiceOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _number = TextEditingController();
  final _title = TextEditingController();
  final _serviceType = TextEditingController();
  final _receivedEquipment = TextEditingController();
  final _waitingReason = TextEditingController();
  final _request = TextEditingController();
  final _diagnosis = TextEditingController();
  final _performed = TextEditingController();
  final _notes = TextEditingController();
  final _labor = TextEditingController(text: '0,00');
  final _discount = TextEditingController(text: '0,00');
  final _scheduledAt = TextEditingController();
  final _itemDescription = TextEditingController();
  final _itemQuantity = TextEditingController(text: '1');
  final _itemPrice = TextEditingController(text: '0,00');

  int? _clientId;
  int? _equipmentId;
  int? _productId;
  String _status = 'aberta';
  String _priority = 'media';
  ServiceOrder? _current;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _current = widget.order;
    final order = widget.order;
    if (order != null) {
      _clientId = order.clientId;
      _equipmentId = order.equipmentId;
      _number.text = order.number ?? '';
      _title.text = order.title;
      _status = order.status;
      _priority = order.priority;
      _serviceType.text = order.serviceType ?? '';
      _receivedEquipment.text = order.receivedEquipment ?? '';
      _waitingReason.text = order.waitingReason ?? '';
      _request.text = order.requestDescription;
      _diagnosis.text = order.technicalDiagnosis ?? '';
      _performed.text = order.servicePerformed ?? '';
      _notes.text = order.internalNotes ?? '';
      _labor.text = _moneyInput(order.laborAmount);
      _discount.text = _moneyInput(order.discountAmount);
      _scheduledAt.text = _dateInput(order.scheduledAt);
    } else if (widget.clients.isNotEmpty) {
      _clientId = widget.clients.first.id;
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _number,
      _title,
      _serviceType,
      _receivedEquipment,
      _waitingReason,
      _request,
      _diagnosis,
      _performed,
      _notes,
      _labor,
      _discount,
      _scheduledAt,
      _itemDescription,
      _itemQuantity,
      _itemPrice,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _clientId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = ServiceOrderPayload(
        clientId: _clientId!,
        equipmentId: _equipmentId,
        number: _number.text,
        title: _title.text,
        status: _status,
        priority: _priority,
        serviceType: _serviceType.text,
        receivedEquipment: _receivedEquipment.text,
        waitingReason: _waitingReason.text,
        requestDescription: _request.text,
        technicalDiagnosis: _diagnosis.text,
        servicePerformed: _performed.text,
        internalNotes: _notes.text,
        laborAmount: _parseMoney(_labor.text),
        discountAmount: _parseMoney(_discount.text),
        scheduledAt: _parseDate(_scheduledAt.text),
      );
      final order = _current;
      final saved = order == null
          ? await widget.api.createServiceOrder(widget.token, payload)
          : await widget.api.updateServiceOrder(
              widget.token,
              order.id,
              payload,
            );
      setState(() => _current = saved);
      if (!mounted) return;
      if (order == null) {
        await _askPrintAfterCreate(saved);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar a OS.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _askPrintAfterCreate(ServiceOrder order) async {
    final action = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('OS ${order.number ?? _serviceOrderCode(order)} criada'),
        content: const Text('Deseja imprimir o comprovante agora?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop('no'),
            child: const Text('Não imprimir'),
          ),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop('thermal'),
            icon: const Icon(Icons.print_outlined),
            label: const Text('Termica'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop('browser'),
            icon: const Icon(Icons.receipt_long_outlined),
            label: const Text('PDF / navegador'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (action == 'browser') {
      openServiceOrderReceipt(
        order: order,
        client: _findClient(widget.clients, order.clientId),
        equipment: _findEquipment(widget.equipments, order.equipmentId),
      );
    }
    if (action == 'thermal') {
      final message = await showDialog<String>(
        context: context,
        builder: (context) => _ThermalPrintDialog(
          api: widget.api,
          token: widget.token,
          serviceOrderId: order.id,
        ),
      );
      if (!mounted || message == null) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _addItem() async {
    final order = _current;
    if (order == null || _itemDescription.text.trim().length < 2) return;
    if (_parseMoney(_itemQuantity.text) <= 0) {
      setState(() => _error = 'Informe uma quantidade maior que zero.');
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.api.addServiceOrderItem(
        widget.token,
        order.id,
        ServiceOrderItemPayload(
          productId: _productId,
          description: _itemDescription.text,
          quantity: _parseMoney(_itemQuantity.text),
          unitPrice: _parseMoney(_itemPrice.text),
        ),
      );
      final updated = (await widget.api.listServiceOrders(
        widget.token,
      )).firstWhere((item) => item.id == order.id);
      setState(() {
        _current = updated;
        _productId = null;
        _itemDescription.clear();
        _itemQuantity.text = '1';
        _itemPrice.text = _moneyInput(0);
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteItem(ServiceOrderItem item) async {
    final order = _current;
    if (order == null) return;
    final updated = await widget.api.deleteServiceOrderItem(
      widget.token,
      order.id,
      item.id,
    );
    setState(() => _current = updated);
  }

  void _printBrowserReceipt() {
    final order = _current;
    if (order == null) return;
    openServiceOrderReceipt(
      order: order,
      client: _findClient(widget.clients, order.clientId),
      equipment: _findEquipment(widget.equipments, order.equipmentId),
    );
  }

  Future<void> _pickScheduledAt() async {
    final current = _parseDate(_scheduledAt.text) ?? DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current),
    );
    if (!mounted) return;
    final selectedTime = time ?? TimeOfDay.fromDateTime(current);
    _scheduledAt.text = _dateInput(
      DateTime(
        date.year,
        date.month,
        date.day,
        selectedTime.hour,
        selectedTime.minute,
      ),
    );
  }

  Future<void> _printThermalReceipt() async {
    final order = _current;
    if (order == null) return;
    final message = await showDialog<String>(
      context: context,
      builder: (context) => _ThermalPrintDialog(
        api: widget.api,
        token: widget.token,
        serviceOrderId: order.id,
      ),
    );
    if (!mounted || message == null) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final filteredEquipments = widget.equipments
        .where((equipment) => equipment.clientId == _clientId)
        .toList();
    if (_equipmentId != null &&
        !filteredEquipments.any((equipment) => equipment.id == _equipmentId)) {
      _equipmentId = null;
    }
    final order = _current;

    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          order == null
                              ? 'Nova OS'
                              : 'OS ${order.number ?? _serviceOrderCode(order)}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton.outlined(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  _ResponsiveFields(
                    children: [
                      DropdownButtonFormField<int>(
                        initialValue: _clientId,
                        decoration: const InputDecoration(
                          labelText: 'Cliente',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final client in widget.clients)
                            DropdownMenuItem(
                              value: client.id,
                              child: Text(client.name),
                            ),
                        ],
                        onChanged: (value) => setState(() {
                          _clientId = value;
                          _equipmentId = null;
                        }),
                        validator: (value) =>
                            value == null ? 'Selecione o cliente.' : null,
                      ),
                      DropdownButtonFormField<int?>(
                        initialValue: _equipmentId,
                        decoration: const InputDecoration(
                          labelText: 'Maquina monitorada, se existir',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: null,
                            child: Text('Sem equipamento'),
                          ),
                          for (final equipment in filteredEquipments)
                            DropdownMenuItem(
                              value: equipment.id,
                              child: Text(equipment.hostname),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _equipmentId = value),
                      ),
                      _field(
                        _number,
                        'Código da OS',
                        hintText: 'Automatico: M1, M2...',
                      ),
                      _field(_title, 'Titulo', required: true),
                      TextFormField(
                        controller: _receivedEquipment,
                        decoration: const InputDecoration(
                          labelText: 'Equipamento recebido/avulso',
                          hintText:
                              'Ex: impressora Epson, notebook Dell, fonte ATX',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (_equipmentId == null &&
                              (value == null || value.trim().length < 2)) {
                            return 'Informe o que o cliente trouxe.';
                          }
                          return null;
                        },
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _status,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final entry in _statuses.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _status = value ?? _status),
                      ),
                      if (_status == 'aguardando_aprovacao')
                        TextFormField(
                          controller: _waitingReason,
                          decoration: const InputDecoration(
                            labelText: 'Motivo do aguardando',
                            hintText:
                                'Ex: aguardando peca, aprovacao, retirada',
                            border: OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (_status == 'aguardando_aprovacao' &&
                                (value == null || value.trim().length < 3)) {
                              return 'Informe o motivo do aguardando.';
                            }
                            return null;
                          },
                        ),
                      DropdownButtonFormField<String>(
                        initialValue: _priority,
                        decoration: const InputDecoration(
                          labelText: 'Prioridade',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final entry in _priorities.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _priority = value ?? _priority),
                      ),
                      _field(_serviceType, 'Tipo de servico'),
                      _field(
                        _scheduledAt,
                        'Agendamento (dd/mm/aaaa hh:mm)',
                        inputFormatters: const [
                          BrazilianDateTimeInputFormatter(),
                        ],
                        suffixIcon: IconButton(
                          tooltip: 'Abrir calendario',
                          onPressed: _pickScheduledAt,
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _textArea(
                    _request,
                    'Descricao do problema/solicitacao',
                    required: true,
                  ),
                  const SizedBox(height: 12),
                  _textArea(_notes, 'Observações internas'),
                  if (order != null) ...[
                    const SizedBox(height: 18),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _printBrowserReceipt,
                          icon: const Icon(Icons.receipt_long_outlined),
                          label: const Text('Imprimir PDF / navegador'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _printThermalReceipt,
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('Impressao termica direta'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const _SectionTitle(
                      title: 'Diagnostico tecnico e valores',
                      subtitle: 'Preenchido depois da avaliacao técnica.',
                    ),
                    const SizedBox(height: 12),
                    _textArea(_diagnosis, 'Diagnostico tecnico'),
                    const SizedBox(height: 12),
                    _textArea(
                      _performed,
                      'Servico executado / solucao aplicada',
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFields(
                      children: [
                        _field(_labor, 'Mao de obra (R\$)', money: true),
                        _field(_discount, 'Desconto (R\$)', money: true),
                      ],
                    ),
                    const SizedBox(height: 18),
                    _ItemsEditor(
                      order: order,
                      products: widget.products,
                      selectedProductId: _productId,
                      description: _itemDescription,
                      quantity: _itemQuantity,
                      price: _itemPrice,
                      onProductChanged: (value) {
                        final product = _findProduct(widget.products, value);
                        setState(() {
                          _productId = value;
                          if (product != null) {
                            _itemDescription.text = product.name;
                            _itemPrice.text = _moneyInput(product.salePrice);
                          }
                        });
                      },
                      onAdd: _saving ? null : _addItem,
                      onDelete: _deleteItem,
                    ),
                    const SizedBox(height: 12),
                    _TotalsPanel(order: order),
                  ],
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(color: Color(0xFFB91C1C)),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Salvando...' : 'Salvar OS'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    TextInputType? keyboardType,
    bool money = false,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
    String? hintText,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: money ? TextInputType.text : keyboardType,
      inputFormatters:
          inputFormatters ??
          (money ? const [BrazilianMoneyInputFormatter()] : null),
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        suffixIcon: suffixIcon,
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().length < 3) {
                return 'Informe ao menos 3 caracteres.';
              }
              return null;
            }
          : null,
    );
  }

  Widget _textArea(
    TextEditingController controller,
    String label, {
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      minLines: 3,
      maxLines: 5,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().length < 3) {
                return 'Informe ao menos 3 caracteres.';
              }
              return null;
            }
          : null,
    );
  }
}

class _ItemsEditor extends StatelessWidget {
  const _ItemsEditor({
    required this.order,
    required this.products,
    required this.selectedProductId,
    required this.description,
    required this.quantity,
    required this.price,
    required this.onProductChanged,
    required this.onAdd,
    required this.onDelete,
  });

  final ServiceOrder order;
  final List<Product> products;
  final int? selectedProductId;
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController price;
  final ValueChanged<int?> onProductChanged;
  final VoidCallback? onAdd;
  final ValueChanged<ServiceOrderItem> onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Produtos, pecas e servicos',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            _ResponsiveFields(
              children: [
                DropdownButtonFormField<int?>(
                  initialValue: selectedProductId,
                  decoration: const InputDecoration(
                    labelText: 'Produto/servico cadastrado',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(
                      value: null,
                      child: Text('Item avulso'),
                    ),
                    for (final product in products)
                      DropdownMenuItem(
                        value: product.id,
                        child: Text(product.name),
                      ),
                  ],
                  onChanged: onProductChanged,
                ),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(
                    labelText: 'Descricao do item',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: quantity,
                  keyboardType: TextInputType.text,
                  inputFormatters: const [BrazilianDecimalInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Quantidade',
                    border: OutlineInputBorder(),
                  ),
                ),
                TextField(
                  controller: price,
                  keyboardType: TextInputType.text,
                  inputFormatters: const [BrazilianMoneyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Valor unitario',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: onAdd,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar item'),
              ),
            ),
            const Divider(height: 24),
            if (order.items.isEmpty)
              const Text('Nenhum item lancado.')
            else
              for (final item in order.items)
                ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(item.description),
                  subtitle: Text(
                    '${_numberText(item.quantity)} x ${_money(item.unitPrice)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _money(item.totalPrice),
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      IconButton(
                        tooltip: 'Remover item',
                        onPressed: () => onDelete(item),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
            const Divider(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                'Itens: ${_money(order.itemsAmount)}   Total: ${_money(order.totalAmount)}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThermalPrintDialog extends StatefulWidget {
  const _ThermalPrintDialog({
    required this.api,
    required this.token,
    required this.serviceOrderId,
  });

  final ApiClient api;
  final String token;
  final int serviceOrderId;

  @override
  State<_ThermalPrintDialog> createState() => _ThermalPrintDialogState();
}

class _ThermalPrintDialogState extends State<_ThermalPrintDialog> {
  final _formKey = GlobalKey<FormState>();
  final _host = TextEditingController();
  final _port = TextEditingController(text: '9100');
  int _paperWidth = 80;
  bool _printing = false;
  String? _error;

  @override
  void dispose() {
    _host.dispose();
    _port.dispose();
    super.dispose();
  }

  Future<void> _print() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _printing = true;
      _error = null;
    });
    try {
      final message = await widget.api.printServiceOrderThermal(
        widget.token,
        widget.serviceOrderId,
        printerHost: _host.text.trim(),
        printerPort: int.tryParse(_port.text.trim()) ?? 9100,
        paperWidth: _paperWidth,
      );
      if (mounted) Navigator.of(context).pop(message);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível enviar para a impressora.');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Impressao termica direta'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Use impressora termica ESC/POS de rede. Normalmente a porta e 9100.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _host,
                decoration: const InputDecoration(
                  labelText: 'IP ou nome da impressora',
                  hintText: 'Ex: 192.168.1.50',
                  border: OutlineInputBorder(),
                ),
                validator: (value) => value == null || value.trim().length < 3
                    ? 'Informe o IP da impressora.'
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _port,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(
                        labelText: 'Porta',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      initialValue: _paperWidth,
                      decoration: const InputDecoration(
                        labelText: 'Papel',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 80, child: Text('80 mm')),
                        DropdownMenuItem(value: 58, child: Text('58 mm')),
                      ],
                      onChanged: (value) =>
                          setState(() => _paperWidth = value ?? 80),
                    ),
                  ),
                ],
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C))),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _printing ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _printing ? null : _print,
          icon: const Icon(Icons.print_outlined),
          label: Text(_printing ? 'Enviando...' : 'Imprimir'),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.engineering_outlined, color: Color(0xFF2563EB)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalsPanel extends StatelessWidget {
  const _TotalsPanel({required this.order});

  final ServiceOrder order;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Wrap(
          spacing: 12,
          runSpacing: 12,
          alignment: WrapAlignment.end,
          children: [
            _TotalBadge(label: 'Itens', value: _money(order.itemsAmount)),
            _TotalBadge(label: 'Mao de obra', value: _money(order.laborAmount)),
            _TotalBadge(label: 'Desconto', value: _money(order.discountAmount)),
            _TotalBadge(
              label: 'Total da OS',
              value: _money(order.totalAmount),
              strong: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalBadge extends StatelessWidget {
  const _TotalBadge({
    required this.label,
    required this.value,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: strong ? const Color(0xFFEFF6FF) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: strong ? const Color(0xFF93C5FD) : const Color(0xFFE2E8F0),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: strong ? 17 : 15,
              fontWeight: FontWeight.w900,
              color: strong ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth >= 520
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);
  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _TwoLine extends StatelessWidget {
  const _TwoLine({required this.primary, required this.secondary});
  final String primary;
  final String secondary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 3),
        Text(
          secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final String status;
  @override
  Widget build(BuildContext context) =>
      _Pill(label: _statuses[status] ?? status, color: const Color(0xFF2563EB));
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});
  final String priority;
  @override
  Widget build(BuildContext context) {
    final color = priority == 'alta'
        ? const Color(0xFFB91C1C)
        : priority == 'baixa'
        ? const Color(0xFF0F766E)
        : const Color(0xFFA16207);
    return _Pill(label: _priorities[priority] ?? priority, color: color);
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, overflow: TextOverflow.ellipsis),
      visualDensity: VisualDensity.compact,
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.24)),
      labelStyle: TextStyle(
        color: color,
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _SummaryItem {
  const _SummaryItem(
    this.label,
    this.value,
    this.icon, {
    this.currency = false,
  });
  final String label;
  final Object value;
  final IconData icon;
  final bool currency;
}

class _WorkflowTab {
  const _WorkflowTab(this.key, this.label, this.statuses, this.icon);

  final String key;
  final String label;
  final List<String> statuses;
  final IconData icon;
}

double _parseMoney(String value) => parseBrazilianNumber(value);

String _numberText(double value) {
  return formatBrazilianDecimal(value);
}

String _moneyInput(double value) => formatBrazilianMoneyInput(value);

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';

int _moneyCents(double value) => (value * 100).round();

int _nonNegativeCents(int value) => value < 0 ? 0 : value;

String _serviceOrderCode(ServiceOrder order) => 'M${order.id}';

String _equipmentLabel(ServiceOrder order, Map<int, Equipment> equipmentById) {
  final received = order.receivedEquipment?.trim();
  if (received != null && received.isNotEmpty) return received;
  if (order.equipmentId == null) return '-';
  return equipmentById[order.equipmentId]?.hostname ??
      'Equip. #${order.equipmentId}';
}

String _clientLine(ServiceOrder order, Map<int, Client> clientById) {
  final clientName =
      clientById[order.clientId]?.name ?? 'Cliente #${order.clientId}';
  final waiting = order.waitingReason?.trim();
  if (order.status == 'aguardando_aprovacao' &&
      waiting != null &&
      waiting.isNotEmpty) {
    return '$clientName - aguardando: $waiting';
  }
  return clientName;
}

Product? _findProduct(List<Product> products, int? id) {
  if (id == null) return null;
  for (final product in products) {
    if (product.id == id) return product;
  }
  return null;
}

Client? _findClient(List<Client> clients, int id) {
  for (final client in clients) {
    if (client.id == id) return client;
  }
  return null;
}

Equipment? _findEquipment(List<Equipment> equipments, int? id) {
  if (id == null) return null;
  for (final equipment in equipments) {
    if (equipment.id == id) return equipment;
  }
  return null;
}

String _dateInput(DateTime? value) {
  if (value == null) return '';
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

DateTime? _parseDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final normalized = trimmed.replaceAll('-', '/');
  final parts = normalized.split(RegExp(r'\s+'));
  final dateParts = parts.first.split('/');
  if (dateParts.length != 3) return null;
  final day = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final year = int.tryParse(dateParts[2]);
  if (day == null || month == null || year == null) return null;
  var hour = 0;
  var minute = 0;
  if (parts.length > 1) {
    final timeParts = parts[1].split(':');
    hour = int.tryParse(timeParts.first) ?? 0;
    if (timeParts.length > 1) minute = int.tryParse(timeParts[1]) ?? 0;
  }
  return DateTime(year, month, day, hour, minute);
}
