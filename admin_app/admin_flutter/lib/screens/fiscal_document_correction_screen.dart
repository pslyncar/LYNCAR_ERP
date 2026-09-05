import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/client.dart';
import '../models/fiscal.dart';
import '../models/fiscal_assistant.dart';
import '../widgets/app_card.dart';
import '../widgets/fiscal_item_card.dart';

class FiscalDocumentCorrectionScreen extends StatefulWidget {
  const FiscalDocumentCorrectionScreen({
    super.key,
    required this.document,
    required this.clients,
    required this.onBack,
    required this.onSave,
    required this.onLoadFiscalSuggestion,
    required this.onSaveFiscalToProduct,
  });

  final FiscalDocument document;
  final List<Client> clients;
  final VoidCallback onBack;
  final Future<void> Function(
    Map<String, dynamic> fields,
    List<FiscalDraftItem> items,
    bool resend,
  )
  onSave;
  final Future<FiscalAssistantResponse> Function(FiscalDraftItem item)
  onLoadFiscalSuggestion;
  final Future<void> Function(FiscalDraftItem item) onSaveFiscalToProduct;

  @override
  State<FiscalDocumentCorrectionScreen> createState() =>
      _FiscalDocumentCorrectionScreenState();
}

class _FiscalDocumentCorrectionScreenState
    extends State<FiscalDocumentCorrectionScreen> {
  static const _operations = <String>[
    '5102 - VENDA DE MERCADORIA',
    '5101 - VENDA DE PRODUÇÃO DO ESTABELECIMENTO',
    '5105 - VENDA DE MERCADORIA DE TERCEIROS',
    '6102 - VENDA DE MERCADORIA (INTERESTADUAL)',
    '6101 - VENDA DE PRODUÇÃO (INTERESTADUAL)',
    '5949 - OUTRA SAÍDA DE MERCADORIA',
  ];
  static const _freightModes = <String>{'0', '1', '2', '3', '4', '9'};

  late final TextEditingController _nature;
  late final TextEditingController _cpf;
  late final TextEditingController _notes;
  late final TextEditingController _freight;
  late final TextEditingController _insurance;
  late final TextEditingController _expenses;
  late final TextEditingController _carrierName;
  late final TextEditingController _carrierDocument;
  late final TextEditingController _carrierIe;
  late final TextEditingController _carrierAddress;
  late final TextEditingController _carrierCity;
  late final TextEditingController _carrierUf;
  late final TextEditingController _volumeQuantity;
  late final TextEditingController _volumeSpecies;
  late final TextEditingController _volumeBrand;
  late final TextEditingController _volumeNumbering;
  late final TextEditingController _netWeight;
  late final TextEditingController _grossWeight;
  late final List<FiscalDraftItem> _items;
  late final List<_FiscalItemControllers> _itemControllers;
  late String _finality;
  late String _payment;
  late String _freightMode;
  int? _clientId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final document = widget.document;
    _nature = TextEditingController(text: document.operationNature ?? '');
    _cpf = TextEditingController(text: document.consumerCpf ?? '');
    _notes = TextEditingController(text: document.fiscalNotes ?? '');
    _freight = _moneyController(document.freightAmount);
    _insurance = _moneyController(document.insuranceAmount);
    _expenses = _moneyController(document.otherExpensesAmount);
    _carrierName = TextEditingController(text: document.carrierName ?? '');
    _carrierDocument = TextEditingController(
      text: document.carrierDocument ?? '',
    );
    _carrierIe = TextEditingController(
      text: document.carrierStateRegistration ?? '',
    );
    _carrierAddress = TextEditingController(
      text: document.carrierAddress ?? '',
    );
    _carrierCity = TextEditingController(text: document.carrierCity ?? '');
    _carrierUf = TextEditingController(text: document.carrierUf ?? '');
    _volumeQuantity = _numberController(document.volumeQuantity);
    _volumeSpecies = TextEditingController(text: document.volumeSpecies ?? '');
    _volumeBrand = TextEditingController(text: document.volumeBrand ?? '');
    _volumeNumbering = TextEditingController(
      text: document.volumeNumbering ?? '',
    );
    _netWeight = _numberController(document.netWeight);
    _grossWeight = _numberController(document.grossWeight);
    _finality = document.finality;
    _payment = document.paymentCondition ?? 'vista';
    _freightMode = _freightModes.contains(document.freightMode)
        ? document.freightMode!
        : '9';
    _clientId = document.fiscalClientId;
    _items = List<FiscalDraftItem>.from(document.fiscalItems);
    _itemControllers = _items.map(_FiscalItemControllers.new).toList();
  }

  TextEditingController _moneyController(double value) => TextEditingController(
    text: value.toStringAsFixed(2).replaceAll('.', ','),
  );

  TextEditingController _numberController(double? value) =>
      TextEditingController(text: value?.toString().replaceAll('.', ',') ?? '');

  double _decimal(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

  String? _optionalText(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  String? _optionalUpperText(TextEditingController controller) {
    final value = controller.text.trim().toUpperCase();
    return value.isEmpty ? null : value;
  }

  /// The clients endpoint can briefly contain the same record more than once
  /// while its sources are refreshed. DropdownMenu requires each value to be
  /// unique, so keep one entry per client id for this selector.
  List<Client> get _uniqueClients {
    final ids = <int>{};
    return widget.clients.where((client) => ids.add(client.id)).toList();
  }

  @override
  void dispose() {
    for (final controller in [
      _nature,
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
    for (final controllers in _itemControllers) {
      controllers.dispose();
    }
    super.dispose();
  }

  Future<void> _save(bool resend) async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final fields = <String, dynamic>{
        if (_clientId != null) 'fiscal_client_id': _clientId,
        'consumer_cpf': _optionalText(_cpf),
        'finality': _finality,
        'payment_condition': _payment,
        'freight_mode': _freightMode,
        'freight_amount': _decimal(_freight),
        'insurance_amount': _decimal(_insurance),
        'other_expenses_amount': _decimal(_expenses),
        'carrier_name': _optionalText(_carrierName),
        'carrier_document': _optionalText(_carrierDocument),
        'carrier_state_registration': _optionalText(_carrierIe),
        'carrier_address': _optionalText(_carrierAddress),
        'carrier_city': _optionalText(_carrierCity),
        'carrier_uf': _optionalUpperText(_carrierUf),
        'volume_quantity': _decimal(_volumeQuantity),
        'volume_species': _optionalText(_volumeSpecies),
        'volume_brand': _optionalText(_volumeBrand),
        'volume_numbering': _optionalText(_volumeNumbering),
        'net_weight': _decimal(_netWeight),
        'gross_weight': _decimal(_grossWeight),
      };
      final items = <FiscalDraftItem>[
        for (var index = 0; index < _itemControllers.length; index++)
          _itemControllers[index].buildItem(_items[index]),
      ];
      await widget.onSave(
        {
          ...fields,
          'operation_nature': _optionalText(_nature),
          'fiscal_notes': _optionalText(_notes),
        },
        items,
        resend,
      );
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveItemFiscalToProduct(int index) async {
    final item = _itemControllers[index].buildItem(_items[index]);
    final productId = item.fiscalProductId ?? item.originalProductId;
    if (productId == null) {
      setState(
        () => _error = 'Este item não está ligado a um produto cadastrado.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSaveFiscalToProduct(item);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Classificação fiscal salva no produto. Próximas notas já puxam esses dados.',
          ),
        ),
      );
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

  Future<void> _loadFiscalSuggestion(int index) async {
    final current = _itemControllers[index].buildItem(_items[index]);
    final productId = current.fiscalProductId ?? current.originalProductId;
    if (productId == null) {
      setState(() {
        _itemControllers[index].fiscalSuggestionMessage =
            'Este item não está ligado a um produto cadastrado.';
      });
      return;
    }
    setState(() {
      _itemControllers[index].loadingFiscalSuggestion = true;
      _itemControllers[index].fiscalSuggestionMessage = null;
    });
    try {
      final response = await widget.onLoadFiscalSuggestion(current);
      final applied = _itemControllers[index].applyBestFiscalSuggestion(
        response,
      );
      if (!mounted) return;
      setState(() {
        _itemControllers[index].expanded = true;
        _itemControllers[index].fiscalAssistant = response;
        final hasOfficialSuggestions =
            response.ncmOfficialSuggestions.isNotEmpty ||
            response.ibsCbsOfficialSuggestions.isNotEmpty;
        _itemControllers[index].fiscalSuggestionMessage = applied
            ? 'Sugestão fiscal aplicada pelo motor. Revise os campos e salve no produto se estiver correto.'
            : hasOfficialSuggestions
            ? 'O motor encontrou opções oficiais de apoio abaixo. Escolha a correta com o contador/responsável fiscal e salve no produto.'
            : 'O motor não achou sugestão fiscal segura para esse produto ainda. Preencha uma vez e salve no produto para aprender.';
      });
    } catch (error) {
      if (mounted) {
        setState(
          () => _itemControllers[index].fiscalSuggestionMessage =
              'Não foi possível consultar a sugestão fiscal: $error',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _itemControllers[index].loadingFiscalSuggestion = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final hasNumber = document.number != null;
    final isNfe = document.documentType == 'nfe';
    final clients = _uniqueClients;
    final selectedClientId = clients.any((client) => client.id == _clientId)
        ? _clientId
        : null;
    return Scaffold(
      backgroundColor: const Color(0xFFF3F6FA),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                key: const Key('fiscal-correction-scroll'),
                padding: const EdgeInsets.all(24),
                children: [
                  Row(
                    children: [
                      IconButton.outlined(
                        tooltip: 'Voltar para notas fiscais',
                        onPressed: _saving ? null : widget.onBack,
                        icon: const Icon(Icons.arrow_back),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Corrigir ${isNfe ? 'NF-e' : 'NFC-e'}',
                              style: const TextStyle(
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              hasNumber
                                  ? 'Série ${document.series} • número ${document.number} será preservado no reenvio'
                                  : 'Ainda sem número • receberá o próximo disponível somente ao transmitir',
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (document.sefazMessage?.trim().isNotEmpty == true)
                    _MessageBanner(
                      message: document.sefazMessage!,
                      hasNumber: hasNumber,
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    _MessageBanner(message: _error!, hasNumber: false),
                  ],
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Operação e destinatário',
                    icon: Icons.receipt_long_outlined,
                    child: _FieldGrid(
                      children: [
                        DropdownMenu<String>(
                          controller: _nature,
                          enableFilter: true,
                          enableSearch: true,
                          requestFocusOnTap: true,
                          label: const Text('Natureza da operação'),
                          hintText: 'Pesquise e selecione',
                          dropdownMenuEntries: _operations
                              .map(
                                (value) => DropdownMenuEntry(
                                  value: value,
                                  label: value,
                                ),
                              )
                              .toList(),
                        ),
                        DropdownMenu<int>(
                          initialSelection: selectedClientId,
                          enableFilter: true,
                          enableSearch: true,
                          requestFocusOnTap: true,
                          label: const Text('Cliente/destinatário'),
                          hintText: 'Buscar por nome ou CPF/CNPJ',
                          onSelected: (value) =>
                              setState(() => _clientId = value),
                          dropdownMenuEntries: clients
                              .map(
                                (client) => DropdownMenuEntry(
                                  value: client.id,
                                  label:
                                      '${client.name} • ${client.documentNumber ?? 'sem documento'}',
                                ),
                              )
                              .toList(),
                        ),
                        TextField(
                          controller: _cpf,
                          decoration: const InputDecoration(
                            labelText: 'CPF/CNPJ na nota',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _finality,
                          decoration: const InputDecoration(
                            labelText: 'Finalidade',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: '1',
                              child: Text('1 - Normal'),
                            ),
                            DropdownMenuItem(
                              value: '2',
                              child: Text('2 - Complementar'),
                            ),
                            DropdownMenuItem(
                              value: '3',
                              child: Text('3 - Ajuste'),
                            ),
                            DropdownMenuItem(
                              value: '4',
                              child: Text('4 - Devolução'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _finality = value ?? '1'),
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _payment,
                          decoration: const InputDecoration(
                            labelText: 'Condição de pagamento',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'vista',
                              child: Text('À vista'),
                            ),
                            DropdownMenuItem(
                              value: 'prazo',
                              child: Text('A prazo'),
                            ),
                            DropdownMenuItem(
                              value: 'outros',
                              child: Text('Outros'),
                            ),
                          ],
                          onChanged: (value) =>
                              setState(() => _payment = value ?? 'vista'),
                        ),
                        TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Observações fiscais',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SectionCard(
                    title: 'Produtos e tributação',
                    icon: Icons.inventory_2_outlined,
                    child: Column(
                      children: [
                        for (
                          var index = 0;
                          index < _itemControllers.length;
                          index++
                        )
                          FiscalItemCard(
                            index: index,
                            productField: InputDecorator(
                              decoration: const InputDecoration(
                                labelText: 'Produto fiscal',
                                border: OutlineInputBorder(),
                              ),
                              child: Text(
                                _itemControllers[index].description.text.isEmpty
                                    ? 'Produto sem descrição'
                                    : _itemControllers[index].description.text,
                              ),
                            ),
                            description: _itemControllers[index].description,
                            quantity: _itemControllers[index].quantity,
                            unit: _itemControllers[index].unit,
                            unitPrice: _itemControllers[index].unitPrice,
                            discount: _itemControllers[index].discount,
                            ncm: _itemControllers[index].ncm,
                            cest: _itemControllers[index].cest,
                            cfop: _itemControllers[index].cfop,
                            origin: _itemControllers[index].origin,
                            cst: _itemControllers[index].cst,
                            csosn: _itemControllers[index].csosn,
                            pisCst: _itemControllers[index].pisCst,
                            cofinsCst: _itemControllers[index].cofinsCst,
                            cbenef: _itemControllers[index].cbenef,
                            ibsCbsCst: _itemControllers[index].ibsCbsCst,
                            ibsCbsClassification:
                                _itemControllers[index].ibsCbsClassification,
                            selectiveTaxCst:
                                _itemControllers[index].selectiveTaxCst,
                            selectiveTaxClassification: _itemControllers[index]
                                .selectiveTaxClassification,
                            total: _itemControllers[index].total,
                            expanded: _itemControllers[index].expanded,
                            onToggleExpanded: () => setState(
                              () => _itemControllers[index].expanded =
                                  !_itemControllers[index].expanded,
                            ),
                            onChanged: () => setState(() {}),
                            onValueChanged: (_) => setState(
                              () => _itemControllers[index].markValueEdited(),
                            ),
                            fiscalSuggestionText:
                                _itemControllers[index].fiscalSuggestionMessage,
                            ncmOfficialSuggestions:
                                _itemControllers[index]
                                    .fiscalAssistant
                                    ?.ncmOfficialSuggestions ??
                                const [],
                            collectiveSuggestions:
                                _itemControllers[index]
                                    .fiscalAssistant
                                    ?.collectiveSuggestions ??
                                const [],
                            ibsCbsOfficialSuggestions:
                                _itemControllers[index]
                                    .fiscalAssistant
                                    ?.ibsCbsOfficialSuggestions ??
                                const [],
                            loadingFiscalSuggestion:
                                _itemControllers[index].loadingFiscalSuggestion,
                            onLoadFiscalSuggestion:
                                (_items[index].fiscalProductId ??
                                        _items[index].originalProductId) ==
                                    null
                                ? null
                                : () => _loadFiscalSuggestion(index),
                            onApplyOfficialNcm: (suggestion) => setState(() {
                              _itemControllers[index].ncm.text =
                                  suggestion.code;
                              _itemControllers[index].expanded = true;
                              _itemControllers[index].fiscalSuggestionMessage =
                                  'NCM oficial ${suggestion.code} aplicado. Confira com contador/classificação fiscal antes de emitir.';
                            }),
                            onApplyCollectiveSuggestion: (suggestion) => setState(() {
                              _itemControllers[index].applyCollectiveFiscalSuggestion(
                                suggestion,
                              );
                              _itemControllers[index].expanded = true;
                              _itemControllers[index].fiscalSuggestionMessage =
                                  'Sugestão coletiva aplicada após sua confirmação. Confira os dados fiscais antes de reenviar.';
                            }),
                            onApplyOfficialIbsCbs: (suggestion) => setState(() {
                              _itemControllers[index].ibsCbsCst.text =
                                  suggestion.cst;
                              _itemControllers[index]
                                      .ibsCbsClassification
                                      .text =
                                  suggestion.cclassTrib;
                              _itemControllers[index].expanded = true;
                              _itemControllers[index].fiscalSuggestionMessage =
                                  'IBS/CBS oficial CST ${suggestion.cst} e cClassTrib ${suggestion.cclassTrib} aplicados. Confira a hipótese fiscal antes de emitir.';
                            }),
                            onDelete: _itemControllers.length <= 1
                                ? null
                                : () => setState(() {
                                    _itemControllers[index].dispose();
                                    _itemControllers.removeAt(index);
                                    _items.removeAt(index);
                                  }),
                            onSaveFiscalToProduct:
                                (_items[index].fiscalProductId ??
                                        _items[index].originalProductId) ==
                                    null
                                ? null
                                : () => _saveItemFiscalToProduct(index),
                          ),
                        if (_itemControllers.isNotEmpty &&
                            _itemControllers.any(
                              (item) => item.pendingFields.isNotEmpty,
                            ))
                          Card(
                            color: const Color(0xFFFFF7ED),
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    'Pendências fiscais',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  for (final item in _itemControllers.where(
                                    (item) => item.pendingFields.isNotEmpty,
                                  ))
                                    Text(
                                      '${item.description.text.isEmpty ? 'Produto sem descrição' : item.description.text}: ${item.pendingFields.join(', ')}',
                                    ),
                                ],
                              ),
                            ),
                          ),
                        const SizedBox(height: 4),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(
                            'Total da nota: R\$ ${_itemControllers.fold<double>(0, (sum, item) => sum + item.total).toStringAsFixed(2).replaceAll('.', ',')}',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (isNfe) ...[
                    const SizedBox(height: 16),
                    SectionCard(
                      title: 'Frete, transportadora e volumes',
                      icon: Icons.local_shipping_outlined,
                      child: _FieldGrid(
                        children: [
                          DropdownButtonFormField<String>(
                            initialValue: _freightMode,
                            decoration: const InputDecoration(
                              labelText: 'Modalidade do frete',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: '0',
                                child: Text('0 - Emitente'),
                              ),
                              DropdownMenuItem(
                                value: '1',
                                child: Text('1 - Destinatário'),
                              ),
                              DropdownMenuItem(
                                value: '2',
                                child: Text('2 - Terceiros'),
                              ),
                              DropdownMenuItem(
                                value: '3',
                                child: Text(
                                  '3 - Transporte próprio do remetente',
                                ),
                              ),
                              DropdownMenuItem(
                                value: '4',
                                child: Text(
                                  '4 - Transporte próprio do destinatário',
                                ),
                              ),
                              DropdownMenuItem(
                                value: '9',
                                child: Text('9 - Sem frete'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _freightMode = value ?? '9'),
                          ),
                          _field(_freight, 'Valor do frete', money: true),
                          _field(_insurance, 'Seguro', money: true),
                          _field(_expenses, 'Outras despesas', money: true),
                          _field(_carrierName, 'Transportadora'),
                          _field(_carrierDocument, 'CPF/CNPJ transportadora'),
                          _field(_carrierIe, 'IE transportadora'),
                          _field(_carrierAddress, 'Endereço transportadora'),
                          _field(_carrierCity, 'Cidade transportadora'),
                          _field(_carrierUf, 'UF transportadora'),
                          _field(
                            _volumeQuantity,
                            'Quantidade de volumes',
                            number: true,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                            ],
                          ),
                          _field(_volumeSpecies, 'Espécie'),
                          _field(_volumeBrand, 'Marca'),
                          _field(_volumeNumbering, 'Numeração'),
                          _field(
                            _netWeight,
                            'Peso líquido',
                            number: true,
                            inputFormatters: const [
                              WeightQuantityInputFormatter(),
                            ],
                          ),
                          _field(
                            _grossWeight,
                            'Peso bruto',
                            number: true,
                            inputFormatters: const [
                              WeightQuantityInputFormatter(),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 110),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                border: Border(top: BorderSide(color: Color(0xFFDCE5F0))),
              ),
              child: LayoutBuilder(
                builder: (context, constraints) => Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 10,
                  runSpacing: 8,
                  children: [
                    TextButton(
                      onPressed: _saving ? null : widget.onBack,
                      child: const Text('Cancelar'),
                    ),
                    OutlinedButton.icon(
                      key: const Key('save-draft'),
                      onPressed: _saving ? null : () => _save(false),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Salvar correções'),
                    ),
                    FilledButton.icon(
                      key: const Key('save-resend'),
                      onPressed: _saving ? null : () => _save(true),
                      icon: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.cloud_upload_outlined),
                      label: Text(
                        hasNumber
                            ? 'Salvar e reenviar nº ${document.number}'
                            : 'Salvar e enviar',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool money = false,
    bool number = false,
    List<TextInputFormatter>? inputFormatters,
  }) => TextField(
    controller: controller,
    keyboardType: money || number
        ? const TextInputType.numberWithOptions(decimal: true)
        : null,
    inputFormatters: money ? const [CurrencyInputFormatter()] : inputFormatters,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _FiscalItemControllers {
  _FiscalItemControllers(FiscalDraftItem item)
    : description = TextEditingController(text: item.fiscalDescription),
      quantity = TextEditingController(
        text: formatFiscalQuantity(item.quantity, item.unit),
      ),
      unit = TextEditingController(text: item.unit),
      unitPrice = TextEditingController(
        text: item.unitPrice.toStringAsFixed(2).replaceAll('.', ','),
      ),
      discount = TextEditingController(
        text: item.discountAmount.toStringAsFixed(2).replaceAll('.', ','),
      ),
      ncm = TextEditingController(text: item.ncm ?? ''),
      cest = TextEditingController(text: item.cest ?? ''),
      cfop = TextEditingController(text: item.cfop ?? ''),
      origin = TextEditingController(text: item.origin ?? ''),
      cst = TextEditingController(text: item.cst ?? ''),
      csosn = TextEditingController(text: item.csosn ?? ''),
      pisCst = TextEditingController(text: item.pisCst ?? ''),
      cofinsCst = TextEditingController(text: item.cofinsCst ?? ''),
      cbenef = TextEditingController(text: item.cbenef ?? ''),
      ibsCbsCst = TextEditingController(text: item.ibsCbsCst ?? ''),
      ibsCbsClassification = TextEditingController(
        text: item.ibsCbsClassification ?? '',
      ),
      selectiveTaxCst = TextEditingController(text: item.selectiveTaxCst ?? ''),
      selectiveTaxClassification = TextEditingController(
        text: item.selectiveTaxClassification ?? '',
      ),
      originalTotal = item.totalPrice;

  bool expanded = false;
  bool _valueEdited = false;
  bool loadingFiscalSuggestion = false;
  String? fiscalSuggestionMessage;
  FiscalAssistantResponse? fiscalAssistant;
  final double originalTotal;
  final TextEditingController description;
  final TextEditingController quantity;
  final TextEditingController unit;
  final TextEditingController unitPrice;
  final TextEditingController discount;
  final TextEditingController ncm;
  final TextEditingController cest;
  final TextEditingController cfop;
  final TextEditingController origin;
  final TextEditingController cst;
  final TextEditingController csosn;
  final TextEditingController pisCst;
  final TextEditingController cofinsCst;
  final TextEditingController cbenef;
  final TextEditingController ibsCbsCst;
  final TextEditingController ibsCbsClassification;
  final TextEditingController selectiveTaxCst;
  final TextEditingController selectiveTaxClassification;

  void markValueEdited() => _valueEdited = true;

  double get calculatedTotal =>
      parseFiscalDecimal(quantity.text) * parseFiscalDecimal(unitPrice.text) -
      parseFiscalDecimal(discount.text);

  double get total => _valueEdited ? calculatedTotal : originalTotal;

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
      applied = _fillIfEmpty(pisCst, suggestion.pisCst) || applied;
      applied = _fillIfEmpty(cofinsCst, suggestion.cofinsCst) || applied;
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
    markValueEdited();
  }

  void _replaceIfPresent(TextEditingController controller, String? value) {
    if (value?.trim().isNotEmpty == true) controller.text = value!.trim();
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
    if (description.text.trim().isEmpty) 'descrição fiscal',
    if (parseFiscalDecimal(quantity.text) <= 0) 'quantidade',
    if (parseFiscalDecimal(unitPrice.text) <= 0) 'valor unitário',
    if (ncm.text.trim().isEmpty) 'NCM',
    if (cfop.text.trim().isEmpty) 'CFOP',
    if (origin.text.trim().isEmpty) 'origem da mercadoria',
    if (cst.text.trim().isEmpty && csosn.text.trim().isEmpty) 'CST/CSOSN',
  ];

  FiscalDraftItem buildItem(FiscalDraftItem source) => source.copyWith(
    fiscalDescription: description.text.trim(),
    quantity: parseFiscalDecimal(quantity.text),
    unit: unit.text.trim(),
    unitPrice: parseFiscalDecimal(unitPrice.text),
    discountAmount: parseFiscalDecimal(discount.text),
    totalPrice: total,
    ncm: ncm.text.trim(),
    cest: cest.text.trim(),
    cfop: cfop.text.trim(),
    origin: origin.text.trim(),
    cst: cst.text.trim(),
    csosn: csosn.text.trim(),
    pisCst: pisCst.text.trim(),
    cofinsCst: cofinsCst.text.trim(),
    cbenef: cbenef.text.trim(),
    ibsCbsCst: ibsCbsCst.text.trim(),
    ibsCbsClassification: ibsCbsClassification.text.trim(),
    selectiveTaxCst: selectiveTaxCst.text.trim(),
    selectiveTaxClassification: selectiveTaxClassification.text.trim(),
  );

  void dispose() {
    for (final controller in [
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
      pisCst,
      cofinsCst,
      cbenef,
      ibsCbsCst,
      ibsCbsClassification,
      selectiveTaxCst,
      selectiveTaxClassification,
    ]) {
      controller.dispose();
    }
  }
}

class _FieldGrid extends StatelessWidget {
  const _FieldGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1100
            ? 3
            : constraints.maxWidth >= 680
            ? 2
            : 1;
        const gap = 12.0;
        final width = (constraints.maxWidth - (columns - 1) * gap) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _MessageBanner extends StatelessWidget {
  const _MessageBanner({required this.message, required this.hasNumber});

  final String message;
  final bool hasNumber;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: hasNumber ? const Color(0xFFFFF7ED) : const Color(0xFFFFF1F2),
        border: Border.all(
          color: hasNumber ? const Color(0xFFFDBA74) : const Color(0xFFFDA4AF),
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            hasNumber ? Icons.info_outline : Icons.error_outline,
            color: hasNumber
                ? const Color(0xFFC2410C)
                : const Color(0xFFBE123C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}
