import 'package:flutter/material.dart';

import '../models/cash_closing.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

class CashClosingsScreen extends StatefulWidget {
  const CashClosingsScreen({super.key, required this.session});

  final Session session;

  @override
  State<CashClosingsScreen> createState() => _CashClosingsScreenState();
}

class _CashClosingsScreenState extends State<CashClosingsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<CashClosing> _closings = [];
  final _search = TextEditingController();
  String _statusFilter = 'todos';
  bool _differenceOnly = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _openClosing(CashClosing closing) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _CashClosingDialog(
        api: _api,
        token: widget.session.token,
        closing: closing,
        canReview: widget.session.can('pdv_operators:manage'),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final closings = await _api.listCashClosings(widget.session.token);
      setState(() {
        _closings = closings;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar os fechamentos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredClosings = _filteredClosings();
    final pending = _closings
        .where((closing) => closing.status == 'pending_treasury')
        .length;
    final divergent = _closings
        .where((closing) => closing.cashDifferenceAmount.abs() >= 0.01)
        .length;
    final total = _closings.fold<double>(
      0,
      (sum, closing) => sum + closing.totalSalesAmount,
    );

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Caixa',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Fechamentos enviados para conferência',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Atualizar',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 920 ? 3 : 1;
                final items = [
                  _Summary('Pendentes', pending, Icons.pending_actions),
                  _Summary('Com diferenca', divergent, Icons.warning_amber),
                  _Summary(
                    'Total fechado',
                    total,
                    Icons.payments_outlined,
                    money: true,
                  ),
                ];
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 86,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) =>
                      _SummaryTile(summary: items[index]),
                );
              },
            ),
            const SizedBox(height: 18),
            AppCard(
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        labelText: 'Buscar fechamentos',
                        hintText: 'Código, operador, status...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statusFilter,
                      decoration: const InputDecoration(
                        labelText: 'Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'todos', child: Text('Todos')),
                        DropdownMenuItem(
                          value: 'pending_treasury',
                          child: Text('Pendente tesouraria'),
                        ),
                        DropdownMenuItem(
                          value: 'approved',
                          child: Text('Aprovado'),
                        ),
                        DropdownMenuItem(
                          value: 'divergent',
                          child: Text('Divergente'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _statusFilter = value ?? 'todos'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilterChip(
                    selected: _differenceOnly,
                    onSelected: (value) =>
                        setState(() => _differenceOnly = value),
                    label: const Text('Com diferenca'),
                    avatar: const Icon(Icons.warning_amber_outlined),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    tooltip: 'Limpar busca',
                    onPressed: () => setState(() {
                      _search.clear();
                      _statusFilter = 'todos';
                      _differenceOnly = false;
                    }),
                    icon: const Icon(Icons.clear),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: filteredClosings.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum fechamento encontrado.'),
                      )
                    : _ClosingsTable(
                        closings: filteredClosings,
                        onOpen: _openClosing,
                      ),
              ),
          ],
        ),
      ),
    );
  }

  List<CashClosing> _filteredClosings() {
    final term = _normalize(_search.text);
    return _closings.where((closing) {
      if (_statusFilter != 'todos' && closing.status != _statusFilter) {
        return false;
      }
      if (_differenceOnly && closing.cashDifferenceAmount.abs() < 0.01) {
        return false;
      }
      if (term.isEmpty) return true;
      final haystack = _normalize(
        [
          closing.number,
          closing.operatorName,
          closing.status,
          closing.notes,
          closing.treasuryNotes,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }
}

class _ClosingsTable extends StatelessWidget {
  const _ClosingsTable({required this.closings, required this.onOpen});

  final List<CashClosing> closings;
  final ValueChanged<CashClosing> onOpen;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDataTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Fechamento')),
          DataColumn(label: Text('Operador')),
          DataColumn(label: Text('Fechou em')),
          DataColumn(label: Text('Vendas')),
          DataColumn(label: Text('Esperado sem fundo')),
          DataColumn(label: Text('Contado')),
          DataColumn(label: Text('Diferenca')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Acoes')),
        ],
        rows: [
          for (final closing in closings)
            DataRow(
              onSelectChanged: (_) => onOpen(closing),
              cells: [
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(closing.number ?? 'CX${closing.id}'),
                      if (closing.crossedBusinessDay) ...[
                        const SizedBox(width: 6),
                        const Tooltip(
                          message: 'Atravessou o dia comercial',
                          child: Icon(
                            Icons.warning_amber_outlined,
                            size: 19,
                            color: Color(0xFFB45309),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                DataCell(Text(closing.operatorName ?? '-')),
                DataCell(Text(_dateTime(closing.closedAt))),
                DataCell(Text(_money(closing.totalSalesAmount))),
                DataCell(Text(_money(closing.expectedCashAmount))),
                DataCell(Text(_money(closing.countedCashAmount))),
                DataCell(
                  Text(
                    _money(closing.cashDifferenceAmount),
                    style: TextStyle(
                      color: closing.cashDifferenceAmount.abs() >= 0.01
                          ? const Color(0xFFB91C1C)
                          : const Color(0xFF047857),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                DataCell(Text(_statusLabel(closing.status))),
                DataCell(
                  IconButton(
                    tooltip: 'Conferir ou editar fechamento',
                    onPressed: () => onOpen(closing),
                    icon: const Icon(Icons.fact_check_outlined),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _CashClosingDialog extends StatefulWidget {
  const _CashClosingDialog({
    required this.api,
    required this.token,
    required this.closing,
    required this.canReview,
  });

  final ApiClient api;
  final String token;
  final CashClosing closing;
  final bool canReview;

  @override
  State<_CashClosingDialog> createState() => _CashClosingDialogState();
}

class _CashClosingDialogState extends State<_CashClosingDialog> {
  final _notes = TextEditingController();
  final _countedCash = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _notes.text = widget.closing.treasuryNotes ?? '';
    _countedCash.text = formatBrazilianMoneyInput(
      widget.closing.countedCashAmount,
    );
  }

  @override
  void dispose() {
    _notes.dispose();
    _countedCash.dispose();
    super.dispose();
  }

  Future<void> _review(
    String status, {
    bool requireDivergenceNote = true,
  }) async {
    if (requireDivergenceNote &&
        status == 'divergent' &&
        _notes.text.trim().isEmpty) {
      setState(() => _error = 'Informe o motivo da divergencia.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.reviewCashClosing(
        widget.token,
        widget.closing.id,
        CashClosingReviewPayload(
          status: status,
          notes: _notes.text,
          countedCashAmount: parseBrazilianNumber(_countedCash.text),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível revisar o fechamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final closing = widget.closing;
    final expectedTotal =
        _paymentAmount(closing, 'dinheiro') -
        closing.totalWithdrawalAmount +
        closing.totalSupplyAmount;
    return Dialog(
      insetPadding: const EdgeInsets.all(20),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 980, maxHeight: 760),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Conferência ${closing.number ?? 'CX${closing.id}'}',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Operador ${closing.operatorName ?? '-'} | ${_dateTime(closing.closedAt)}',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  _StatusChip(status: closing.status),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (closing.crossedBusinessDay) ...[
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF7ED),
                    border: Border.all(color: const Color(0xFFF59E0B)),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.warning_amber_outlined,
                          color: Color(0xFFB45309),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Esta sessão atravessou o dia comercial. '
                            'Dia de referência: ${_dateOnly(closing.businessDate)}; '
                            'corte configurado: ${_time(closing.businessDayCutoffMinutes)}.',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.maxWidth >= 760 ? 4 : 2;
                          final cards = [
                            _Summary(
                              'Fundo inicial',
                              closing.openingAmount,
                              Icons.savings_outlined,
                              money: true,
                            ),
                            _Summary(
                              'Vendas',
                              closing.totalSalesAmount,
                              Icons.point_of_sale_outlined,
                              money: true,
                            ),
                            _Summary(
                              'Esperado sem fundo',
                              closing.expectedCashAmount,
                              Icons.payments_outlined,
                              money: true,
                            ),
                            _Summary(
                              'Diferenca',
                              closing.cashDifferenceAmount,
                              closing.cashDifferenceAmount.abs() >= 0.01
                                  ? Icons.warning_amber_outlined
                                  : Icons.check_circle_outline,
                              money: true,
                            ),
                          ];
                          return GridView.builder(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: cards.length,
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  mainAxisExtent: 86,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemBuilder: (context, index) =>
                                _SummaryTile(summary: cards[index]),
                          );
                        },
                      ),
                      const SizedBox(height: 16),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _SectionTitle('Resumo do dinheiro'),
                            _ReviewLine('Fundo inicial', closing.openingAmount),
                            _ReviewLine(
                              'Fundo retirado antes da contagem',
                              -closing.openingAmount,
                            ),
                            _ReviewLine(
                              'Vendas em dinheiro',
                              _paymentAmount(closing, 'dinheiro'),
                            ),
                            _ReviewLine(
                              'Sangrias',
                              -closing.totalWithdrawalAmount,
                            ),
                            _ReviewLine(
                              'Suprimentos',
                              closing.totalSupplyAmount,
                            ),
                            const Divider(height: 20),
                            _ReviewLine(
                              'Esperado após retirar o fundo',
                              expectedTotal,
                              strong: true,
                            ),
                            _ReviewLine(
                              'Esperado registrado',
                              closing.expectedCashAmount,
                            ),
                            _ReviewLine(
                              'Contado pelo operador',
                              closing.countedCashAmount,
                              strong: true,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _SectionTitle('Formas de pagamento'),
                            if (closing.payments.isEmpty)
                              const Text('Nenhum pagamento informado.')
                            else
                              for (final payment in closing.payments)
                                _ReviewLine(
                                  _paymentLabel(payment.method),
                                  payment.amount,
                                ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      AppCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            const _SectionTitle('Movimentos do caixa'),
                            if (closing.movements.isEmpty)
                              const Text('Nenhuma sangria ou suprimento.')
                            else
                              for (final movement in closing.movements)
                                ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: Icon(
                                    movement.movementType == 'sangria'
                                        ? Icons.south_west
                                        : Icons.north_east,
                                  ),
                                  title: Text(
                                    '${_movementLabel(movement.movementType)} - ${_money(movement.amount)}',
                                  ),
                                  subtitle: Text(
                                    [
                                      if (movement.createdAt != null)
                                        _dateTime(movement.createdAt!),
                                      if (movement.reason != null &&
                                          movement.reason!.isNotEmpty)
                                        movement.reason!,
                                    ].join(' | '),
                                  ),
                                ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (closing.notes != null && closing.notes!.isNotEmpty)
                        AppCard(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const _SectionTitle('Observação do operador'),
                              Text(closing.notes!),
                            ],
                          ),
                        ),
                      if (widget.canReview) ...[
                        const SizedBox(height: 12),
                        TextField(
                          controller: _countedCash,
                          keyboardType: TextInputType.text,
                          inputFormatters: const [
                            BrazilianMoneyInputFormatter(),
                          ],
                          decoration: const InputDecoration(
                            labelText: 'Contagem corrigida',
                            helperText:
                                'Use quando o dinheiro foi contado errado no fechamento. O fundo inicial não entra nesta contagem.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _notes,
                          minLines: 2,
                          maxLines: 4,
                          decoration: const InputDecoration(
                            labelText: 'Observação da tesouraria',
                            hintText:
                                'Obrigatorio se marcar divergencia. Opcional para aprovacao.',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                      if (_error != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFFB91C1C),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Fechar'),
                  ),
                  if (widget.canReview) ...[
                    OutlinedButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _review(
                              closing.status,
                              requireDivergenceNote: false,
                            ),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Salvar correção'),
                    ),
                    if (closing.status == 'pending_treasury') ...[
                      OutlinedButton.icon(
                        onPressed: _saving ? null : () => _review('divergent'),
                        icon: const Icon(Icons.report_problem_outlined),
                        label: const Text('Marcar divergencia'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : () => _review('approved'),
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('Aprovar fechamento'),
                      ),
                    ],
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Summary {
  const _Summary(this.label, this.value, this.icon, {this.money = false});
  final String label;
  final Object value;
  final IconData icon;
  final bool money;
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _ReviewLine extends StatelessWidget {
  const _ReviewLine(this.label, this.value, {this.strong = false});

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    final color = value < 0 ? const Color(0xFFB91C1C) : const Color(0xFF0F172A);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF475569),
                fontWeight: strong ? FontWeight.w900 : FontWeight.w500,
              ),
            ),
          ),
          Text(
            _money(value),
            style: TextStyle(
              color: strong ? color : const Color(0xFF0F172A),
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    final color = switch (status) {
      'approved' => const Color(0xFF047857),
      'divergent' => const Color(0xFFB91C1C),
      _ => const Color(0xFFB45309),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          _statusLabel(status),
          style: TextStyle(color: color, fontWeight: FontWeight.w900),
        ),
      ),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.summary});
  final _Summary summary;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(summary.icon, color: const Color(0xFF2563EB)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    summary.label,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                  Text(
                    summary.money
                        ? _money(summary.value as double)
                        : '${summary.value}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w900,
                    ),
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

String _statusLabel(String value) {
  return switch (value) {
    'pending_treasury' => 'Pendente tesouraria',
    'approved' => 'Aprovado',
    'divergent' => 'Divergente',
    _ => value,
  };
}

String _paymentLabel(String value) {
  return switch (value) {
    'dinheiro' || 'Dinheiro' => 'Dinheiro',
    'pix' || 'Pix' => 'Pix',
    'cartao_credito' || 'Credito' => 'Cartão de crédito',
    'cartao_debito' || 'Debito' => 'Cartão de débito',
    'credito' => 'Crédito',
    'debito' => 'Débito',
    'crediario' => 'Crediário',
    'transferencia' => 'Transferência',
    _ => value,
  };
}

String _movementLabel(String value) {
  return switch (value) {
    'sangria' => 'Sangria',
    'suprimento' => 'Suprimento',
    _ => value,
  };
}

double _paymentAmount(CashClosing closing, String method) {
  final normalized = method.toLowerCase();
  return closing.payments.fold<double>(0, (sum, payment) {
    if (payment.method.toLowerCase() != normalized) return sum;
    return sum + payment.amount;
  });
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';

String _dateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(value.day)}/${two(value.month)}/${value.year} ${two(value.hour)}:${two(value.minute)}';
}

String _dateOnly(DateTime? value) {
  if (value == null) return '-';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _time(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _normalize(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'õ': 'o',
    'ô': 'o',
    'ú': 'u',
    'ç': 'c',
  };
  var normalized = value.toLowerCase().trim();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}
