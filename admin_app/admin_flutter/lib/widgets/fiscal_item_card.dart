import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    required this.total,
    required this.expanded,
    required this.onToggleExpanded,
    required this.onChanged,
    required this.onValueChanged,
    this.onDelete,
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
  final double total;
  final bool expanded;
  final VoidCallback onToggleExpanded;
  final VoidCallback onChanged;
  final ValueChanged<String> onValueChanged;
  final VoidCallback? onDelete;

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
                if (onDelete != null)
                  IconButton(
                    tooltip: 'Remover item',
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline),
                  ),
              ],
            ),
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
