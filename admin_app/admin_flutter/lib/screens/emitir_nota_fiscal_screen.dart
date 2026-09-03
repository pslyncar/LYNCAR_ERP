import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/client.dart';
import '../models/fiscal.dart';
import '../models/product.dart';
import '../models/session.dart';
import '../services/api_client.dart';

/// Conteúdo fiscal exibido dentro do [AppShell]. Não é uma rota/modal: o menu
/// lateral permanece disponível enquanto o usuário prepara a nota.
class EmitirNotaFiscalScreen extends StatefulWidget {
  const EmitirNotaFiscalScreen({
    super.key,
    required this.session,
    required this.onBack,
  });

  final Session session;
  final VoidCallback onBack;

  @override
  State<EmitirNotaFiscalScreen> createState() => _EmitirNotaFiscalScreenState();
}

class _EmitirNotaFiscalScreenState extends State<EmitirNotaFiscalScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _sale = TextEditingController();
  final _cpf = TextEditingController();
  final _notes = TextEditingController();
  final _freight = TextEditingController(text: '0,00');
  final _insurance = TextEditingController(text: '0,00');
  final _expenses = TextEditingController(text: '0,00');
  final _carrierName = TextEditingController();
  final _carrierDocument = TextEditingController();
  final _carrierIe = TextEditingController();
  final _carrierAddress = TextEditingController();
  final _carrierCity = TextEditingController();
  final _carrierUf = TextEditingController();
  final _volumeQuantity = TextEditingController();
  final _volumeSpecies = TextEditingController();
  final _volumeBrand = TextEditingController();
  final _volumeNumbering = TextEditingController();
  final _netWeight = TextEditingController();
  final _grossWeight = TextEditingController();
  String _type = 'nfe';
  String _freightMode = '9';
  String _finality = '1';
  String _payment = 'vista';
  String _nature = '';
  Client? _fiscalClient;
  List<Client> _clients = const [];
  List<Product> _products = const [];
  bool _saving = false;
  String? _error;
  final List<_ItemEditor> _items = [];

  static const _operations = <String>[
    '5102 - VENDA DE MERCADORIA',
    '5101 - VENDA DE PRODUÇÃO DO ESTABELECIMENTO',
    '5105 - VENDA DE MERCADORIA DE TERCEIROS',
    '6102 - VENDA DE MERCADORIA (INTERESTADUAL)',
    '6101 - VENDA DE PRODUÇÃO (INTERESTADUAL)',
    '5949 - OUTRA SAÍDA DE MERCADORIA',
  ];

  @override
  void initState() {
    super.initState();
    _loadClients();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    try {
      final products = await _api.listProducts(
        widget.session.token,
        active: true,
      );
      if (mounted) setState(() => _products = products);
    } catch (_) {}
  }

  Future<void> _loadClients() async {
    try {
      final clients = await _api.listClients(widget.session.token);
      if (mounted) {
        setState(
          () => _clients = clients.where((item) => item.active).toList(),
        );
      }
    } catch (_) {
      // A tela continua utilizável e informa a falha quando o usuário pesquisar.
    }
  }

  @override
  void dispose() {
    for (final controller in [
      _sale,
      _cpf,
      _notes,
      _freight,
      _insurance,
      _expenses,
      _carrierName,
      _carrierDocument,
      _carrierIe,
      _carrierAddress,
      _carrierCity,
      _carrierUf,
      _volumeQuantity,
      _volumeSpecies,
      _volumeBrand,
      _volumeNumbering,
      _netWeight,
      _grossWeight,
    ]) {
      controller.dispose();
    }
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  double _number(String value) =>
      double.tryParse(value.trim().replaceAll('.', '').replaceAll(',', '.')) ??
      0;
  int? get _fiscalClientId => _fiscalClient?.id;

  Future<void> _prepare() async {
    if (_nature.isEmpty) {
      setState(() => _error = 'Selecione a natureza da operação.');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = 'Inclua pelo menos um produto fiscal na nota.');
      return;
    }
    if (_type == 'nfe' && _fiscalClientId == null) {
      setState(
        () => _error = 'NF-e exige a seleção do cliente/destinatário fiscal.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final items = _items.map((item) => item.toFiscalItem()).toList();
      final document = _sale.text.trim().isEmpty
          ? await _api.prepareManualFiscalDocument(
              widget.session.token,
              items: items,
              documentType: _type,
              fiscalClientId: _fiscalClientId,
              consumerCpf: _type == 'nfce' ? _cpf.text.trim() : null,
              operationNature: _nature,
              paymentCondition: _payment,
              fiscalNotes: _notes.text.trim(),
            )
          : await _api.prepareFiscalDocumentWithItems(
              widget.session.token,
              saleId: int.parse(
                _sale.text.trim().replaceAll(RegExp(r'[^0-9]'), ''),
              ),
              items: items,
              documentType: _type,
              fiscalClientId: _fiscalClientId,
              consumerCpf: _type == 'nfce' ? _cpf.text.trim() : null,
              operationNature: _nature,
              paymentCondition: _payment,
              fiscalNotes: _notes.text.trim(),
            );
      await _api.updateFiscalDocument(
        widget.session.token,
        document.id,
        items: items,
        additionalFields: _transportPayload(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Rascunho fiscal preparado. Revise-o em Notas fiscais antes de enviar à SEFAZ.',
          ),
        ),
      );
      widget.onBack();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Não foi possível preparar a nota: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Map<String, dynamic> _transportPayload() => {
    'finality': _finality,
    'freight_mode': _freightMode,
    'freight_amount': _number(_freight.text),
    'insurance_amount': _number(_insurance.text),
    'other_expenses_amount': _number(_expenses.text),
    'carrier_name': _carrierName.text.trim(),
    'carrier_document': _carrierDocument.text.trim(),
    'carrier_state_registration': _carrierIe.text.trim(),
    'carrier_address': _carrierAddress.text.trim(),
    'carrier_city': _carrierCity.text.trim(),
    'carrier_uf': _carrierUf.text.trim().toUpperCase(),
    'volume_quantity': _number(_volumeQuantity.text),
    'volume_species': _volumeSpecies.text.trim(),
    'volume_brand': _volumeBrand.text.trim(),
    'volume_numbering': _volumeNumbering.text.trim(),
    'net_weight': _number(_netWeight.text),
    'gross_weight': _number(_grossWeight.text),
  };

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F6FA),
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final twoColumns = constraints.maxWidth >= 940;
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                children: [
                  IconButton(
                    tooltip: 'Voltar para notas fiscais',
                    onPressed: widget.onBack,
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Emitir nota fiscal',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        Text(
                          'Rascunho completo: revise os dados antes da transmissão à SEFAZ',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              _section(
                'Identificação da operação',
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'nfce', label: Text('NFC-e')),
                        ButtonSegment(value: 'nfe', label: Text('NF-e')),
                      ],
                      selected: {_type},
                      onSelectionChanged: (v) =>
                          setState(() => _type = v.first),
                    ),
                    _select('Finalidade', _finality, const {
                      '1': 'NF-e normal',
                      '2': 'Complementar',
                      '3': 'Ajuste',
                      '4': 'Devolução',
                    }, (v) => setState(() => _finality = v)),
                    _select('Pagamento', _payment, const {
                      'vista': 'À vista',
                      'prazo': 'A prazo',
                      'outros': 'Outros',
                    }, (v) => setState(() => _payment = v)),
                  ],
                ),
              ),
              _section(
                'Origem e destinatário',
                _fields(twoColumns, [
                  _field(_sale, 'Venda de origem (opcional)'),
                  _clientSelector(),
                  if (_type == 'nfce')
                    _field(
                      _cpf,
                      'CPF/CNPJ do consumidor (opcional)',
                      number: true,
                    ),
                  _operationSelector(),
                ]),
              ),
              if (_type == 'nfce')
                _section(
                  'Entrega NFC-e',
                  const Text(
                    'NFC-e é destinada ao consumidor final. Transporte, volumes e transportadora não são exibidos neste fluxo comum; entrega a domicílio exige regras específicas da SEFAZ.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
                ),
              _section(
                'Produtos e tributação por item',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final item in _items) _itemCard(item),
                    if (_items.isNotEmpty &&
                        _items.any((item) => item.pendingFields.isNotEmpty))
                      Card(
                        color: const Color(0xFFFFF7ED),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pendências fiscais',
                                style: TextStyle(fontWeight: FontWeight.w800),
                              ),
                              for (final item in _items.where(
                                (item) => item.pendingFields.isNotEmpty,
                              ))
                                Text(
                                  '${item.description.text.isEmpty ? 'Produto sem descrição' : item.description.text}: ${item.pendingFields.join(', ')}',
                                ),
                            ],
                          ),
                        ),
                      ),
                    OutlinedButton.icon(
                      onPressed: () =>
                          setState(() => _items.add(_ItemEditor())),
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar produto fiscal'),
                    ),
                    if (_items.isNotEmpty)
                      Align(
                        alignment: Alignment.centerRight,
                        child: Text(
                          'Total da nota: R\$ ${_items.fold<double>(0, (sum, item) => sum + item.total).toStringAsFixed(2).replaceAll('.', ',')}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (_type == 'nfe')
                _section(
                  'Frete, transporte e volumes (NF-e)',
                  _fields(twoColumns, [
                    _select(
                      'Modalidade do frete',
                      _freightMode,
                      const {
                        '0': '0 – Emitente',
                        '1': '1 – Destinatário',
                        '2': '2 – Terceiros',
                        '3': '3 – Próprio remetente',
                        '4': '4 – Próprio destinatário',
                        '9': '9 – Sem transporte',
                      },
                      (v) => setState(() => _freightMode = v),
                    ),
                    _field(_freight, 'Valor do frete', number: true),
                    _field(_insurance, 'Seguro', number: true),
                    _field(_expenses, 'Outras despesas', number: true),
                    _field(_carrierName, 'Transportadora'),
                    _field(
                      _carrierDocument,
                      'CNPJ/CPF transportadora',
                      number: true,
                    ),
                    _field(_carrierIe, 'IE transportadora'),
                    _field(_carrierAddress, 'Endereço transportadora'),
                    _field(_carrierCity, 'Cidade'),
                    _field(_carrierUf, 'UF', max: 2),
                    _field(
                      _volumeQuantity,
                      'Quantidade de volumes',
                      number: true,
                    ),
                    _field(_volumeSpecies, 'Espécie'),
                    _field(_volumeBrand, 'Marca'),
                    _field(_volumeNumbering, 'Numeração'),
                    _field(_netWeight, 'Peso líquido (kg)', number: true),
                    _field(_grossWeight, 'Peso bruto (kg)', number: true),
                  ]),
                ),
              _section(
                'Informações complementares',
                _field(_notes, 'Observações fiscais', lines: 4),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _prepare,
                  icon: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_outlined),
                  label: const Text('Preparar rascunho para revisão'),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );

  Widget _clientSelector() => Autocomplete<Client>(
    displayStringForOption: (client) =>
        '${client.name} — ${client.documentNumber ?? 'sem documento'}',
    optionsBuilder: (value) {
      final query = value.text.trim().toLowerCase();
      return _clients
          .where(
            (client) =>
                query.isEmpty ||
                [
                  client.name,
                  client.tradeName,
                  client.documentNumber,
                  client.city,
                  client.state,
                ].whereType<String>().join(' ').toLowerCase().contains(query),
          )
          .take(30);
    },
    onSelected: (client) => setState(() => _fiscalClient = client),
    fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
      controller: controller,
      focusNode: focusNode,
      onChanged: (_) {
        if (_fiscalClient != null) setState(() => _fiscalClient = null);
      },
      decoration: InputDecoration(
        labelText:
            'Pesquisar cliente/destinatário${_type == 'nfe' ? ' *' : ''}',
        hintText: 'Nome, CPF/CNPJ, cidade ou UF',
        border: const OutlineInputBorder(),
        suffixIcon: const Icon(Icons.search),
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 280),
          child: ListView(
            children: [
              for (final client in options)
                ListTile(
                  title: Text(client.name),
                  subtitle: Text(
                    [
                      client.documentNumber,
                      client.city,
                      client.state,
                    ].whereType<String>().join(' • '),
                  ),
                  onTap: () => onSelected(client),
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _operationSelector() => Autocomplete<String>(
    optionsBuilder: (value) => _operations.where(
      (item) => item.toLowerCase().contains(value.text.trim().toLowerCase()),
    ),
    onSelected: (value) => setState(() => _nature = value),
    fieldViewBuilder: (context, controller, focusNode, onSubmit) => TextField(
      controller: controller,
      focusNode: focusNode,
      decoration: const InputDecoration(
        labelText: 'Natureza da operação',
        hintText: 'Digite para pesquisar e selecione',
        border: OutlineInputBorder(),
        suffixIcon: Icon(Icons.search),
      ),
    ),
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 240),
          child: ListView(
            children: [
              for (final value in options)
                ListTile(title: Text(value), onTap: () => onSelected(value)),
            ],
          ),
        ),
      ),
    ),
  );

  Widget _section(String title, Widget child) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    ),
  );
  Widget _fields(bool two, List<Widget> children) => two
      ? Wrap(
          spacing: 12,
          runSpacing: 12,
          children: children
              .map((w) => SizedBox(width: 390, child: w))
              .toList(),
        )
      : Column(
          children: children
              .map(
                (w) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: w,
                ),
              )
              .toList(),
        );
  Widget _field(
    TextEditingController c,
    String label, {
    bool number = false,
    int? max,
    int lines = 1,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: c,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    maxLength: max,
    minLines: lines,
    maxLines: lines,
    inputFormatters: inputFormatters,
    onChanged: onChanged,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
  Widget _select(
    String label,
    String value,
    Map<String, String> options,
    ValueChanged<String> changed,
  ) => SizedBox(
    width: 280,
    child: DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      items: options.entries
          .map(
            (e) => DropdownMenuItem(
              value: e.key,
              child: Text(e.value, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (v) {
        if (v != null) changed(v);
      },
    ),
  );
  Widget _itemCard(_ItemEditor item) => Card(
    color: const Color(0xFFF8FAFC),
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _productSelector(item),
          _field(
            item.quantity,
            'Quantidade (${item.unit})',
            number: true,
            inputFormatters: item.isWeight
                ? [_WeightInputFormatter()]
                : [FilteringTextInputFormatter.digitsOnly],
            onChanged: (_) => setState(() {}),
          ),
          _field(
            item.unitPrice,
            'Valor unitário',
            number: true,
            onChanged: (_) => setState(() {}),
          ),
          Text(
            'Total do item: R\$ ${item.total.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() => item.expanded = !item.expanded),
            icon: Icon(item.expanded ? Icons.expand_less : Icons.tune),
            label: Text(
              item.expanded ? 'Ocultar dados fiscais' : 'Editar dados fiscais',
            ),
          ),
          if (item.expanded) ...[
            _field(item.description, 'Descrição fiscal *'),
            _field(item.ncm, 'NCM'),
            _field(item.cfop, 'CFOP'),
            _field(item.origin, 'Origem'),
            _field(item.cst, 'CST'),
            _field(item.csosn, 'CSOSN'),
            _field(item.pis, 'PIS CST'),
            _field(item.cofins, 'COFINS CST'),
          ],
          IconButton(
            onPressed: () => setState(() {
              _items.remove(item);
              item.dispose();
            }),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    ),
  );

  Widget _productSelector(_ItemEditor item) => Autocomplete<Product>(
    displayStringForOption: (p) => '${p.name} (#${p.id})',
    optionsBuilder: (value) {
      final q = value.text.trim().toLowerCase();
      return _products
          .where(
            (p) =>
                q.isEmpty ||
                [
                  p.name,
                  p.internalCode,
                  p.barcode,
                ].whereType<String>().join(' ').toLowerCase().contains(q),
          )
          .take(30);
    },
    onSelected: (product) => setState(() => item.applyProduct(product)),
    fieldViewBuilder: (context, controller, focusNode, onSubmit) {
      if (item.productId.text.isNotEmpty && controller.text.isEmpty) {
        controller.text = item.description.text;
      }
      return TextField(
        controller: controller,
        focusNode: focusNode,
        decoration: const InputDecoration(
          labelText: 'Adicionar produto',
          hintText: 'Nome, código ou código de barras',
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.search),
        ),
      );
    },
    optionsViewBuilder: (context, onSelected, options) => Align(
      alignment: Alignment.topLeft,
      child: Material(
        elevation: 6,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520, maxHeight: 280),
          child: ListView(
            children: [
              for (final p in options)
                ListTile(
                  title: Text(p.name),
                  subtitle: Text(
                    'ID ${p.id} • Estoque ${p.stockQuantity} ${p.unit}',
                  ),
                  onTap: () => onSelected(p),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ItemEditor {
  bool expanded = false;
  String unit = 'UN';
  bool get isWeight => unit == 'KG' || unit == 'KGS';
  double get total =>
      (double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0) *
      (double.tryParse(unitPrice.text.replaceAll(',', '.')) ?? 0);
  final productId = TextEditingController();
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unitPrice = TextEditingController(text: '0');
  final ncm = TextEditingController();
  final cfop = TextEditingController();
  final origin = TextEditingController();
  final cst = TextEditingController();
  final csosn = TextEditingController();
  final pis = TextEditingController();
  final cofins = TextEditingController();
  void applyProduct(Product p) {
    productId.text = '${p.id}';
    description.text = p.description?.trim().isNotEmpty == true
        ? p.description!.trim()
        : p.name;
    unit = p.unit.trim().toUpperCase().isEmpty
        ? 'UN'
        : p.unit.trim().toUpperCase();
    quantity.text = isWeight ? '0,001' : '1';
    unitPrice.text = p.salePrice.toStringAsFixed(2).replaceAll('.', ',');
    ncm.text = p.ncm ?? '';
    cfop.text = p.cfopSale ?? '';
    origin.text = p.origin ?? '';
    cst.text = p.cst ?? '';
    csosn.text = p.csosn ?? '';
  }

  List<String> get pendingFields => [
    if (productId.text.trim().isEmpty) 'produto',
    if (description.text.trim().isEmpty) 'descrição fiscal',
    if (double.tryParse(quantity.text.replaceAll(',', '.')) == null ||
        double.tryParse(quantity.text.replaceAll(',', '.'))! <= 0)
      'quantidade',
    if (double.tryParse(unitPrice.text.replaceAll(',', '.')) == null ||
        double.tryParse(unitPrice.text.replaceAll(',', '.'))! <= 0)
      'valor unitário',
    if (ncm.text.trim().isEmpty) 'NCM',
    if (cfop.text.trim().isEmpty) 'CFOP',
  ];
  FiscalDraftItem toFiscalItem() => FiscalDraftItem(
    fiscalProductId: int.tryParse(productId.text.trim()),
    fiscalDescription: description.text.trim(),
    quantity: double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0,
    unit: unit,
    unitPrice: double.tryParse(unitPrice.text.replaceAll(',', '.')) ?? 0,
    discountAmount: 0,
    totalPrice:
        (double.tryParse(quantity.text.replaceAll(',', '.')) ?? 0) *
        (double.tryParse(unitPrice.text.replaceAll(',', '.')) ?? 0),
    ncm: ncm.text.trim(),
    cfop: cfop.text.trim(),
    origin: origin.text.trim(),
    cst: cst.text.trim(),
    csosn: csosn.text.trim(),
    pisCst: pis.text.trim(),
    cofinsCst: cofins.text.trim(),
  );
  void dispose() {
    for (final c in [
      productId,
      description,
      quantity,
      unitPrice,
      ncm,
      cfop,
      origin,
      cst,
      csosn,
      pis,
      cofins,
    ]) {
      c.dispose();
    }
  }
}

class _WeightInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) {
      return newValue.copyWith(
        text: '0,000',
        selection: const TextSelection.collapsed(offset: 5),
      );
    }
    final padded = digits.padLeft(4, '0');
    final integer = padded
        .substring(0, padded.length - 3)
        .replaceFirst(RegExp(r'^0+(?=\d)'), '');
    final text =
        '${integer.isEmpty ? '0' : integer},${padded.substring(padded.length - 3)}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
