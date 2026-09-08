import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/app_session_storage.dart';

class TourTargetKeys {
  final search = GlobalKey();
  final company = GlobalKey();
  final notices = GlobalKey();
  final metrics = GlobalKey();
  final activities = GlobalKey();
  final shortcuts = GlobalKey();
  final finance = GlobalKey();
  final menu = GlobalKey();
}

class TourTargets extends InheritedWidget {
  const TourTargets({super.key, required this.targets, required super.child});
  final TourTargetKeys targets;

  static TourTargetKeys of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<TourTargets>()!.targets;

  @override
  bool updateShouldNotify(TourTargets oldWidget) =>
      targets != oldWidget.targets;
}

class FirstAccessTour extends StatefulWidget {
  const FirstAccessTour({
    super.key,
    required this.session,
    required this.child,
  });
  final Session session;
  final Widget child;

  @override
  State<FirstAccessTour> createState() => _FirstAccessTourState();
}

class _FirstAccessTourState extends State<FirstAccessTour> {
  final _storage = AppSessionStorage();
  final _targets = TourTargetKeys();
  int _step = 0;
  bool _loading = true;
  bool _visible = false;

  String get _storageKey =>
      'lyncar.first-access-tour.v3.${widget.session.companyCode}.${widget.session.userId ?? widget.session.role}';

  List<_TourStep> get _steps => [
    _TourStep(
      'Comece por aqui',
      'O painel inicial da sua empresa.',
      Icons.dashboard_outlined,
      _targets.company,
      const Color(0xFF2563EB),
    ),
    _TourStep(
      'Central de avisos',
      'Mensalidades e comunicados importantes ficam neste card. Clique no card inteiro para abrir.',
      Icons.notifications_active_outlined,
      _targets.notices,
      const Color(0xFFD97706),
    ),
    _TourStep(
      'Indicadores',
      'Veja vendas, pedidos, contas a receber e estoque baixo com dados reais.',
      Icons.insights_outlined,
      _targets.metrics,
      const Color(0xFF059669),
    ),
    _TourStep(
      'Atividades recentes',
      'Acompanhe movimentações recentes, como vendas e alertas de estoque.',
      Icons.history_outlined,
      _targets.activities,
      const Color(0xFF7C3AED),
    ),
    if (widget.session.can('sales:create') ||
        widget.session.can('products:create') ||
        widget.session.can('clients:view'))
      _TourStep(
        'Atalhos rápidos',
        'Abra diretamente as funções liberadas para o seu usuário.',
        Icons.flash_on_outlined,
        _targets.shortcuts,
        const Color(0xFF0F766E),
      ),
    if (widget.session.can('finance:view') ||
        widget.session.can('finance:receivables:view'))
      _TourStep(
        'Resumo financeiro',
        'Acompanhe valores a vencer, vencidos e recebidos.',
        Icons.account_balance_wallet_outlined,
        _targets.finance,
        const Color(0xFFDC2626),
      ),
    _TourStep(
      'Busca no topo e menu lateral',
      'Use o campo de busca no topo ou o menu lateral para acessar os módulos liberados.',
      Icons.menu_open,
      _targets.search,
      const Color(0xFF1D4ED8),
      additionalTargets: [_targets.menu],
    ),
  ];

  @override
  void initState() {
    super.initState();
    _loadStatus();
  }

  Future<void> _loadStatus() async {
    final completed = await _storage.read(_storageKey);
    if (!mounted) return;
    setState(() {
      _loading = false;
      _visible = completed != 'true';
    });
  }

  Future<void> _finish() async {
    await _storage.write(_storageKey, 'true');
    if (mounted) setState(() => _visible = false);
  }

  Future<void> _next() async {
    final steps = _steps;
    if (_step == steps.length - 1) return _finish();
    final nextStep = _step + 1;
    setState(() => _step = nextStep);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    final targetContext = steps[nextStep].target.currentContext;
    if (targetContext != null && targetContext.mounted) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeOut,
        alignment: nextStep == steps.length - 1 ? .04 : .25,
      );
      await WidgetsBinding.instance.endOfFrame;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = TourTargets(targets: _targets, child: widget.child);
    if (_loading || !_visible) return child;
    final steps = _steps;
    final current = steps[_step];
    final targetRects = <Rect>[];
    for (final target in [current.target, ...current.additionalTargets]) {
      final renderObject = target.currentContext?.findRenderObject();
      if (renderObject is RenderBox && renderObject.hasSize) {
        targetRects.add(
          renderObject.localToGlobal(Offset.zero) & renderObject.size,
        );
      }
    }
    final rect = targetRects.isEmpty ? null : targetRects.first;
    return Stack(
      fit: StackFit.expand,
      children: [
        AbsorbPointer(absorbing: true, child: child),
        const ModalBarrier(dismissible: false, color: Colors.transparent),
        IgnorePointer(
          child: CustomPaint(painter: _SpotlightPainter(targetRects)),
        ),
        _TourCard(
          step: current,
          stepNumber: _step + 1,
          total: steps.length,
          targetRect: rect,
          onSkip: _finish,
          onNext: _next,
          last: _step == steps.length - 1,
        ),
      ],
    );
  }
}

class _TourCard extends StatelessWidget {
  const _TourCard({
    required this.step,
    required this.stepNumber,
    required this.total,
    required this.targetRect,
    required this.onSkip,
    required this.onNext,
    required this.last,
  });
  final _TourStep step;
  final int stepNumber;
  final int total;
  final Rect? targetRect;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const margin = 18.0;
    const gap = 18.0;
    const estimatedHeight = 292.0;
    final width = (size.width - margin * 2).clamp(280.0, 360.0);
    double left;
    double top;
    if (step.additionalTargets.isNotEmpty) {
      left = (size.width - width) / 2;
      final belowSearch = (targetRect?.bottom ?? margin) + gap;
      top = belowSearch + estimatedHeight <= size.height - margin
          ? belowSearch
          : size.height - estimatedHeight - margin;
    } else if (targetRect == null) {
      left = (size.width - width) / 2;
      top = (size.height - estimatedHeight) / 2;
    } else if (targetRect!.right + gap + width <= size.width - margin) {
      left = targetRect!.right + gap;
      top = (targetRect!.center.dy - estimatedHeight / 2).clamp(
        margin,
        size.height - estimatedHeight - margin,
      );
    } else if (targetRect!.left - gap - width >= margin) {
      left = targetRect!.left - gap - width;
      top = (targetRect!.center.dy - estimatedHeight / 2).clamp(
        margin,
        size.height - estimatedHeight - margin,
      );
    } else {
      left = (size.width - width) / 2;
      final below = targetRect!.bottom + estimatedHeight + gap <= size.height;
      top = below
          ? targetRect!.bottom + gap
          : targetRect!.top - estimatedHeight - gap;
      top = top.clamp(margin, size.height - estimatedHeight - margin);
    }
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: Material(
        color: Colors.white,
        elevation: 22,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(step.icon, color: step.color, size: 25),
                  const Spacer(),
                  Text(
                    '$stepNumber/$total',
                    style: const TextStyle(
                      color: Color(0xFF71839B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                step.title,
                style: const TextStyle(
                  color: Color(0xFF13233B),
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                step.description,
                style: const TextStyle(color: Color(0xFF5E718B), height: 1.35),
              ),
              if (step.additionalTargets.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: const [
                    _TourLabel(text: 'Campo de busca'),
                    _TourLabel(text: 'Menu lateral'),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              LinearProgressIndicator(
                value: stepNumber / total,
                minHeight: 5,
                color: step.color,
                backgroundColor: const Color(0xFFE7EDF5),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  TextButton(onPressed: onSkip, child: const Text('Pular')),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onNext,
                    icon: Icon(last ? Icons.check : Icons.arrow_forward),
                    label: Text(last ? 'Começar' : 'Próximo'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TourLabel extends StatelessWidget {
  const _TourLabel({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEAF1FF),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFB9D0FF)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF245CC6),
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SpotlightPainter extends CustomPainter {
  const _SpotlightPainter(this.targetRects);
  final List<Rect> targetRects;

  @override
  void paint(Canvas canvas, Size size) {
    final overlay = Paint()..color = Colors.black.withValues(alpha: .58);
    canvas.saveLayer(Offset.zero & size, Paint());
    if (targetRects.isEmpty) {
      canvas.drawRect(Offset.zero & size, overlay);
      canvas.restore();
      return;
    }
    final path = Path()..addRect(Offset.zero & size);
    final highlights = [
      for (final rect in targetRects)
        RRect.fromRectAndRadius(rect.inflate(8), const Radius.circular(14)),
    ];
    for (final highlight in highlights) {
      path.addRRect(highlight);
    }
    canvas.drawPath(path, overlay);
    final cutout = Paint()..blendMode = BlendMode.dstOut;
    for (final highlight in highlights) {
      canvas.drawRRect(highlight, cutout);
    }
    final border = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;
    for (final highlight in highlights) {
      canvas.drawRRect(highlight, border);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SpotlightPainter oldDelegate) =>
      oldDelegate.targetRects != targetRects;
}

class _TourStep {
  const _TourStep(
    this.title,
    this.description,
    this.icon,
    this.target,
    this.color, {
    this.additionalTargets = const [],
  });
  final String title;
  final String description;
  final IconData icon;
  final GlobalKey target;
  final Color color;
  final List<GlobalKey> additionalTargets;
}
