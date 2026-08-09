import 'dart:async';

import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/production_order.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class ProductionOrdersScreen extends StatefulWidget {
  const ProductionOrdersScreen({super.key, required this.session});

  final Session session;

  @override
  State<ProductionOrdersScreen> createState() => _ProductionOrdersScreenState();
}

class _ProductionOrdersScreenState extends State<ProductionOrdersScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  final _dueDate = TextEditingController();
  List<Product> _products = [];
  ProductionOrderPreview? _preview;
  List<ProductionOrder> _orders = [];
  int? _productId;
  String _statusFilter = 'abertas';
  bool _loading = true;
  bool _previewLoading = false;
  bool _saving = false;
  Timer? _previewDebounce;
  String? _error;

  List<Product> get _producibleProducts {
    const producibleTypes = {'produto', 'produto_acabado'};
    return _products
        .where(
          (product) =>
              product.active && producibleTypes.contains(product.productType),
        )
        .toList();
  }

  Product? get _selectedProduct {
    final id = _productId;
    if (id == null) return null;
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  double get _plannedQuantity {
    final value = parseBrazilianNumber(_quantity.text);
    return value <= 0 ? 0 : value;
  }

  @override
  void initState() {
    super.initState();
    _quantity.addListener(() {
      setState(() {});
      _previewDebounce?.cancel();
      _previewDebounce = Timer(const Duration(milliseconds: 450), _loadPreview);
    });
    _load();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _notes.dispose();
    _dueDate.dispose();
    _previewDebounce?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listProducts(widget.session.token, active: true),
        _api.listProductionOrders(widget.session.token, limit: 100),
      ]);
      final products = results[0] as List<Product>;
      final orders = results[1] as List<ProductionOrder>;
      setState(() {
        _products = products;
        _orders = orders;
        final options = _producibleProducts;
        if (_productId == null && options.isNotEmpty) {
          _productId = options.first.id;
        }
      });
      await _loadPreview();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar as ordens.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadPreview() async {
    final productId = _productId;
    if (productId == null || _plannedQuantity <= 0) {
      setState(() => _preview = null);
      return;
    }
    setState(() => _previewLoading = true);
    try {
      final preview = await _api.previewProductionOrder(
        widget.session.token,
        productId: productId,
        quantity: _plannedQuantity,
      );
      if (mounted) setState(() => _preview = preview);
    } catch (_) {
      if (mounted) setState(() => _preview = null);
    } finally {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Future<void> _openProductPicker() async {
    final search = TextEditingController();
    try {
      final selected = await showDialog<Product>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final query = search.text.trim().toLowerCase();
            final products = _producibleProducts
                .where((product) {
                  if (query.isEmpty) return true;
                  final haystack = [
                    product.name,
                    product.internalCode,
                    product.barcode,
                  ].whereType<String>().join(' ').toLowerCase();
                  return haystack.contains(query);
                })
                .toList(growable: false);

            return AlertDialog(
              title: const Text('Escolher produto para produção'),
              content: SizedBox(
                width: 760,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: search,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText:
                            'Pesquisar por nome, código ou código de barras',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (_) => setDialogState(() {}),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: products.isEmpty
                          ? const Center(
                              child: Text('Nenhum produto encontrado.'),
                            )
                          : ListView.separated(
                              itemCount: products.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = products[index];
                                return ListTile(
                                  title: Text(
                                    product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${product.internalCode ?? product.barcode ?? '-'} • Estoque ${formatBrazilianDecimal(product.stockQuantity)} ${product.unit}',
                                  ),
                                  trailing: FilledButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(product),
                                    child: const Text('Usar'),
                                  ),
                                  onTap: () =>
                                      Navigator.of(context).pop(product),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
              ],
            );
          },
        ),
      );
      if (selected == null || !mounted) return;
      setState(() => _productId = selected.id);
      await _loadPreview();
    } finally {
      search.dispose();
    }
  }

  Future<void> _createOrder() async {
    final productId = _productId;
    if (productId == null || _plannedQuantity <= 0) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.createProductionOrder(
        widget.session.token,
        ProductionOrderPayload(
          productId: productId,
          quantity: _plannedQuantity,
          dueDate: _parseDateToIso(_dueDate.text),
          notes: _notes.text,
        ),
      );
      _quantity.text = '1';
      _notes.clear();
      _dueDate.clear();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('OP planejada criada.')));
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível criar a OP.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _startOrder(ProductionOrder order) async {
    await _runOrderAction(
      () => _api.startProductionOrder(widget.session.token, order.id),
      'OP iniciada.',
    );
  }

  Future<void> _completeOrder(ProductionOrder order) async {
    final quantity = TextEditingController(
      text: formatBrazilianDecimal(order.quantity),
    );
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Concluir ${order.number ?? '#${order.id}'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextFormField(
              controller: quantity,
              keyboardType: TextInputType.number,
              inputFormatters: [BrazilianDecimalInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Quantidade realmente produzida',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: notes,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Observação de conclusao',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Concluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runOrderAction(
      () => _api.completeProductionOrder(
        widget.session.token,
        order.id,
        ProductionOrderCompletePayload(
          producedQuantity: parseBrazilianNumber(quantity.text),
          notes: notes.text,
        ),
      ),
      'OP concluida. Estoque atualizado.',
    );
  }

  Future<void> _cancelOrder(ProductionOrder order) async {
    final reason = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancelar ${order.number ?? '#${order.id}'}'),
        content: TextFormField(
          controller: reason,
          minLines: 3,
          maxLines: 5,
          decoration: const InputDecoration(
            labelText: 'Motivo obrigatorio',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Voltar'),
          ),
          FilledButton.tonalIcon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.block),
            label: const Text('Cancelar OP'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runOrderAction(
      () => _api.cancelProductionOrder(
        widget.session.token,
        order.id,
        reason.text,
      ),
      'OP cancelada.',
    );
  }

  Future<void> _runOrderAction(
    Future<ProductionOrder> Function() action,
    String successMessage,
  ) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await action();
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(successMessage)));
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível atualizar a OP.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickDueDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    _dueDate.text =
        '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
  }

  @override
  Widget build(BuildContext context) {
    final options = _producibleProducts;
    final filteredOrders = _filteredOrders();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            _Header(onRefresh: _load),
            const SizedBox(height: 18),
            if (_error != null) ...[
              ErrorPanel(message: _error!, onRetry: _load),
              const SizedBox(height: 18),
            ],
            _SummaryCards(orders: _orders),
            const SizedBox(height: 18),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Nova ordem de produção',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 14),
                  if (options.isEmpty)
                    const _WarningBox(
                      'Cadastre um produto acabado e monte a ficha técnica antes de produzir.',
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 900;
                        final fieldWidth = wide
                            ? (constraints.maxWidth - 24) / 3
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: wide ? fieldWidth * 2 + 12 : fieldWidth,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: _openProductPicker,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Produto acabado',
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(Icons.search),
                                  ),
                                  child: Text(
                                    _selectedProduct == null
                                        ? 'Pesquisar produto'
                                        : '${_selectedProduct!.name} | Estoque ${formatBrazilianDecimal(_selectedProduct!.stockQuantity)} ${_selectedProduct!.unit}',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: TextFormField(
                                controller: _quantity,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  BrazilianDecimalInputFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Quantidade planejada',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: TextFormField(
                                controller: _dueDate,
                                readOnly: true,
                                onTap: _pickDueDate,
                                decoration: const InputDecoration(
                                  labelText: 'Previsao',
                                  border: OutlineInputBorder(),
                                  suffixIcon: Icon(Icons.calendar_month),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: wide ? fieldWidth * 2 + 12 : fieldWidth,
                              child: TextFormField(
                                controller: _notes,
                                decoration: const InputDecoration(
                                  labelText: 'Observação',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: fieldWidth,
                              child: FilledButton.icon(
                                onPressed: _saving ? null : _createOrder,
                                icon: const Icon(Icons.add_task),
                                label: Text(
                                  _saving
                                      ? 'Salvando...'
                                      : 'Criar OP planejada',
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  const SizedBox(height: 16),
                  _CompositionPreview(
                    product: _selectedProduct,
                    plannedQuantity: _plannedQuantity,
                    loading: _previewLoading,
                    preview: _preview,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _StatusFilter(
              selected: _statusFilter,
              onChanged: (value) => setState(() => _statusFilter = value),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const LinearProgressIndicator()
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: filteredOrders.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhuma OP neste status.'),
                      )
                    : _ProductionOrdersTable(
                        orders: filteredOrders,
                        canManage: widget.session.can('production:create'),
                        onStart: _startOrder,
                        onComplete: _completeOrder,
                        onCancel: _cancelOrder,
                      ),
              ),
          ],
        ),
      ),
    );
  }

  List<ProductionOrder> _filteredOrders() {
    return switch (_statusFilter) {
      'abertas' =>
        _orders
            .where(
              (order) => {'planejada', 'em_produção'}.contains(order.status),
            )
            .toList(),
      'concluidas' =>
        _orders.where((order) => order.status == 'concluida').toList(),
      'canceladas' =>
        _orders.where((order) => order.status == 'cancelada').toList(),
      _ => _orders,
    };
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Produção',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'OP planejada, consumo de materia-prima e entrada de produto acabado',
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
      ],
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.orders});

  final List<ProductionOrder> orders;

  @override
  Widget build(BuildContext context) {
    final planned = orders.where((order) => order.status == 'planejada').length;
    final running = orders
        .where((order) => order.status == 'em_produção')
        .length;
    final done = orders.where((order) => order.status == 'concluida').length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 900
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            SizedBox(width: width, child: _MetricCard('Planejadas', planned)),
            SizedBox(width: width, child: _MetricCard('Em produção', running)),
            SizedBox(width: width, child: _MetricCard('Concluidas', done)),
          ],
        );
      },
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value);

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.precision_manufacturing, color: Color(0xFF2563EB)),
          const SizedBox(width: 14),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF64748B))),
              Text(
                value.toString(),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CompositionPreview extends StatelessWidget {
  const _CompositionPreview({
    required this.product,
    required this.plannedQuantity,
    required this.loading,
    required this.preview,
  });

  final Product? product;
  final double plannedQuantity;
  final bool loading;
  final ProductionOrderPreview? preview;

  @override
  Widget build(BuildContext context) {
    if (product == null) return const SizedBox.shrink();
    if (loading) return const LinearProgressIndicator();
    final currentPreview = preview;
    if (currentPreview == null || currentPreview.components.isEmpty) {
      return const _WarningBox(
        'Este produto ainda não tem ficha técnica. Monte a composição no Estoque antes de criar OP.',
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Previa da ficha técnica',
                    style: TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                Text(
                  'Custo estimado: ${_money(currentPreview.estimatedTotalCost ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          for (final item in currentPreview.components)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.componentName,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          'Estoque: ${formatBrazilianDecimal(item.stockQuantity)} ${item.unit}',
                          style: TextStyle(
                            color: item.enoughStock
                                ? const Color(0xFF64748B)
                                : const Color(0xFFB91C1C),
                            fontSize: 12,
                            fontWeight: item.enoughStock
                                ? FontWeight.w500
                                : FontWeight.w900,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${formatBrazilianDecimal(item.requiredQuantity)} ${item.unit}',
                  ),
                  const SizedBox(width: 20),
                  SizedBox(
                    width: 110,
                    child: Text(
                      _money(item.totalCost ?? 0),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _WarningBox extends StatelessWidget {
  const _WarningBox(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF92400E),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _StatusFilter extends StatelessWidget {
  const _StatusFilter({required this.selected, required this.onChanged});

  final String selected;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = {
      'abertas': 'Abertas',
      'concluidas': 'Concluidas',
      'canceladas': 'Canceladas',
      'todas': 'Todas',
    };
    return Wrap(
      spacing: 8,
      children: [
        for (final entry in options.entries)
          ChoiceChip(
            label: Text(entry.value),
            selected: selected == entry.key,
            onSelected: (_) => onChanged(entry.key),
          ),
      ],
    );
  }
}

class _ProductionOrdersTable extends StatelessWidget {
  const _ProductionOrdersTable({
    required this.orders,
    required this.canManage,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
  });

  final List<ProductionOrder> orders;
  final bool canManage;
  final Future<void> Function(ProductionOrder order) onStart;
  final Future<void> Function(ProductionOrder order) onComplete;
  final Future<void> Function(ProductionOrder order) onCancel;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 1040,
        child: Column(
          children: [
            Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: const BoxDecoration(
                color: Color(0xFFF8FAFC),
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 100, child: _HeaderCell('OP')),
                  Expanded(child: _HeaderCell('Produto')),
                  SizedBox(width: 130, child: _HeaderCell('Status')),
                  SizedBox(width: 130, child: _HeaderCell('Planejado')),
                  SizedBox(width: 120, child: _HeaderCell('Produzido')),
                  SizedBox(width: 120, child: _HeaderCell('Custo')),
                  SizedBox(width: 120, child: _HeaderCell('Acoes')),
                ],
              ),
            ),
            for (final order in orders)
              ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 18),
                title: Row(
                  children: [
                    SizedBox(
                      width: 100,
                      child: Text(order.number ?? '#${order.id}'),
                    ),
                    Expanded(
                      child: Text(
                        order.productName,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                    SizedBox(width: 130, child: _StatusPill(order.status)),
                    SizedBox(
                      width: 130,
                      child: Text(
                        '${formatBrazilianDecimal(order.quantity)} ${order.unit}',
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: Text(
                        order.producedQuantity <= 0
                            ? '-'
                            : '${formatBrazilianDecimal(order.producedQuantity)} ${order.unit}',
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: Text(
                        order.totalCost != null
                            ? _money(order.totalCost!)
                            : order.estimatedTotalCost != null
                            ? '~ ${_money(order.estimatedTotalCost!)}'
                            : '-',
                      ),
                    ),
                    SizedBox(
                      width: 120,
                      child: _OrderActions(
                        order: order,
                        canManage: canManage,
                        onStart: onStart,
                        onComplete: onComplete,
                        onCancel: onCancel,
                      ),
                    ),
                  ],
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (order.notes != null) Text('Obs.: ${order.notes}'),
                        if (order.cancellationReason != null)
                          Text('Cancelamento: ${order.cancellationReason}'),
                        const SizedBox(height: 8),
                        if (order.components.isEmpty)
                          const Text(
                            'Componentes serao registrados ao concluir a OP.',
                          )
                        else
                          for (final component in order.components)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(component.componentName),
                                  ),
                                  SizedBox(
                                    width: 130,
                                    child: Text(
                                      '-${formatBrazilianDecimal(component.quantity)} ${component.unit}',
                                      style: const TextStyle(
                                        color: Color(0xFFB91C1C),
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  SizedBox(
                                    width: 120,
                                    child: Text(
                                      component.totalCost == null
                                          ? '-'
                                          : _money(component.totalCost!),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                      ],
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _OrderActions extends StatelessWidget {
  const _OrderActions({
    required this.order,
    required this.canManage,
    required this.onStart,
    required this.onComplete,
    required this.onCancel,
  });

  final ProductionOrder order;
  final bool canManage;
  final Future<void> Function(ProductionOrder order) onStart;
  final Future<void> Function(ProductionOrder order) onComplete;
  final Future<void> Function(ProductionOrder order) onCancel;

  @override
  Widget build(BuildContext context) {
    if (!canManage || {'cancelada'}.contains(order.status)) {
      return const Text('-');
    }
    return Row(
      children: [
        if (order.status == 'planejada')
          IconButton(
            tooltip: 'Iniciar',
            onPressed: () => onStart(order),
            icon: const Icon(Icons.play_arrow),
          ),
        if ({'planejada', 'em_produção'}.contains(order.status))
          IconButton(
            tooltip: 'Concluir',
            onPressed: () => onComplete(order),
            icon: const Icon(Icons.check_circle),
          ),
        if ({'planejada', 'em_produção', 'concluida'}.contains(order.status))
          IconButton(
            tooltip: 'Cancelar',
            onPressed: () => onCancel(order),
            icon: const Icon(Icons.cancel),
          ),
      ],
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill(this.status);

  final String status;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (status) {
      'planejada' => ('Planejada', const Color(0xFF2563EB)),
      'em_produção' => ('Em produção', const Color(0xFFD97706)),
      'concluida' => ('Concluida', const Color(0xFF059669)),
      'cancelada' => ('Cancelada', const Color(0xFFDC2626)),
      _ => (status, const Color(0xFF64748B)),
    };
    return Text(
      label,
      style: TextStyle(color: color, fontWeight: FontWeight.w900),
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
      style: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';

String? _parseDateToIso(String value) {
  final digits = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.length != 8) return null;
  return '${digits.substring(4, 8)}-${digits.substring(2, 4)}-${digits.substring(0, 2)}';
}
