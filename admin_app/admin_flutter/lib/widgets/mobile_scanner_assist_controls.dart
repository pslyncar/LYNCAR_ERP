import 'package:flutter/material.dart';

class MobileScannerAssistControls extends StatelessWidget {
  const MobileScannerAssistControls({
    super.key,
    required this.zoom,
    required this.smallCodeMode,
    required this.onZoomChanged,
    required this.onSmallCodeToggle,
    required this.onTorchToggle,
  });

  final double zoom;
  final bool smallCodeMode;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onSmallCodeToggle;
  final VoidCallback onTorchToggle;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD8E2EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: onSmallCodeToggle,
                    icon: const Icon(Icons.center_focus_strong_outlined),
                    label: Text(
                      smallCodeMode
                          ? 'Codigo pequeno ativo'
                          : 'Codigo pequeno / zoom',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filledTonal(
                  tooltip: 'Ligar/desligar lanterna',
                  onPressed: onTorchToggle,
                  icon: const Icon(Icons.flashlight_on_outlined),
                ),
              ],
            ),
            Row(
              children: [
                const Icon(
                  Icons.zoom_in_outlined,
                  color: Color(0xFF64748B),
                  size: 20,
                ),
                Expanded(
                  child: Slider(
                    value: zoom.clamp(0, 1),
                    onChanged: onZoomChanged,
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: Text(
                    '${(zoom * 100).round()}%',
                    textAlign: TextAlign.end,
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const Text(
              'Para codigo pequeno, aproxime um pouco e ajuste o zoom ate a camera focar.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
