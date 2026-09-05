import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/client.dart';
import '../models/fiscal.dart';
import '../models/fiscal_assistant.dart';
import '../models/product.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/fiscal_item_card.dart';

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
  int? _sourceSaleId;
  bool _loadingSaleOrigin = false;
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

  Product? _productById(int? productId) {
    if (productId == null) return null;
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  Future<void> _loadSaleOrigin() async {
    final query = _sale.text.trim();
    if (query.isEmpty) {
      setState(() {
        _sourceSaleId = null;
        _error = 'Informe o número da venda para puxar os produtos.';
      });
      return;
    }
    setState(() {
      _loadingSaleOrigin = true;
      _error = null;
    });
    try {
      final draft = await _api.getFiscalSaleDraft(widget.session.token, query);
      if (!mounted) return;
      setState(() {
        for (final item in _items) {
          item.dispose();
        }
        _items
          ..clear()
          ..addAll(
            draft.items.map(
              (draftItem) => _ItemEditor.fromFiscalDraft(
                draftItem,
                product: _productById(draftItem.fiscalProductId),
              ),
            ),
          );
        _sourceSaleId = draft.saleId;
        _sale.text = draft.saleNumber ?? query;
        if (_type == 'nfce' &&
            _cpf.text.trim().isEmpty &&
            draft.consumerCpf?.trim().isNotEmpty == true) {
          _cpf.text = draft.consumerCpf!.trim();
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Venda ${draft.saleNumber ?? query} carregada com ${draft.items.length} produto(s). Você pode editar descrição, quantidade, valor e dados fiscais antes de preparar a nota.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar a venda: $error');
      }
    } finally {
      if (mounted) setState(() => _loadingSaleOrigin = false);
    }
  }

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  String? _optionalUpperText(TextEditingController controller) {
    final value = controller.text.trim().toUpperCase();
    return value.isEmpty ? null : value;
  }

  Future<void> _prepare() async {
    if (_nature.isEmpty) {
      setState(() => _error = 'Selecione a natureza da operação.');
      return;
    }
    if (_items.isEmpty) {
      setState(() => _error = 'Inclua pelo menos um produto fiscal na nota.');
      return;
    }
    if (_sale.text.trim().isNotEmpty && _sourceSaleId == null) {
      setState(
        () => _error =
            'Carregue a venda pela lupa antes de preparar a nota. Assim o sistema usa a venda correta.',
      );
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
              consumerCpf: _type == 'nfce' ? _optionalText(_cpf) : null,
              operationNature: _nature,
              paymentCondition: _payment,
              fiscalNotes: _optionalText(_notes),
            )
          : await _api.prepareFiscalDocumentWithItems(
              widget.session.token,
              saleId: _sourceSaleId!,
              items: items,
              documentType: _type,
              fiscalClientId: _fiscalClientId,
              consumerCpf: _type == 'nfce' ? _optionalText(_cpf) : null,
              operationNature: _nature,
              paymentCondition: _payment,
              fiscalNotes: _optionalText(_notes),
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
    'carrier_name': _optionalText(_carrierName),
    'carrier_document': _optionalText(_carrierDocument),
    'carrier_state_registration': _optionalText(_carrierIe),
    'carrier_address': _optionalText(_carrierAddress),
    'carrier_city': _optionalText(_carrierCity),
    'carrier_uf': _optionalUpperText(_carrierUf),
    'volume_quantity': _number(_volumeQuantity.text),
    'volume_species': _optionalText(_volumeSpecies),
    'volume_brand': _optionalText(_volumeBrand),
    'volume_numbering': _optionalText(_volumeNumbering),
    'net_weight': _number(_netWeight.text),
    'gross_weight': _number(_grossWeight.text),
  };

  Map<String, dynamic> _taxProfilePayload(_ItemEditor item) => {
    'ncm': _optionalText(item.ncm),
    'cest': _optionalText(item.cest),
    'cfop_sale': _optionalText(item.cfop),
    'origin': _optionalText(item.origin),
    'cst': _optionalText(item.cst),
    'csosn': _optionalText(item.csosn),
    'ibs_cbs_cst': _optionalText(item.ibsCbsCst),
    'ibs_cbs_classification': _optionalText(item.ibsCbsClassification),
    'selective_tax_cst': _optionalText(item.selectiveTaxCst),
    'selective_tax_classification': _optionalText(
      item.selectiveTaxClassification,
    ),
  };

  Future<void> _saveFiscalToProduct(_ItemEditor item) async {
    final productId = int.tryParse(item.productId.text.trim());
    if (productId == null) {
      setState(
        () => _error =
            'Selecione um produto cadastrado antes de salvar o fiscal.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await _api.updateProductTaxProfile(
        widget.session.token,
        productId,
        _taxProfilePayload(item),
      );
      await _loadProducts();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Classificação fiscal salva no produto. Próximas notas já puxam esses dados.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível salvar o fiscal no produto: $error',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _loadFiscalSuggestion(_ItemEditor item) async {
    final productId = int.tryParse(item.productId.text.trim());
    if (productId == null) {
      setState(() {
        item.fiscalSuggestionMessage =
            'Selecione um produto cadastrado para consultar o motor fiscal.';
      });
      return;
    }
    setState(() {
      item.loadingFiscalSuggestion = true;
      item.fiscalSuggestionMessage = null;
    });
    try {
      final response = await _api.getFiscalAssistantProductSuggestions(
        widget.session.token,
        productId: productId,
        description: item.description.text,
      );
      final applied = item.applyBestFiscalSuggestion(response);
      if (!mounted) return;
      setState(() {
        item.expanded = true;
        item.fiscalAssistant = response;
        final hasOfficialSuggestions =
            response.ncmOfficialSuggestions.isNotEmpty ||
            response.ibsCbsOfficialSuggestions.isNotEmpty;
        item.fiscalSuggestionMessage = applied
            ? 'Sugestão fiscal aplicada pelo motor. Revise os campos e salve no produto se estiver correto.'
            : hasOfficialSuggestions
            ? 'O motor encontrou opções oficiais de apoio abaixo. Escolha a correta com o contador/responsável fiscal e salve no produto.'
            : 'O motor não achou sugestão fiscal segura para esse produto ainda. Preencha uma vez e salve no produto para aprender.';
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() => item.fiscalSuggestionMessage = error.message);
      }
    } catch (error) {
      if (mounted) {
        setState(
          () => item.fiscalSuggestionMessage =
              'Não foi possível consultar a sugestão fiscal: $error',
        );
      }
    } finally {
      if (mounted) setState(() => item.loadingFiscalSuggestion = false);
    }
  }

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
                  _saleOriginField(),
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
                    _field(
                      _freight,
                      'Valor do frete',
                      number: true,
                      inputFormatters: const [CurrencyInputFormatter()],
                    ),
                    _field(
                      _insurance,
                      'Seguro',
                      number: true,
                      inputFormatters: const [CurrencyInputFormatter()],
                    ),
                    _field(
                      _expenses,
                      'Outras despesas',
                      number: true,
                      inputFormatters: const [CurrencyInputFormatter()],
                    ),
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

  Widget _saleOriginField() => TextField(
    controller: _sale,
    textInputAction: TextInputAction.search,
    onChanged: (_) {
      if (_sourceSaleId != null) {
        setState(() => _sourceSaleId = null);
      }
    },
    onSubmitted: (_) => _loadSaleOrigin(),
    decoration: InputDecoration(
      labelText: 'Venda de origem (opcional)',
      hintText: 'Ex.: V45',
      helperText: 'Digite o número e clique na lupa para puxar os produtos.',
      border: const OutlineInputBorder(),
      suffixIcon: _loadingSaleOrigin
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : IconButton(
              tooltip: 'Carregar venda',
              onPressed: _loadSaleOrigin,
              icon: const Icon(Icons.search),
            ),
    ),
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
  Widget _itemCard(_ItemEditor item) => FiscalItemCard(
    index: _items.indexOf(item),
    productField: _productSelector(item),
    description: item.description,
    quantity: item.quantity,
    unit: item.unit,
    unitPrice: item.unitPrice,
    discount: item.discount,
    ncm: item.ncm,
    cest: item.cest,
    cfop: item.cfop,
    origin: item.origin,
    cst: item.cst,
    csosn: item.csosn,
    pisCst: item.pis,
    cofinsCst: item.cofins,
    cbenef: item.cbenef,
    ibsCbsCst: item.ibsCbsCst,
    ibsCbsClassification: item.ibsCbsClassification,
    selectiveTaxCst: item.selectiveTaxCst,
    selectiveTaxClassification: item.selectiveTaxClassification,
    total: item.total,
    expanded: item.expanded,
    onToggleExpanded: () => setState(() => item.expanded = !item.expanded),
    onChanged: () => setState(() {}),
    onValueChanged: (_) => setState(() {}),
    onDelete: () => setState(() {
      _items.remove(item);
      item.dispose();
    }),
    fiscalSuggestionText: item.fiscalSuggestionMessage,
    ncmOfficialSuggestions:
        item.fiscalAssistant?.ncmOfficialSuggestions ?? const [],
    collectiveSuggestions:
        item.fiscalAssistant?.collectiveSuggestions ?? const [],
    ibsCbsOfficialSuggestions:
        item.fiscalAssistant?.ibsCbsOfficialSuggestions ?? const [],
    loadingFiscalSuggestion: item.loadingFiscalSuggestion,
    onLoadFiscalSuggestion: int.tryParse(item.productId.text.trim()) == null
        ? null
        : () => _loadFiscalSuggestion(item),
    onApplyOfficialNcm: (suggestion) => setState(() {
      item.ncm.text = suggestion.code;
      item.expanded = true;
      item.fiscalSuggestionMessage =
          'NCM oficial ${suggestion.code} aplicado. Confira com contador/classificação fiscal antes de emitir.';
    }),
    onApplyCollectiveSuggestion: (suggestion) => setState(() {
      item.applyCollectiveFiscalSuggestion(suggestion);
      item.expanded = true;
      item.fiscalSuggestionMessage =
          'Sugestão coletiva aplicada após sua confirmação. Confira os dados fiscais antes de emitir.';
    }),
    onApplyOfficialIbsCbs: (suggestion) => setState(() {
      item.ibsCbsCst.text = suggestion.cst;
      item.ibsCbsClassification.text = suggestion.cclassTrib;
      item.expanded = true;
      item.fiscalSuggestionMessage =
          'IBS/CBS oficial CST ${suggestion.cst} e cClassTrib ${suggestion.cclassTrib} aplicados. Confira a hipótese fiscal antes de emitir.';
    }),
    onSaveFiscalToProduct: int.tryParse(item.productId.text.trim()) == null
        ? null
        : () => _saveFiscalToProduct(item),
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
  final productId = TextEditingController();
  final description = TextEditingController();
  final quantity = TextEditingController(text: '1');
  final unit = TextEditingController(text: 'UN');
  final unitPrice = TextEditingController(text: '0');
  final discount = TextEditingController(text: '0,00');
  final ncm = TextEditingController();
  final cest = TextEditingController();
  final cfop = TextEditingController();
  final origin = TextEditingController();
  final cst = TextEditingController();
  final csosn = TextEditingController();
  final pis = TextEditingController();
  final cofins = TextEditingController();
  final cbenef = TextEditingController();
  final ibsCbsCst = TextEditingController();
  final ibsCbsClassification = TextEditingController();
  final selectiveTaxCst = TextEditingController();
  final selectiveTaxClassification = TextEditingController();
  bool loadingFiscalSuggestion = false;
  String? fiscalSuggestionMessage;
  FiscalAssistantResponse? fiscalAssistant;

  _ItemEditor();

  factory _ItemEditor.fromFiscalDraft(
    FiscalDraftItem draft, {
    Product? product,
  }) {
    final item = _ItemEditor();
    if (product != null) item.applyProduct(product);
    item.productId.text = '${draft.fiscalProductId ?? draft.originalProductId ?? ''}';
    item.description.text = draft.fiscalDescription;
    item.unit.text = draft.unit.trim().isEmpty ? 'UN' : draft.unit.trim().toUpperCase();
    item.quantity.text = formatFiscalQuantity(draft.quantity, item.unit.text);
    item.unitPrice.text = formatFiscalMoney(draft.unitPrice);
    item.discount.text = formatFiscalMoney(draft.discountAmount);
    item._replaceIfPresent(item.ncm, draft.ncm);
    item._replaceIfPresent(item.cest, draft.cest);
    item._replaceIfPresent(item.cfop, draft.cfop);
    item._replaceIfPresent(item.origin, draft.origin);
    item._replaceIfPresent(item.cst, draft.cst);
    item._replaceIfPresent(item.csosn, draft.csosn);
    item._replaceIfPresent(item.pis, draft.pisCst);
    item._replaceIfPresent(item.cofins, draft.cofinsCst);
    item._replaceIfPresent(item.cbenef, draft.cbenef);
    item._replaceIfPresent(item.ibsCbsCst, draft.ibsCbsCst);
    item._replaceIfPresent(
      item.ibsCbsClassification,
      draft.ibsCbsClassification,
    );
    item._replaceIfPresent(item.selectiveTaxCst, draft.selectiveTaxCst);
    item._replaceIfPresent(
      item.selectiveTaxClassification,
      draft.selectiveTaxClassification,
    );
    return item;
  }

  void _replaceIfPresent(TextEditingController controller, String? value) {
    if (value?.trim().isNotEmpty == true) controller.text = value!.trim();
  }

  bool get isWeight {
    final normalized = unit.text.trim().toUpperCase();
    return normalized == 'KG' || normalized == 'KGS';
  }

  double get total =>
      parseFiscalDecimal(quantity.text) * parseFiscalDecimal(unitPrice.text) -
      parseFiscalDecimal(discount.text);

  void applyProduct(Product p) {
    productId.text = '${p.id}';
    description.text = p.description?.trim().isNotEmpty == true
        ? p.description!.trim()
        : p.name;
    unit.text = p.unit.trim().toUpperCase().isEmpty
        ? 'UN'
        : p.unit.trim().toUpperCase();
    quantity.text = isWeight ? '0,001' : '1';
    unitPrice.text = p.salePrice.toStringAsFixed(2).replaceAll('.', ',');
    ncm.text = p.ncm ?? '';
    cest.text = p.cest ?? '';
    cfop.text = p.cfopSale ?? '';
    origin.text = p.origin ?? '';
    cst.text = p.cst ?? '';
    csosn.text = p.csosn ?? '';
    ibsCbsCst.text = p.ibsCbsCst ?? '';
    ibsCbsClassification.text = p.ibsCbsClassification ?? '';
    selectiveTaxCst.text = p.selectiveTaxCst ?? '';
    selectiveTaxClassification.text = p.selectiveTaxClassification ?? '';
    fiscalSuggestionMessage = null;
    fiscalAssistant = null;
  }

  bool applyBestFiscalSuggestion(FiscalAssistantResponse response) {
    FiscalSuggestion? suggestion;
    for (final item in response.suggestions) {
      if (_hasValue(item.ncm) ||
          _hasValue(item.cest) ||
          _hasValue(item.cfop) ||
          _hasValue(item.origin) ||
          _hasValue(item.cst) ||
          _hasValue(item.csosn) ||
          _hasValue(item.pisCst) ||
          _hasValue(item.cofinsCst) ||
          _hasValue(item.ibsCbsCst) ||
          _hasValue(item.ibsCbsClassification) ||
          _hasValue(item.selectiveTaxCst) ||
          _hasValue(item.selectiveTaxClassification)) {
        suggestion = item;
        break;
      }
    }
    var applied = false;
    if (suggestion != null) {
      applied = _fillIfEmpty(ncm, suggestion.ncm) || applied;
      applied = _fillIfEmpty(cest, suggestion.cest) || applied;
      applied = _fillIfEmpty(cfop, suggestion.cfop) || applied;
      applied = _fillIfEmpty(origin, suggestion.origin) || applied;
      applied = _fillIfEmpty(cst, suggestion.cst) || applied;
      applied = _fillIfEmpty(csosn, suggestion.csosn) || applied;
      applied = _fillIfEmpty(pis, suggestion.pisCst) || applied;
      applied = _fillIfEmpty(cofins, suggestion.cofinsCst) || applied;
      applied = _fillIfEmpty(ibsCbsCst, suggestion.ibsCbsCst) || applied;
      applied =
          _fillIfEmpty(ibsCbsClassification, suggestion.ibsCbsClassification) ||
          applied;
      applied =
          _fillIfEmpty(selectiveTaxCst, suggestion.selectiveTaxCst) || applied;
      applied =
          _fillIfEmpty(
            selectiveTaxClassification,
            suggestion.selectiveTaxClassification,
          ) ||
          applied;
    }
    if (response.ibsCbsOfficialSuggestions.isNotEmpty) {
      final official = response.ibsCbsOfficialSuggestions.first;
      applied = _fillIfEmpty(ibsCbsCst, official.cst) || applied;
      applied =
          _fillIfEmpty(ibsCbsClassification, official.cclassTrib) || applied;
    }
    // Official NCM rows are alternatives, not an automatic fiscal decision.
    // They are deliberately applied only when the operator selects one in the
    // suggestion list.
    if (!applied) return false;
    expanded = true;
    return true;
  }

  void applyCollectiveFiscalSuggestion(FiscalCollectiveSuggestion suggestion) {
    _replaceIfPresent(ncm, suggestion.ncm);
    _replaceIfPresent(cest, suggestion.cest);
    _replaceIfPresent(cfop, suggestion.cfop);
    _replaceIfPresent(origin, suggestion.origin);
    _replaceIfPresent(cst, suggestion.cst);
    _replaceIfPresent(csosn, suggestion.csosn);
    _replaceIfPresent(ibsCbsCst, suggestion.ibsCbsCst);
    _replaceIfPresent(ibsCbsClassification, suggestion.ibsCbsClassification);
    _replaceIfPresent(selectiveTaxCst, suggestion.selectiveTaxCst);
    _replaceIfPresent(
      selectiveTaxClassification,
      suggestion.selectiveTaxClassification,
    );
  }

  static bool _hasValue(String? value) => value?.trim().isNotEmpty == true;

  static bool _fillIfEmpty(TextEditingController controller, String? value) {
    if (controller.text.trim().isEmpty && value?.trim().isNotEmpty == true) {
      controller.text = value!.trim();
      return true;
    }
    return false;
  }

  List<String> get pendingFields => [
    if (productId.text.trim().isEmpty) 'produto',
    if (description.text.trim().isEmpty) 'descrição fiscal',
    if (parseFiscalDecimal(quantity.text) <= 0) 'quantidade',
    if (parseFiscalDecimal(unitPrice.text) <= 0) 'valor unitário',
    if (ncm.text.trim().isEmpty) 'NCM',
    if (cfop.text.trim().isEmpty) 'CFOP',
    if (origin.text.trim().isEmpty) 'origem da mercadoria',
    if (cst.text.trim().isEmpty && csosn.text.trim().isEmpty) 'CST/CSOSN',
  ];
  FiscalDraftItem toFiscalItem() => FiscalDraftItem(
    fiscalProductId: int.tryParse(productId.text.trim()),
    fiscalDescription: description.text.trim(),
    quantity: parseFiscalDecimal(quantity.text),
    unit: unit.text.trim().toUpperCase(),
    unitPrice: parseFiscalDecimal(unitPrice.text),
    discountAmount: parseFiscalDecimal(discount.text),
    totalPrice: total,
    ncm: ncm.text.trim(),
    cest: cest.text.trim(),
    cfop: cfop.text.trim(),
    origin: origin.text.trim(),
    cst: cst.text.trim(),
    csosn: csosn.text.trim(),
    pisCst: pis.text.trim(),
    cofinsCst: cofins.text.trim(),
    cbenef: cbenef.text.trim(),
    ibsCbsCst: ibsCbsCst.text.trim(),
    ibsCbsClassification: ibsCbsClassification.text.trim(),
    selectiveTaxCst: selectiveTaxCst.text.trim(),
    selectiveTaxClassification: selectiveTaxClassification.text.trim(),
  );
  void dispose() {
    for (final c in [
      productId,
      description,
      quantity,
      unit,
      unitPrice,
      discount,
      ncm,
      cest,
      cfop,
      origin,
      cst,
      csosn,
      pis,
      cofins,
      cbenef,
      ibsCbsCst,
      ibsCbsClassification,
      selectiveTaxCst,
      selectiveTaxClassification,
    ]) {
      c.dispose();
    }
  }
}
