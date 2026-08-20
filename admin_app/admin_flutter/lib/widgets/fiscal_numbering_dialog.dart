import 'package:flutter/material.dart';

import '../models/fiscal.dart';

class FiscalNumberingDialog extends StatefulWidget {
  const FiscalNumberingDialog({
    super.key,
    required this.initialStatus,
    required this.onSynchronize,
  });

  final FiscalNumberingStatus? initialStatus;
  final Future<FiscalNumberingStatus> Function() onSynchronize;

  @override
  State<FiscalNumberingDialog> createState() => _FiscalNumberingDialogState();
}

class _FiscalNumberingDialogState extends State<FiscalNumberingDialog> {
  FiscalNumberingStatus? _status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    WidgetsBinding.instance.addPostFrameCallback((_) => _synchronize());
  }

  Future<void> _synchronize() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final status = await widget.onSynchronize();
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 920, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 14, 16),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.pin_outlined,
                      color: Color(0xFF0A66D8),
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conferir numeração fiscal',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'Última autorização e próxima emissão de cada modelo.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_loading) ...[
                      const LinearProgressIndicator(minHeight: 3),
                      const SizedBox(height: 12),
                      const Text(
                        'Consultando a numeração e atualizando os dados...',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (_error != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF1F0),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF6C8C4)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Color(0xFFB42318)),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cards = [
                          _NumberingModelCard(
                            key: const Key('nfce-numbering-card'),
                            title: 'NFC-e',
                            model: 'Modelo 65',
                            series: _status?.nfceSeries ?? 1,
                            lastAuthorized: _status?.nfceLastAuthorizedNumber,
                            nextNumber: _status?.nfceNextNumber ?? 1,
                            source: 'Conferida pela SEFAZ-SP',
                            icon: Icons.point_of_sale_outlined,
                          ),
                          _NumberingModelCard(
                            key: const Key('nfe-numbering-card'),
                            title: 'NF-e',
                            model: 'Modelo 55',
                            series: _status?.nfeSeries ?? 1,
                            lastAuthorized: _status?.nfeLastAuthorizedNumber,
                            nextNumber: _status?.nfeNextNumber ?? 1,
                            source: 'Confirmada pelo motor fiscal',
                            icon: Icons.local_shipping_outlined,
                          ),
                        ];
                        if (constraints.maxWidth >= 700) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: cards[0]),
                              const SizedBox(width: 14),
                              Expanded(child: cards[1]),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            cards[0],
                            const SizedBox(height: 12),
                            cards[1],
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'A janela permanece aberta até você fechá-la. Números cancelados continuam considerados utilizados.',
                      style: TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  OutlinedButton.icon(
                    onPressed: _loading ? null : _synchronize,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Consultar novamente'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton(
                    onPressed: _loading
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NumberingModelCard extends StatelessWidget {
  const _NumberingModelCard({
    super.key,
    required this.title,
    required this.model,
    required this.series,
    required this.lastAuthorized,
    required this.nextNumber,
    required this.source,
    required this.icon,
  });

  final String title;
  final String model;
  final int series;
  final int? lastAuthorized;
  final int nextNumber;
  final String source;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD7E2EF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: const Color(0xFF0A66D8)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '$title • $model • Série $series',
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _NumberValue(
                  label: 'Última autorizada',
                  value: lastAuthorized?.toString() ?? 'Nenhuma',
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _NumberValue(
                  label: 'Próxima emissão',
                  value: nextNumber.toString(),
                  highlighted: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            source,
            style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
          ),
        ],
      ),
    );
  }
}

class _NumberValue extends StatelessWidget {
  const _NumberValue({
    required this.label,
    required this.value,
    this.highlighted = false,
  });

  final String label;
  final String value;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.w900,
            color: highlighted
                ? const Color(0xFF0A66D8)
                : const Color(0xFF172235),
          ),
        ),
      ],
    );
  }
}
