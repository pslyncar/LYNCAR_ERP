import 'dart:math';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';

import '../models/product.dart';
import '../models/product_batch.dart';
import '../models/product_composition.dart';
import '../models/fiscal_assistant.dart';
import '../models/session.dart';
import '../models/stock_movement.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _productTypes = {
  'produto': 'Produto',
  'produto_acabado': 'Produto acabado',
  'mercadoria': 'Mercadoria/revenda',
  'materia_prima': 'Materia-prima',
  'embalagem': 'Embalagem',
  'peca': 'Peca',
  'servico': 'Servico',
  'insumo': 'Insumo',
};

const _unitOptions = {
  'un': 'Unidade',
  'pc': 'Peca',
  'eb': 'Embalagem',
  'cx': 'Caixa',
  'pct': 'Pacote',
  'kit': 'Kit',
  'par': 'Par',
  'jogo': 'Jogo',
  'kg': 'Quilograma',
  'g': 'Grama',
  't': 'Tonelada',
  'l': 'Litro',
  'ml': 'Mililitro',
  'm': 'Metro',
  'cm': 'Centimetro',
  'mm': 'Milimetro',
  'm2': 'Metro quadrado',
  'm3': 'Metro cubico',
  'h': 'Hora',
  'dia': 'Dia',
  'mes': 'Mes',
  'serv': 'Servico',
};

const _unitFamilies = {
  'kg': 'mass',
  'g': 'mass',
  't': 'mass',
  'l': 'volume',
  'ml': 'volume',
  'm': 'length',
  'cm': 'length',
  'mm': 'length',
  'm2': 'área',
  'm3': 'volume3',
};

const _unitFactors = {
  'kg': 1000.0,
  'g': 1.0,
  't': 1000000.0,
  'l': 1000.0,
  'ml': 1.0,
  'm': 1000.0,
  'cm': 10.0,
  'mm': 1.0,
  'm2': 1.0,
  'm3': 1.0,
};

const _fiscalOrigins = {
  '0': 'Nacional, exceto as indicadas nos codigos 3, 4, 5 e 8',
  '1': 'Estrangeira - importacao direta',
  '2': 'Estrangeira - adquirida no mercado interno',
  '3': 'Nacional, mercadoria com conteudo de importacao superior a 40%',
  '4': 'Nacional, produzida conforme processos produtivos basicos',
  '5': 'Nacional, conteudo de importacao inferior ou igual a 40%',
  '6': 'Estrangeira - importacao direta, sem similar nacional',
  '7': 'Estrangeira - mercado interno, sem similar nacional',
  '8': 'Nacional, conteudo de importacao superior a 70%',
};

const _cfopSaleOptions = {
  '5101': 'Venda de producao do estabelecimento',
  '5102': 'Venda de mercadoria adquirida ou recebida de terceiros',
  '5103': 'Venda de producao do estabelecimento para entrega futura',
  '5104': 'Venda de mercadoria de terceiros para entrega futura',
  '5105': 'Venda de producao com mercadoria sujeita a ST',
  '5106': 'Venda de mercadoria de terceiros sujeita a ST',
  '5401': 'Venda de producao sujeita a substituicao tributaria',
  '5403': 'Venda de mercadoria de terceiros sujeita a ST',
  '5405': 'Venda de mercadoria sujeita a ST, como contribuinte substituido',
  '5656': 'Venda de combustivel ou lubrificante adquirido de terceiros',
  '6101': 'Venda interestadual de producao do estabelecimento',
  '6102': 'Venda interestadual de mercadoria de terceiros',
  '6401': 'Venda interestadual de producao sujeita a ST',
  '6403': 'Venda interestadual de mercadoria de terceiros sujeita a ST',
  '6404': 'Venda interestadual de mercadoria sujeita a ST como substituido',
  '7101': 'Venda de producao do estabelecimento para exterior',
  '7102': 'Venda de mercadoria adquirida de terceiros para exterior',
};

const _icmsCstOptions = {
  '00': 'Tributada integralmente',
  '10': 'Tributada com cobranca do ICMS por substituicao tributaria',
  '20': 'Com reducao de base de calculo',
  '30': 'Isenta ou nao tributada com cobranca do ICMS por ST',
  '40': 'Isenta',
  '41': 'Nao tributada',
  '50': 'Suspensao',
  '51': 'Diferimento',
  '60': 'ICMS cobrado anteriormente por substituicao tributaria',
  '70': 'Reducao de base e cobranca do ICMS por ST',
  '90': 'Outras',
};

const _csosnOptions = {
  '101': 'Tributada pelo Simples Nacional com permissao de credito',
  '102': 'Tributada pelo Simples Nacional sem permissao de credito',
  '103': 'Isencao do ICMS para faixa de receita bruta',
  '201': 'Com permissao de credito e ICMS por ST',
  '202': 'Sem permissao de credito e ICMS por ST',
  '203': 'Isencao para faixa de receita bruta e ICMS por ST',
  '300': 'Imune',
  '400': 'Nao tributada pelo Simples Nacional',
  '500': 'ICMS cobrado anteriormente por ST ou antecipacao',
  '900': 'Outros',
};

const _ibsCbsCstOptions = {
  '000': 'Tributacao integral',
  '010': 'Tributacao com aliquotas uniformes',
  '011': 'Tributacao com aliquotas uniformes reduzidas',
  '200': 'Aliquota reduzida',
  '210': 'Reducao de aliquota com redutor de base',
  '220': 'Aliquota fixa',
  '400': 'Isencao',
  '410': 'Imunidade e nao incidencia',
  '510': 'Diferimento',
  '550': 'Suspensao',
  '620': 'Tributacao monofasica',
  '800': 'Transferencia de credito',
  '900': 'Outras',
};

class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, required this.session});

  final Session session;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<Product> _products = [];
  final _search = TextEditingController();
  final _minSale = TextEditingController();
  final _maxSale = TextEditingController();
  String _typeFilter = 'todos';
  String _statusFilter = 'ativos';
  bool _lowStockOnly = false;
  bool _withBatchOnly = false;
  bool _advancedOpen = false;
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
    _minSale.dispose();
    _maxSale.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _api.listProducts(widget.session.token);
      setState(() => _products = products);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar o estoque.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Product? product]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ProductDialog(
        api: _api,
        token: widget.session.token,
        product: product,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _openHistory(Product product) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _StockHistoryDialog(
        api: _api,
        token: widget.session.token,
        product: product,
      ),
    );
  }

  Future<void> _openBatches(Product product) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _ProductBatchesDialog(
        api: _api,
        token: widget.session.token,
        product: product,
      ),
    );
  }

  Future<void> _openComposition(Product product) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _CompositionDialog(
        api: _api,
        token: widget.session.token,
        product: product,
        products: _products,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = widget.session.can('products:create');
    final canUpdate = widget.session.can('products:update');
    final filteredProducts = _filteredProducts();
    final active = _products.where((product) => product.active).length;
    final lowStock = _products
        .where((product) => product.stockQuantity <= product.minimumStock)
        .length;
    final value = _products.fold<double>(
      0,
      (sum, product) => sum + (product.stockQuantity * product.salePrice),
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Estoque',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Produtos, mercadorias, materias-primas e ficha técnica',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Atualizar',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 8),
                if (canCreate)
                  FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Novo item'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            _SummaryGrid(
              items: [
                _SummaryItem(
                  'Itens ativos',
                  active,
                  Icons.inventory_2_outlined,
                ),
                _SummaryItem(
                  'Estoque baixo',
                  lowStock,
                  Icons.warning_amber_outlined,
                ),
                _SummaryItem(
                  'Valor em venda',
                  value,
                  Icons.payments_outlined,
                  money: true,
                ),
              ],
            ),
            const SizedBox(height: 18),
            _ProductSearchPanel(
              search: _search,
              minSale: _minSale,
              maxSale: _maxSale,
              typeFilter: _typeFilter,
              statusFilter: _statusFilter,
              lowStockOnly: _lowStockOnly,
              withBatchOnly: _withBatchOnly,
              advancedOpen: _advancedOpen,
              onChanged: () => setState(() {}),
              onToggleAdvanced: () =>
                  setState(() => _advancedOpen = !_advancedOpen),
              onTypeChanged: (value) =>
                  setState(() => _typeFilter = value ?? 'todos'),
              onStatusChanged: (value) =>
                  setState(() => _statusFilter = value ?? 'ativos'),
              onLowStockChanged: (value) =>
                  setState(() => _lowStockOnly = value),
              onBatchChanged: (value) => setState(() => _withBatchOnly = value),
              onClear: _clearFilters,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: filteredProducts.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhum item encontrado com esses filtros.',
                        ),
                      )
                    : _ProductsTable(
                        products: filteredProducts,
                        apiBaseUrl: widget.session.apiBaseUrl,
                        canEdit: canUpdate,
                        canViewBatches: widget.session.can(
                          'stock:batches:view',
                        ),
                        onOpen: _openForm,
                        onBatches: _openBatches,
                        onHistory: _openHistory,
                        onComposition: _openComposition,
                      ),
              ),
          ],
        ),
      ),
    );
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _minSale.clear();
      _maxSale.clear();
      _typeFilter = 'todos';
      _statusFilter = 'ativos';
      _lowStockOnly = false;
      _withBatchOnly = false;
    });
  }

  List<Product> _filteredProducts() {
    final term = _normalize(_search.text);
    final minSale = _nullableMoney(_minSale.text);
    final maxSale = _nullableMoney(_maxSale.text);
    return _products.where((product) {
      if (_statusFilter == 'ativos' && !product.active) return false;
      if (_statusFilter == 'inativos' && product.active) return false;
      if (_typeFilter != 'todos' && product.productType != _typeFilter) {
        return false;
      }
      if (_lowStockOnly && product.stockQuantity > product.minimumStock) {
        return false;
      }
      if (_withBatchOnly &&
          product.nearestBatchNumber == null &&
          product.nearestExpirationDate == null &&
          !product.tracksBatch) {
        return false;
      }
      if (minSale != null && product.salePrice < minSale) return false;
      if (maxSale != null && product.salePrice > maxSale) return false;
      if (term.isEmpty) return true;
      final haystack = _normalize(
        [
          product.name,
          product.internalCode,
          product.barcode,
          product.purchasePackageBarcode,
          product.category,
          product.brand,
          product.model,
          product.ncm,
          product.cest,
          product.stockLocation,
          product.nearestBatchNumber,
          product.lastReceiptSupplierName,
          product.lastReceiptInvoiceNumber,
          _productTypes[product.productType],
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }
}

class _ProductSearchPanel extends StatelessWidget {
  const _ProductSearchPanel({
    required this.search,
    required this.minSale,
    required this.maxSale,
    required this.typeFilter,
    required this.statusFilter,
    required this.lowStockOnly,
    required this.withBatchOnly,
    required this.advancedOpen,
    required this.onChanged,
    required this.onToggleAdvanced,
    required this.onTypeChanged,
    required this.onStatusChanged,
    required this.onLowStockChanged,
    required this.onBatchChanged,
    required this.onClear,
  });

  final TextEditingController search;
  final TextEditingController minSale;
  final TextEditingController maxSale;
  final String typeFilter;
  final String statusFilter;
  final bool lowStockOnly;
  final bool withBatchOnly;
  final bool advancedOpen;
  final VoidCallback onChanged;
  final VoidCallback onToggleAdvanced;
  final ValueChanged<String?> onTypeChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<bool> onLowStockChanged;
  final ValueChanged<bool> onBatchChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Buscar no estoque',
                    hintText:
                        'Nome, código, EAN, marca, categoria, NCM, lote, fornecedor...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onToggleAdvanced,
                icon: Icon(
                  advancedOpen
                      ? Icons.tune_outlined
                      : Icons.manage_search_outlined,
                ),
                label: Text(
                  advancedOpen ? 'Ocultar filtros' : 'Busca avancada',
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Limpar busca',
                onPressed: onClear,
                icon: const Icon(Icons.clear),
              ),
            ],
          ),
          if (advancedOpen) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 980
                    ? (constraints.maxWidth - 36) / 4
                    : constraints.maxWidth >= 640
                    ? (constraints.maxWidth - 12) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        initialValue: typeFilter,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos os tipos'),
                          ),
                          for (final entry in _productTypes.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: onTypeChanged,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        initialValue: statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(
                            value: 'ativos',
                            child: Text('Ativos'),
                          ),
                          DropdownMenuItem(
                            value: 'inativos',
                            child: Text('Inativos'),
                          ),
                        ],
                        onChanged: onStatusChanged,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: minSale,
                        onChanged: (_) => onChanged(),
                        inputFormatters: const [BrazilianMoneyInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Venda minima',
                          prefixText: 'R\$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: TextField(
                        controller: maxSale,
                        onChanged: (_) => onChanged(),
                        inputFormatters: const [BrazilianMoneyInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Venda maxima',
                          prefixText: 'R\$ ',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    FilterChip(
                      selected: lowStockOnly,
                      onSelected: onLowStockChanged,
                      avatar: const Icon(Icons.warning_amber_outlined),
                      label: const Text('Somente estoque baixo'),
                    ),
                    FilterChip(
                      selected: withBatchOnly,
                      onSelected: onBatchChanged,
                      avatar: const Icon(Icons.event_outlined),
                      label: const Text('Com lote/validade'),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ProductsTable extends StatelessWidget {
  const _ProductsTable({
    required this.products,
    required this.apiBaseUrl,
    required this.canEdit,
    required this.canViewBatches,
    required this.onOpen,
    required this.onBatches,
    required this.onHistory,
    required this.onComposition,
  });

  final List<Product> products;
  final String apiBaseUrl;
  final bool canEdit;
  final bool canViewBatches;
  final ValueChanged<Product> onOpen;
  final ValueChanged<Product> onBatches;
  final ValueChanged<Product> onHistory;
  final ValueChanged<Product> onComposition;

  @override
  Widget build(BuildContext context) {
    return Column(
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
              Expanded(flex: 3, child: _HeaderCell('Produto')),
              SizedBox(width: 110, child: _HeaderCell('Tipo')),
              SizedBox(width: 110, child: _HeaderCell('Estoque')),
              SizedBox(width: 150, child: _HeaderCell('Validade/Lote')),
              SizedBox(width: 120, child: _HeaderCell('Venda')),
              SizedBox(width: 110, child: _HeaderCell('NCM')),
              SizedBox(width: 120, child: _HeaderCell('IBS/CBS')),
              SizedBox(width: 148, child: _HeaderCell('Acoes')),
            ],
          ),
        ),
        for (final product in products)
          InkWell(
            onTap: canEdit ? () => onOpen(product) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 74),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Row(
                      children: [
                        _ProductThumb(
                          imageUrl: product.imageUrl,
                          apiBaseUrl: apiBaseUrl,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _TwoLine(
                            primary: product.name,
                            secondary: [
                              product.internalCode,
                              product.barcode,
                              product.category,
                              product.purchaseConversionEnabled &&
                                      (product.purchasePackageFactor ?? 0) > 0
                                  ? 'Compra: 1 ${product.purchaseInvoiceUnit ?? 'pc'} = ${_number(product.purchasePackageFactor!)} ${product.unit}'
                                  : null,
                              product.purchasePackageBarcode == null
                                  ? null
                                  : 'Cod. pacote ${product.purchasePackageBarcode}',
                              'Fiscal: disp. ${_number(product.fiscalAvailableQuantity)} ${product.unit} em ${product.fiscalEntryCount} nota(s)',
                            ].whereType<String>().where((item) => item.isNotEmpty).join(' | '),
                          ),
                        ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      _productTypes[product.productType] ?? product.productType,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: Text(
                      '${_number(product.stockQuantity)} ${product.unit}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: product.stockQuantity <= product.minimumStock
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFF0F172A),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 150,
                    child: _TwoLine(
                      primary: product.nearestExpirationDate ?? '-',
                      secondary: [
                        product.nearestBatchNumber == null
                            ? null
                            : 'Lote ${product.nearestBatchNumber}',
                        product.lastReceiptInvoiceNumber == null
                            ? null
                            : 'NF ${product.lastReceiptInvoiceNumber}',
                      ].whereType<String>().join(' | '),
                    ),
                  ),
                  SizedBox(width: 120, child: Text(_money(product.salePrice))),
                  SizedBox(width: 110, child: Text(product.ncm ?? '-')),
                  SizedBox(
                    width: 120,
                    child: Text(
                      product.newTaxSystem ? 'Preparado' : 'Pendente',
                    ),
                  ),
                  SizedBox(
                    width: 148,
                    child: Row(
                      children: [
                        IconButton(
                          tooltip: 'Ficha técnica / composição',
                          onPressed: () => onComposition(product),
                          icon: const Icon(Icons.account_tree_outlined),
                        ),
                        if (canViewBatches)
                          IconButton(
                            tooltip: 'Saldos por lote',
                            onPressed: () => onBatches(product),
                            icon: const Icon(Icons.inventory_outlined),
                          ),
                        IconButton(
                          tooltip: 'Histórico do estoque',
                          onPressed: () => onHistory(product),
                          icon: const Icon(Icons.history_outlined),
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

class _ProductThumb extends StatelessWidget {
  const _ProductThumb({required this.imageUrl, required this.apiBaseUrl});

  final String? imageUrl;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final url = _publicUrl(apiBaseUrl, imageUrl);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 44,
        height: 44,
        color: const Color(0xFFEFF6FF),
        child: url == null
            ? const Icon(
                Icons.image_outlined,
                size: 21,
                color: Color(0xFF64748B),
              )
            : Image.network(
                url,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => const Icon(
                  Icons.broken_image_outlined,
                  color: Color(0xFF64748B),
                ),
              ),
      ),
    );
  }
}

class _ImagePickerPanel extends StatelessWidget {
  const _ImagePickerPanel({
    required this.title,
    required this.imageUrl,
    required this.apiBaseUrl,
    required this.onPick,
    required this.onClear,
    this.uploading = false,
  });

  final String title;
  final String imageUrl;
  final String apiBaseUrl;
  final VoidCallback? onPick;
  final VoidCallback? onClear;
  final bool uploading;

  @override
  Widget build(BuildContext context) {
    final url = _publicUrl(apiBaseUrl, imageUrl);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Container(
                width: 92,
                height: 92,
                color: Colors.white,
                child: url == null
                    ? const Icon(
                        Icons.add_photo_alternate_outlined,
                        size: 34,
                        color: Color(0xFF64748B),
                      )
                    : Image.network(
                        url,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.broken_image_outlined,
                              color: Color(0xFF64748B),
                            ),
                      ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    uploading
                        ? 'Enviando foto...'
                        : url == null
                        ? 'Imagem opcional para aparecer no estoque e nas vitrines.'
                        : imageUrl,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  if (uploading) ...[
                    const SizedBox(height: 8),
                    const LinearProgressIndicator(minHeight: 4),
                  ],
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: uploading ? null : onPick,
                        icon: const Icon(Icons.upload_file_outlined),
                        label: Text(
                          uploading ? 'Enviando...' : 'Selecionar foto',
                        ),
                      ),
                      if (url != null)
                        TextButton.icon(
                          onPressed: onClear,
                          icon: const Icon(Icons.close),
                          label: const Text('Remover'),
                        ),
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

class _ProductBatchesDialog extends StatefulWidget {
  const _ProductBatchesDialog({
    required this.api,
    required this.token,
    required this.product,
  });

  final ApiClient api;
  final String token;
  final Product product;

  @override
  State<_ProductBatchesDialog> createState() => _ProductBatchesDialogState();
}

class _ProductBatchesDialogState extends State<_ProductBatchesDialog> {
  List<ProductBatch> _batches = [];
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
      final batches = await widget.api.listProductBatches(
        widget.token,
        widget.product.id,
      );
      setState(() => _batches = batches);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar os lotes.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Saldos por lote',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.product.name,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Atualizar',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                ErrorPanel(message: _error!, onRetry: _load)
              else if (_batches.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Nenhum lote com saldo registrado.'),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 160, child: _HeaderCell('Lote')),
                              SizedBox(
                                width: 120,
                                child: _HeaderCell('Validade'),
                              ),
                              SizedBox(width: 120, child: _HeaderCell('Saldo')),
                              Expanded(child: _HeaderCell('Origem')),
                              SizedBox(
                                width: 150,
                                child: _HeaderCell('Fornecedor'),
                              ),
                              SizedBox(width: 110, child: _HeaderCell('NF')),
                            ],
                          ),
                        ),
                        for (final batch in _batches)
                          Container(
                            constraints: const BoxConstraints(minHeight: 58),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: const BoxDecoration(
                              border: Border(
                                bottom: BorderSide(color: Color(0xFFE2E8F0)),
                              ),
                            ),
                            child: Row(
                              children: [
                                SizedBox(
                                  width: 160,
                                  child: Text(batch.batchNumber ?? '-'),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: Text(
                                    _formatDate(batch.expirationDate),
                                  ),
                                ),
                                SizedBox(
                                  width: 120,
                                  child: Text(
                                    '${_number(batch.quantity)} ${batch.unit}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                                Expanded(child: Text(_batchSource(batch))),
                                SizedBox(
                                  width: 150,
                                  child: Text(batch.supplierName ?? '-'),
                                ),
                                SizedBox(
                                  width: 110,
                                  child: Text(batch.invoiceNumber ?? '-'),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _batchSource(ProductBatch batch) {
    final type = switch (batch.sourceType) {
      'stock_entry' => 'Entrada',
      'production' => 'Produção',
      'product_initial' => 'Saldo inicial',
      'pdv' => 'PDV',
      'venda' => 'Venda',
      'stock_withdrawal' => 'Baixa de estoque',
      'service_contract' => 'Contrato',
      _ => 'Movimentação de estoque',
    };
    return batch.sourceNumber == null ? type : '$type ${batch.sourceNumber}';
  }
}

class _StockHistoryDialog extends StatefulWidget {
  const _StockHistoryDialog({
    required this.api,
    required this.token,
    required this.product,
  });

  final ApiClient api;
  final String token;
  final Product product;

  @override
  State<_StockHistoryDialog> createState() => _StockHistoryDialogState();
}

class _StockHistoryDialogState extends State<_StockHistoryDialog> {
  List<StockMovement> _movements = [];
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
      final movements = await widget.api.listProductStockMovements(
        widget.token,
        widget.product.id,
      );
      setState(() => _movements = movements);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar o histórico.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 680),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Histórico do estoque',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.product.name,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Atualizar',
                    onPressed: _load,
                    icon: const Icon(Icons.refresh),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                ErrorPanel(message: _error!, onRetry: _load)
              else if (_movements.isEmpty)
                const Expanded(
                  child: Center(
                    child: Text('Nenhuma movimentacao registrada ainda.'),
                  ),
                )
              else
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        Container(
                          height: 46,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: const BoxDecoration(
                            color: Color(0xFFF8FAFC),
                            border: Border(
                              bottom: BorderSide(color: Color(0xFFE2E8F0)),
                            ),
                          ),
                          child: const Row(
                            children: [
                              SizedBox(width: 132, child: _HeaderCell('Data')),
                              SizedBox(
                                width: 150,
                                child: _HeaderCell('Origem'),
                              ),
                              Expanded(child: _HeaderCell('Motivo')),
                              SizedBox(width: 104, child: _HeaderCell('Mov.')),
                              SizedBox(width: 104, child: _HeaderCell('Antes')),
                              SizedBox(
                                width: 104,
                                child: _HeaderCell('Depois'),
                              ),
                              SizedBox(width: 110, child: _HeaderCell('Valor')),
                            ],
                          ),
                        ),
                        for (final movement in _movements)
                          _StockMovementRow(
                            movement: movement,
                            source: _movementSource(movement),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _movementSource(StockMovement movement) {
    final source = switch (movement.sourceType) {
      'pdv' => 'PDV',
      'venda' => 'Venda',
      'os' => 'OS',
      'stock_entry' => 'Entrada de estoque',
      'stock_withdrawal' => 'Baixa de estoque',
      'production' => 'Produção',
      'product_initial' => 'Saldo inicial',
      'service_contract' => 'Contrato',
      _ => 'Movimentação de estoque',
    };
    final number = movement.sourceNumber;
    return number == null || number.isEmpty ? source : '$source $number';
  }
}

class _CompositionDialog extends StatefulWidget {
  const _CompositionDialog({
    required this.api,
    required this.token,
    required this.product,
    required this.products,
  });

  final ApiClient api;
  final String token;
  final Product product;
  final List<Product> products;

  @override
  State<_CompositionDialog> createState() => _CompositionDialogState();
}

class _StockMovementRow extends StatelessWidget {
  const _StockMovementRow({required this.movement, required this.source});

  final StockMovement movement;
  final String source;

  bool get _hasReceiptInfo {
    return movement.supplierName != null ||
        movement.invoiceNumber != null ||
        movement.batchNumber != null ||
        movement.expirationDate != null ||
        movement.receivedQuantity != null;
  }

  @override
  Widget build(BuildContext context) {
    final details = <String>[
      if (movement.supplierName != null) 'Fornecedor: ${movement.supplierName}',
      if (movement.supplierDocument != null)
        'Doc: ${movement.supplierDocument}',
      if (movement.invoiceNumber != null)
        'NF: ${movement.invoiceNumber}${movement.invoiceSeries == null ? '' : ' / serie ${movement.invoiceSeries}'}',
      if (movement.batchNumber != null) 'Lote: ${movement.batchNumber}',
      if (movement.expirationDate != null)
        'Validade: ${movement.expirationDate}',
      if (movement.receivedQuantity != null)
        'Recebido: ${_number(movement.receivedQuantity!)} ${movement.unit}',
      if (movement.checkNotes != null) 'Obs.: ${movement.checkNotes}',
    ];
    return Container(
      constraints: const BoxConstraints(minHeight: 58),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
      ),
      child: Column(
        children: [
          Row(
            children: [
              SizedBox(width: 132, child: Text(_dateTime(movement.createdAt))),
              SizedBox(width: 150, child: Text(source)),
              Expanded(
                child: Text(
                  movement.reason ?? movement.notes ?? '-',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 104,
                child: Text(
                  '${_signedNumber(movement.quantityDelta)} ${movement.unit}',
                  style: TextStyle(
                    color: movement.quantityDelta < 0
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF047857),
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(
                width: 104,
                child: Text(
                  '${_number(movement.quantityBefore)} ${movement.unit}',
                ),
              ),
              SizedBox(
                width: 104,
                child: Text(
                  '${_number(movement.quantityAfter)} ${movement.unit}',
                ),
              ),
              SizedBox(
                width: 110,
                child: Text(
                  movement.totalValue == null
                      ? '-'
                      : _money(movement.totalValue!),
                ),
              ),
            ],
          ),
          if (_hasReceiptInfo) ...[
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                details.join(' | '),
                style: const TextStyle(color: Color(0xFF475569)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CompositionDialogState extends State<_CompositionDialog> {
  final _quantity = TextEditingController(text: '1');
  final _wastePercent = TextEditingController(text: '0');
  final _notes = TextEditingController();
  final _componentSearch = TextEditingController();
  List<ProductCompositionItem> _items = [];
  int? _componentProductId;
  String _unit = 'un';
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Product> get _componentOptions {
    return widget.products
        .where((product) => product.id != widget.product.id && product.active)
        .toList();
  }

  Product? get _selectedComponent {
    final selectedId = _componentProductId;
    if (selectedId == null) return null;
    for (final product in _componentOptions) {
      if (product.id == selectedId) return product;
    }
    return null;
  }

  Map<String, String> get _componentUnitOptions {
    final stockUnit = _selectedComponent?.unit ?? 'un';
    final family = _unitFamilies[stockUnit];
    if (family == null) {
      return {stockUnit: _unitOptions[stockUnit] ?? stockUnit};
    }
    return {
      for (final entry in _unitOptions.entries)
        if (_unitFamilies[entry.key] == family) entry.key: entry.value,
    };
  }

  double get _estimatedCost {
    return _items.fold<double>(0, (sum, item) {
      final cost = item.componentCostPrice;
      if (cost == null) return sum;
      final convertedQuantity = _convertQuantity(
        item.quantity,
        item.unit,
        item.componentUnit,
      );
      if (convertedQuantity == null) return sum;
      final quantityWithLoss =
          convertedQuantity * (1 + (item.wastePercent / 100));
      return sum + (quantityWithLoss * cost);
    });
  }

  double? _componentTotalCost(ProductCompositionItem item) {
    final cost = item.componentCostPrice;
    if (cost == null) return null;
    final convertedQuantity = _convertQuantity(
      item.quantity,
      item.unit,
      item.componentUnit,
    );
    if (convertedQuantity == null) return null;
    return convertedQuantity * (1 + item.wastePercent / 100) * cost;
  }

  @override
  void initState() {
    super.initState();
    final options = _componentOptions;
    if (options.isNotEmpty) {
      _componentProductId = options.first.id;
      _unit = options.first.unit;
    }
    _load();
  }

  @override
  void dispose() {
    _quantity.dispose();
    _wastePercent.dispose();
    _notes.dispose();
    _componentSearch.dispose();
    super.dispose();
  }

  Future<void> _openComponentPicker() async {
    _componentSearch.clear();
    final selected = await showDialog<Product>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final query = _componentSearch.text.trim().toLowerCase();
          final products = _componentOptions
              .where((product) {
                if (query.isEmpty) return true;
                final haystack = [
                  product.name,
                  product.internalCode,
                  product.barcode,
                  _productTypes[product.productType],
                ].whereType<String>().join(' ').toLowerCase();
                return haystack.contains(query);
              })
              .toList(growable: false);

          return AlertDialog(
            title: const Text('Escolher componente'),
            content: SizedBox(
              width: 760,
              height: 520,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _componentSearch,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Pesquisar por nome, código ou tipo',
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
                                  '${product.internalCode ?? product.barcode ?? '-'} • ${_productTypes[product.productType] ?? product.productType} • Estoque ${formatBrazilianDecimal(product.stockQuantity)} ${product.unit}',
                                ),
                                trailing: FilledButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(product),
                                  child: const Text('Usar'),
                                ),
                                onTap: () => Navigator.of(context).pop(product),
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
    setState(() {
      _componentProductId = selected.id;
      _unit = selected.unit;
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await widget.api.listProductComposition(
        widget.token,
        widget.product.id,
      );
      setState(() => _items = items);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar a ficha técnica.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _addItem() async {
    final componentId = _componentProductId;
    if (componentId == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.createProductCompositionItem(
        widget.token,
        widget.product.id,
        ProductCompositionPayload(
          componentProductId: componentId,
          quantity: _moneyValue(_quantity.text),
          unit: _unit,
          wastePercent: _moneyValue(_wastePercent.text),
          notes: _notes.text,
        ),
      );
      _quantity.text = '1';
      _wastePercent.text = '0';
      _notes.clear();
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível adicionar o componente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _deleteItem(ProductCompositionItem item) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.deleteProductCompositionItem(
        widget.token,
        widget.product.id,
        item.id,
      );
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível remover o componente.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final options = _componentOptions;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Ficha técnica / composição',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.product.name,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      child: Text(
                        'Custo estimado: ${_money(_estimatedCost)}',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Section('Adicionar componente'),
                    if (options.isEmpty) ...[
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFFBEB),
                          border: Border.all(color: const Color(0xFFFDE68A)),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Cadastre produtos no estoque. Depois volte aqui para montar a ficha técnica deste produto.',
                          style: TextStyle(
                            color: Color(0xFF92400E),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final width = constraints.maxWidth >= 920
                            ? (constraints.maxWidth - 36) / 4
                            : constraints.maxWidth >= 620
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            SizedBox(
                              width: width * 2 + 12,
                              child: InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: options.isEmpty
                                    ? null
                                    : _openComponentPicker,
                                child: InputDecorator(
                                  decoration: const InputDecoration(
                                    labelText: 'Componente',
                                    border: OutlineInputBorder(),
                                    suffixIcon: Icon(Icons.search),
                                  ),
                                  child: Text(
                                    _selectedComponent == null
                                        ? 'Pesquisar produto'
                                        : '${_selectedComponent!.name} (${_productTypes[_selectedComponent!.productType] ?? _selectedComponent!.productType})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: TextFormField(
                                controller: _quantity,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  BrazilianDecimalInputFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Quantidade',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: DropdownButtonFormField<String>(
                                initialValue: _unit,
                                decoration: const InputDecoration(
                                  labelText: 'Unidade',
                                  border: OutlineInputBorder(),
                                ),
                                items: [
                                  for (final entry
                                      in _componentUnitOptions.entries)
                                    DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(
                                        '${entry.key} - ${entry.value}',
                                      ),
                                    ),
                                ],
                                onChanged: (value) =>
                                    setState(() => _unit = value ?? 'un'),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: TextFormField(
                                controller: _wastePercent,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  BrazilianDecimalInputFormatter(),
                                ],
                                decoration: const InputDecoration(
                                  labelText: 'Perda %',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width * 2 + 12,
                              child: TextFormField(
                                controller: _notes,
                                decoration: const InputDecoration(
                                  labelText: 'Observação',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ),
                            SizedBox(
                              width: width,
                              child: FilledButton.icon(
                                onPressed: _saving || options.isEmpty
                                    ? null
                                    : _addItem,
                                icon: const Icon(Icons.add),
                                label: const Text('Adicionar'),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                ErrorPanel(message: _error!, onRetry: _load)
              else
                Expanded(
                  child: AppCard(
                    padding: EdgeInsets.zero,
                    child: _items.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24),
                              child: Text(
                                'Nenhum componente na ficha técnica ainda.',
                              ),
                            ),
                          )
                        : SingleChildScrollView(
                            child: Column(
                              children: [
                                Container(
                                  height: 46,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF8FAFC),
                                    border: Border(
                                      bottom: BorderSide(
                                        color: Color(0xFFE2E8F0),
                                      ),
                                    ),
                                  ),
                                  child: const Row(
                                    children: [
                                      Expanded(
                                        child: _HeaderCell('Componente'),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: _HeaderCell('Quantidade'),
                                      ),
                                      SizedBox(
                                        width: 90,
                                        child: _HeaderCell('Perda'),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: _HeaderCell('Custo base'),
                                      ),
                                      SizedBox(
                                        width: 120,
                                        child: _HeaderCell('Custo total'),
                                      ),
                                      SizedBox(width: 52),
                                    ],
                                  ),
                                ),
                                for (final item in _items)
                                  Container(
                                    constraints: const BoxConstraints(
                                      minHeight: 62,
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 10,
                                    ),
                                    decoration: const BoxDecoration(
                                      border: Border(
                                        bottom: BorderSide(
                                          color: Color(0xFFE2E8F0),
                                        ),
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: _TwoLine(
                                            primary: item.componentName,
                                            secondary:
                                                [
                                                      item.componentInternalCode,
                                                      item.notes,
                                                    ]
                                                    .whereType<String>()
                                                    .where(
                                                      (value) => value
                                                          .trim()
                                                          .isNotEmpty,
                                                    )
                                                    .join(' | '),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            '${_number(item.quantity)} ${item.unit}',
                                          ),
                                        ),
                                        SizedBox(
                                          width: 90,
                                          child: Text(
                                            '${_number(item.wastePercent)}%',
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            item.componentCostPrice == null
                                                ? '-'
                                                : '${_money(item.componentCostPrice!)}/${item.componentUnit}',
                                          ),
                                        ),
                                        SizedBox(
                                          width: 120,
                                          child: Text(
                                            item.componentCostPrice == null
                                                ? '-'
                                                : _money(
                                                    _componentTotalCost(item) ??
                                                        0,
                                                  ),
                                          ),
                                        ),
                                        SizedBox(
                                          width: 52,
                                          child: IconButton(
                                            tooltip: 'Remover componente',
                                            onPressed: _saving
                                                ? null
                                                : () => _deleteItem(item),
                                            icon: const Icon(
                                              Icons.delete_outline,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FiscalStockInfo extends StatelessWidget {
  const _FiscalStockInfo({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 3),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductDialog extends StatefulWidget {
  const _ProductDialog({required this.api, required this.token, this.product});

  final ApiClient api;
  final String token;
  final Product? product;

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _internalCode = TextEditingController();
  final _barcode = TextEditingController();
  final _imageUrl = TextEditingController();
  final _description = TextEditingController();
  final _brand = TextEditingController();
  final _model = TextEditingController();
  final _category = TextEditingController();
  final _stockLocation = TextEditingController();
  final _initialBatchNumber = TextEditingController();
  final _initialExpirationDate = TextEditingController();
  final _salePrice = TextEditingController(text: '0,00');
  final _offerPrice = TextEditingController();
  final _offerStartAt = TextEditingController();
  final _offerEndAt = TextEditingController();
  final _purchaseTotalCost = TextEditingController();
  final _purchaseQuantity = TextEditingController();
  final _lastPurchaseUnitCost = TextEditingController();
  final _averageCost = TextEditingController();
  final _purchasePackageFactor = TextEditingController(text: '1');
  final _purchasePackageBarcode = TextEditingController();
  final _marginPercent = TextEditingController();
  final _stockQuantity = TextEditingController(text: '0');
  final _minimumStock = TextEditingController(text: '0');
  final _unit = TextEditingController(text: 'un');
  final _ncm = TextEditingController();
  final _cest = TextEditingController();
  final _cfopSale = TextEditingController();
  final _origin = TextEditingController();
  final _cst = TextEditingController();
  final _csosn = TextEditingController();
  final _icmsRate = TextEditingController();
  final _pisRate = TextEditingController();
  final _cofinsRate = TextEditingController();
  final _ipiRate = TextEditingController();
  final _issRate = TextEditingController();
  final _municipalServiceCode = TextEditingController();
  final _taxRate = TextEditingController();
  final _fiscalNotes = TextEditingController();
  final _ibsCbsCst = TextEditingController();
  final _ibsCbsClassification = TextEditingController();
  final _cbsRate = TextEditingController();
  final _ibsStateRate = TextEditingController();
  final _ibsCityRate = TextEditingController();
  final _selectiveTaxCst = TextEditingController();
  final _selectiveTaxClassification = TextEditingController();
  final _selectiveTaxRate = TextEditingController();
  final _oldTaxSystemNotes = TextEditingController();
  final _newTaxSystemNotes = TextEditingController();
  final _costFocus = FocusNode();
  final _unitCostFocus = FocusNode();
  final _averageCostFocus = FocusNode();
  final _saleFocus = FocusNode();
  final _marginFocus = FocusNode();
  String _productType = 'produto';
  String _selectedUnit = 'un';
  String _purchaseInvoiceUnit = 'pc';
  bool _active = true;
  bool _tracksBatch = false;
  bool _purchaseConversionEnabled = false;
  bool _newTaxSystem = false;
  bool _saving = false;
  bool _uploadingImage = false;
  bool _syncingPrices = false;
  bool _manualCostEditEnabled = false;
  bool _loadingFiscalAssistant = false;
  FiscalAssistantResponse? _fiscalAssistant;
  String? _error;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    _manualCostEditEnabled = product == null;
    if (product != null) {
      _name.text = product.name;
      _productType = product.productType;
      _internalCode.text = product.internalCode ?? '';
      _barcode.text = product.barcode ?? '';
      _imageUrl.text = product.imageUrl ?? '';
      _description.text = product.description ?? '';
      _brand.text = product.brand ?? '';
      _model.text = product.model ?? '';
      _category.text = product.category ?? '';
      _stockLocation.text = product.stockLocation ?? '';
      _tracksBatch = product.tracksBatch;
      _initialBatchNumber.text = product.initialBatchNumber ?? '';
      _initialExpirationDate.text = product.initialExpirationDate ?? '';
      _salePrice.text = _unitPriceInputValue(product.salePrice);
      _offerPrice.text = product.offerPrice == null
          ? ''
          : _unitPriceInputValue(product.offerPrice!);
      _offerStartAt.text = product.offerStartAt == null
          ? ''
          : _dateTimeInputValue(product.offerStartAt!);
      _offerEndAt.text = product.offerEndAt == null
          ? ''
          : _dateTimeInputValue(product.offerEndAt!);
      _purchaseTotalCost.text = product.purchaseTotalCost == null
          ? ''
          : _moneyInputValue(product.purchaseTotalCost!);
      _purchaseQuantity.text = _numberOrEmpty(product.purchaseQuantity);
      _averageCost.text = product.averageCost == null
          ? ''
          : _moneyInputValue(product.averageCost!);
      _purchaseConversionEnabled = product.purchaseConversionEnabled;
      _purchaseInvoiceUnit =
          _unitOptions.containsKey(product.purchaseInvoiceUnit)
          ? product.purchaseInvoiceUnit!
          : 'pc';
      _purchasePackageFactor.text =
          _numberOrEmpty(product.purchasePackageFactor).isEmpty
          ? '1'
          : _numberOrEmpty(product.purchasePackageFactor);
      _purchasePackageBarcode.text = product.purchasePackageBarcode ?? '';
      _marginPercent.text = _numberOrEmpty(product.marginPercent);
      _stockQuantity.text = _number(product.stockQuantity);
      _minimumStock.text = _number(product.minimumStock);
      _selectedUnit = _unitOptions.containsKey(product.unit)
          ? product.unit
          : 'un';
      _unit.text = _selectedUnit;
      _ncm.text = product.ncm ?? '';
      _cest.text = product.cest ?? '';
      _cfopSale.text = product.cfopSale ?? '';
      _origin.text = product.origin ?? '';
      _cst.text = product.cst ?? '';
      _csosn.text = product.csosn ?? '';
      _icmsRate.text = _numberOrEmpty(product.icmsRate);
      _pisRate.text = _numberOrEmpty(product.pisRate);
      _cofinsRate.text = _numberOrEmpty(product.cofinsRate);
      _ipiRate.text = _numberOrEmpty(product.ipiRate);
      _issRate.text = _numberOrEmpty(product.issRate);
      _municipalServiceCode.text = product.municipalServiceCode ?? '';
      _taxRate.text = _numberOrEmpty(product.taxRate);
      _fiscalNotes.text = product.fiscalNotes ?? '';
      _ibsCbsCst.text = product.ibsCbsCst ?? '';
      _ibsCbsClassification.text = product.ibsCbsClassification ?? '';
      _cbsRate.text = _numberOrEmpty(product.cbsRate);
      _ibsStateRate.text = _numberOrEmpty(product.ibsStateRate);
      _ibsCityRate.text = _numberOrEmpty(product.ibsCityRate);
      _selectiveTaxCst.text = product.selectiveTaxCst ?? '';
      _selectiveTaxClassification.text =
          product.selectiveTaxClassification ?? '';
      _selectiveTaxRate.text = _numberOrEmpty(product.selectiveTaxRate);
      _newTaxSystem = product.newTaxSystem;
      _oldTaxSystemNotes.text = product.oldTaxSystemNotes ?? '';
      _newTaxSystemNotes.text = product.newTaxSystemNotes ?? '';
      _active = product.active;
    }
    _purchaseTotalCost.addListener(_syncPriceFields);
    _purchaseQuantity.addListener(_syncPriceFields);
    _salePrice.addListener(_syncPriceFields);
    _marginPercent.addListener(_syncPriceFields);
    _syncPriceFields();
    for (final focus in [_costFocus, _saleFocus, _marginFocus]) {
      focus.addListener(_formatMoneyFieldsOnBlur);
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _internalCode,
      _barcode,
      _imageUrl,
      _description,
      _brand,
      _model,
      _category,
      _stockLocation,
      _initialBatchNumber,
      _initialExpirationDate,
      _salePrice,
      _offerPrice,
      _offerStartAt,
      _offerEndAt,
      _purchaseTotalCost,
      _purchaseQuantity,
      _lastPurchaseUnitCost,
      _averageCost,
      _purchasePackageFactor,
      _purchasePackageBarcode,
      _marginPercent,
      _stockQuantity,
      _minimumStock,
      _unit,
      _ncm,
      _cest,
      _cfopSale,
      _origin,
      _cst,
      _csosn,
      _icmsRate,
      _pisRate,
      _cofinsRate,
      _ipiRate,
      _issRate,
      _municipalServiceCode,
      _taxRate,
      _fiscalNotes,
      _ibsCbsCst,
      _ibsCbsClassification,
      _cbsRate,
      _ibsStateRate,
      _ibsCityRate,
      _selectiveTaxCst,
      _selectiveTaxClassification,
      _selectiveTaxRate,
      _oldTaxSystemNotes,
      _newTaxSystemNotes,
    ]) {
      controller.dispose();
    }
    _costFocus.dispose();
    _unitCostFocus.dispose();
    _averageCostFocus.dispose();
    _saleFocus.dispose();
    _marginFocus.dispose();
    super.dispose();
  }

  void _syncPriceFields() {
    if (_syncingPrices) return;
    final purchaseTotal = _moneyValue(_purchaseTotalCost.text);
    final purchaseQuantity = _decimalValue(_purchaseQuantity.text);
    final unitCost = purchaseQuantity > 0
        ? purchaseTotal / purchaseQuantity
        : purchaseTotal;
    _syncingPrices = true;
    if (!_unitCostFocus.hasFocus) {
      _lastPurchaseUnitCost.text = unitCost > 0
          ? _moneyInputValue(unitCost)
          : '';
    }
    if (_manualCostEditEnabled && !_averageCostFocus.hasFocus) {
      _averageCost.text = unitCost > 0 ? _moneyInputValue(unitCost) : '';
    }
    if (unitCost <= 0) {
      _syncingPrices = false;
      return;
    }
    if (_saleFocus.hasFocus) {
      final sale = _moneyValue(_salePrice.text);
      if (sale > 0) {
        _marginPercent.text = _number(((sale - unitCost) / unitCost) * 100);
      }
    } else if (_marginFocus.hasFocus || _costFocus.hasFocus) {
      final margin = _decimalValue(_marginPercent.text);
      _salePrice.text = _moneyInputValue(unitCost * (1 + (margin / 100)));
    }
    _syncingPrices = false;
  }

  Future<void> _confirmManualCostEdit() async {
    if (_manualCostEditEnabled || widget.product == null) {
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Corrigir custo manualmente?'),
        content: const Text(
          'Normalmente o custo total, quantidade, custo unitario e custo medio vem das entradas/notas fiscais. '
          'Use esta liberacao somente para corrigir cadastro ou entrada feita errada. Deseja liberar a edicao agora?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Nao'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sim, corrigir'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _manualCostEditEnabled = true;
      _syncPriceFields();
    });
    _costFocus.requestFocus();
  }

  void _formatMoneyFieldsOnBlur() {
    if (_costFocus.hasFocus || _saleFocus.hasFocus || _marginFocus.hasFocus) {
      return;
    }
    _formatControllerNumber(_purchaseTotalCost, money: true);
    _formatControllerNumber(_salePrice, unitPrice: true);
    _formatControllerNumber(_marginPercent);
  }

  void _formatControllerNumber(
    TextEditingController controller, {
    bool money = false,
    bool unitPrice = false,
  }) {
    if (controller.text.trim().isEmpty) return;
    controller.text = unitPrice
        ? _unitPriceInputValue(_moneyValue(controller.text))
        : money
        ? _moneyInputValue(_moneyValue(controller.text))
        : _number(_decimalValue(controller.text));
  }

  Future<void> _pickProductImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'webp', 'gif'],
        withData: true,
      );
      final file = result?.files.single;
      final bytes = file?.bytes;
      if (file == null || bytes == null) return;
      setState(() {
        _uploadingImage = true;
        _error = null;
      });
      final url = await widget.api.uploadImage(
        widget.token,
        bytes: bytes,
        filename: file.name,
      );
      setState(() => _imageUrl.text = url);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível enviar a imagem.');
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  String _generateInternalCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final random = Random();
    final suffix = List.generate(
      6,
      (_) => chars[random.nextInt(chars.length)],
    ).join();
    final prefix = switch (_productType) {
      'servico' => 'SER',
      'peca' => 'PEC',
      'materia_prima' => 'MAT',
      'embalagem' => 'EMB',
      'insumo' => 'INS',
      'mercadoria' => 'MER',
      'produto_acabado' => 'PRA',
      _ => 'PRD',
    };
    return '$prefix-$suffix';
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final offerPrice = _nullableMoney(_offerPrice.text);
    final offerStartAt = _nullableDateTime(_offerStartAt.text);
    final offerEndAt = _nullableDateTime(_offerEndAt.text);
    final hasAnyOfferField =
        offerPrice != null ||
        _offerStartAt.text.trim().isNotEmpty ||
        _offerEndAt.text.trim().isNotEmpty;
    if (hasAnyOfferField &&
        (offerPrice == null || offerStartAt == null || offerEndAt == null)) {
      setState(
        () => _error =
            'Para oferta, informe preco, inicio e fim com data e hora.',
      );
      return;
    }
    if (offerStartAt != null &&
        offerEndAt != null &&
        !offerEndAt.isAfter(offerStartAt)) {
      setState(() => _error = 'Fim da oferta precisa ser depois do inicio.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    if (_internalCode.text.trim().isEmpty) {
      _internalCode.text = _generateInternalCode();
    }
    final purchaseQuantity = _nullableDecimal(_purchaseQuantity.text);
    final manualUnitCost = _nullableMoney(_lastPurchaseUnitCost.text);
    final purchaseTotalCost =
        _manualCostEditEnabled &&
            manualUnitCost != null &&
            purchaseQuantity != null
        ? manualUnitCost * purchaseQuantity
        : _nullableMoney(_purchaseTotalCost.text);
    final payload = ProductPayload(
      name: _name.text,
      productType: _productType,
      internalCode: _internalCode.text,
      barcode: _barcode.text,
      imageUrl: _imageUrl.text,
      description: _description.text,
      brand: _brand.text,
      model: _model.text,
      category: _category.text,
      stockLocation: _stockLocation.text,
      tracksBatch: _tracksBatch,
      initialBatchNumber: _initialBatchNumber.text,
      initialExpirationDate: _initialExpirationDate.text,
      salePrice: _moneyValue(_salePrice.text),
      offerPrice: offerPrice,
      offerStartAt: offerStartAt,
      offerEndAt: offerEndAt,
      purchaseTotalCost: purchaseTotalCost,
      purchaseQuantity: purchaseQuantity,
      averageCost: _nullableMoney(_averageCost.text),
      purchaseConversionEnabled: _purchaseConversionEnabled,
      purchaseInvoiceUnit: _purchaseConversionEnabled
          ? _purchaseInvoiceUnit
          : null,
      purchasePackageFactor: _purchaseConversionEnabled
          ? _nullableDecimal(_purchasePackageFactor.text)
          : null,
      purchasePackageBarcode: _purchaseConversionEnabled
          ? _purchasePackageBarcode.text
          : null,
      marginPercent: _nullableDecimal(_marginPercent.text),
      stockQuantity: _moneyValue(_stockQuantity.text),
      minimumStock: _moneyValue(_minimumStock.text),
      unit: _selectedUnit,
      ncm: _ncm.text,
      cest: _cest.text,
      cfopSale: _cfopSale.text,
      origin: _origin.text,
      cst: _cst.text,
      csosn: _csosn.text,
      icmsRate: _nullableMoney(_icmsRate.text),
      pisRate: _nullableMoney(_pisRate.text),
      cofinsRate: _nullableMoney(_cofinsRate.text),
      ipiRate: _nullableMoney(_ipiRate.text),
      issRate: _nullableMoney(_issRate.text),
      municipalServiceCode: _municipalServiceCode.text,
      taxRate: _nullableMoney(_taxRate.text),
      fiscalNotes: _fiscalNotes.text,
      ibsCbsCst: _ibsCbsCst.text,
      ibsCbsClassification: _ibsCbsClassification.text,
      cbsRate: _nullableMoney(_cbsRate.text),
      ibsStateRate: _nullableMoney(_ibsStateRate.text),
      ibsCityRate: _nullableMoney(_ibsCityRate.text),
      selectiveTaxCst: _selectiveTaxCst.text,
      selectiveTaxClassification: _selectiveTaxClassification.text,
      selectiveTaxRate: _nullableMoney(_selectiveTaxRate.text),
      newTaxSystem: _newTaxSystem,
      oldTaxSystemNotes: _oldTaxSystemNotes.text,
      newTaxSystemNotes: _newTaxSystemNotes.text,
      active: _active,
    );
    try {
      final product = widget.product;
      if (product == null) {
        await widget.api.createProduct(widget.token, payload);
      } else {
        await widget.api.updateProduct(widget.token, product.id, payload);
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o item.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadFiscalAssistant() async {
    setState(() {
      _loadingFiscalAssistant = true;
      _error = null;
    });
    try {
      final response = await widget.api.getFiscalAssistantProductSuggestions(
        widget.token,
        productId: widget.product?.id,
        description: _name.text,
        barcode: _barcode.text,
      );
      if (mounted) setState(() => _fiscalAssistant = response);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(
        () => _error = 'Nao foi possivel consultar o assistente fiscal.',
      );
    } finally {
      if (mounted) setState(() => _loadingFiscalAssistant = false);
    }
  }

  void _applyFiscalSuggestion(FiscalSuggestion suggestion) {
    setState(() {
      _ncm.text = suggestion.ncm ?? _ncm.text;
      _cest.text = suggestion.cest ?? _cest.text;
      _cfopSale.text = suggestion.cfop ?? _cfopSale.text;
      _origin.text = suggestion.origin ?? _origin.text;
      _cst.text = suggestion.cst ?? _cst.text;
      _csosn.text = suggestion.csosn ?? _csosn.text;
      _icmsRate.text = suggestion.icmsRate == null
          ? _icmsRate.text
          : _number(suggestion.icmsRate!);
      _pisRate.text = suggestion.pisRate == null
          ? _pisRate.text
          : _number(suggestion.pisRate!);
      _cofinsRate.text = suggestion.cofinsRate == null
          ? _cofinsRate.text
          : _number(suggestion.cofinsRate!);
      _ipiRate.text = suggestion.ipiRate == null
          ? _ipiRate.text
          : _number(suggestion.ipiRate!);
      _ibsCbsCst.text = suggestion.ibsCbsCst ?? _ibsCbsCst.text;
      _ibsCbsClassification.text =
          suggestion.ibsCbsClassification ?? _ibsCbsClassification.text;
      _cbsRate.text = suggestion.cbsRate == null
          ? _cbsRate.text
          : _number(suggestion.cbsRate!);
      _ibsStateRate.text = suggestion.ibsStateRate == null
          ? _ibsStateRate.text
          : _number(suggestion.ibsStateRate!);
      _ibsCityRate.text = suggestion.ibsCityRate == null
          ? _ibsCityRate.text
          : _number(suggestion.ibsCityRate!);
      _selectiveTaxCst.text =
          suggestion.selectiveTaxCst ?? _selectiveTaxCst.text;
      _selectiveTaxClassification.text =
          suggestion.selectiveTaxClassification ??
          _selectiveTaxClassification.text;
      _selectiveTaxRate.text = suggestion.selectiveTaxRate == null
          ? _selectiveTaxRate.text
          : _number(suggestion.selectiveTaxRate!);
      if ((suggestion.ibsCbsCst ?? suggestion.selectiveTaxCst) != null) {
        _newTaxSystem = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1080, maxHeight: 780),
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
                          widget.product == null ? 'Novo item' : 'Editar item',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      Switch(
                        value: _active,
                        onChanged: (value) => setState(() => _active = value),
                      ),
                      const Text('Ativo'),
                      const SizedBox(width: 8),
                      IconButton.outlined(
                        onPressed: () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _Section('Dados principais'),
                  _Fields(
                    children: [
                      _field(_name, 'Nome', required: true),
                      DropdownButtonFormField<String>(
                        initialValue: _productType,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final entry in _productTypes.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: (value) =>
                            setState(() => _productType = value ?? 'produto'),
                      ),
                      _field(_internalCode, 'Código interno'),
                      _field(_barcode, 'Código da unidade / EAN de venda'),
                      _field(_brand, 'Marca'),
                      _field(_model, 'Modelo'),
                      _field(_category, 'Categoria'),
                      _field(_stockLocation, 'Localizacao no estoque'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _ImagePickerPanel(
                    title: 'Foto do produto',
                    imageUrl: _imageUrl.text,
                    apiBaseUrl: widget.api.baseUrl,
                    uploading: _uploadingImage,
                    onPick: _saving || _uploadingImage
                        ? null
                        : _pickProductImage,
                    onClear: _saving
                        ? null
                        : () => setState(() => _imageUrl.clear()),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  _area(_description, 'Descricao'),
                  const SizedBox(height: 16),
                  _Section('Estoque e preços'),
                  _Fields(
                    children: [
                      _unitDropdown(),
                      _field(_stockQuantity, 'Estoque atual', number: true),
                      _field(_minimumStock, 'Estoque minimo', number: true),
                      _field(
                        _purchaseTotalCost,
                        'Valor total da última compra',
                        number: true,
                        money: true,
                        focusNode: _costFocus,
                        readOnly: !_manualCostEditEnabled,
                        helperText: _manualCostEditEnabled
                            ? 'Correcao manual liberada. As proximas entradas voltam a atualizar este valor.'
                            : 'Vem da nota/entrada. Clique para liberar correcao manual.',
                        onTap: _manualCostEditEnabled
                            ? null
                            : _confirmManualCostEdit,
                      ),
                      _field(
                        _purchaseQuantity,
                        'Quantidade recebida na última compra',
                        number: true,
                        readOnly: !_manualCostEditEnabled,
                        helperText: _manualCostEditEnabled
                            ? 'Informe a quantidade correta que entrou no estoque.'
                            : 'Vem da nota/entrada. Clique para liberar correcao manual.',
                        onTap: _manualCostEditEnabled
                            ? null
                            : _confirmManualCostEdit,
                      ),
                      _readOnlyField(
                        _lastPurchaseUnitCost,
                        'Custo unitário da última compra',
                        helperText: _manualCostEditEnabled
                            ? 'Correcao manual liberada. Ajuste total/quantidade se precisar alterar o unitario.'
                            : 'Calculado pela nota/entrada. Clique para liberar correcao manual.',
                        locked: !_manualCostEditEnabled,
                        focusNode: _unitCostFocus,
                        onTap: _manualCostEditEnabled
                            ? null
                            : _confirmManualCostEdit,
                      ),
                      _readOnlyField(
                        _averageCost,
                        'Custo médio atual',
                        helperText: _manualCostEditEnabled
                            ? 'Correcao manual liberada. Proximas entradas recalculam a media normalmente.'
                            : 'Media ponderada das entradas. Clique para liberar correcao manual.',
                        locked: !_manualCostEditEnabled,
                        focusNode: _averageCostFocus,
                        onTap: _manualCostEditEnabled
                            ? null
                            : _confirmManualCostEdit,
                      ),
                      _field(
                        _salePrice,
                        'Venda',
                        number: true,
                        unitPrice: true,
                        focusNode: _saleFocus,
                      ),
                      _field(
                        _offerPrice,
                        'Preco de oferta',
                        number: true,
                        unitPrice: true,
                        helperText:
                            'Opcional. Usado automaticamente dentro do periodo.',
                      ),
                      _field(
                        _offerStartAt,
                        'Inicio da oferta',
                        helperText: 'Formato: dd/mm/aaaa hh:mm',
                      ),
                      _field(
                        _offerEndAt,
                        'Fim da oferta',
                        helperText: 'Formato: dd/mm/aaaa hh:mm',
                      ),
                      _field(
                        _marginPercent,
                        'Margem %',
                        number: true,
                        focusNode: _marginFocus,
                      ),
                    ],
                  ),
                  if (widget.product != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEFF6FF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFBFDBFE)),
                      ),
                      child: Wrap(
                        spacing: 18,
                        runSpacing: 8,
                        children: [
                          _FiscalStockInfo(
                            label: 'Entrou com nota',
                            value:
                                '${_number(widget.product!.fiscalReceivedQuantity)} ${widget.product!.unit}',
                          ),
                          _FiscalStockInfo(
                            label: 'Ja usado em notas',
                            value:
                                '${_number(widget.product!.fiscalIssuedQuantity)} ${widget.product!.unit}',
                          ),
                          _FiscalStockInfo(
                            label: 'Disponivel para emitir',
                            value:
                                '${_number(widget.product!.fiscalAvailableQuantity)} ${widget.product!.unit}',
                          ),
                          _FiscalStockInfo(
                            label: 'Notas/entradas',
                            value: '${widget.product!.fiscalEntryCount}',
                          ),
                        ],
                      ),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'Converter pacote/embalagem da nota para unidade de estoque',
                    ),
                    subtitle: const Text(
                      'Deixe cadastrado quando o fornecedor manda 1 pacote/caixa/embalagem, mas o estoque e a venda controlam por unidade.',
                    ),
                    value: _purchaseConversionEnabled,
                    onChanged: (value) =>
                        setState(() => _purchaseConversionEnabled = value),
                  ),
                  if (_purchaseConversionEnabled) ...[
                    _Fields(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue:
                              _unitOptions.containsKey(_purchaseInvoiceUnit)
                              ? _purchaseInvoiceUnit
                              : 'pc',
                          decoration: const InputDecoration(
                            labelText: 'Unidade que vem na nota/XML',
                            border: OutlineInputBorder(),
                          ),
                          items: [
                            for (final entry in _unitOptions.entries)
                              DropdownMenuItem(
                                value: entry.key,
                                child: Text('${entry.key} - ${entry.value}'),
                              ),
                          ],
                          onChanged: (value) => setState(
                            () => _purchaseInvoiceUnit = value ?? 'pc',
                          ),
                        ),
                        _field(
                          _purchasePackageFactor,
                          'Unidades por pacote/embalagem',
                          number: true,
                        ),
                        _field(
                          _purchasePackageBarcode,
                          'Código do pacote/caixa/embalagem',
                        ),
                      ],
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 4, bottom: 8),
                      child: Text(
                        'Exemplo: se a nota vem 1 eb e dentro entram 45 un, deixe unidade da nota = eb e fator = 45. Se amanhã mudar para 50, altere aqui; os próximos recebimentos já puxam o novo padrão.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                  ],
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Controla lote e validade'),
                    subtitle: const Text(
                      'Use para alimentos, mercado, farmacia, cosmeticos e itens com vencimento.',
                    ),
                    value: _tracksBatch,
                    onChanged: (value) => setState(() => _tracksBatch = value),
                  ),
                  if (_tracksBatch)
                    _Fields(
                      children: [
                        _field(_initialBatchNumber, 'Lote inicial'),
                        _dateField(_initialExpirationDate, 'Validade inicial'),
                      ],
                    ),
                  const SizedBox(height: 16),
                  _Section('Fiscal atual'),
                  _fiscalAssistantPanel(),
                  const SizedBox(height: 12),
                  _Fields(
                    children: [
                      _field(
                        _ncm,
                        'NCM',
                        helperText:
                            'Normalmente vem do XML. Base completa oficial deve ser consultada por tabela/API NCM.',
                      ),
                      _field(
                        _cest,
                        'CEST',
                        helperText:
                            'Use quando houver substituicao tributaria conforme regra fiscal do produto.',
                      ),
                      _catalogDropdown(
                        _cfopSale,
                        'CFOP venda',
                        _cfopSaleOptions,
                      ),
                      _catalogDropdown(_origin, 'Origem', _fiscalOrigins),
                      _catalogDropdown(_cst, 'CST ICMS', _icmsCstOptions),
                      _catalogDropdown(_csosn, 'CSOSN', _csosnOptions),
                      _field(_icmsRate, 'ICMS %', number: true),
                      _field(_pisRate, 'PIS %', number: true),
                      _field(_cofinsRate, 'COFINS %', number: true),
                      _field(_ipiRate, 'IPI %', number: true),
                      _field(_issRate, 'ISS %', number: true),
                      _field(_municipalServiceCode, 'Código servico municipal'),
                      _field(
                        _taxRate,
                        'Aliquota fiscal padrao %',
                        number: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _area(_fiscalNotes, 'Observações fiscais'),
                  const SizedBox(height: 16),
                  _Section('Reforma Tributaria - IBS/CBS/IS'),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Preparado para novo regime IBS/CBS'),
                    value: _newTaxSystem,
                    onChanged: (value) => setState(() => _newTaxSystem = value),
                  ),
                  _Fields(
                    children: [
                      _catalogDropdown(
                        _ibsCbsCst,
                        'CST IBS/CBS',
                        _ibsCbsCstOptions,
                      ),
                      _field(_ibsCbsClassification, 'cClassTrib'),
                      _field(_cbsRate, 'CBS %', number: true),
                      _field(_ibsStateRate, 'IBS estadual %', number: true),
                      _field(_ibsCityRate, 'IBS municipal %', number: true),
                      _field(_selectiveTaxCst, 'CST IS'),
                      _field(_selectiveTaxClassification, 'cClassTrib IS'),
                      _field(
                        _selectiveTaxRate,
                        'Imposto Seletivo %',
                        number: true,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _area(_oldTaxSystemNotes, 'Notas regra antiga/transicao'),
                  const SizedBox(height: 12),
                  _area(_newTaxSystemNotes, 'Notas regra nova IBS/CBS/IS'),
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
                        label: Text(_saving ? 'Salvando...' : 'Salvar item'),
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
    bool number = false,
    bool money = false,
    bool unitPrice = false,
    FocusNode? focusNode,
    bool readOnly = false,
    String? helperText,
    VoidCallback? onTap,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      onTap: onTap,
      keyboardType: number ? TextInputType.text : null,
      inputFormatters: number
          ? [
              if (unitPrice)
                const BrazilianDecimalInputFormatter()
              else if (money)
                const BrazilianMoneyInputFormatter()
              else
                const BrazilianDecimalInputFormatter(),
            ]
          : null,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        filled: readOnly,
        fillColor: readOnly ? const Color(0xFFF8FAFC) : null,
        suffixIcon: readOnly ? const Icon(Icons.lock_outline) : suffixIcon,
        border: const OutlineInputBorder(),
      ),
      validator: required
          ? (value) => value == null || value.trim().length < 2
                ? 'Informe ao menos 2 caracteres.'
                : null
          : null,
    );
  }

  Widget _fiscalAssistantPanel() {
    final assistant = _fiscalAssistant;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD7E3F4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Assistente Fiscal Inteligente',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _loadingFiscalAssistant
                    ? null
                    : _loadFiscalAssistant,
                icon: _loadingFiscalAssistant
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.manage_search_outlined),
                label: Text(
                  _loadingFiscalAssistant ? 'Consultando...' : 'Consultar',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            assistant?.legalNotice ??
                'As informações fiscais são sugestões automáticas do sistema e devem ser conferidas pelo responsável fiscal ou contador da empresa.',
            style: const TextStyle(
              color: Color(0xFF92400E),
              fontWeight: FontWeight.w700,
            ),
          ),
          if (assistant != null) ...[
            if (assistant.alerts.isNotEmpty) ...[
              const SizedBox(height: 10),
              for (final alert in assistant.alerts)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        alert.severity == 'warning'
                            ? Icons.warning_amber_outlined
                            : Icons.info_outline,
                        size: 18,
                        color: alert.severity == 'warning'
                            ? const Color(0xFFD97706)
                            : const Color(0xFF2563EB),
                      ),
                      const SizedBox(width: 6),
                      Expanded(child: Text(alert.message)),
                    ],
                  ),
                ),
            ],
            const SizedBox(height: 8),
            if (assistant.ncmOfficialSuggestions.isNotEmpty) ...[
              const Text(
                'Sugestoes oficiais de NCM',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              for (final ncm in assistant.ncmOfficialSuggestions.take(3))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('${ncm.code} - ${ncm.description}'),
                    subtitle: const Text(
                      'Fonte: tabela NCM oficial local. Conferir com contador.',
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () => setState(() => _ncm.text = ncm.code),
                      child: const Text('Usar NCM'),
                    ),
                  ),
                ),
              const SizedBox(height: 8),
            ],
            if (assistant.suggestions.isEmpty)
              const Text('Nenhuma sugestao encontrada ainda para este produto.')
            else
              for (final suggestion in assistant.suggestions.take(3))
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.originalDescription ??
                              suggestion.normalizedDescription,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            if (suggestion.ncm != null) 'NCM ${suggestion.ncm}',
                            if (suggestion.cest != null)
                              'CEST ${suggestion.cest}',
                            if (suggestion.cfop != null)
                              'CFOP ${suggestion.cfop}',
                            if (suggestion.cst != null) 'CST ${suggestion.cst}',
                            if (suggestion.csosn != null)
                              'CSOSN ${suggestion.csosn}',
                            if (suggestion.ibsCbsCst != null)
                              'IBS/CBS ${suggestion.ibsCbsCst}',
                          ].join(' • '),
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _applyFiscalSuggestion(suggestion),
                            icon: const Icon(Icons.done_all_outlined),
                            label: const Text('Aplicar sugestao'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
          ],
        ],
      ),
    );
  }

  Widget _readOnlyField(
    TextEditingController controller,
    String label, {
    String? helperText,
    bool locked = true,
    FocusNode? focusNode,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      readOnly: locked,
      onTap: onTap,
      keyboardType: TextInputType.text,
      inputFormatters: const [BrazilianMoneyInputFormatter()],
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        prefixText: 'R\$ ',
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        suffixIcon: locked ? const Icon(Icons.lock_outline) : null,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _unitDropdown() {
    return DropdownButtonFormField<String>(
      initialValue: _selectedUnit,
      decoration: const InputDecoration(
        labelText: 'Unidade de venda/estoque',
        helperText:
            'Se o fornecedor manda pacote/caixa, converta na entrada da mercadoria.',
        border: OutlineInputBorder(),
      ),
      items: [
        for (final entry in _unitOptions.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text('${entry.key} - ${entry.value}'),
          ),
      ],
      onChanged: (value) {
        final selected = value ?? 'un';
        setState(() {
          _selectedUnit = selected;
          _unit.text = selected;
        });
      },
    );
  }

  Widget _catalogDropdown(
    TextEditingController controller,
    String label,
    Map<String, String> options, {
    String? helperText,
  }) {
    final current = controller.text.trim();
    final selected = options.containsKey(current) ? current : null;
    return DropdownButtonFormField<String>(
      initialValue: selected,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText ?? 'Clique para escolher um codigo padrao.',
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final entry in options.entries)
          DropdownMenuItem(
            value: entry.key,
            child: Text(
              '${entry.key} - ${entry.value}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: (value) {
        if (value == null) return;
        setState(() => controller.text = value);
      },
    );
  }

  Widget _dateField(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      readOnly: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: IconButton(
          tooltip: 'Selecionar data',
          icon: const Icon(Icons.calendar_month_outlined),
          onPressed: () async {
            final current = DateTime.tryParse(controller.text);
            final picked = await showDatePicker(
              context: context,
              initialDate: current ?? DateTime.now(),
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            controller.text = _dateOnly(picked);
          },
        ),
      ),
    );
  }

  Widget _area(TextEditingController controller, String label) {
    return TextFormField(
      controller: controller,
      minLines: 2,
      maxLines: 4,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _Fields extends StatelessWidget {
  const _Fields({required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 860
            ? (constraints.maxWidth - 24) / 3
            : constraints.maxWidth >= 560
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

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text(
        title,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.items});
  final List<_SummaryItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 820 ? 3 : 1;
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
            Icon(item.icon, color: const Color(0xFF2563EB)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  Text(
                    item.money ? _money(item.value as double) : '${item.value}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
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

class _SummaryItem {
  const _SummaryItem(this.label, this.value, this.icon, {this.money = false});
  final String label;
  final Object value;
  final IconData icon;
  final bool money;
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
          secondary.isEmpty ? '-' : secondary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
        ),
      ],
    );
  }
}

double _moneyValue(String value) => parseBrazilianNumber(value);

double _decimalValue(String value) {
  final sanitized = value.trim().replaceAll(RegExp(r'[^0-9,.]'), '');
  if (sanitized.isEmpty) return 0;
  if (sanitized.contains(',')) {
    return double.tryParse(
          sanitized.replaceAll('.', '').replaceAll(',', '.'),
        ) ??
        0;
  }
  final dotGroups = sanitized.split('.');
  if (dotGroups.length > 1 &&
      dotGroups.skip(1).every((part) => part.length == 3)) {
    return double.tryParse(dotGroups.join()) ?? 0;
  }
  return double.tryParse(sanitized) ?? 0;
}

double? _nullableMoney(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return _moneyValue(trimmed);
}

double? _nullableDecimal(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return _decimalValue(trimmed);
}

String _number(double value) {
  return formatBrazilianDecimal(value);
}

String _numberOrEmpty(double? value) => value == null ? '' : _number(value);
String _moneyInputValue(double value) => formatBrazilianMoneyInput(value);
String _unitPriceInputValue(double value) {
  var fixed = value.toStringAsFixed(4);
  fixed = fixed.replaceFirst(RegExp(r'0+$'), '');
  if (fixed.endsWith('.')) fixed = '${fixed}00';
  final parts = fixed.split('.');
  final decimals = parts.length > 1 ? parts.last.padRight(2, '0') : '00';
  return '${_groupIntegerForPrice(parts.first)},$decimals';
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';

String _groupIntegerForPrice(String value) {
  final clean = value.replaceAll(RegExp(r'[^0-9]'), '');
  if (clean.isEmpty) return '0';
  final buffer = StringBuffer();
  for (var index = 0; index < clean.length; index++) {
    final remaining = clean.length - index;
    buffer.write(clean[index]);
    if (remaining > 1 && remaining % 3 == 1) buffer.write('.');
  }
  return buffer.toString();
}

String _dateTimeInputValue(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

DateTime? _nullableDateTime(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  final iso = DateTime.tryParse(trimmed);
  if (iso != null) return iso;
  final match = RegExp(
    r'^(\d{1,2})/(\d{1,2})/(\d{4})(?:\s+(\d{1,2}):(\d{2}))?$',
  ).firstMatch(trimmed);
  if (match == null) return null;
  final day = int.tryParse(match.group(1)!);
  final month = int.tryParse(match.group(2)!);
  final year = int.tryParse(match.group(3)!);
  final hour = int.tryParse(match.group(4) ?? '0');
  final minute = int.tryParse(match.group(5) ?? '0');
  if (day == null ||
      month == null ||
      year == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  return DateTime(year, month, day, hour, minute);
}

double? _convertQuantity(double quantity, String fromUnit, String toUnit) {
  final normalizedFrom = fromUnit.trim().toLowerCase();
  final normalizedTo = toUnit.trim().toLowerCase();
  if (normalizedFrom == normalizedTo) return quantity;
  final fromFamily = _unitFamilies[normalizedFrom];
  final toFamily = _unitFamilies[normalizedTo];
  final fromFactor = _unitFactors[normalizedFrom];
  final toFactor = _unitFactors[normalizedTo];
  if (fromFamily == null ||
      toFamily == null ||
      fromFactor == null ||
      toFactor == null ||
      fromFamily != toFamily) {
    return null;
  }
  return quantity * fromFactor / toFactor;
}

String _signedNumber(double value) {
  final formatted = _number(value.abs());
  return value < 0 ? '-$formatted' : '+$formatted';
}

String _dateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)} ${two(value.hour)}:${two(value.minute)}';
}

String _dateOnly(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)}';
}

String? _publicUrl(String apiBaseUrl, String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final base = apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;
  final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return '$base$path';
}

String _normalize(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  var normalized = value.toLowerCase().trim();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}

String _formatDate(String? value) {
  if (value == null || value.isEmpty) return '-';
  final parsed = DateTime.tryParse(value);
  if (parsed == null) return value;
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(parsed.day)}/${two(parsed.month)}/${parsed.year}';
}
