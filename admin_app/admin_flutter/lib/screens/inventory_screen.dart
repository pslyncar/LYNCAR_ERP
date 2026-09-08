import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../models/stock_movement.dart';
import '../services/api_client.dart';
import '../services/file_download.dart';
import '../widgets/app_card.dart';
import '../widgets/app_pagination.dart';
import '../widgets/error_panel.dart';
import 'products_screen.dart'
    show
        ProductStockAction,
        showProductEditorDialog,
        showProductStockActionDialog;

/// New inventory workspace. The old product screen remains available as the
/// editing engine while this page owns the new inventory experience.
class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key, required this.session});

  final Session session;

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  static const _pageSize = 50;
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  List<Product> _products = const [];
  List<StockMovement> _recentMovements = const [];
  bool _movementsLoading = false;
  String? _movementsError;
  int _tab = 0;
  int _page = 0;
  String _statusFilter = 'Todos';
  String _typeFilter = 'Todos';
  String _locationFilter = 'Todos';
  bool _onlyAttention = false;
  bool _filtersExpanded = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _api.listProducts(widget.session.token);
      if (!mounted) {
        return;
      }
      setState(() {
        _products = products;
        _page = 0;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar o estoque.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadRecentMovements() async {
    if (_movementsLoading) return;
    setState(() {
      _movementsLoading = true;
      _movementsError = null;
    });
    try {
      final movements = await _api.listRecentStockWithdrawals(
        widget.session.token,
        limit: 100,
      );
      if (!mounted) return;
      setState(() => _recentMovements = movements);
    } on ApiException catch (error) {
      if (mounted) setState(() => _movementsError = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _movementsError = 'Não foi possível carregar as movimentações.',
        );
      }
    } finally {
      if (mounted) setState(() => _movementsLoading = false);
    }
  }

  void _changeTab(int value) {
    setState(() => _tab = value);
    if (value == 1 && _recentMovements.isEmpty) {
      _loadRecentMovements();
    }
  }

  List<Product> get _filtered {
    final term = _search.text.trim().toLowerCase();
    return _products
        .where((product) {
          final status = product.stockQuantity <= 0
              ? 'Sem estoque'
              : product.stockQuantity <= product.minimumStock
              ? 'Baixo'
              : 'Disponível';
          final type = _productType(product.productType);
          final location = product.stockLocation?.isNotEmpty == true
              ? product.stockLocation!
              : 'Principal';
          final haystack = [
            product.name,
            product.internalCode,
            product.barcode,
            product.category,
            product.stockLocation,
          ].whereType<String>().join(' ').toLowerCase();
          return (term.isEmpty || haystack.contains(term)) &&
              (_statusFilter == 'Todos' || status == _statusFilter) &&
              (_typeFilter == 'Todos' || type == _typeFilter) &&
              (_locationFilter == 'Todos' || location == _locationFilter) &&
              (!_onlyAttention ||
                  product.stockQuantity <= product.minimumStock);
        })
        .toList(growable: false);
  }

  Future<void> _newProduct() async {
    final saved = await showProductEditorDialog(
      context,
      api: _api,
      token: widget.session.token,
    );
    if (saved == true) {
      _load();
    }
  }

  Future<void> _edit(Product product) async {
    final saved = await showProductEditorDialog(
      context,
      api: _api,
      token: widget.session.token,
      product: product,
    );
    if (saved == true) {
      _load();
    }
  }

  Future<void> _openStockAction(
    Product product,
    ProductStockAction action,
  ) async {
    final changed = await showProductStockActionDialog(
      context,
      api: _api,
      token: widget.session.token,
      product: product,
      products: _products,
      action: action,
    );
    if (changed && action == ProductStockAction.adjust) {
      await _load();
    }
  }

  Future<void> _showExportMessage(BuildContext context) async {
    var scope = 'filtered';
    var format = 'visual';
    final export = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Exportar estoque'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Escolha como deseja apresentar as informações para sua equipe.',
                  style: TextStyle(color: Color(0xFF667085)),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Formato do relatório',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                RadioGroup<String>(
                  groupValue: format,
                  onChanged: (value) => setDialogState(() => format = value!),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'visual',
                        title: const Text('Relatório visual Lyncar'),
                        subtitle: const Text(
                          'Resumo executivo, indicadores e tabela organizada para leitura.',
                        ),
                        secondary: const Icon(Icons.auto_awesome_outlined),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'csv',
                        title: const Text('Dados para Excel'),
                        subtitle: const Text(
                          'Formato tabular para análises, filtros e planilhas.',
                        ),
                        secondary: const Icon(Icons.table_chart_outlined),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 22),
                const Text(
                  'Escopo dos dados',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                RadioGroup<String>(
                  groupValue: scope,
                  onChanged: (value) => setDialogState(() => scope = value!),
                  child: Column(
                    children: [
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'filtered',
                        title: Text(
                          'Resultado atual (${_filtered.length} itens)',
                        ),
                        subtitle: const Text(
                          'Respeita a busca e os filtros selecionados.',
                        ),
                      ),
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: 'all',
                        title: Text(
                          'Estoque completo (${_products.length} itens)',
                        ),
                        subtitle: const Text(
                          'Ignora a busca e exporta todos os produtos.',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, {
                'scope': scope,
                'format': format,
              }),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Gerar relatório'),
            ),
          ],
        ),
      ),
    );
    if (export != null) {
      final products = export['scope'] == 'all' ? _products : _filtered;
      if (export['format'] == 'visual') {
        _downloadVisualReport(products, filtered: export['scope'] != 'all');
      } else {
        _downloadStockReport(products);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(this.context).showSnackBar(
        const SnackBar(
          content: Text('Relatório gerado e baixado com sucesso.'),
        ),
      );
    }
  }

  void _downloadVisualReport(List<Product> products, {required bool filtered}) {
    final low = products
        .where(
          (item) =>
              item.stockQuantity > 0 && item.stockQuantity <= item.minimumStock,
        )
        .length;
    final empty = products.where((item) => item.stockQuantity <= 0).length;
    final totalValue = products.fold<double>(
      0,
      (sum, item) => sum + item.stockValue,
    );
    final rows = products.map((product) {
      final status = product.stockQuantity <= 0
          ? ('Sem estoque', '#DC2626')
          : product.stockQuantity <= product.minimumStock
          ? ('Baixo', '#D97706')
          : ('Disponível', '#059669');
      final location = product.stockLocation?.isNotEmpty == true
          ? product.stockLocation!
          : 'Principal';
      return '''<tr>
        <td><strong>${_html(product.name)}</strong><small>${_html(product.internalCode ?? product.barcode ?? 'Sem código')}</small></td>
        <td>${_html(_productType(product.productType))}</td>
        <td><strong>${_html('${_number(product.stockQuantity)} ${product.unit}')}</strong></td>
        <td>${_html('${_number(product.minimumStock)} ${product.unit}')}</td>
        <td>${_html('$location · ${_brazilDate(product.nearestExpirationDate)}')}</td>
        <td>${_html(_money(product.effectiveSalePrice))}</td>
        <td><span class="status" style="color:${status.$2};background:${status.$2}18">${status.$1}</span></td>
      </tr>''';
    }).join();
    final html =
        '''<!doctype html>
<html lang="pt-BR"><head><meta charset="utf-8"><title>Relatório de estoque</title>
<style>
@page{size:A4 landscape;margin:18mm}*{box-sizing:border-box}body{margin:0;background:#f4f7fb;color:#172033;font-family:Inter,Segoe UI,Arial,sans-serif;padding:36px}
.page{max-width:1400px;margin:auto;background:#fff;border:1px solid #dce5f0;border-radius:20px;padding:38px;box-shadow:0 14px 40px #17203312}.brand{color:#0967c6;font-size:14px;font-weight:800;letter-spacing:.12em;text-transform:uppercase}.head{display:flex;justify-content:space-between;gap:24px;border-bottom:1px solid #e5eaf1;padding-bottom:24px}.head h1{font-size:32px;margin:8px 0}.muted{color:#667085}.date{text-align:right;color:#667085;font-size:13px}.cards{display:grid;grid-template-columns:repeat(4,1fr);gap:14px;margin:24px 0}.card{border:1px solid #e1e8f2;border-radius:14px;padding:16px;background:#f9fbfe}.card span{display:block;color:#667085;font-size:13px}.card strong{display:block;font-size:24px;margin-top:6px}.card.attention{background:#fff8eb;border-color:#f5d8a0}.table{width:100%;border-collapse:collapse;font-size:13px}.table th{background:#f4f7fb;color:#53657e;text-align:left;padding:12px 10px}.table td{padding:13px 10px;border-bottom:1px solid #edf0f4}.table small{display:block;color:#667085;margin-top:4px}.status{display:inline-block;border-radius:999px;padding:6px 10px;font-weight:700}.foot{border-top:1px solid #e5eaf1;margin-top:24px;padding-top:14px;color:#98a2b3;font-size:12px}@media print{body{background:#fff;padding:0}.page{box-shadow:none;border:0;padding:0}.head h1{font-size:25px}}
</style></head><body><main class="page"><header class="head"><div><div class="brand">Lyncar ERP</div><h1>Relatório de estoque</h1><div class="muted">Visão consolidada de produtos, saldos e necessidades de reposição</div></div><div class="date">Gerado em<br><strong>${_dateLabel(DateTime.now())}</strong><br><br>${filtered ? 'Filtros atuais aplicados' : 'Estoque completo'}</div></header>
<section class="cards"><div class="card"><span>Itens no relatório</span><strong>${products.length}</strong></div><div class="card attention"><span>Estoque baixo</span><strong>$low</strong></div><div class="card attention"><span>Sem estoque</span><strong>$empty</strong></div><div class="card"><span>Valor em estoque</span><strong>${_money(totalValue)}</strong></div></section>
<table class="table"><thead><tr><th>Produto / SKU</th><th>Tipo</th><th>Disponível</th><th>Mínimo</th><th>Depósito / validade</th><th>Venda</th><th>Status</th></tr></thead><tbody>$rows</tbody></table><footer class="foot">Relatório gerado pelo Lyncar ERP · Este documento é informativo e reflete os dados disponíveis no momento da exportação.</footer></main></body></html>''';
    downloadTextFile(
      filename: 'relatorio_visual_estoque_${_fileDate(DateTime.now())}.html',
      content: html,
      mimeType: 'text/html;charset=utf-8',
    );
  }

  void _downloadStockReport(List<Product> products) {
    final lines = <String>[
      '\uFEFFRelatório de estoque',
      'Gerado em;${_csvCell(_dateLabel(DateTime.now()))}',
      'Itens exportados;${products.length}',
      '',
      'Produto;SKU/EAN;Tipo;Disponível;Mínimo;Depósito;Validade/Lote;Preço de venda;Valor em estoque;Status',
      for (final product in products)
        [
          product.name,
          product.internalCode ?? product.barcode ?? '-',
          _productType(product.productType),
          '${_number(product.stockQuantity)} ${product.unit}',
          '${_number(product.minimumStock)} ${product.unit}',
          product.stockLocation?.isNotEmpty == true
              ? product.stockLocation!
              : 'Principal',
          '${_brazilDate(product.nearestExpirationDate)}${product.nearestBatchNumber == null ? '' : ' / ${product.nearestBatchNumber}'}',
          _money(product.effectiveSalePrice),
          _money(product.stockValue),
          product.stockQuantity <= 0
              ? 'Sem estoque'
              : product.stockQuantity <= product.minimumStock
              ? 'Baixo'
              : 'Disponível',
        ].map(_csvCell).join(';'),
    ];
    downloadTextFile(
      filename: 'relatorio_estoque_${_fileDate(DateTime.now())}.csv',
      content: lines.join('\r\n'),
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  @override
  Widget build(BuildContext context) {
    final products = _filtered;
    final active = _products.where((item) => item.active).length;
    final low = _products
        .where((item) => item.stockQuantity <= item.minimumStock)
        .length;
    final empty = _products.where((item) => item.stockQuantity <= 0).length;
    final stockValue = _products.fold<double>(
      0,
      (sum, item) => sum + item.stockValue,
    );
    final pageCount = products.isEmpty
        ? 0
        : (products.length / _pageSize).ceil();
    final safePage = pageCount == 0 ? 0 : _page.clamp(0, pageCount - 1);
    final pageProducts = products
        .skip(safePage * _pageSize)
        .take(_pageSize)
        .toList();
    final filterTypes = <String>{
      'Todos',
      ..._products.map((product) => _productType(product.productType)),
    }.toList();
    final filterLocations = <String>{
      'Todos',
      ..._products.map(
        (product) => product.stockLocation?.isNotEmpty == true
            ? product.stockLocation!
            : 'Principal',
      ),
    }.toList();

    return ColoredBox(
      color: const Color(0xFFF5F8FC),
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
          children: [
            _PageHeader(onRefresh: _load, onCreate: _newProduct),
            const SizedBox(height: 18),
            _InventoryTabs(selected: _tab, onChanged: _changeTab),
            const SizedBox(height: 18),
            if (_tab == 0) ...[
              _KpiGrid(
                active: active,
                low: low,
                empty: empty,
                value: stockValue,
              ),
              const SizedBox(height: 18),
              _AttentionPanel(low: low, empty: empty),
              const SizedBox(height: 18),
              _InventoryToolbar(
                controller: _search,
                onChanged: () => setState(() => _page = 0),
                filtersExpanded: _filtersExpanded,
                onFilters: () =>
                    setState(() => _filtersExpanded = !_filtersExpanded),
                onExport: () => _showExportMessage(context),
              ),
              if (_filtersExpanded) ...[
                const SizedBox(height: 10),
                _InlineFiltersPanel(
                  status: _statusFilter,
                  type: _typeFilter,
                  location: _locationFilter,
                  onlyAttention: _onlyAttention,
                  types: filterTypes,
                  locations: filterLocations,
                  onStatusChanged: (value) => setState(() {
                    _statusFilter = value;
                    _page = 0;
                  }),
                  onTypeChanged: (value) => setState(() {
                    _typeFilter = value;
                    _page = 0;
                  }),
                  onLocationChanged: (value) => setState(() {
                    _locationFilter = value;
                    _page = 0;
                  }),
                  onAttentionChanged: (value) => setState(() {
                    _onlyAttention = value;
                    _page = 0;
                  }),
                  onClear: () => setState(() {
                    _statusFilter = 'Todos';
                    _typeFilter = 'Todos';
                    _locationFilter = 'Todos';
                    _onlyAttention = false;
                    _page = 0;
                  }),
                ),
              ],
              const SizedBox(height: 12),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                ErrorPanel(message: _error!, onRetry: _load)
              else
                _ProductGrid(
                  products: pageProducts,
                  apiBaseUrl: widget.session.apiBaseUrl,
                  onOpen: _edit,
                  onAction: _openStockAction,
                  currentPage: safePage,
                  totalItems: products.length,
                  onPageChanged: (page) => setState(() => _page = page),
                ),
            ] else if (_tab == 1)
              _MovementsPanel(
                movements: _recentMovements,
                loading: _movementsLoading,
                error: _movementsError,
                onRetry: _loadRecentMovements,
              )
            else if (_tab == 3)
              _ExpiryPanel(products: _products)
            else
              _ComingSoonPanel(tab: _tab),
          ],
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({required this.onRefresh, required this.onCreate});
  final VoidCallback onRefresh;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Estoque',
                style: TextStyle(
                  fontSize: 32,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF172033),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Gerencie produtos, movimentos e inventário em um só lugar.',
                style: TextStyle(color: Color(0xFF667085), fontSize: 15),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          onPressed: onRefresh,
          tooltip: 'Atualizar',
          icon: const Icon(Icons.refresh_outlined),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.add),
          label: const Text('Novo item'),
        ),
      ],
    );
  }
}

class _InventoryTabs extends StatelessWidget {
  const _InventoryTabs({required this.selected, required this.onChanged});
  final int selected;
  final ValueChanged<int> onChanged;

  static const labels = [
    'Produtos',
    'Movimentações',
    'Inventário',
    'Lotes e validades',
    'Depósitos',
  ];
  static const icons = [
    Icons.inventory_2_outlined,
    Icons.swap_vert_outlined,
    Icons.fact_check_outlined,
    Icons.event_available_outlined,
    Icons.warehouse_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var index = 0; index < labels.length; index++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: TextButton.icon(
                  onPressed: () => onChanged(index),
                  style: TextButton.styleFrom(
                    backgroundColor: selected == index
                        ? const Color(0xFFE8F3FF)
                        : Colors.transparent,
                    foregroundColor: selected == index
                        ? const Color(0xFF0967C6)
                        : const Color(0xFF667085),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: Icon(icons[index], size: 18),
                  label: Text(labels[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _KpiGrid extends StatelessWidget {
  const _KpiGrid({
    required this.active,
    required this.low,
    required this.empty,
    required this.value,
  });
  final int active;
  final int low;
  final int empty;
  final double value;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        'Itens ativos',
        '$active',
        'de produtos cadastrados',
        Icons.inventory_2_outlined,
        const Color(0xFF2563EB),
      ),
      (
        'Estoque baixo',
        '$low',
        'abaixo do mínimo',
        Icons.warning_amber_outlined,
        const Color(0xFFD97706),
      ),
      (
        'Sem estoque',
        '$empty',
        'precisam de reposição',
        Icons.block_outlined,
        const Color(0xFFDC2626),
      ),
      (
        'Valor do estoque',
        _money(value),
        'valor de custo total',
        Icons.account_balance_wallet_outlined,
        const Color(0xFF0D9488),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 4
            : constraints.maxWidth >= 700
            ? 2
            : 1;
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: items.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 112,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemBuilder: (context, index) {
            final item = items[index];
            return AppCard(
              child: Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: item.$5.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(item.$4, color: item.$5),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.$1,
                          style: const TextStyle(color: Color(0xFF667085)),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          item.$2,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF172033),
                          ),
                        ),
                        Text(
                          item.$3,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF98A2B3),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _AttentionPanel extends StatelessWidget {
  const _AttentionPanel({required this.low, required this.empty});
  final int low;
  final int empty;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(
            Icons.notifications_none_outlined,
            color: Color(0xFF0967C6),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Atenções do estoque',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
          ),
          if (low > 0)
            _AttentionChip(
              label: '$low abaixo do mínimo',
              color: const Color(0xFFD97706),
            ),
          if (empty > 0) ...[
            const SizedBox(width: 8),
            _AttentionChip(
              label: '$empty sem estoque',
              color: Color(0xFFDC2626),
            ),
          ],
          if (low == 0 && empty == 0)
            const Text(
              'Nenhuma pendência',
              style: TextStyle(color: Color(0xFF059669)),
            ),
        ],
      ),
    );
  }
}

class _AttentionChip extends StatelessWidget {
  const _AttentionChip({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    ),
  );
}

class _InventoryToolbar extends StatelessWidget {
  const _InventoryToolbar({
    required this.controller,
    required this.onChanged,
    required this.filtersExpanded,
    required this.onFilters,
    required this.onExport,
  });
  final TextEditingController controller;
  final VoidCallback onChanged;
  final bool filtersExpanded;
  final VoidCallback onFilters;
  final VoidCallback onExport;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 700;
                final search = TextField(
                  controller: controller,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Buscar produto, SKU ou código de barras',
                  ),
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onFilters,
                      icon: const Icon(Icons.tune_outlined),
                      label: Text(
                        filtersExpanded ? 'Ocultar filtros' : 'Filtros',
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: onExport,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Exportar'),
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [search, const SizedBox(height: 10), actions],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: search),
                    const SizedBox(width: 10),
                    actions,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineFiltersPanel extends StatelessWidget {
  const _InlineFiltersPanel({
    required this.status,
    required this.type,
    required this.location,
    required this.onlyAttention,
    required this.types,
    required this.locations,
    required this.onStatusChanged,
    required this.onTypeChanged,
    required this.onLocationChanged,
    required this.onAttentionChanged,
    required this.onClear,
  });
  final String status;
  final String type;
  final String location;
  final bool onlyAttention;
  final List<String> types;
  final List<String> locations;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<String> onTypeChanged;
  final ValueChanged<String> onLocationChanged;
  final ValueChanged<bool> onAttentionChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final columns = constraints.maxWidth >= 900 ? 4 : 2;
          final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: width,
                child: DropdownButtonFormField<String>(
                  initialValue: status,
                  decoration: const InputDecoration(labelText: 'Status'),
                  items: const [
                    DropdownMenuItem(value: 'Todos', child: Text('Todos')),
                    DropdownMenuItem(
                      value: 'Disponível',
                      child: Text('Disponível'),
                    ),
                    DropdownMenuItem(value: 'Baixo', child: Text('Baixo')),
                    DropdownMenuItem(
                      value: 'Sem estoque',
                      child: Text('Sem estoque'),
                    ),
                  ],
                  onChanged: (value) => onStatusChanged(value ?? 'Todos'),
                ),
              ),
              SizedBox(
                width: width,
                child: DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: 'Tipo'),
                  items: [
                    for (final value in types)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => onTypeChanged(value ?? 'Todos'),
                ),
              ),
              SizedBox(
                width: width,
                child: DropdownButtonFormField<String>(
                  initialValue: location,
                  decoration: const InputDecoration(labelText: 'Depósito'),
                  items: [
                    for (final value in locations)
                      DropdownMenuItem(value: value, child: Text(value)),
                  ],
                  onChanged: (value) => onLocationChanged(value ?? 'Todos'),
                ),
              ),
              SizedBox(
                width: width,
                child: Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        contentPadding: EdgeInsets.zero,
                        value: onlyAttention,
                        title: const Text('Somente atenção'),
                        onChanged: (value) =>
                            onAttentionChanged(value ?? false),
                      ),
                    ),
                    TextButton(onPressed: onClear, child: const Text('Limpar')),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductGrid extends StatelessWidget {
  const _ProductGrid({
    required this.products,
    required this.apiBaseUrl,
    required this.onOpen,
    required this.onAction,
    required this.currentPage,
    required this.totalItems,
    required this.onPageChanged,
  });
  final List<Product> products;
  final String apiBaseUrl;
  final ValueChanged<Product> onOpen;
  final void Function(Product, ProductStockAction) onAction;
  final int currentPage;
  final int totalItems;
  final ValueChanged<int> onPageChanged;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final desktopTable = constraints.maxWidth >= 1500;
              final mediumTable = constraints.maxWidth >= 960;
              if (desktopTable) {
                return SizedBox(
                  width: double.infinity,
                  child: Column(
                    children: [
                      const _InventoryTableHeader(),
                      for (final product in products)
                        _InventoryRow(
                          product: product,
                          apiBaseUrl: apiBaseUrl,
                          onOpen: onOpen,
                          onAction: onAction,
                        ),
                    ],
                  ),
                );
              }
              if (mediumTable) {
                return Column(
                  children: [
                    const _DenseInventoryTableHeader(),
                    for (final product in products)
                      _DenseInventoryRow(
                        product: product,
                        apiBaseUrl: apiBaseUrl,
                        onOpen: onOpen,
                        onAction: onAction,
                      ),
                  ],
                );
              }
              return Column(
                children: [
                  for (final product in products)
                    _CompactInventoryRow(
                      product: product,
                      apiBaseUrl: apiBaseUrl,
                      onOpen: onOpen,
                      onAction: onAction,
                    ),
                ],
              );
            },
          ),
          if (products.isEmpty)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Text('Nenhum produto encontrado.'),
            ),
          AppPagination(
            currentPage: currentPage,
            totalItems: totalItems,
            pageSize: 50,
            itemLabel: 'produtos',
            onPageChanged: onPageChanged,
          ),
        ],
      ),
    );
  }
}

class _DenseInventoryTableHeader extends StatelessWidget {
  const _DenseInventoryTableHeader();

  @override
  Widget build(BuildContext context) => Container(
    color: const Color(0xFFF8FAFC),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: const Row(
      children: [
        Expanded(
          flex: 4,
          child: Text('Produto / SKU', style: _tableHeaderStyle),
        ),
        Expanded(flex: 2, child: Text('Disponível', style: _tableHeaderStyle)),
        Expanded(flex: 2, child: Text('Mínimo', style: _tableHeaderStyle)),
        Expanded(flex: 2, child: Text('Venda', style: _tableHeaderStyle)),
        Expanded(
          flex: 3,
          child: Text('Validade / depósito', style: _tableHeaderStyle),
        ),
        Expanded(flex: 2, child: Text('Status', style: _tableHeaderStyle)),
        SizedBox(width: 44, child: Text('')),
      ],
    ),
  );
}

class _ProductActionsButton extends StatelessWidget {
  const _ProductActionsButton({
    required this.product,
    required this.onEdit,
    required this.onAction,
  });

  final Product product;
  final ValueChanged<Product> onEdit;
  final void Function(Product, ProductStockAction) onAction;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Ações de ${product.name}',
      icon: const Icon(Icons.more_horiz),
      onSelected: (value) {
        switch (value) {
          case 'edit':
            onEdit(product);
          case 'composition':
            onAction(product, ProductStockAction.composition);
          case 'batches':
            onAction(product, ProductStockAction.batches);
          case 'history':
            onAction(product, ProductStockAction.history);
          case 'adjust':
            onAction(product, ProductStockAction.adjust);
        }
      },
      itemBuilder: (context) => const [
        PopupMenuItem(
          value: 'edit',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.edit_outlined),
            title: Text('Editar cadastro'),
          ),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'composition',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.account_tree_outlined),
            title: Text('Ficha técnica / composição'),
          ),
        ),
        PopupMenuItem(
          value: 'batches',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_available_outlined),
            title: Text('Saldos por lote'),
          ),
        ),
        PopupMenuItem(
          value: 'history',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.history),
            title: Text('Histórico de movimentações'),
          ),
        ),
        PopupMenuItem(
          value: 'adjust',
          child: ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.tune_outlined),
            title: Text('Ajustar estoque'),
          ),
        ),
      ],
    );
  }
}

const _tableHeaderStyle = TextStyle(fontWeight: FontWeight.w700);

class _DenseInventoryRow extends StatelessWidget {
  const _DenseInventoryRow({
    required this.product,
    required this.apiBaseUrl,
    required this.onOpen,
    required this.onAction,
  });
  final Product product;
  final String apiBaseUrl;
  final ValueChanged<Product> onOpen;
  final void Function(Product, ProductStockAction) onAction;

  @override
  Widget build(BuildContext context) {
    final status = product.stockQuantity <= 0
        ? ('Sem estoque', const Color(0xFFDC2626))
        : product.stockQuantity <= product.minimumStock
        ? ('Baixo', const Color(0xFFD97706))
        : ('Disponível', const Color(0xFF059669));
    final location = product.stockLocation?.isNotEmpty == true
        ? product.stockLocation!
        : 'Principal';
    return InkWell(
      onTap: () => onOpen(product),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
        ),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Row(
                children: [
                  _ProductImage(url: product.imageUrl, apiBaseUrl: apiBaseUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          product.internalCode ??
                              product.barcode ??
                              'Sem código',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Text(
                '${_number(product.stockQuantity)} ${product.unit}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            Expanded(
              flex: 2,
              child: Text('${_number(product.minimumStock)} ${product.unit}'),
            ),
            Expanded(flex: 2, child: Text(_money(product.effectiveSalePrice))),
            Expanded(
              flex: 3,
              child: Text(
                '${_brazilDate(product.nearestExpirationDate)} · $location',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Expanded(
              flex: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: _StatusPill(label: status.$1, color: status.$2),
              ),
            ),
            _ProductActionsButton(
              product: product,
              onEdit: onOpen,
              onAction: onAction,
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactInventoryRow extends StatelessWidget {
  const _CompactInventoryRow({
    required this.product,
    required this.apiBaseUrl,
    required this.onOpen,
    required this.onAction,
  });
  final Product product;
  final String apiBaseUrl;
  final ValueChanged<Product> onOpen;
  final void Function(Product, ProductStockAction) onAction;

  @override
  Widget build(BuildContext context) {
    final status = product.stockQuantity <= 0
        ? ('Sem estoque', const Color(0xFFDC2626))
        : product.stockQuantity <= product.minimumStock
        ? ('Baixo', const Color(0xFFD97706))
        : ('Disponível', const Color(0xFF059669));
    return InkWell(
      onTap: () => onOpen(product),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ProductImage(url: product.imageUrl, apiBaseUrl: apiBaseUrl),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          product.name,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF172033),
                          ),
                        ),
                      ),
                      _ProductActionsButton(
                        product: product,
                        onEdit: onOpen,
                        onAction: onAction,
                      ),
                    ],
                  ),
                  Text(
                    product.internalCode ?? product.barcode ?? 'Sem código',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF667085),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    children: [
                      _CompactField(
                        label: 'Disponível',
                        value:
                            '${_number(product.stockQuantity)} ${product.unit}',
                        emphasis: true,
                      ),
                      _CompactField(
                        label: 'Mínimo',
                        value:
                            '${_number(product.minimumStock)} ${product.unit}',
                      ),
                      _CompactField(
                        label: 'Venda',
                        value: _money(product.effectiveSalePrice),
                      ),
                      _CompactField(
                        label: 'Validade',
                        value: _brazilDate(product.nearestExpirationDate),
                      ),
                      _CompactField(
                        label: 'Depósito',
                        value: product.stockLocation?.isNotEmpty == true
                            ? product.stockLocation!
                            : 'Principal',
                      ),
                      _StatusPill(label: status.$1, color: status.$2),
                    ],
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

class _CompactField extends StatelessWidget {
  const _CompactField({
    required this.label,
    required this.value,
    this.emphasis = false,
  });
  final String label;
  final String value;
  final bool emphasis;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 92, maxWidth: 170),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 11, color: Color(0xFF667085)),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: emphasis ? FontWeight.w700 : FontWeight.w500,
            color: const Color(0xFF172033),
          ),
        ),
      ],
    ),
  );
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.10),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    ),
  );
}

class _InventoryTableHeader extends StatelessWidget {
  const _InventoryTableHeader();
  @override
  Widget build(BuildContext context) => Container(
    height: 50,
    padding: const EdgeInsets.symmetric(horizontal: 16),
    color: const Color(0xFFF8FAFC),
    child: const Row(
      children: [
        SizedBox(
          width: 330,
          child: Text('Produto', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          width: 120,
          child: Text(
            'SKU / EAN',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 100,
          child: Text('Tipo', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          width: 110,
          child: Text(
            'Disponível',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 90,
          child: Text('Mínimo', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          width: 150,
          child: Text(
            'Depósito',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 140,
          child: Text(
            'Próx. validade',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SizedBox(
          width: 100,
          child: Text('Venda', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          width: 120,
          child: Text('Status', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
        SizedBox(
          width: 60,
          child: Text('Ações', style: TextStyle(fontWeight: FontWeight.w700)),
        ),
      ],
    ),
  );
}

class _InventoryRow extends StatelessWidget {
  const _InventoryRow({
    required this.product,
    required this.apiBaseUrl,
    required this.onOpen,
    required this.onAction,
  });
  final Product product;
  final String apiBaseUrl;
  final ValueChanged<Product> onOpen;
  final void Function(Product, ProductStockAction) onAction;

  @override
  Widget build(BuildContext context) {
    final status = product.stockQuantity <= 0
        ? ('Sem estoque', const Color(0xFFDC2626))
        : product.stockQuantity <= product.minimumStock
        ? ('Baixo', const Color(0xFFD97706))
        : ('Disponível', const Color(0xFF059669));
    return InkWell(
      onTap: () => onOpen(product),
      child: Container(
        height: 70,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 330,
              child: Row(
                children: [
                  _ProductImage(url: product.imageUrl, apiBaseUrl: apiBaseUrl),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          product.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF172033),
                          ),
                        ),
                        Text(
                          [product.category, product.unit]
                              .whereType<String>()
                              .where((value) => value.isNotEmpty)
                              .join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF667085),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 120,
              child: Text(product.internalCode ?? product.barcode ?? '-'),
            ),
            SizedBox(
              width: 100,
              child: Text(_productType(product.productType)),
            ),
            SizedBox(
              width: 110,
              child: Text(
                '${_number(product.stockQuantity)} ${product.unit}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            SizedBox(
              width: 90,
              child: Text('${_number(product.minimumStock)} ${product.unit}'),
            ),
            SizedBox(
              width: 150,
              child: Text(
                product.stockLocation?.isNotEmpty == true
                    ? product.stockLocation!
                    : 'Principal',
              ),
            ),
            SizedBox(
              width: 140,
              child: Text(_brazilDate(product.nearestExpirationDate)),
            ),
            SizedBox(
              width: 100,
              child: Text(_money(product.effectiveSalePrice)),
            ),
            SizedBox(
              width: 120,
              child: Align(
                alignment: Alignment.centerLeft,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: status.$2.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 6,
                    ),
                    child: Text(
                      status.$1,
                      style: TextStyle(
                        color: status.$2,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 60,
              child: IconButton(
                onPressed: () => onOpen(product),
                tooltip: 'Editar produto',
                icon: const Icon(Icons.more_horiz),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url, required this.apiBaseUrl});
  final String? url;
  final String apiBaseUrl;
  @override
  Widget build(BuildContext context) {
    final source = url == null || url!.isEmpty
        ? null
        : (url!.startsWith('http')
              ? url
              : '${apiBaseUrl.replaceAll(RegExp(r'/$'), '')}/${url!.replaceFirst(RegExp(r'^/'), '')}');
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: const Color(0xFFF0F4FA),
        borderRadius: BorderRadius.circular(8),
      ),
      child: source == null
          ? const Icon(Icons.image_outlined, color: Color(0xFF98A2B3), size: 20)
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.network(
                source,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.image_outlined,
                  color: Color(0xFF98A2B3),
                  size: 20,
                ),
              ),
            ),
    );
  }
}

class _MovementsPanel extends StatelessWidget {
  const _MovementsPanel({
    required this.movements,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final List<StockMovement> movements;
  final bool loading;
  final String? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Movimentações recentes',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Acompanhe baixas, ajustes e documentos que alteraram o saldo.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 18),
          if (loading)
            const LinearProgressIndicator()
          else if (error != null)
            ErrorPanel(message: error!, onRetry: onRetry)
          else if (movements.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('Nenhuma movimentação recente.')),
            )
          else
            for (final movement in movements)
              _MovementSummaryRow(movement: movement),
        ],
      ),
    );
  }
}

class _MovementSummaryRow extends StatelessWidget {
  const _MovementSummaryRow({required this.movement});

  final StockMovement movement;

  @override
  Widget build(BuildContext context) {
    final incoming = movement.quantityDelta >= 0;
    final source = switch (movement.sourceType) {
      'stock_entry' => 'Entrada de estoque',
      'stock_withdrawal' => 'Baixa de estoque',
      'product_initial' => 'Saldo inicial',
      'pdv' => 'PDV',
      'venda' => 'Venda',
      _ => 'Movimentação de estoque',
    };
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE4E7EC))),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 19,
            backgroundColor: incoming
                ? const Color(0xFFE7F7EF)
                : const Color(0xFFFFECEC),
            child: Icon(
              incoming ? Icons.south_west : Icons.north_east,
              color: incoming
                  ? const Color(0xFF059669)
                  : const Color(0xFFDC2626),
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  movement.productName ?? 'Produto #${movement.productId}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  '$source · ${_dateTimeLabel(movement.createdAt)}${movement.reason == null ? '' : ' · ${movement.reason}'}',
                  style: const TextStyle(
                    color: Color(0xFF667085),
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Text(
            '${incoming ? '+' : ''}${_number(movement.quantityDelta)} ${movement.unit}',
            style: TextStyle(
              color: incoming
                  ? const Color(0xFF059669)
                  : const Color(0xFFDC2626),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _ExpiryPanel extends StatelessWidget {
  const _ExpiryPanel({required this.products});

  final List<Product> products;

  @override
  Widget build(BuildContext context) {
    final tracked = products
        .where((product) => product.nearestExpirationDate != null)
        .toList();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Lotes e validades',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          const Text(
            'Produtos com validade conhecida. Abra as ações do produto para consultar o saldo detalhado por lote.',
            style: TextStyle(color: Color(0xFF667085)),
          ),
          const SizedBox(height: 18),
          if (tracked.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Nenhum produto com validade cadastrada.'),
              ),
            )
          else
            for (final product in tracked)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const CircleAvatar(
                  backgroundColor: Color(0xFFFFF4E5),
                  child: Icon(
                    Icons.event_available_outlined,
                    color: Color(0xFFD97706),
                  ),
                ),
                title: Text(
                  product.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  product.nearestBatchNumber == null
                      ? 'Validade: ${_brazilDate(product.nearestExpirationDate)}'
                      : 'Lote ${product.nearestBatchNumber} · Validade: ${_brazilDate(product.nearestExpirationDate)}',
                ),
              ),
        ],
      ),
    );
  }
}

class _ComingSoonPanel extends StatelessWidget {
  const _ComingSoonPanel({required this.tab});
  final int tab;
  @override
  Widget build(BuildContext context) {
    const titles = [
      'Produtos',
      'Movimentações',
      'Inventário',
      'Lotes e validades',
      'Depósitos',
    ];
    const icons = [
      Icons.inventory_2_outlined,
      Icons.swap_vert_outlined,
      Icons.fact_check_outlined,
      Icons.event_available_outlined,
      Icons.warehouse_outlined,
    ];
    return AppCard(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 70, horizontal: 24),
        child: Column(
          children: [
            Icon(icons[tab], size: 48, color: const Color(0xFF0967C6)),
            const SizedBox(height: 14),
            Text(
              titles[tab],
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            const Text(
              'Em breve',
              style: TextStyle(
                color: Color(0xFF0967C6),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              tab == 2
                  ? 'O inventário físico será disponibilizado nesta área.'
                  : 'Estamos preparando esta área para completar a gestão do estoque.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF667085)),
            ),
          ],
        ),
      ),
    );
  }
}

String _productType(String value) => switch (value) {
  'produto' => 'Produto',
  'mercadoria' => 'Mercadoria',
  'materia_prima' => 'Matéria-prima',
  _ => value,
};

String _number(double value) => value == value.roundToDouble()
    ? value.toInt().toString()
    : value.toStringAsFixed(2).replaceAll('.', ',');

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

String _dateLabel(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

String _dateTimeLabel(DateTime value) =>
    '${_dateLabel(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

String _fileDate(DateTime value) =>
    '${value.year}${value.month.toString().padLeft(2, '0')}${value.day.toString().padLeft(2, '0')}';

String _csvCell(String value) => '"${value.replaceAll('"', '""')}"';

String _html(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

String _brazilDate(String? value) {
  if (value == null || value.isEmpty) return '-';
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
