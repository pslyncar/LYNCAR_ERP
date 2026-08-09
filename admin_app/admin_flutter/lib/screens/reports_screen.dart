import 'package:flutter/material.dart';

import '../models/cash_closing.dart';
import '../models/client.dart';
import '../models/payable.dart';
import '../models/product.dart';
import '../models/receivable.dart';
import '../models/sale.dart';
import '../models/session.dart';
import '../models/stock_entry.dart';
import '../models/stock_movement.dart';
import '../services/api_client.dart';
import '../services/file_download.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key, required this.session});

  final Session session;

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();

  List<Product> _products = [];
  List<Sale> _sales = [];
  List<Receivable> _receivables = [];
  List<Payable> _payables = [];
  List<StockEntry> _entries = [];
  List<Client> _clients = [];
  List<CashClosing> _closings = [];
  List<StockMovement> _withdrawals = [];

  DateTime _salesDateFrom = DateTime.now().subtract(const Duration(days: 29));
  DateTime _salesDateTo = DateTime.now();

  bool _loading = true;
  String? _error;
  String _category = 'estoque';
  String _reportKey = '';

  bool get _canProducts =>
      widget.session.can('products:view') || widget.session.can('stock:view');
  bool get _canSales => widget.session.can('sales:view');
  bool get _canFinance =>
      widget.session.can('finance:view') ||
      widget.session.can('finance:receivables:view') ||
      widget.session.can('finance:payables:view');
  bool get _canEntries =>
      widget.session.can('stock:entries:view') ||
      widget.session.can('stock:entries:create') ||
      widget.session.can('stock:entries:confirm');
  bool get _canClients => widget.session.can('clients:view');
  bool get _canWithdrawals => widget.session.can('stock:withdraw');

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
      final products = _canProducts
          ? await _api.listProducts(widget.session.token)
          : <Product>[];
      final sales = _canSales
          ? await _api.listSales(
              widget.session.token,
              limit: 2000,
              dateFrom: _comparisonDateFrom,
              dateTo: _salesDateTo,
            )
          : <Sale>[];
      final receivables = _canFinance
          ? await _api.listReceivables(widget.session.token, limit: 200)
          : <Receivable>[];
      final payables = _canFinance
          ? await _api.listPayables(widget.session.token, limit: 200)
          : <Payable>[];
      final entries = _canEntries
          ? await _api.listStockEntries(widget.session.token, limit: 200)
          : <StockEntry>[];
      final clients = _canClients
          ? await _api.listClients(widget.session.token)
          : <Client>[];
      final closings = _canSales
          ? await _api.listCashClosings(widget.session.token, limit: 200)
          : <CashClosing>[];
      final withdrawals = _canWithdrawals
          ? await _api.listRecentStockWithdrawals(
              widget.session.token,
              limit: 1000,
            )
          : <StockMovement>[];
      if (!mounted) return;
      setState(() {
        _products = products;
        _sales = sales;
        _receivables = receivables;
        _payables = payables;
        _entries = entries;
        _clients = clients;
        _closings = closings;
        _withdrawals = withdrawals;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar relatórios.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  int get _salesPeriodDays =>
      DateTime(_salesDateTo.year, _salesDateTo.month, _salesDateTo.day)
          .difference(
            DateTime(
              _salesDateFrom.year,
              _salesDateFrom.month,
              _salesDateFrom.day,
            ),
          )
          .inDays +
      1;

  DateTime get _comparisonDateFrom =>
      _salesDateFrom.subtract(Duration(days: _salesPeriodDays));

  List<Sale> get _currentPeriodSales => _sales
      .where(
        (sale) =>
            !_day(sale.soldAt).isBefore(_day(_salesDateFrom)) &&
            !_day(sale.soldAt).isAfter(_day(_salesDateTo)),
      )
      .toList();

  List<Sale> get _previousPeriodSales {
    final previousTo = _salesDateFrom.subtract(const Duration(days: 1));
    return _sales
        .where(
          (sale) =>
              !_day(sale.soldAt).isBefore(_day(_comparisonDateFrom)) &&
              !_day(sale.soldAt).isAfter(_day(previousTo)),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final report = _reportKey.isEmpty ? null : _selectedReport();
    final rows = report == null ? <_ReportRow>[] : _filteredRows(report.rows);
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
                        'Relatórios',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Análises gerenciais, auditoria e exportações do ERP',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null) ErrorPanel(message: _error!, onRetry: _load),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              _summaryCards(),
              const SizedBox(height: 16),
              if (report == null)
                _reportLibrary()
              else ...[
                if (_category == 'vendas') ...[
                  _salesPeriodCard(),
                  const SizedBox(height: 16),
                ],
                _reportDetailControls(report),
                const SizedBox(height: 16),
                _reportTable(report, rows),
              ],
            ],
          ],
        ),
      ),
    );
  }

  Widget _summaryCards() {
    final stockValue = _products.fold<double>(
      0,
      (sum, product) => sum + product.stockValue,
    );
    final openReceivables = _receivables
        .where((item) => item.balanceAmount > 0 && item.status != 'paid')
        .fold<double>(0, (sum, item) => sum + item.balanceAmount);
    final openPayables = _payables
        .where((item) => item.balanceAmount > 0 && item.status != 'paid')
        .fold<double>(0, (sum, item) => sum + item.balanceAmount);
    final salesTotal = _currentPeriodSales
        .where((sale) => sale.status != 'cancelada')
        .fold<double>(0, (sum, sale) => sum + sale.totalAmount);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 820;
        final cards = [
          _KpiCard(
            label: 'Valor em estoque',
            value: _money(stockValue),
            icon: Icons.inventory_2_outlined,
          ),
          _KpiCard(
            label: 'Vendas no período',
            value: _money(salesTotal),
            icon: Icons.receipt_long_outlined,
          ),
          _KpiCard(
            label: 'A receber aberto',
            value: _money(openReceivables),
            icon: Icons.trending_up,
          ),
          _KpiCard(
            label: 'A pagar aberto',
            value: _money(openPayables),
            icon: Icons.trending_down,
          ),
        ];
        if (compact) {
          return Column(
            children: [
              for (final card in cards) ...[card, const SizedBox(height: 10)],
            ],
          );
        }
        return Row(
          children: [
            for (final card in cards) ...[
              Expanded(child: card),
              if (card != cards.last) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }

  Widget _salesPeriodCard() {
    return AppCard(
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Text('Período:', style: TextStyle(fontWeight: FontWeight.w900)),
          for (final preset in const [
            ('Hoje', 0),
            ('7 dias', 6),
            ('30 dias', 29),
            ('90 dias', 89),
          ])
            ChoiceChip(
              selected:
                  _sameDay(_salesDateTo, DateTime.now()) &&
                  _salesPeriodDays == preset.$2 + 1,
              label: Text(preset.$1),
              onSelected: (_) => _applySalesPreset(preset.$2),
            ),
          OutlinedButton.icon(
            onPressed: () => _selectSalesDate(from: true),
            icon: const Icon(Icons.calendar_month_outlined),
            label: Text('De ${_date(_salesDateFrom)}'),
          ),
          OutlinedButton.icon(
            onPressed: () => _selectSalesDate(from: false),
            icon: const Icon(Icons.event_outlined),
            label: Text('Até ${_date(_salesDateTo)}'),
          ),
          Text(
            'Comparado com ${_date(_comparisonDateFrom)} a '
            '${_date(_salesDateFrom.subtract(const Duration(days: 1)))}',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }

  Future<void> _applySalesPreset(int daysBack) async {
    final today = _day(DateTime.now());
    setState(() {
      _salesDateTo = today;
      _salesDateFrom = today.subtract(Duration(days: daysBack));
    });
    await _load();
  }

  Future<void> _selectSalesDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: from ? _salesDateFrom : _salesDateTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      helpText: from ? 'Início do período' : 'Fim do período',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (from) {
        _salesDateFrom = selected;
        if (_salesDateTo.isBefore(selected)) _salesDateTo = selected;
      } else {
        _salesDateTo = selected;
        if (_salesDateFrom.isAfter(selected)) _salesDateFrom = selected;
      }
    });
    await _load();
  }

  Widget _reportLibrary() {
    final categories = _availableCategories();
    return Column(
      children: [
        for (final category in categories) ...[
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(category.icon, color: const Color(0xFF2563EB)),
                    const SizedBox(width: 10),
                    Text(
                      category.label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final columns = width >= 980
                        ? 3
                        : width >= 640
                        ? 2
                        : 1;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final report in _reportsForCategory(category.key))
                          SizedBox(
                            width: (width - (12 * (columns - 1))) / columns,
                            child: _ReportButton(
                              report: report,
                              onTap: () => setState(() {
                                _category = category.key;
                                _reportKey = report.key;
                                _search.clear();
                              }),
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ],
    );
  }

  Widget _reportDetailControls(_ReportData report) {
    return AppCard(
      child: Row(
        children: [
          IconButton.outlined(
            tooltip: 'Voltar para relatórios',
            onPressed: () => setState(() {
              _reportKey = '';
              _search.clear();
            }),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                labelText: _filterLabel(report.key),
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: () => _exportReport(report),
            icon: const Icon(Icons.download_outlined),
            label: const Text('Exportar'),
          ),
        ],
      ),
    );
  }

  Widget _reportTable(_ReportData report, List<_ReportRow> rows) {
    if (report.key == 'sales_dashboard') {
      return _SalesDashboard(
        currentSales: _currentPeriodSales,
        previousSales: _previousPeriodSales,
        dateFrom: _salesDateFrom,
        dateTo: _salesDateTo,
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            report.title,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            report.description,
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          if (report.key == 'receivable_aging') ...[
            const SizedBox(height: 10),
            const _InfoBox(
              text:
                  'Aging separa automaticamente os títulos em aberto pela quantidade de dias vencidos. Não e um campo cadastrado; ele usa a data de vencimento da conta a receber.',
            ),
          ],
          const SizedBox(height: 14),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nenhum dado encontrado.')),
            )
          else
            ResponsiveDataTable(
              child: DataTable(
                columns: [
                  for (final column in report.columns)
                    DataColumn(label: Text(column)),
                ],
                rows: [
                  for (final row in rows.take(300))
                    DataRow(
                      cells: [
                        for (final value in row.values)
                          DataCell(
                            Text(value, overflow: TextOverflow.ellipsis),
                          ),
                      ],
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<_ReportRow> _filteredRows(List<_ReportRow> rows) {
    final term = _normalize(_search.text);
    if (term.isEmpty) return rows;
    return rows
        .where((row) => _normalize(row.values.join(' ')).contains(term))
        .toList();
  }

  void _exportReport(_ReportData report) {
    final rows = _filteredRows(report.rows);
    final content = [
      report.columns.map(_csvCell).join(';'),
      for (final row in rows) row.values.map(_csvCell).join(';'),
    ].join('\r\n');
    downloadTextFile(
      filename: '${report.key}_${_todayFile()}.csv',
      mimeType: 'text/csv;charset=utf-8',
      content: content,
    );
  }

  _ReportData _selectedReport() {
    final reports = _reportsForCategory(_category);
    return reports.firstWhere(
      (report) => report.key == _reportKey,
      orElse: () => reports.first,
    );
  }

  List<_Category> _availableCategories() {
    return [
      if (_canProducts || _canWithdrawals)
        const _Category('estoque', 'Estoque', Icons.inventory_2_outlined),
      if (_canSales)
        const _Category('vendas', 'Vendas', Icons.receipt_long_outlined),
      if (_canFinance)
        const _Category(
          'financeiro',
          'Financeiro',
          Icons.account_balance_outlined,
        ),
      if (_canEntries)
        const _Category('compras', 'Compras', Icons.input_outlined),
      if (_canSales)
        const _Category(
          'caixa',
          'Caixa',
          Icons.account_balance_wallet_outlined,
        ),
      if (_canClients)
        const _Category('clientes', 'Clientes', Icons.business_outlined),
    ];
  }

  List<_ReportData> _reportsForCategory(String category) {
    return switch (category) {
      'estoque' => _stockReports(),
      'vendas' => _salesReports(),
      'financeiro' => _financeReports(),
      'compras' => _purchaseReports(),
      'caixa' => _cashReports(),
      'clientes' => _clientReports(),
      _ => _stockReports(),
    };
  }

  List<_ReportData> _stockReports() {
    final today = DateTime.now();
    return [
      if (_canWithdrawals)
        _ReportData(
          key: 'stock_withdrawals',
          title: 'Baixas de estoque',
          description:
              'Perdas, consumo, vencimentos e outras saídas com custo e responsável.',
          columns: const [
            'Data',
            'Produto',
            'Motivo',
            'Quantidade',
            'Unidade',
            'Impacto a custo',
            'Responsável',
            'Observações',
          ],
          rows: [
            for (final movement in _withdrawals)
              _ReportRow([
                _dateTime(movement.createdAt),
                movement.productName ?? '-',
                movement.reason ?? '-',
                _number(movement.quantityDelta.abs()),
                movement.unit,
                _money(movement.totalValue ?? 0),
                movement.userName ?? 'Usuário removido',
                movement.notes ?? '-',
              ]),
          ],
        ),
      if (_canProducts) ...[
        _ReportData(
          key: 'stock_position',
          title: 'Posicao de estoque',
          description: 'Saldo, custo medio e valor em estoque por produto.',
          columns: const [
            'Produto',
            'Código',
            'Barras',
            'Un',
            'Saldo',
            'Minimo',
            'Custo medio',
            'Valor estoque',
            'Validade',
          ],
          rows: [
            for (final product in _products)
              _ReportRow([
                product.name,
                product.internalCode ?? '-',
                product.barcode ?? '-',
                product.unit,
                _number(product.stockQuantity),
                _number(product.minimumStock),
                _money(product.averageCost ?? 0),
                _money(product.stockValue),
                product.nearestExpirationDate ?? '-',
              ]),
          ],
        ),
        _ReportData(
          key: 'stock_low',
          title: 'Estoque baixo',
          description:
              'Produtos com saldo igual ou abaixo do minimo configurado.',
          columns: const ['Produto', 'Código', 'Saldo', 'Minimo', 'Falta'],
          rows: [
            for (final product in _products.where(
              (p) => p.stockQuantity <= p.minimumStock,
            ))
              _ReportRow([
                product.name,
                product.internalCode ?? '-',
                _number(product.stockQuantity),
                _number(product.minimumStock),
                _number(product.minimumStock - product.stockQuantity),
              ]),
          ],
        ),
        _ReportData(
          key: 'stock_expiring',
          title: 'Produtos próximos ao vencimento',
          description: 'Itens com validade nos próximos 30 dias.',
          columns: const [
            'Produto',
            'Código',
            'Lote',
            'Validade',
            'Dias',
            'Saldo',
          ],
          rows: [
            for (final product in _products)
              if (_daysUntil(product.nearestExpirationDate, today) != null &&
                  _daysUntil(product.nearestExpirationDate, today)! >= 0 &&
                  _daysUntil(product.nearestExpirationDate, today)! <= 30)
                _ReportRow([
                  product.name,
                  product.internalCode ?? '-',
                  product.nearestBatchNumber ?? '-',
                  product.nearestExpirationDate ?? '-',
                  '${_daysUntil(product.nearestExpirationDate, today)}',
                  _number(product.stockQuantity),
                ]),
          ],
        ),
        _ReportData(
          key: 'stock_expired',
          title: 'Produtos vencidos',
          description: 'Itens cuja proxima validade já passou.',
          columns: const [
            'Produto',
            'Código',
            'Lote',
            'Validade',
            'Dias vencido',
            'Saldo',
          ],
          rows: [
            for (final product in _products)
              if (_daysUntil(product.nearestExpirationDate, today) != null &&
                  _daysUntil(product.nearestExpirationDate, today)! < 0)
                _ReportRow([
                  product.name,
                  product.internalCode ?? '-',
                  product.nearestBatchNumber ?? '-',
                  product.nearestExpirationDate ?? '-',
                  '${_daysUntil(product.nearestExpirationDate, today)!.abs()}',
                  _number(product.stockQuantity),
                ]),
          ],
        ),
      ],
    ];
  }

  List<_ReportData> _salesReports() {
    final productTotals = <String, double>{};
    final productQty = <String, double>{};
    final paymentTotals = <String, double>{};
    final periodSales = _currentPeriodSales
        .where((sale) => sale.status != 'cancelada')
        .toList();
    for (final sale in periodSales) {
      for (final item in sale.items) {
        productTotals[item.description] =
            (productTotals[item.description] ?? 0) + item.totalPrice;
        productQty[item.description] =
            (productQty[item.description] ?? 0) + item.quantity;
      }
      for (final payment in sale.payments) {
        paymentTotals[payment.method] =
            (paymentTotals[payment.method] ?? 0) + payment.amount;
      }
    }
    return [
      _ReportData(
        key: 'sales_dashboard',
        title: 'Painel de vendas',
        description:
            'Faturamento, ticket médio, tendência, comparação e destaques do período.',
        columns: const ['Indicador', 'Valor'],
        rows: _salesDashboardRows(periodSales),
      ),
      _ReportData(
        key: 'sales_period',
        title: 'Vendas por periodo',
        description: 'Lista das vendas recentes com status e total.',
        columns: const [
          'Data',
          'Número',
          'Origem',
          'Status',
          'Total',
          'Pago',
          'Troco',
        ],
        rows: [
          for (final sale in periodSales)
            _ReportRow([
              _date(sale.soldAt),
              sale.number ?? 'VEN${sale.id}',
              sale.source.toUpperCase(),
              sale.status,
              _money(sale.totalAmount),
              _money(sale.amountPaid),
              _money(sale.changeAmount),
            ]),
        ],
      ),
      _ReportData(
        key: 'sales_products',
        title: 'Produtos mais vendidos',
        description: 'Quantidade e valor vendidos por produto.',
        columns: const ['Produto', 'Quantidade', 'Total vendido'],
        rows: _sortedMapRows(productTotals, productQty),
      ),
      _ReportData(
        key: 'sales_payments',
        title: 'Formas de pagamento',
        description: 'Total recebido por forma de pagamento.',
        columns: const ['Forma', 'Total'],
        rows: [
          for (final entry in _sortedEntries(paymentTotals))
            _ReportRow([_paymentLabel(entry.key), _money(entry.value)]),
        ],
      ),
    ];
  }

  List<_ReportRow> _salesDashboardRows(List<Sale> sales) {
    final valid = sales.where((sale) => sale.status != 'cancelada').toList();
    final total = valid.fold<double>(0, (sum, sale) => sum + sale.totalAmount);
    final items = valid.fold<double>(
      0,
      (sum, sale) =>
          sum +
          sale.items.fold<double>(
            0,
            (itemSum, item) => itemSum + item.quantity,
          ),
    );
    return [
      _ReportRow(['Faturamento', _money(total)]),
      _ReportRow(['Vendas', '${valid.length}']),
      _ReportRow([
        'Ticket médio',
        _money(valid.isEmpty ? 0 : total / valid.length),
      ]),
      _ReportRow(['Itens vendidos', _number(items)]),
    ];
  }

  List<_ReportData> _financeReports() {
    final aging = _agingRows();
    return [
      _ReportData(
        key: 'receivables_open',
        title: 'Contas a receber em aberto',
        description: 'Títulos de clientes ainda não quitados.',
        columns: const [
          'Cliente',
          'Titulo',
          'Vencimento',
          'Original',
          'Pago',
          'Saldo',
          'Status',
        ],
        rows: [
          for (final item in _receivables.where(
            (r) => r.balanceAmount > 0 && r.status != 'paid',
          ))
            _ReportRow([
              item.clientName ?? '-',
              item.number ?? 'CR${item.id}',
              _dateNullable(item.dueDate),
              _money(item.originalAmount),
              _money(item.paidAmount),
              _money(item.balanceAmount),
              item.status,
            ]),
        ],
      ),
      _ReportData(
        key: 'receivable_aging',
        title: 'Aging de clientes',
        description: 'Saldo aberto por faixa de atraso dos clientes.',
        columns: const [
          'Cliente',
          'A vencer',
          '0-30 dias',
          '31-60 dias',
          '61-90 dias',
          '90+ dias',
          'Total',
        ],
        rows: aging,
      ),
      _ReportData(
        key: 'payables_open',
        title: 'Contas a pagar em aberto',
        description: 'Títulos de fornecedores e despesas ainda não quitados.',
        columns: const [
          'Fornecedor',
          'Titulo',
          'Categoria',
          'Vencimento',
          'Original',
          'Pago',
          'Saldo',
          'Status',
        ],
        rows: [
          for (final item in _payables.where(
            (p) => p.balanceAmount > 0 && p.status != 'paid',
          ))
            _ReportRow([
              item.supplierName ?? '-',
              item.number ?? 'CP${item.id}',
              item.category ?? '-',
              _dateNullable(item.dueDate),
              _money(item.originalAmount),
              _money(item.paidAmount),
              _money(item.balanceAmount),
              item.status,
            ]),
        ],
      ),
    ];
  }

  List<_ReportData> _purchaseReports() {
    final supplierTotals = <String, double>{};
    for (final entry in _entries) {
      final supplier = entry.supplierName ?? 'Sem fornecedor';
      supplierTotals[supplier] =
          (supplierTotals[supplier] ?? 0) + entry.totalAmount;
    }
    return [
      _ReportData(
        key: 'entries_recent',
        title: 'Entradas de mercadoria',
        description: 'Recebimentos recentes por NF, fornecedor e origem.',
        columns: const [
          'Fornecedor',
          'Origem',
          'NF',
          'Série',
          'Total',
          'Itens',
        ],
        rows: [
          for (final entry in _entries)
            _ReportRow([
              entry.supplierName ?? '-',
              entry.source,
              entry.invoiceNumber ?? '-',
              entry.invoiceSeries ?? '-',
              _money(entry.totalAmount),
              '${entry.items.length}',
            ]),
        ],
      ),
      _ReportData(
        key: 'entries_supplier',
        title: 'Compras por fornecedor',
        description: 'Total comprado por fornecedor nas entradas carregadas.',
        columns: const ['Fornecedor', 'Total comprado'],
        rows: [
          for (final entry in _sortedEntries(supplierTotals))
            _ReportRow([entry.key, _money(entry.value)]),
        ],
      ),
      _ReportData(
        key: 'entries_pending',
        title: 'Pendências de conferência',
        description: 'Itens pendentes, sem produto ou marcados para devolucao.',
        columns: const [
          'Fornecedor',
          'NF',
          'Produto',
          'Status',
          'Qtd',
          'Observação',
        ],
        rows: [
          for (final entry in _entries)
            for (final item in entry.items)
              if (item.checkStatus != 'accepted' || item.productId == null)
                _ReportRow([
                  entry.supplierName ?? '-',
                  entry.invoiceNumber ?? '-',
                  item.description,
                  item.checkStatus,
                  _number(item.receivedQuantity ?? item.quantity),
                  item.checkNotes ?? '-',
                ]),
        ],
      ),
    ];
  }

  List<_ReportData> _cashReports() {
    return [
      _ReportData(
        key: 'cash_closings',
        title: 'Fechamentos de caixa',
        description: 'Resumo dos fechamentos enviados pelo PDV.',
        columns: const [
          'Data',
          'Operador',
          'Status',
          'Vendas',
          'Qtd vendas',
          'Esperado',
          'Contado',
          'Diferenca',
        ],
        rows: [
          for (final closing in _closings)
            _ReportRow([
              _date(closing.closedAt),
              closing.operatorName ?? '-',
              closing.status,
              _money(closing.totalSalesAmount),
              '${closing.totalSalesCount}',
              _money(closing.expectedCashAmount),
              _money(closing.countedCashAmount),
              _money(closing.cashDifferenceAmount),
            ]),
        ],
      ),
    ];
  }

  List<_ReportData> _clientReports() {
    final balanceByClient = <int, double>{};
    for (final receivable in _receivables.where((r) => r.balanceAmount > 0)) {
      if (receivable.clientId == null) continue;
      balanceByClient[receivable.clientId!] =
          (balanceByClient[receivable.clientId!] ?? 0) +
          receivable.balanceAmount;
    }
    return [
      _ReportData(
        key: 'clients_credit',
        title: 'Clientes com saldo em crediario',
        description: 'Clientes com saldo aberto no contas a receber.',
        columns: const [
          'Cliente',
          'Documento',
          'Limite',
          'Status credito',
          'Saldo aberto',
        ],
        rows: [
          for (final client in _clients)
            if ((balanceByClient[client.id] ?? 0) > 0)
              _ReportRow([
                client.name,
                client.documentNumber ?? '-',
                _money(client.creditLimit),
                client.creditStatus,
                _money(balanceByClient[client.id] ?? 0),
              ]),
        ],
      ),
      _ReportData(
        key: 'clients_register',
        title: 'Cadastro de clientes',
        description: 'Lista exportavel de clientes cadastrados.',
        columns: const [
          'Cliente',
          'Fantasia',
          'Documento',
          'Telefone',
          'Email',
          'Cidade',
          'UF',
          'Ativo',
        ],
        rows: [
          for (final client in _clients)
            _ReportRow([
              client.name,
              client.tradeName ?? '-',
              client.documentNumber ?? '-',
              client.phone ?? client.mobilePhone ?? '-',
              client.email ?? '-',
              client.city ?? '-',
              client.state ?? '-',
              client.active ? 'Sim' : 'Não',
            ]),
        ],
      ),
    ];
  }

  List<_ReportRow> _agingRows() {
    final today = DateTime.now();
    final buckets = <String, List<double>>{};
    for (final item in _receivables.where(
      (r) => r.balanceAmount > 0 && r.status != 'paid',
    )) {
      final client = item.clientName ?? 'Sem cliente';
      final values = buckets.putIfAbsent(client, () => [0, 0, 0, 0, 0]);
      final due = item.dueDate;
      if (due == null || due.isAfter(today)) {
        values[0] += item.balanceAmount;
        continue;
      }
      final days = today
          .difference(DateTime(due.year, due.month, due.day))
          .inDays;
      if (days <= 30) {
        values[1] += item.balanceAmount;
      } else if (days <= 60) {
        values[2] += item.balanceAmount;
      } else if (days <= 90) {
        values[3] += item.balanceAmount;
      } else {
        values[4] += item.balanceAmount;
      }
    }
    final entries = buckets.entries.toList()
      ..sort(
        (a, b) => b.value
            .fold<double>(0, (s, v) => s + v)
            .compareTo(a.value.fold<double>(0, (s, v) => s + v)),
      );
    return [
      for (final entry in entries)
        _ReportRow([
          entry.key,
          for (final value in entry.value) _money(value),
          _money(entry.value.fold<double>(0, (sum, value) => sum + value)),
        ]),
    ];
  }
}

class _ReportData {
  const _ReportData({
    required this.key,
    required this.title,
    required this.description,
    required this.columns,
    required this.rows,
  });

  final String key;
  final String title;
  final String description;
  final List<String> columns;
  final List<_ReportRow> rows;
}

class _SalesDashboard extends StatelessWidget {
  const _SalesDashboard({
    required this.currentSales,
    required this.previousSales,
    required this.dateFrom,
    required this.dateTo,
  });

  final List<Sale> currentSales;
  final List<Sale> previousSales;
  final DateTime dateFrom;
  final DateTime dateTo;

  @override
  Widget build(BuildContext context) {
    final current = currentSales
        .where((sale) => sale.status != 'cancelada')
        .toList();
    final previous = previousSales
        .where((sale) => sale.status != 'cancelada')
        .toList();
    final total = _salesTotal(current);
    final previousTotal = _salesTotal(previous);
    final ticket = current.isEmpty ? 0.0 : total / current.length;
    final previousTicket = previous.isEmpty
        ? 0.0
        : previousTotal / previous.length;
    final items = current.fold<double>(
      0,
      (sum, sale) =>
          sum +
          sale.items.fold<double>(
            0,
            (itemSum, item) => itemSum + item.quantity,
          ),
    );
    final discount = current.fold<double>(
      0,
      (sum, sale) => sum + sale.discountAmount,
    );
    final trend = _salesTrend(current, dateFrom, dateTo);
    final weekday = _weekdaySales(current);
    final products = _topProductSales(current);
    final payments = _paymentSales(current);

    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth >= 1050
                ? (constraints.maxWidth - 36) / 4
                : constraints.maxWidth >= 620
                ? (constraints.maxWidth - 12) / 2
                : constraints.maxWidth;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: width,
                  child: _ComparisonKpi(
                    label: 'Faturamento',
                    value: _money(total),
                    variation: _variation(total, previousTotal),
                    icon: Icons.payments_outlined,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ComparisonKpi(
                    label: 'Vendas',
                    value: '${current.length}',
                    variation: _variation(
                      current.length.toDouble(),
                      previous.length.toDouble(),
                    ),
                    icon: Icons.receipt_long_outlined,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ComparisonKpi(
                    label: 'Ticket médio',
                    value: _money(ticket),
                    variation: _variation(ticket, previousTicket),
                    icon: Icons.shopping_bag_outlined,
                  ),
                ),
                SizedBox(
                  width: width,
                  child: _ComparisonKpi(
                    label: 'Itens / descontos',
                    value: '${_number(items)} • ${_money(discount)}',
                    icon: Icons.inventory_2_outlined,
                  ),
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 950;
            final trendCard = _ChartCard(
              title: 'Evolução das vendas',
              subtitle: 'Faturamento ao longo do período selecionado',
              child: _ColumnChart(data: trend),
            );
            final weekdayCard = _ChartCard(
              title: 'Vendas por dia da semana',
              subtitle: 'Ajuda a identificar os dias mais fortes e mais fracos',
              child: _HorizontalBars(data: weekday),
            );
            if (!wide) {
              return Column(
                children: [trendCard, const SizedBox(height: 12), weekdayCard],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(flex: 3, child: trendCard),
                const SizedBox(width: 12),
                Expanded(flex: 2, child: weekdayCard),
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 850;
            final productCard = _ChartCard(
              title: 'Produtos com maior faturamento',
              subtitle: 'Top 8 no período',
              child: _HorizontalBars(data: products),
            );
            final paymentCard = _ChartCard(
              title: 'Formas de pagamento',
              subtitle: 'Participação no valor recebido',
              child: _HorizontalBars(data: payments),
            );
            if (!wide) {
              return Column(
                children: [
                  productCard,
                  const SizedBox(height: 12),
                  paymentCard,
                ],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: productCard),
                const SizedBox(width: 12),
                Expanded(child: paymentCard),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _ComparisonKpi extends StatelessWidget {
  const _ComparisonKpi({
    required this.label,
    required this.value,
    required this.icon,
    this.variation,
  });

  final String label;
  final String value;
  final IconData icon;
  final double? variation;

  @override
  Widget build(BuildContext context) {
    final change = variation;
    final positive = (change ?? 0) >= 0;
    return AppCard(
      child: Row(
        children: [
          CircleAvatar(child: Icon(icon)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 3),
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (change != null)
                  Text(
                    '${positive ? '+' : ''}${change.toStringAsFixed(1).replaceAll('.', ',')}% vs. período anterior',
                    style: TextStyle(
                      color: positive
                          ? const Color(0xFF047857)
                          : const Color(0xFFB91C1C),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
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

class _ChartCard extends StatelessWidget {
  const _ChartCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 16),
          SizedBox(height: 260, child: child),
        ],
      ),
    );
  }
}

class _ChartValue {
  const _ChartValue(this.label, this.value);

  final String label;
  final double value;
}

class _ColumnChart extends StatelessWidget {
  const _ColumnChart({required this.data});

  final List<_ChartValue> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) {
      return const Center(child: Text('Sem vendas no período.'));
    }
    final maxValue = data.fold<double>(
      0,
      (max, item) => item.value > max ? item.value : max,
    );
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (final item in data)
          Expanded(
            child: Tooltip(
              message: '${item.label}: ${_money(item.value)}',
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      _compactMoney(item.value),
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontSize: 9),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: maxValue <= 0
                          ? 2
                          : 190 * (item.value / maxValue).clamp(0.02, 1),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      item.label,
                      maxLines: 1,
                      overflow: TextOverflow.fade,
                      style: const TextStyle(fontSize: 9),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _HorizontalBars extends StatelessWidget {
  const _HorizontalBars({required this.data});

  final List<_ChartValue> data;

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const Center(child: Text('Sem dados no período.'));
    final maxValue = data.fold<double>(
      0,
      (max, item) => item.value > max ? item.value : max,
    );
    return ListView.separated(
      physics: const NeverScrollableScrollPhysics(),
      itemCount: data.length.clamp(0, 8),
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) {
        final item = data[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  _compactMoney(item.value),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ],
            ),
            const SizedBox(height: 3),
            LinearProgressIndicator(
              value: maxValue <= 0 ? 0 : item.value / maxValue,
              minHeight: 8,
              borderRadius: BorderRadius.circular(8),
              color: const Color(0xFF0F766E),
              backgroundColor: const Color(0xFFE2E8F0),
            ),
          ],
        );
      },
    );
  }
}

class _ReportRow {
  const _ReportRow(this.values);
  final List<String> values;
}

class _Category {
  const _Category(this.key, this.label, this.icon);
  final String key;
  final String label;
  final IconData icon;
}

class _KpiCard extends StatelessWidget {
  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF2563EB)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 3),
                Text(
                  value,
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
    );
  }
}

class _ReportButton extends StatelessWidget {
  const _ReportButton({required this.report, required this.onTap});

  final _ReportData report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        constraints: const BoxConstraints(minHeight: 112),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.analytics_outlined, color: Color(0xFF2563EB)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    report.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF64748B)),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              report.description,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 8),
            Text(
              '${report.rows.length} registro(s)',
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline, color: Color(0xFF1D4ED8)),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

List<MapEntry<String, double>> _sortedEntries(Map<String, double> values) {
  return values.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
}

double _salesTotal(List<Sale> sales) =>
    sales.fold<double>(0, (sum, sale) => sum + sale.totalAmount);

double? _variation(double current, double previous) {
  if (previous == 0) return current == 0 ? 0 : null;
  return ((current - previous) / previous) * 100;
}

List<_ChartValue> _salesTrend(
  List<Sale> sales,
  DateTime dateFrom,
  DateTime dateTo,
) {
  final days = _day(dateTo).difference(_day(dateFrom)).inDays + 1;
  final values = <String, double>{};
  String keyFor(DateTime value) {
    if (days > 93) {
      return '${value.month.toString().padLeft(2, '0')}/${value.year}';
    }
    if (days > 31) {
      final start = _day(
        value,
      ).subtract(Duration(days: _day(value).weekday - DateTime.monday));
      return '${start.day.toString().padLeft(2, '0')}/${start.month.toString().padLeft(2, '0')}';
    }
    return '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}';
  }

  final orderedSales = [...sales]..sort((a, b) => a.soldAt.compareTo(b.soldAt));
  for (final sale in orderedSales) {
    final key = keyFor(sale.soldAt);
    values[key] = (values[key] ?? 0) + sale.totalAmount;
  }
  return [
    for (final entry in values.entries) _ChartValue(entry.key, entry.value),
  ];
}

List<_ChartValue> _weekdaySales(List<Sale> sales) {
  const labels = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];
  final totals = List<double>.filled(7, 0);
  for (final sale in sales) {
    totals[sale.soldAt.weekday - 1] += sale.totalAmount;
  }
  return [
    for (var index = 0; index < labels.length; index++)
      _ChartValue(labels[index], totals[index]),
  ];
}

List<_ChartValue> _topProductSales(List<Sale> sales) {
  final totals = <String, double>{};
  for (final sale in sales.where((sale) => sale.status != 'cancelada')) {
    for (final item in sale.items) {
      totals[item.description] =
          (totals[item.description] ?? 0) + item.totalPrice;
    }
  }
  return [
    for (final entry in _sortedEntries(totals).take(8))
      _ChartValue(entry.key, entry.value),
  ];
}

List<_ChartValue> _paymentSales(List<Sale> sales) {
  final totals = <String, double>{};
  for (final sale in sales.where((sale) => sale.status != 'cancelada')) {
    for (final payment in sale.payments) {
      totals[_paymentLabel(payment.method)] =
          (totals[_paymentLabel(payment.method)] ?? 0) + payment.amount;
    }
  }
  return [
    for (final entry in _sortedEntries(totals))
      _ChartValue(entry.key, entry.value),
  ];
}

List<_ReportRow> _sortedMapRows(
  Map<String, double> totals,
  Map<String, double> quantities,
) {
  return [
    for (final entry in _sortedEntries(totals))
      _ReportRow([
        entry.key,
        _number(quantities[entry.key] ?? 0),
        _money(entry.value),
      ]),
  ];
}

int? _daysUntil(String? value, DateTime today) {
  if (value == null || value.isEmpty) return null;
  final date = DateTime.tryParse(value);
  if (date == null) return null;
  return DateTime(
    date.year,
    date.month,
    date.day,
  ).difference(DateTime(today.year, today.month, today.day)).inDays;
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';
String _number(double value) => formatBrazilianDecimal(value);
String _compactMoney(double value) {
  if (value.abs() >= 1000000) {
    return 'R\$ ${(value / 1000000).toStringAsFixed(1).replaceAll('.', ',')} mi';
  }
  if (value.abs() >= 1000) {
    return 'R\$ ${(value / 1000).toStringAsFixed(1).replaceAll('.', ',')} mil';
  }
  return _money(value);
}

String _date(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
String _dateTime(DateTime value) =>
    '${_date(value)} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _dateNullable(DateTime? value) => value == null ? '-' : _date(value);
DateTime _day(DateTime value) => DateTime(value.year, value.month, value.day);
bool _sameDay(DateTime a, DateTime b) => _day(a) == _day(b);

String _paymentLabel(String method) {
  return switch (method) {
    'dinheiro' => 'Dinheiro',
    'pix' => 'Pix',
    'debito' => 'Débito',
    'credito' => 'Crédito',
    'crediario' => 'Crediário',
    'transferencia' => 'Transferência',
    _ => method,
  };
}

String _filterLabel(String key) {
  return switch (key) {
    'stock_position' => 'Filtrar por produto, código, barras ou validade',
    'stock_low' => 'Filtrar por produto ou código',
    'stock_expiring' ||
    'stock_expired' => 'Filtrar por produto, lote ou validade',
    'stock_withdrawals' =>
      'Filtrar por produto, motivo, responsável ou observação',
    'sales_dashboard' => 'Filtrar indicadores do painel',
    'sales_period' => 'Filtrar por data, número, origem ou status',
    'sales_products' => 'Filtrar por produto',
    'sales_payments' => 'Filtrar por forma de pagamento',
    'receivables_open' || 'receivable_aging' => 'Filtrar por cliente ou titulo',
    'payables_open' => 'Filtrar por fornecedor, categoria ou titulo',
    'entries_recent' ||
    'entries_supplier' => 'Filtrar por fornecedor, NF ou origem',
    'entries_pending' => 'Filtrar por fornecedor, NF, produto ou status',
    'cash_closings' => 'Filtrar por data, operador ou status',
    'clients_credit' ||
    'clients_register' => 'Filtrar por cliente, documento ou cidade',
    _ => 'Filtrar no relatorio',
  };
}

String _todayFile() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}

String _normalize(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'õ': 'o',
    'ô': 'o',
    'ú': 'u',
    'ç': 'c',
  };
  var normalized = value.toLowerCase().trim();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}
