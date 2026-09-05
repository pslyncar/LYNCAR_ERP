import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/fiscal_assistant.dart';

double parseFiscalDecimal(String value) =>
    double.tryParse(value.trim().replaceAll('.', '').replaceAll(',', '.')) ?? 0;

String formatFiscalMoney(double value) =>
    value.toStringAsFixed(2).replaceAll('.', ',');

String formatFiscalQuantity(double value, String unit) {
  final normalized = unit.trim().toUpperCase();
  if (normalized == 'KG' || normalized == 'KGS') {
    return value.toStringAsFixed(3).replaceAll('.', ',');
  }
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString().replaceAll('.', ',');
}

String _ibsCbsSuggestionLabel(FiscalIbsCbsOfficialSuggestion suggestion) {
  final descriptions = <String>{
    if (suggestion.name?.trim().isNotEmpty == true) suggestion.name!.trim(),
    if (suggestion.description?.trim().isNotEmpty == true)
      suggestion.description!.trim(),
  };
  final detail = descriptions.join(' — ');
  return 'CST ${suggestion.cst} • cClassTrib ${suggestion.cclassTrib}'
      '${detail.isEmpty ? '' : ' • $detail'}';
}

class FiscalItemCard extends StatelessWidget {
  const FiscalItemCard({
    super.key,
    required this.index,
    required this.productField,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.discount,
    required this.ncm,
    required this.cest,
    required this.cfop,
    required this.origin,
    required this.cst,
    required this.csosn,
    required this.pisCst,
    required this.cofinsCst,
    required this.cbenef,
    required this.ibsCbsCst,
    required this.ibsCbsClassification,
    required this.selectiveTaxCst,
    required this.selectiveTaxClassification,
    required this.total,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onValueChanged,
    this.fiscalSuggestionText,
    this.ncmOfficialSuggestions = const [],
    this.collectiveSuggestions = const [],
    this.ibsCbsOfficialSuggestions = const [],
    this.loadingFiscalSuggestion = false,
    this.onLoadFiscalSuggestion,
    this.onApplyOfficialNcm,
    this.onApplyCollectiveSuggestion,
    this.onApplyOfficialIbsCbs,
    this.onDelete,
    this.onSaveFiscalToProduct,
  });

  final int index;
  final Widget productField;
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
  final double total;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onChanged;
  final ValueChanged<String> onValueChanged;
  final String? fiscalSuggestionText;
  final List<FiscalNcmOfficialSuggestion> ncmOfficialSuggestions;
  final List<FiscalCollectiveSuggestion> collectiveSuggestions;
  final List<FiscalIbsCbsOfficialSuggestion> ibsCbsOfficialSuggestions;
  final bool loadingFiscalSuggestion;
  final VoidCallback? onLoadFiscalSuggestion;
  final ValueChanged<FiscalNcmOfficialSuggestion>? onApplyOfficialNcm;
  final ValueChanged<FiscalCollectiveSuggestion>? onApplyCollectiveSuggestion;
  final ValueChanged<FiscalIbsCbsOfficialSuggestion>? onApplyOfficialIbsCbs;
  final VoidCallback? onDelete;
  final VoidCallback? onSaveFiscalToProduct;

  bool get _isWeight {
    final normalized = unit.text.trim().toUpperCase();
    return normalized == 'KG' || normalized == 'KGS';
  }

  @override
  Widget build(BuildContext context) {
    final unitText = unit.text.trim().isEmpty
        ? 'UN'
        : unit.text.trim().toUpperCase();
    return Card(
      key: ValueKey('fiscal-item-$index'),
      color: const Color(0xFFF8FAFC),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 520, child: productField),
                SizedBox(
                  width: 180,
                  child: _text(
                    quantity,
                    'Quantidade ($unitText)',
                    number: true,
                    inputFormatters: _isWeight
                        ? const [WeightQuantityInputFormatter()]
                        : [FilteringTextInputFormatter.digitsOnly],
                    onChanged: onValueChanged,
                  ),
                ),
                SizedBox(
                  width: 160,
                  child: _text(
                    unitPrice,
                    'Valor unitário',
                    number: true,
                    inputFormatters: const [CurrencyInputFormatter()],
                    onChanged: onValueChanged,
                  ),
                ),
                ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: 180),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Text(
                      'Total do item: R\$ ${formatFiscalMoney(total)}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onToggleExpanded,
                  icon: Icon(expanded ? Icons.expand_less : Icons.tune),
                  label: Text(
                    expanded ? 'Ocultar dados fiscais' : 'Editar dados fiscais',
                  ),
                ),
                if (onLoadFiscalSuggestion != null)
                  OutlinedButton.icon(
                    onPressed: loadingFiscalSuggestion
                        ? null
                        : onLoadFiscalSuggestion,
                    icon: loadingFiscalSuggestion
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(
                      loadingFiscalSuggestion
                          ? 'Buscando sugestão...'
                          : 'Buscar sugestão fiscal',
                    ),
                  ),
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Remover item',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
                if (onSaveFiscalToProduct != null)
                  OutlinedButton.icon(
                    onPressed: onSaveFiscalToProduct,
                    icon: const Icon(Icons.save_as_outlined),
                    label: const Text('Salvar fiscal no produto'),
                  ),
              ],
            ),
            if (fiscalSuggestionText != null &&
                fiscalSuggestionText!.trim().isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF1D4ED8),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        fiscalSuggestionText!,
                        style: const TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (ncmOfficialSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sugestões oficiais de NCM pela descrição',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Use como apoio. NCM precisa ser conferido antes de emitir.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final suggestion in ncmOfficialSuggestions.take(20))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.fact_check_outlined),
                              label: Text(
                                '${suggestion.code} • ${suggestion.description}',
                                softWrap: true,
                                maxLines: null,
                              ),
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: onApplyOfficialNcm == null
                                  ? null
                                  : () => onApplyOfficialNcm!(suggestion),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (collectiveSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  border: Border.all(color: const Color(0xFFFDE68A)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sugestões coletivas do Lyncar',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Classificações confirmadas de forma agregada por outras empresas. Escolha somente após conferir.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    for (final suggestion in collectiveSuggestions)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.groups_outlined),
                          label: Text(
                            'NCM ${suggestion.ncm ?? '-'} • CFOP ${suggestion.cfop ?? '-'} • confirmado por ${suggestion.companiesCount} empresas',
                            softWrap: true,
                            maxLines: null,
                          ),
                          style: OutlinedButton.styleFrom(
                            alignment: Alignment.centerLeft,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                          ),
                          onPressed: onApplyCollectiveSuggestion == null
                              ? null
                              : () => onApplyCollectiveSuggestion!(suggestion),
                        ),
                      ),
                  ],
                ),
              ),
            ],
            if (ibsCbsOfficialSuggestions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4),
                  border: Border.all(color: const Color(0xFFBBF7D0)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sugestões oficiais IBS/CBS',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'Use quando a SEFAZ/homologação exigir IBS/CBS. Confira a hipótese fiscal antes de emitir.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                    const SizedBox(height: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (final suggestion in ibsCbsOfficialSuggestions.take(
                          5,
                        ))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.balance_outlined),
                              label: Text(
                                _ibsCbsSuggestionLabel(suggestion),
                                softWrap: true,
                                maxLines: null,
                              ),
                              style: OutlinedButton.styleFrom(
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                              ),
                              onPressed: onApplyOfficialIbsCbs == null
                                  ? null
                                  : () => onApplyOfficialIbsCbs!(suggestion),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
            if (expanded) ...[
              const SizedBox(height: 12),
              FiscalFieldGrid(
                children: [
                  _text(description, 'Descrição fiscal *'),
                  _text(unit, 'Unidade'),
                  _text(
                    discount,
                    'Desconto',
                    number: true,
                    inputFormatters: const [CurrencyInputFormatter()],
                    onChanged: onValueChanged,
                  ),
                  _text(ncm, 'NCM'),
                  _text(cest, 'CEST'),
                  _text(cfop, 'CFOP'),
                  _text(origin, 'Origem da mercadoria'),
                  _text(cst, 'CST ICMS'),
                  _text(csosn, 'CSOSN'),
                  _text(pisCst, 'CST PIS'),
                  _text(cofinsCst, 'CST COFINS'),
                  _text(cbenef, 'Código de benefício fiscal'),
                  _text(ibsCbsCst, 'CST IBS/CBS'),
                  _text(ibsCbsClassification, 'cClassTrib IBS/CBS'),
                  _text(selectiveTaxCst, 'CST Imposto Seletivo'),
                  _text(
                    selectiveTaxClassification,
                    'cClassTrib Imposto Seletivo',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _text(
    TextEditingController controller,
    String label, {
    bool number = false,
    List<TextInputFormatter>? inputFormatters,
    ValueChanged<String>? onChanged,
  }) => TextField(
    controller: controller,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    inputFormatters: inputFormatters,
    onChanged: onChanged ?? (_) => this.onChanged(),
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
  );
}

class FiscalFieldGrid extends StatelessWidget {
  const FiscalFieldGrid({super.key, required this.children});

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

class CurrencyInputFormatter extends TextInputFormatter {
  const CurrencyInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '0,00',
        selection: TextSelection.collapsed(offset: 4),
      );
    }
    final cents = int.parse(digits);
    final text = '${cents ~/ 100},${(cents % 100).toString().padLeft(2, '0')}';
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}

class WeightQuantityInputFormatter extends TextInputFormatter {
  const WeightQuantityInputFormatter();

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(
        text: '0,000',
        selection: TextSelection.collapsed(offset: 5),
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
