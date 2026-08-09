import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../models/stock_movement.dart';
import '../services/api_client.dart';
import '../services/file_download.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _withdrawalReasons = {
  'loss_damage': 'Perda ou avaria',
  'expired': 'Produto vencido',
  'internal_consumption': 'Consumo interno',
  'employee_meal': 'Alimentação da equipe',
  'production_use': 'Uso na produção',
  'sample_gift': 'Amostra ou brinde',
  'theft': 'Furto ou desaparecimento',
  'inventory_adjustment': 'Ajuste de inventário',
  'other': 'Outros',
};

class StockWithdrawalsScreen extends StatefulWidget {
  const StockWithdrawalsScreen({super.key, required this.session});

  final Session session;

  @override
  State<StockWithdrawalsScreen> createState() => _StockWithdrawalsScreenState();
}

class _StockWithdrawalsScreenState extends State<StockWithdrawalsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _code = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _notes = TextEditingController();
  final _historySearch = TextEditingController();
  List<Product> _products = [];
  List<StockMovement> _withdrawals = [];
  Product? _selectedProduct;
  String _reasonCode = 'loss_damage';
  String _historyReason = 'todos';
  DateTime _dateFrom = DateTime(DateTime.now().year, DateTime.now().month, 1);
  DateTime _dateTo = DateTime.now();
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _code.dispose();
    _quantity.dispose();
    _notes.dispose();
    _historySearch.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listProducts(widget.session.token),
        _api.listRecentStockWithdrawals(
          widget.session.token,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
        ),
      ]);
      if (!mounted) return;
      setState(() {
        _products = (results[0] as List<Product>)
            .where(
              (product) => product.active && product.productType != 'servico',
            )
            .toList();
        _withdrawals = results[1] as List<StockMovement>;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar as baixas.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<StockMovement> get _filteredWithdrawals {
    final term = _historySearch.text.trim().toLowerCase();
    return _withdrawals.where((movement) {
      if (_historyReason != 'todos' &&
          movement.reason != _withdrawalReasons[_historyReason]) {
        return false;
      }
      if (term.isEmpty) return true;
      return [
        movement.productName,
        movement.userName,
        movement.reason,
        movement.notes,
        movement.sourceNumber,
      ].whereType<String>().join(' ').toLowerCase().contains(term);
    }).toList();
  }

  Future<void> _selectDate({required bool from}) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: from ? _dateFrom : _dateTo,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 1)),
      helpText: from ? 'Data inicial' : 'Data final',
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (from) {
        _dateFrom = selected;
        if (_dateTo.isBefore(selected)) _dateTo = selected;
      } else {
        _dateTo = selected;
        if (_dateFrom.isAfter(selected)) _dateFrom = selected;
      }
    });
    await _load();
  }

  Product? _productById(int id) {
    for (final product in _products) {
      if (product.id == id) return product;
    }
    return null;
  }

  void _exportReport() {
    final rows = _filteredWithdrawals;
    final quantity = rows.fold<double>(
      0,
      (sum, item) => sum + item.quantityDelta.abs(),
    );
    final value = rows.fold<double>(
      0,
      (sum, item) => sum + (item.totalValue ?? 0),
    );
    final content = [
      'RELATORIO DE BAIXAS DE ESTOQUE',
      'Periodo;${_date(_dateFrom)} a ${_date(_dateTo)}',
      'Registros;${rows.length}',
      'Quantidade total;${_number(quantity)}',
      'Impacto a custo;${_money(value)}',
      '',
      'Data;Produto;Codigo;Motivo;Quantidade;Unidade;Custo unitario;Impacto a custo;Responsavel;Observacoes;Saldo antes;Saldo depois;Origem',
      for (final movement in rows)
        [
          _dateTime(movement.createdAt),
          movement.productName ?? '-',
          _productById(movement.productId)?.internalCode ?? '-',
          movement.reason ?? '-',
          _number(movement.quantityDelta.abs()),
          movement.unit,
          _money(movement.unitPrice ?? 0),
          _money(movement.totalValue ?? 0),
          movement.userName ?? 'Usuario removido',
          movement.notes ?? '',
          _number(movement.quantityBefore),
          _number(movement.quantityAfter),
          _sourceLabel(movement.sourceType, movement.sourceNumber),
        ].map(_csvCell).join(';'),
    ].join('\r\n');
    downloadTextFile(
      filename:
          'relatorio_baixas_${_fileDate(_dateFrom)}_${_fileDate(_dateTo)}.csv',
      content: '\uFEFF$content',
      mimeType: 'text/csv;charset=utf-8',
    );
  }

  Future<void> _lookupCode() async {
    final code = _code.text.trim();
    if (code.isEmpty) return;
    setState(() => _error = null);
    try {
      final product = await _api.lookupProductByCode(
        widget.session.token,
        code,
      );
      if (!mounted) return;
      if (product.productType == 'servico') {
        setState(() => _error = 'Serviços não possuem saldo de estoque.');
        return;
      }
      setState(() => _selectedProduct = product);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _chooseProduct() async {
    final product = await showDialog<Product>(
      context: context,
      builder: (context) => _ProductPickerDialog(products: _products),
    );
    if (product == null || !mounted) return;
    setState(() {
      _selectedProduct = product;
      _code.text = product.barcode ?? product.internalCode ?? '';
    });
  }

  Future<void> _submit() async {
    final product = _selectedProduct;
    final quantity = parseBrazilianNumber(_quantity.text);
    final notes = _notes.text.trim();
    if (product == null) {
      setState(() => _error = 'Selecione ou leia o código de um produto.');
      return;
    }
    if (quantity <= 0) {
      setState(() => _error = 'Informe uma quantidade maior que zero.');
      return;
    }
    if (_reasonCode == 'other' && notes.length < 5) {
      setState(() => _error = 'Explique o motivo da baixa em Observações.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.createStockWithdrawal(
        widget.session.token,
        productId: product.id,
        quantity: quantity,
        reasonCode: _reasonCode,
        notes: notes.isEmpty ? null : notes,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Baixa registrada para ${product.name}. Responsável: usuário logado.',
          ),
        ),
      );
      setState(() {
        _selectedProduct = null;
        _code.clear();
        _quantity.text = '1';
        _notes.clear();
      });
      await _load();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível registrar a baixa.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredWithdrawals;
    final totalQuantity = filtered.fold<double>(
      0,
      (sum, item) => sum + item.quantityDelta.abs(),
    );
    final totalValue = filtered.fold<double>(
      0,
      (sum, item) => sum + (item.totalValue ?? 0),
    );
    final reasonTotals = <String, double>{};
    for (final movement in filtered) {
      final reason = movement.reason ?? 'Sem motivo';
      reasonTotals[reason] =
          (reasonTotals[reason] ?? 0) + movement.quantityDelta.abs();
    }
    final rankedReasons = reasonTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
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
                        'Baixas de estoque',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Perdas, vencimentos, consumo interno e outras saídas identificadas',
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
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null) ...[
              ErrorPanel(message: _error!, onRetry: _load),
              const SizedBox(height: 14),
            ],
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Registrar baixa',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'O responsável será preenchido automaticamente com o usuário conectado.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final wide = constraints.maxWidth >= 850;
                      final codeField = TextField(
                        controller: _code,
                        textInputAction: TextInputAction.search,
                        onSubmitted: (_) => _lookupCode(),
                        decoration: InputDecoration(
                          labelText: 'Código de barras ou código interno',
                          prefixIcon: const Icon(Icons.qr_code_scanner),
                          suffixIcon: IconButton(
                            tooltip: 'Localizar código',
                            onPressed: _lookupCode,
                            icon: const Icon(Icons.search),
                          ),
                        ),
                      );
                      final chooseButton = OutlinedButton.icon(
                        onPressed: _chooseProduct,
                        icon: const Icon(Icons.inventory_2_outlined),
                        label: const Text('Escolher produto'),
                      );
                      if (!wide) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            codeField,
                            const SizedBox(height: 10),
                            chooseButton,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: codeField),
                          const SizedBox(width: 12),
                          chooseButton,
                        ],
                      );
                    },
                  ),
                  if (_selectedProduct != null) ...[
                    const SizedBox(height: 14),
                    _SelectedProductCard(product: _selectedProduct!),
                  ],
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final width = constraints.maxWidth >= 760
                          ? (constraints.maxWidth - 24) / 3
                          : constraints.maxWidth;
                      return Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          SizedBox(
                            width: width,
                            child: TextField(
                              controller: _quantity,
                              inputFormatters: const [
                                BrazilianDecimalInputFormatter(),
                              ],
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                              decoration: InputDecoration(
                                labelText: 'Quantidade',
                                suffixText: _selectedProduct?.unit,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: DropdownButtonFormField<String>(
                              initialValue: _reasonCode,
                              decoration: const InputDecoration(
                                labelText: 'Motivo',
                              ),
                              items: [
                                for (final reason in _withdrawalReasons.entries)
                                  DropdownMenuItem(
                                    value: reason.key,
                                    child: Text(reason.value),
                                  ),
                              ],
                              onChanged: (value) => setState(
                                () => _reasonCode = value ?? 'loss_damage',
                              ),
                            ),
                          ),
                          SizedBox(
                            width: width,
                            child: TextField(
                              controller: _notes,
                              maxLength: 1000,
                              decoration: InputDecoration(
                                labelText: _reasonCode == 'other'
                                    ? 'Observações (obrigatório)'
                                    : 'Observações',
                                counterText: '',
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: const Icon(Icons.remove_circle_outline),
                      label: Text(_saving ? 'Registrando...' : 'Dar baixa'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                'Consulta e relatório de baixas',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: filtered.isEmpty
                                  ? null
                                  : _exportReport,
                              icon: const Icon(Icons.download_outlined),
                              label: const Text('Exportar relatório'),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            SizedBox(
                              width: 320,
                              child: TextField(
                                controller: _historySearch,
                                onChanged: (_) => setState(() {}),
                                decoration: const InputDecoration(
                                  labelText: 'Pesquisar baixas',
                                  hintText:
                                      'Produto, responsável, motivo ou observação',
                                  prefixIcon: Icon(Icons.search),
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _selectDate(from: true),
                              icon: const Icon(Icons.calendar_month_outlined),
                              label: Text('De ${_date(_dateFrom)}'),
                            ),
                            OutlinedButton.icon(
                              onPressed: () => _selectDate(from: false),
                              icon: const Icon(Icons.event_outlined),
                              label: Text('Até ${_date(_dateTo)}'),
                            ),
                            SizedBox(
                              width: 230,
                              child: DropdownButtonFormField<String>(
                                initialValue: _historyReason,
                                decoration: const InputDecoration(
                                  labelText: 'Motivo',
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: 'todos',
                                    child: Text('Todos os motivos'),
                                  ),
                                  for (final reason
                                      in _withdrawalReasons.entries)
                                    DropdownMenuItem(
                                      value: reason.key,
                                      child: Text(reason.value),
                                    ),
                                ],
                                onChanged: (value) => setState(
                                  () => _historyReason = value ?? 'todos',
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 14),
                        Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: [
                            _ReportMetric(
                              label: 'Lançamentos',
                              value: '${filtered.length}',
                              icon: Icons.receipt_long_outlined,
                            ),
                            _ReportMetric(
                              label: 'Quantidade baixada',
                              value: _number(totalQuantity),
                              icon: Icons.remove_shopping_cart_outlined,
                            ),
                            _ReportMetric(
                              label: 'Impacto a custo',
                              value: _money(totalValue),
                              icon: Icons.payments_outlined,
                            ),
                            _ReportMetric(
                              label: 'Principal motivo',
                              value: rankedReasons.isEmpty
                                  ? '-'
                                  : rankedReasons.first.key,
                              icon: Icons.analytics_outlined,
                            ),
                          ],
                        ),
                        if (rankedReasons.isNotEmpty) ...[
                          const SizedBox(height: 16),
                          const Text(
                            'Resumo por motivo',
                            style: TextStyle(fontWeight: FontWeight.w900),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final reason in rankedReasons)
                                Chip(
                                  label: Text(
                                    '${reason.key}: ${_number(reason.value)}',
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  if (_loading)
                    const LinearProgressIndicator()
                  else if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(22),
                      child: Text(
                        'Nenhuma baixa encontrada para os filtros informados.',
                      ),
                    )
                  else
                    for (final movement in filtered)
                      ListTile(
                        leading: const CircleAvatar(
                          child: Icon(Icons.remove_shopping_cart_outlined),
                        ),
                        title: Text(
                          '${movement.productName ?? 'Produto'} • ${movement.reason ?? '-'}',
                        ),
                        subtitle: Text(
                          '${_dateTime(movement.createdAt)} • ${movement.userName ?? 'Usuário removido'}'
                          '${movement.notes == null ? '' : '\n${movement.notes}'}',
                        ),
                        isThreeLine: movement.notes != null,
                        trailing: Text(
                          '${_number(movement.quantityDelta.abs())} ${movement.unit}',
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w900,
                          ),
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

class _SelectedProductCard extends StatelessWidget {
  const _SelectedProductCard({required this.product});

  final Product product;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFBFDBFE)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            const Icon(Icons.inventory_2_outlined, color: Color(0xFF1D4ED8)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    'Código ${product.internalCode ?? '-'} • EAN ${product.barcode ?? '-'}',
                    style: const TextStyle(color: Color(0xFF475569)),
                  ),
                ],
              ),
            ),
            Text(
              'Saldo ${_number(product.stockQuantity)} ${product.unit}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportMetric extends StatelessWidget {
  const _ReportMetric({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 220,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF135A77)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({required this.products});

  final List<Product> products;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.text.trim().toLowerCase();
    final products = widget.products
        .where((product) {
          if (term.isEmpty) return true;
          return [
            product.name,
            product.internalCode,
            product.barcode,
          ].whereType<String>().join(' ').toLowerCase().contains(term);
        })
        .take(100)
        .toList();
    return AlertDialog(
      title: const Text('Escolher produto'),
      content: SizedBox(
        width: 620,
        height: 480,
        child: Column(
          children: [
            TextField(
              controller: _search,
              autofocus: true,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'Nome, código ou código de barras',
                prefixIcon: Icon(Icons.search),
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return ListTile(
                    title: Text(product.name),
                    subtitle: Text(
                      '${product.internalCode ?? '-'} • ${product.barcode ?? '-'}',
                    ),
                    trailing: Text(
                      '${_number(product.stockQuantity)} ${product.unit}',
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
  }
}

String _number(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll('.', ',');
}

String _dateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} '
      '${two(value.hour)}:${two(value.minute)}';
}

String _date(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year}';
}

String _fileDate(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}${two(value.month)}${two(value.day)}';
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

String _sourceLabel(String? type, String? number) {
  final label = switch (type) {
    'stock_withdrawal' => 'Baixa de estoque',
    'stock_entry' => 'Entrada de estoque',
    'product_initial' => 'Saldo inicial',
    'production' => 'Produção',
    'venda' => 'Venda',
    'pdv' => 'PDV',
    'os' => 'OS',
    'service_contract' => 'Contrato',
    _ => 'Movimentação de estoque',
  };
  return number == null || number.isEmpty ? label : '$label $number';
}

String _csvCell(String value) {
  final escaped = value.replaceAll('"', '""');
  return '"$escaped"';
}
