import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/fiscal.dart';
import '../widgets/app_card.dart';

class FiscalDocumentCorrectionScreen extends StatefulWidget {
  const FiscalDocumentCorrectionScreen({
    super.key,
    required this.document,
    required this.clients,
    required this.onBack,
    required this.onSave,
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
    _freightMode = document.freightMode ?? '9';
    _clientId = document.fiscalClientId;
    _itemControllers = document.fiscalItems
        .map(_FiscalItemControllers.new)
        .toList();
  }

  TextEditingController _moneyController(double value) => TextEditingController(
    text: value.toStringAsFixed(2).replaceAll('.', ','),
  );

  TextEditingController _numberController(double? value) =>
      TextEditingController(text: value?.toString().replaceAll('.', ',') ?? '');

  double _decimal(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? 0;

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
        'consumer_cpf': _cpf.text.trim(),
        'finality': _finality,
        'payment_condition': _payment,
        'freight_mode': _freightMode,
        'freight_amount': _decimal(_freight),
        'insurance_amount': _decimal(_insurance),
        'other_expenses_amount': _decimal(_expenses),
        'carrier_name': _carrierName.text.trim(),
        'carrier_document': _carrierDocument.text.trim(),
        'carrier_state_registration': _carrierIe.text.trim(),
        'carrier_address': _carrierAddress.text.trim(),
        'carrier_city': _carrierCity.text.trim(),
        'carrier_uf': _carrierUf.text.trim().toUpperCase(),
        'volume_quantity': _decimal(_volumeQuantity),
        'volume_species': _volumeSpecies.text.trim(),
        'volume_brand': _volumeBrand.text.trim(),
        'volume_numbering': _volumeNumbering.text.trim(),
        'net_weight': _decimal(_netWeight),
        'gross_weight': _decimal(_grossWeight),
      };
      final items = <FiscalDraftItem>[
        for (var index = 0; index < widget.document.fiscalItems.length; index++)
          _itemControllers[index].buildItem(widget.document.fiscalItems[index]),
      ];
      await widget.onSave(
        {
          ...fields,
          'operation_nature': _nature.text.trim(),
          'fiscal_notes': _notes.text.trim(),
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

  @override
  Widget build(BuildContext context) {
    final document = widget.document;
    final hasNumber = document.number != null;
    final isNfe = document.documentType == 'nfe';
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
                          initialSelection: _clientId,
                          enableFilter: true,
                          enableSearch: true,
                          requestFocusOnTap: true,
                          label: const Text('Cliente/destinatário'),
                          hintText: 'Buscar por nome ou CPF/CNPJ',
                          onSelected: (value) =>
                              setState(() => _clientId = value),
                          dropdownMenuEntries: widget.clients
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
                          _FiscalItemEditor(
                            index: index,
                            source: document.fiscalItems[index],
                            controllers: _itemControllers[index],
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
                                value: '9',
                                child: Text('9 - Sem frete'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _freightMode = value ?? '9'),
                          ),
                          _field(_freight, 'Valor do frete'),
                          _field(_insurance, 'Seguro'),
                          _field(_expenses, 'Outras despesas'),
                          _field(_carrierName, 'Transportadora'),
                          _field(_carrierDocument, 'CPF/CNPJ transportadora'),
                          _field(_carrierIe, 'IE transportadora'),
                          _field(_carrierAddress, 'Endereço transportadora'),
                          _field(_carrierCity, 'Cidade transportadora'),
                          _field(_carrierUf, 'UF transportadora'),
                          _field(_volumeQuantity, 'Quantidade de volumes'),
                          _field(_volumeSpecies, 'Espécie'),
                          _field(_volumeBrand, 'Marca'),
                          _field(_volumeNumbering, 'Numeração'),
                          _field(_netWeight, 'Peso líquido'),
                          _field(_grossWeight, 'Peso bruto'),
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

  Widget _field(TextEditingController controller, String label) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class _FiscalItemControllers {
  _FiscalItemControllers(FiscalDraftItem item)
    : description = TextEditingController(text: item.fiscalDescription),
      quantity = TextEditingController(text: item.quantity.toString()),
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
      cbenef = TextEditingController(text: item.cbenef ?? '');

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

  double _decimal(TextEditingController value) =>
      double.tryParse(value.text.trim().replaceAll(',', '.')) ?? 0;

  FiscalDraftItem buildItem(FiscalDraftItem source) => source.copyWith(
    fiscalDescription: description.text.trim(),
    quantity: _decimal(quantity),
    unit: unit.text.trim(),
    unitPrice: _decimal(unitPrice),
    discountAmount: _decimal(discount),
    ncm: ncm.text.trim(),
    cest: cest.text.trim(),
    cfop: cfop.text.trim(),
    origin: origin.text.trim(),
    cst: cst.text.trim(),
    csosn: csosn.text.trim(),
    pisCst: pisCst.text.trim(),
    cofinsCst: cofinsCst.text.trim(),
    cbenef: cbenef.text.trim(),
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
    ]) {
      controller.dispose();
    }
  }
}

class _FiscalItemEditor extends StatelessWidget {
  const _FiscalItemEditor({
    required this.index,
    required this.source,
    required this.controllers,
  });

  final int index;
  final FiscalDraftItem source;
  final _FiscalItemControllers controllers;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          side: const BorderSide(color: Color(0xFFDCE5F0)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: ExpansionTile(
          initiallyExpanded: index == 0,
          title: Text(
            '${index + 1}. ${source.fiscalDescription}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: Text(
            'NCM ${source.ncm?.isNotEmpty == true ? source.ncm : 'pendente'} • CFOP ${source.cfop?.isNotEmpty == true ? source.cfop : 'automático'}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          children: [
            _FieldGrid(
              children: [
                _text(controllers.description, 'Descrição fiscal'),
                _text(controllers.quantity, 'Quantidade'),
                _text(controllers.unit, 'Unidade'),
                _text(controllers.unitPrice, 'Valor unitário'),
                _text(controllers.discount, 'Desconto'),
                _text(controllers.ncm, 'NCM'),
                _text(controllers.cest, 'CEST'),
                _text(controllers.cfop, 'CFOP'),
                _text(controllers.origin, 'Origem da mercadoria'),
                _text(controllers.cst, 'CST ICMS'),
                _text(controllers.csosn, 'CSOSN'),
                _text(controllers.pisCst, 'CST PIS'),
                _text(controllers.cofinsCst, 'CST COFINS'),
                _text(controllers.cbenef, 'Código de benefício fiscal'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _text(TextEditingController controller, String label) => TextField(
    controller: controller,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
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
