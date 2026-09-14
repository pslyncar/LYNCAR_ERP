import 'package:flutter/material.dart';

import '../domain/pedeon_settings.dart';

class StoreHoursCard extends StatefulWidget {
  const StoreHoursCard({
    super.key,
    required this.initialValue,
    required this.saving,
    required this.onSave,
  });

  final PedeOnDeliveryOperation initialValue;
  final bool saving;
  final Future<bool> Function(PedeOnDeliveryOperation value) onSave;

  @override
  State<StoreHoursCard> createState() => _StoreHoursCardState();
}

class _StoreHoursCardState extends State<StoreHoursCard> {
  late PedeOnDeliveryOperation value;

  static const dayLabels = {
    'monday': 'Segunda',
    'tuesday': 'Terça',
    'wednesday': 'Quarta',
    'thursday': 'Quinta',
    'friday': 'Sexta',
    'saturday': 'Sábado',
    'sunday': 'Domingo',
  };

  @override
  void initState() {
    super.initState();
    value = widget.initialValue;
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(
            value: 'manual',
            icon: Icon(Icons.touch_app_outlined),
            label: Text('Abrir e fechar manualmente'),
          ),
          ButtonSegment(
            value: 'schedule',
            icon: Icon(Icons.schedule_outlined),
            label: Text('Usar horários programados'),
          ),
        ],
        selected: {value.openingMode},
        onSelectionChanged: (selection) => setState(
          () => value = value.copyWith(openingMode: selection.first),
        ),
      ),
      const SizedBox(height: 14),
      if (value.openingMode == 'manual')
        const Text(
          'A equipe controla o atendimento pelo botão “Recebendo pedidos”. O cardápio continua publicado quando a loja fecha.',
        )
      else ...[
        const Text(
          'O atendimento abre e fecha automaticamente no horário local da empresa.',
        ),
        const SizedBox(height: 14),
        for (final day in PedeOnDeliveryOperation.weekDays) _dayRow(day),
      ],
      const SizedBox(height: 16),
      Align(
        alignment: Alignment.centerRight,
        child: FilledButton.icon(
          onPressed: widget.saving ? null : () => widget.onSave(value),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar funcionamento'),
        ),
      ),
    ],
  );

  Widget _dayRow(String key) {
    final day = value.weeklyHours[key] ?? const PedeOnBusinessHoursDay();
    return LayoutBuilder(
      builder: (context, constraints) {
        final controls = [
          OutlinedButton.icon(
            onPressed: day.enabled ? () => _pickTime(key, day, true) : null,
            icon: const Icon(Icons.login),
            label: Text(day.openTime),
          ),
          OutlinedButton.icon(
            onPressed: day.enabled ? () => _pickTime(key, day, false) : null,
            icon: const Icon(Icons.logout),
            label: Text(day.closeTime),
          ),
        ];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: constraints.maxWidth >= 560
              ? Row(
                  children: [
                    SizedBox(width: 130, child: _daySwitch(key, day)),
                    const SizedBox(width: 12),
                    Expanded(child: controls[0]),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('até'),
                    ),
                    Expanded(child: controls[1]),
                  ],
                )
              : Column(
                  children: [
                    _daySwitch(key, day),
                    Row(
                      children: [
                        Expanded(child: controls[0]),
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 8),
                          child: Text('até'),
                        ),
                        Expanded(child: controls[1]),
                      ],
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _daySwitch(String key, PedeOnBusinessHoursDay day) =>
      SwitchListTile.adaptive(
        contentPadding: EdgeInsets.zero,
        title: Text(dayLabels[key]!),
        value: day.enabled,
        onChanged: (enabled) => _updateDay(key, day.copyWith(enabled: enabled)),
      );

  void _updateDay(String key, PedeOnBusinessHoursDay day) {
    final hours = Map<String, PedeOnBusinessHoursDay>.from(value.weeklyHours)
      ..[key] = day;
    setState(() => value = value.copyWith(weeklyHours: hours));
  }

  Future<void> _pickTime(
    String key,
    PedeOnBusinessHoursDay day,
    bool opening,
  ) async {
    final parts = (opening ? day.openTime : day.closeTime).split(':');
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      ),
    );
    if (selected == null) return;
    final formatted =
        '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}';
    _updateDay(
      key,
      opening
          ? day.copyWith(openTime: formatted)
          : day.copyWith(closeTime: formatted),
    );
  }
}
