import 'package:flutter/material.dart';

class FinanceLaunchModeSelector extends StatelessWidget {
  const FinanceLaunchModeSelector({
    super.key,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
  });

  final String selected;
  final ValueChanged<String> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final selector = SegmentedButton<String>(
          showSelectedIcon: false,
          selected: {selected},
          onSelectionChanged: enabled
              ? (value) => onChanged(value.first)
              : null,
          segments: const [
            ButtonSegment(
              value: 'products',
              icon: Icon(Icons.inventory_2_outlined),
              label: Text('Produtos'),
            ),
            ButtonSegment(
              value: 'service',
              icon: Icon(Icons.design_services_outlined),
              label: Text('Serviço'),
            ),
            ButtonSegment(
              value: 'legacy',
              icon: Icon(Icons.history_outlined),
              label: Text('Saldo anterior'),
            ),
          ],
        );
        if (!compact) return selector;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: selector,
        );
      },
    );
  }
}
