import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/session.dart';
import '../models/stock_entry.dart';
import '../models/supplier.dart';
import '../services/api_client.dart';

/// Staged manual receiving. Stock is only affected by the later confirmation.
class ManualReceivingScreen extends StatefulWidget {
  const ManualReceivingScreen({super.key, required this.session});
  final Session session;
  @override
  State<ManualReceivingScreen> createState() => _ManualReceivingScreenState();
}

class _ManualReceivingScreenState extends State<ManualReceivingScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _invoice = TextEditingController(),
      _series = TextEditingController(),
      _key = TextEditingController();
  final _operation = TextEditingController(text: 'Compra para revenda'),
      _notes = TextEditingController();
  final _freight = TextEditingController(text: '0,00'),
      _insurance = TextEditingController(text: '0,00');
  final _discount = TextEditingController(text: '0,00'),
      _other = TextEditingController(text: '0,00');
  final _declared = TextEditingController(),
      _transportName = TextEditingController(),
      _transportDoc = TextEditingController();
  final _plate = TextEditingController(),
      _uf = TextEditingController(),
      _volumes = TextEditingController(),
      _orderNumber = TextEditingController();
  List<Product> _products = const [];
  List<Supplier> _suppliers = const [];
  List<_Line> _lines = [];
  int? _supplierId;
  int _step = 0;
  bool _withoutTransport = true,
      _withoutOrder = true,
      _loading = true,
      _saving = false;
  String? _error;
  String? _duplicateNotice;
  Timer? _lookupTimer;
  static const _steps = [
    'Documento',
    'Valores',
    'Transporte',
    'Pedido',
    'Produtos',
    'Totalização',
    'Conferência',
    'Revisão',
  ];

  @override
  void initState() {
    super.initState();
    _lines = [_Line()];
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await Future.wait([
        _api.listProducts(widget.session.token, active: true),
        _api.listSuppliers(widget.session.token),
      ]);
      if (!mounted) return;
      setState(() {
        _products = (result[0] as List<Product>)
            .where((p) => p.productType != 'servico')
            .toList();
        _suppliers = (result[1] as List<Supplier>)
            .where((s) => s.active)
            .toList();
        _loading = false;
      });
    } on ApiException catch (e) {
      if (mounted)
        setState(() {
          _error = e.message;
          _loading = false;
        });
    }
  }

  Future<void> _checkExistingNumber(String value) async {
    _lookupTimer?.cancel();
    final number = value.trim();
    if (number.isEmpty) {
      if (mounted) setState(() => _duplicateNotice = null);
      return;
    }
    _lookupTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final result = await Future.wait([
          _api.findStockReceiptsByNumber(widget.session.token, number),
          _api.listXmlInboxMessages(widget.session.token, limit: 100),
        ]);
        final entries = result[0] as List<StockEntry>;
        final xmlMessages = (result[1] as List<XmlInboxMessage>)
            .where(
              (message) =>
                  message.invoiceNumber?.trim().toLowerCase() ==
                      number.toLowerCase() &&
                  message.status != 'rejected',
            )
            .toList();
        if (!mounted || _invoice.text.trim() != number) return;
        if (entries.isEmpty && xmlMessages.isEmpty) {
          setState(() => _duplicateNotice = null);
          return;
        }
        if (entries.isEmpty && xmlMessages.isNotEmpty) {
          setState(
            () => _duplicateNotice =
                'A nota $number já está aguardando na Caixa de XML (${xmlMessages.first.status}).',
          );
          return;
        }
        final entry = entries.first;
        final status = switch (entry.status) {
          'confirmed' => 'já foi confirmada',
          'receiving' => 'está aguardando conferência',
          'draft' => 'está salva como rascunho',
          _ => 'já está registrada',
        };
        setState(
          () => _duplicateNotice =
              'A nota $number $status (entrada #${entry.id}, origem ${entry.source}).',
        );
      } on ApiException {
        // A consulta preventiva não impede o lançamento se estiver indisponível.
      }
    });
  }

  @override
  void dispose() {
    _lookupTimer?.cancel();
    for (final c in [
      _invoice,
      _series,
      _key,
      _operation,
      _notes,
      _freight,
      _insurance,
      _discount,
      _other,
      _declared,
      _transportName,
      _transportDoc,
      _plate,
      _uf,
      _volumes,
      _orderNumber,
    ])
      c.dispose();
    for (final l in _lines) l.dispose();
    super.dispose();
  }

  double _n(String value) =>
      double.tryParse(value.trim().replaceAll('.', '').replaceAll(',', '.')) ??
      0;
  double get _productsTotal =>
      _lines.fold(0, (sum, l) => sum + _n(l.qty.text) * _n(l.cost.text));
  double get _total =>
      _productsTotal +
      _n(_freight.text) +
      _n(_insurance.text) +
      _n(_other.text) -
      _n(_discount.text);
  String _money(double v) => 'R\$ ${v.toStringAsFixed(2).replaceAll('.', ',')}';

  bool _valid() {
    String? error;
    if (_step == 0 && (_supplierId == null || _invoice.text.trim().isEmpty))
      error = 'Informe fornecedor e número do documento.';
    if ((_step == 4 || _step == 6 || _step == 7) &&
        (_lines.isEmpty ||
            _lines.any((l) => l.productId == null || _n(l.qty.text) <= 0)))
      error = 'Informe produto e quantidade válida em todos os itens.';
    if (_step == 5 &&
        _declared.text.trim().isNotEmpty &&
        (_n(_declared.text) - _total).abs() > .01)
      error = 'O total informado difere do calculado. Revise os valores.';
    if (error != null) setState(() => _error = error);
    return error == null;
  }

  void _next() {
    if (!_valid()) return;
    if (_step < 7)
      setState(() {
        _step++;
        _error = null;
      });
  }

  void _back() {
    if (_step > 0)
      setState(() {
        _step--;
        _error = null;
      });
  }

  bool _allValid() {
    final old = _step;
    for (var i = 0; i < 8; i++) {
      _step = i;
      if (!_valid()) {
        setState(() {});
        return false;
      }
    }
    _step = old;
    return true;
  }

  StockEntryPayload _payload() {
    final supplier = _suppliers.where((s) => s.id == _supplierId).firstOrNull;
    final notes = jsonEncode({
      'manual_receiving_version': 1,
      'step': _step + 1,
      'operation': _operation.text.trim(),
      'declared_total': _n(_declared.text),
      'calculated_total': _total,
      'values': {
        'freight': _n(_freight.text),
        'insurance': _n(_insurance.text),
        'discount': _n(_discount.text),
        'other_expenses': _n(_other.text),
      },
      'transport': {
        'without_transport': _withoutTransport,
        'name': _transportName.text.trim(),
        'document': _transportDoc.text.trim(),
        'plate': _plate.text.trim(),
        'uf': _uf.text.trim(),
        'volumes': _volumes.text.trim(),
      },
      'purchase_order': _withoutOrder ? null : _orderNumber.text.trim(),
      'note': _notes.text.trim(),
    });
    final items = _lines.map((l) {
      final p = _products.firstWhere((p) => p.id == l.productId);
      final q = _n(l.qty.text), c = _n(l.cost.text);
      return StockEntryItem(
        productId: p.id,
        description: p.name,
        barcode: p.barcode,
        quantity: q,
        receivedQuantity: _n(l.received.text) == 0 ? q : _n(l.received.text),
        unit: p.unit,
        unitCost: c,
        totalCost: q * c,
        batchNumber: l.batch.text.trim().isEmpty ? null : l.batch.text.trim(),
        expirationDate: l.expiration.text.trim().isEmpty
            ? null
            : l.expiration.text.trim(),
      );
    }).toList();
    return StockEntryPayload(
      supplierId: supplier?.id,
      supplierName: supplier?.name,
      supplierDocument: supplier?.documentNumber,
      source: 'manual',
      invoiceKey: _key.text.trim().isEmpty ? null : _key.text.trim(),
      invoiceNumber: _invoice.text.trim(),
      invoiceSeries: _series.text.trim().isEmpty ? null : _series.text.trim(),
      notes: notes,
      items: items,
    );
  }

  Future<void> _save({required bool draft}) async {
    if (!_allValid()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final p = _payload();
      final entry = draft
          ? await _api.createDraftStockEntry(widget.session.token, p)
          : await _api.createOpenStockEntry(widget.session.token, p);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            draft
                ? 'Rascunho #${entry.id} salvo. Nenhum estoque foi alterado.'
                : 'Entrada #${entry.id} enviada para conferência.',
          ),
        ),
      );
      Navigator.pop(context, entry);
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text('Nova entrada manual'),
        backgroundColor: const Color(0xfff6f8fb),
        foregroundColor: const Color(0xff172b4d),
        elevation: 0,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, c) => SingleChildScrollView(
                padding: EdgeInsets.all(c.maxWidth > 900 ? 28 : 16),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1240),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Recebimento manual',
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w700,
                            color: Color(0xff172b4d),
                          ),
                        ),
                        const SizedBox(height: 4),
                        const Text(
                          'Registre, confira e só depois envie para conferência. O estoque não é alterado neste fluxo.',
                          style: TextStyle(color: Color(0xff64748b)),
                        ),
                        const SizedBox(height: 20),
                        _stepper(),
                        const SizedBox(height: 16),
                        Card(
                          elevation: 0,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _body(c.maxWidth > 900),
                          ),
                        ),
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              _error!,
                              style: const TextStyle(color: Color(0xffb42318)),
                            ),
                          ),
                        const SizedBox(height: 18),
                        _actions(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _stepper() => Wrap(
    spacing: 6,
    runSpacing: 6,
    children: _steps
        .asMap()
        .entries
        .map(
          (e) => ChoiceChip(
            label: Text('${e.key + 1}. ${e.value}'),
            selected: e.key == _step,
            onSelected: (_) =>
                e.key <= _step ? setState(() => _step = e.key) : null,
            selectedColor: const Color(0xffd9f0f3),
          ),
        )
        .toList(),
  );
  Widget _body(bool wide) {
    switch (_step) {
      case 0:
        return _document(wide);
      case 1:
        return _values(wide);
      case 2:
        return _transport(wide);
      case 3:
        return _order(wide);
      case 4:
        return _items(wide, false);
      case 5:
        return _totals();
      case 6:
        return _items(wide, true);
      default:
        return _review();
    }
  }

  Widget _section(String title, String subtitle, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        title,
        style: const TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: Color(0xff172b4d),
        ),
      ),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: Color(0xff64748b))),
      const SizedBox(height: 18),
      child,
    ],
  );
  Widget _field(
    TextEditingController c,
    String label, {
    double width = 220,
    bool number = false,
    ValueChanged<String>? onChanged,
  }) => SizedBox(
    width: width,
    child: TextField(
      controller: c,
      onChanged: onChanged,
      keyboardType: number ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    ),
  );
  Widget _document(bool wide) => _section(
    'Documento e fornecedor',
    'Identifique a compra antes dos valores.',
    Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(
          width: wide ? 320 : double.infinity,
          child: DropdownButtonFormField<int>(
            initialValue: _supplierId,
            decoration: const InputDecoration(
              labelText: 'Fornecedor *',
              border: OutlineInputBorder(),
            ),
            items: _suppliers
                .map(
                  (s) => DropdownMenuItem(
                    value: s.id,
                    child: Text(s.name, overflow: TextOverflow.ellipsis),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => _supplierId = v),
          ),
        ),
        _field(
          _invoice,
          'Número do documento *',
          width: wide ? 220 : double.infinity,
          onChanged: _checkExistingNumber,
        ),
        _field(_series, 'Série', width: wide ? 120 : double.infinity),
        _field(
          _key,
          'Chave NF-e (44 dígitos)',
          width: wide ? 350 : double.infinity,
        ),
        _field(
          _operation,
          'Natureza da operação',
          width: wide ? 300 : double.infinity,
        ),
        _field(_notes, 'Observação', width: wide ? 450 : double.infinity),
        if (_duplicateNotice != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xfffff4e5),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xffffb020)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xffb54708),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _duplicateNotice!,
                    style: const TextStyle(color: Color(0xff8a3b12)),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
  Widget _values(bool wide) => _section(
    'Valores da operação',
    'Declarado e calculado ficam separados; divergências não são ajustadas automaticamente.',
    Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _readout('Produtos calculados', _money(_productsTotal), wide),
        _field(_freight, 'Frete', width: 160, number: true),
        _field(_insurance, 'Seguro', width: 160, number: true),
        _field(_discount, 'Desconto', width: 160, number: true),
        _field(_other, 'Outras despesas', width: 180, number: true),
        _field(_declared, 'Total informado', width: 180, number: true),
      ],
    ),
  );
  Widget _transport(bool wide) => _section(
    'Transporte',
    'Informe apenas quando houver transportador.',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Sem transporte'),
          value: _withoutTransport,
          onChanged: (v) => setState(() => _withoutTransport = v),
        ),
        if (!_withoutTransport)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _field(
                _transportName,
                'Transportador',
                width: wide ? 300 : double.infinity,
              ),
              _field(_transportDoc, 'CNPJ/CPF', width: 200),
              _field(_plate, 'Placa', width: 120),
              _field(_uf, 'UF', width: 90),
              _field(_volumes, 'Volumes', width: 120, number: true),
            ],
          ),
      ],
    ),
  );
  Widget _order(bool wide) => _section(
    'Pedido de compra',
    'Vincule o pedido para comparar solicitado x recebido.',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Continuar sem pedido de compra'),
          value: _withoutOrder,
          onChanged: (v) => setState(() => _withoutOrder = v),
        ),
        if (!_withoutOrder)
          _field(
            _orderNumber,
            'Número do pedido',
            width: wide ? 280 : double.infinity,
          ),
      ],
    ),
  );
  Widget _items(bool wide, bool conference) => _section(
    conference ? 'Conferência física' : 'Produtos recebidos',
    conference
        ? 'Compare documento e quantidade realmente recebida. Ainda não movimenta estoque.'
        : 'Selecione produtos existentes; nenhum produto é criado automaticamente.',
    Column(
      children: [
        ..._lines.asMap().entries.map(
          (e) => _line(e.key, e.value, wide, conference),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton.icon(
            onPressed: () => setState(() => _lines.add(_Line())),
            icon: const Icon(Icons.add),
            label: const Text('Adicionar item'),
          ),
        ),
      ],
    ),
  );
  Widget _line(int index, _Line l, bool wide, bool conference) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: wide ? 330 : double.infinity,
          child: DropdownButtonFormField<int>(
            initialValue: l.productId,
            decoration: const InputDecoration(
              labelText: 'Produto *',
              border: OutlineInputBorder(),
            ),
            items: _products
                .map(
                  (p) => DropdownMenuItem(
                    value: p.id,
                    child: Text(
                      '${p.name}${p.internalCode == null ? '' : ' • ${p.internalCode}'}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                )
                .toList(),
            onChanged: (v) => setState(() => l.productId = v),
          ),
        ),
        _field(
          l.qty,
          conference ? 'Qtd. documento' : 'Quantidade *',
          width: 140,
          number: true,
        ),
        _field(l.cost, 'Custo unitário', width: 150, number: true),
        if (conference)
          _field(l.received, 'Qtd. recebida', width: 145, number: true),
        _field(l.batch, 'Lote', width: 145),
        _field(l.expiration, 'Validade', width: 145),
        IconButton(
          tooltip: 'Remover item',
          onPressed: _lines.length == 1
              ? null
              : () => setState(() {
                  final r = _lines.removeAt(index);
                  r.dispose();
                }),
          icon: const Icon(Icons.delete_outline),
        ),
      ],
    ),
  );
  Widget _totals() => _section(
    'Totalização',
    'Revise os números antes da conferência.',
    Column(
      children: [
        _row('Produtos', _money(_productsTotal)),
        _row(
          'Acréscimos',
          _money(_n(_freight.text) + _n(_insurance.text) + _n(_other.text)),
        ),
        _row('Descontos', _money(_n(_discount.text))),
        const Divider(),
        _row('Total calculado', _money(_total), strong: true),
        _row(
          'Total informado',
          _declared.text.trim().isEmpty
              ? 'Não informado'
              : _money(_n(_declared.text)),
        ),
        if (_declared.text.trim().isNotEmpty)
          Text(
            'Diferença: ${_money(_n(_declared.text) - _total)}',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: (_n(_declared.text) - _total).abs() > .01
                  ? Colors.red
                  : Colors.green,
            ),
          ),
      ],
    ),
  );
  Widget _review() => _section(
    'Revisão',
    'Confira o impacto antes de enviar.',
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Fornecedor: ${_suppliers.where((s) => s.id == _supplierId).firstOrNull?.name ?? '-'}',
        ),
        Text('Documento: ${_invoice.text} • Itens: ${_lines.length}'),
        Text('Total calculado: ${_money(_total)}'),
        const SizedBox(height: 12),
        const Text(
          'A entrada ficará aguardando conferência. Estoque, custo médio, lotes e financeiro só serão processados na confirmação.',
          style: TextStyle(color: Color(0xff475569)),
        ),
      ],
    ),
  );
  Widget _actions() => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      OutlinedButton(
        onPressed: _saving ? null : () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      const SizedBox(width: 8),
      OutlinedButton(
        onPressed: _saving ? null : () => _save(draft: true),
        child: const Text('Salvar rascunho'),
      ),
      const SizedBox(width: 8),
      if (_step > 0)
        OutlinedButton(
          onPressed: _saving ? null : _back,
          child: const Text('Voltar'),
        ),
      const SizedBox(width: 8),
      FilledButton.icon(
        onPressed: _saving
            ? null
            : (_step == 7 ? () => _save(draft: false) : _next),
        icon: Icon(_step == 7 ? Icons.send_outlined : Icons.arrow_forward),
        label: Text(
          _saving
              ? 'Salvando...'
              : _step == 7
              ? 'Enviar para conferência'
              : 'Continuar',
        ),
      ),
    ],
  );
  Widget _readout(String label, String value, bool wide) => SizedBox(
    width: wide ? 220 : double.infinity,
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
    ),
  );
  Widget _row(String label, String value, {bool strong = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: strong ? FontWeight.w700 : FontWeight.normal,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontWeight: strong ? FontWeight.w700 : FontWeight.normal,
          ),
        ),
      ],
    ),
  );
}

class _Line {
  int? productId;
  final qty = TextEditingController(text: '1'),
      received = TextEditingController(),
      cost = TextEditingController(text: '0,00'),
      batch = TextEditingController(),
      expiration = TextEditingController();
  void dispose() {
    qty.dispose();
    received.dispose();
    cost.dispose();
    batch.dispose();
    expiration.dispose();
  }
}
