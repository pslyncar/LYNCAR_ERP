import 'package:flutter/material.dart';

import '../domain/pedeon_settings.dart';

class DeliveryOperationCard extends StatefulWidget {
  const DeliveryOperationCard({
    super.key,
    required this.initialValue,
    required this.saving,
    required this.onSave,
  });

  final PedeOnDeliveryOperation initialValue;
  final bool saving;
  final Future<bool> Function(PedeOnDeliveryOperation value) onSave;

  @override
  State<DeliveryOperationCard> createState() => _DeliveryOperationCardState();
}

class _DeliveryOperationCardState extends State<DeliveryOperationCard> {
  late PedeOnDeliveryOperation value;
  late final TextEditingController fee;
  late final TextEditingController minimum;
  late final TextEditingController freeAbove;
  late final TextEditingController preparationMin;
  late final TextEditingController preparationMax;

  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
    fee = TextEditingController(text: value.fixedFeeAmount.toStringAsFixed(2));
    minimum = TextEditingController(
      text: value.fixedMinimumOrderAmount.toStringAsFixed(2),
    );
    freeAbove = TextEditingController(
      text: value.fixedFreeDeliveryThreshold?.toStringAsFixed(2) ?? '',
    );
    preparationMin = TextEditingController(
      text: value.preparationMinutesMin.toString(),
    );
    preparationMax = TextEditingController(
      text: value.preparationMinutesMax.toString(),
    );
  }

  @override
  void dispose() {
    for (final item in [
      fee,
      minimum,
      freeAbove,
      preparationMin,
      preparationMax,
    ]) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Como cobrar a entrega?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 10),
      LayoutBuilder(
        builder: (context, constraints) {
          final cards = [
            _choice(
              'fixed',
              Icons.payments_outlined,
              'Taxa fixa',
              'Um único valor para qualquer endereço atendido.',
            ),
            _choice(
              'zones',
              Icons.map_outlined,
              'Por área',
              'Cada raio, bairro ou faixa de CEP possui taxa, mínimo e prazo próprios.',
            ),
          ];
          return constraints.maxWidth >= 650
              ? Row(
                  children: [
                    Expanded(child: cards[0]),
                    const SizedBox(width: 12),
                    Expanded(child: cards[1]),
                  ],
                )
              : Column(
                  children: [cards[0], const SizedBox(height: 10), cards[1]],
                );
        },
      ),
      if (value.pricingMode == 'fixed') ...[
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final fields = [
              _money(fee, 'Taxa fixa'),
              _money(minimum, 'Pedido mínimo'),
              _money(freeAbove, 'Grátis a partir de', optional: true),
            ];
            return constraints.maxWidth >= 760
                ? Row(
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        if (i > 0) const SizedBox(width: 12),
                        Expanded(child: fields[i]),
                      ],
                    ],
                  )
                : Column(
                    children: [
                      for (var i = 0; i < fields.length; i++) ...[
                        fields[i],
                        if (i < fields.length - 1) const SizedBox(height: 12),
                      ],
                    ],
                  );
          },
        ),
      ],
      const Divider(height: 36),
      Text(
        'Previsão mostrada ao cliente',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 4),
      const Text(
        'Informe a faixa normal de preparo. A área pode acrescentar seu próprio prazo de deslocamento.',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(child: _minutes(preparationMin, 'Preparo mínimo')),
          const SizedBox(width: 12),
          Expanded(child: _minutes(preparationMax, 'Preparo máximo')),
        ],
      ),
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: widget.saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar cobrança e prazo'),
        ),
      ),
    ],
  );

  Widget _choice(String mode, IconData icon, String title, String subtitle) {
    final selected = value.pricingMode == mode;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => setState(() => value = value.copyWith(pricingMode: mode)),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE7F7F5) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? const Color(0xFF007F79) : const Color(0xFFD7E0EA),
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          children: [
            Icon(icon, color: selected ? const Color(0xFF007F79) : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 3),
                  Text(subtitle),
                ],
              ),
            ),
            if (selected)
              const Icon(Icons.check_circle, color: Color(0xFF007F79)),
          ],
        ),
      ),
    );
  }

  Widget _money(
    TextEditingController controller,
    String label, {
    bool optional = false,
  }) => TextField(
    controller: controller,
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    decoration: InputDecoration(
      labelText: label,
      prefixText: r'R$ ',
      helperText: optional ? 'Opcional' : null,
    ),
  );

  Widget _minutes(TextEditingController controller, String label) => TextField(
    controller: controller,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(labelText: label, suffixText: 'min'),
  );

  double _decimal(TextEditingController controller) =>
      double.tryParse(controller.text.replaceAll(',', '.')) ?? 0;

  Future<void> _save() async {
    final min = int.tryParse(preparationMin.text) ?? 0;
    final max = int.tryParse(preparationMax.text) ?? 0;
    if (min <= 0 || max <= 0 || min > max) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Revise a faixa de tempo de preparo.')),
      );
      return;
    }
    await widget.onSave(
      value.copyWith(
        fixedFeeAmount: _decimal(fee),
        fixedMinimumOrderAmount: _decimal(minimum),
        fixedFreeDeliveryThreshold: freeAbove.text.trim().isEmpty
            ? null
            : _decimal(freeAbove),
        clearFreeThreshold: freeAbove.text.trim().isEmpty,
        preparationMinutesMin: min,
        preparationMinutesMax: max,
      ),
    );
  }
}
