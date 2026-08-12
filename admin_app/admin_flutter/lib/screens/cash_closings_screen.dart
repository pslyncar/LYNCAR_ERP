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
  DateTime? _startDate;
  DateTime? _endDate;
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
        canReview:
            widget.session.can('cash_closings:manage') ||
            widget.session.can('pdv_operators:manage'),
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
    final pending = filteredClosings
        .where((closing) => closing.status == 'pending_treasury')
        .length;
    final divergent = filteredClosings
        .where((closing) => closing.cashDifferenceAmount.abs() >= 0.01)
        .length;
    final approved = filteredClosings
        .where((closing) => closing.status == 'approved')
        .length;
    final total = filteredClosings.fold<double>(
      0,
      (sum, closing) => sum + closing.totalSalesAmount,
    );
    final differenceTotal = filteredClosings.fold<double>(
      0,
      (sum, closing) => sum + closing.cashDifferenceAmount,
    );
    final withdrawalsTotal = _sumMovements(filteredClosings, 'sangria');
    final suppliesTotal = _sumMovements(filteredClosings, 'suprimento');
    final paymentTotals = _paymentTotals(filteredClosings);
    final hasDifference = differenceTotal.abs() >= 0.01;

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
                        'Caixa e tesouraria',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Conferência de fechamentos, divergências e formas de pagamento',
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
                final columns = constraints.maxWidth >= 1180
                    ? 4
                    : constraints.maxWidth >= 760
                    ? 2
                    : 1;
                final items = [
                  const _Summary(
                    'Pendentes',
                    0,
                    Icons.pending_actions,
                    color: Color(0xFFB45309),
                    helper: 'Aguardando conferência',
                  ).copyWith(value: pending),
                  const _Summary(
                    'Aprovados',
                    0,
                    Icons.verified_outlined,
                    color: Color(0xFF047857),
                    helper: 'Conferidos pela tesouraria',
                  ).copyWith(value: approved),
                  const _Summary(
                    'Divergentes',
                    0,
                    Icons.warning_amber,
                    color: Color(0xFFB91C1C),
                    helper: 'Precisam de atenção',
                  ).copyWith(value: divergent),
                  _Summary(
                    'Diferença total',
                    differenceTotal,
                    Icons.balance_outlined,
                    money: true,
                    color: hasDifference
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF047857),
                    helper: hasDifference
                        ? 'Sobra/falta acumulada'
                        : 'Sem diferença',
                  ),
                ];
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 98,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                  ),
                  itemBuilder: (context, index) =>
                      _SummaryTile(summary: items[index]),
                );
              },
            ),
            const SizedBox(height: 18),
            _TreasuryOverview(
              totalSales: total,
              withdrawals: withdrawalsTotal,
              supplies: suppliesTotal,
              paymentTotals: paymentTotals,
              visibleCount: filteredClosings.length,
              loadedCount: _closings.length,
              pending: pending,
              divergent: divergent,
            ),
            const SizedBox(height: 18),
            AppCard(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final searchWidth = constraints.maxWidth < 760
                      ? constraints.maxWidth
                      : (constraints.maxWidth - 230).clamp(320.0, 520.0);
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: searchWidth,
                        child: TextField(
                          controller: _search,
                          onChanged: (_) => setState(() {}),
                          decoration: const InputDecoration(
                            labelText: 'Buscar fechamentos',
                            hintText: 'Código, operador, caixa ou status...',
                            prefixIcon: Icon(Icons.search),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: DropdownButtonFormField<String>(
                          initialValue: _statusFilter,
                          decoration: const InputDecoration(
                            labelText: 'Status',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'todos',
                              child: Text('Todos'),
                            ),
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
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(start: true),
                        icon: const Icon(Icons.calendar_today_outlined),
                        label: Text(
                          _dateFilterLabel(_startDate, 'Data inicial'),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () => _pickDate(start: false),
                        icon: const Icon(Icons.event_available_outlined),
                        label: Text(_dateFilterLabel(_endDate, 'Data final')),
                      ),
                      FilterChip(
                        selected: _differenceOnly,
                        onSelected: (value) =>
                            setState(() => _differenceOnly = value),
                        label: const Text('Com diferença'),
                        avatar: const Icon(Icons.warning_amber_outlined),
                      ),
                      IconButton.outlined(
                        tooltip: 'Limpar busca',
                        onPressed: () => setState(() {
                          _search.clear();
                          _statusFilter = 'todos';
                          _startDate = null;
                          _endDate = null;
                          _differenceOnly = false;
                        }),
                        icon: const Icon(Icons.clear),
                      ),
                    ],
                  );
                },
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
      final referenceDate = _onlyDate(closing.businessDate ?? closing.closedAt);
      if (_startDate != null &&
          referenceDate.isBefore(_onlyDate(_startDate!))) {
        return false;
      }
      if (_endDate != null && referenceDate.isAfter(_onlyDate(_endDate!))) {
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

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final current = start ? _startDate : _endDate;
    final initialDate = current ?? (start ? _endDate : _startDate) ?? now;
    final picked = await showDatePicker(
      context: context,
      locale: const Locale('pt', 'BR'),
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 2, 12, 31),
      helpText: start ? 'Selecionar data inicial' : 'Selecionar data final',
      cancelText: 'Cancelar',
      confirmText: 'Confirmar',
      fieldLabelText: start ? 'Data inicial' : 'Data final',
      fieldHintText: 'dd/mm/aaaa',
    );
    if (picked == null) return;
    setState(() {
      if (start) {
        _startDate = _onlyDate(picked);
        if (_endDate != null && _endDate!.isBefore(_startDate!)) {
          _endDate = _startDate;
        }
      } else {
        _endDate = _onlyDate(picked);
        if (_startDate != null && _startDate!.isAfter(_endDate!)) {
          _startDate = _endDate;
        }
      }
    });
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
          DataColumn(label: Text('Diferença')),
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
                              'Diferença',
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
                                  mainAxisExtent: 98,
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
                                'Obrigatório se marcar divergência. Opcional para aprovação.',
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
  const _Summary(
    this.label,
    this.value,
    this.icon, {
    this.money = false,
    this.color = const Color(0xFF2563EB),
    this.helper,
  });

  final String label;
  final Object value;
  final IconData icon;
  final bool money;
  final Color color;
  final String? helper;

  _Summary copyWith({Object? value}) {
    return _Summary(
      label,
      value ?? this.value,
      icon,
      money: money,
      color: color,
      helper: helper,
    );
  }
}

class _TreasuryOverview extends StatelessWidget {
  const _TreasuryOverview({
    required this.totalSales,
    required this.withdrawals,
    required this.supplies,
    required this.paymentTotals,
    required this.pending,
    required this.divergent,
    required this.visibleCount,
    required this.loadedCount,
  });

  final double totalSales;
  final double withdrawals;
  final double supplies;
  final Map<String, double> paymentTotals;
  final int pending;
  final int divergent;
  final int visibleCount;
  final int loadedCount;

  @override
  Widget build(BuildContext context) {
    final sortedPayments = paymentTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final paymentTotal = sortedPayments.fold<double>(
      0,
      (sum, entry) => sum + entry.value,
    );
    final scopeText = visibleCount == loadedCount
        ? 'Somando os $loadedCount fechamento(s) carregado(s)'
        : 'Somando $visibleCount de $loadedCount fechamento(s) carregado(s)';
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final payments = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PanelHeader(
                icon: Icons.account_balance_wallet_outlined,
                title: 'Conciliação por pagamento',
                subtitle: 'Valores por forma de pagamento da lista atual',
              ),
              Padding(
                padding: const EdgeInsets.only(left: 52, top: 2),
                child: Text(
                  scopeText,
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              if (sortedPayments.isEmpty)
                const _EmptyHint('Nenhum pagamento nos fechamentos carregados.')
              else
                for (final entry in sortedPayments.take(7))
                  _PaymentBreakdownRow(
                    label: _paymentLabel(entry.key),
                    value: entry.value,
                    share: paymentTotal <= 0 ? 0 : entry.value / paymentTotal,
                    color: _paymentColor(entry.key),
                  ),
            ],
          ),
        );
        final operations = AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PanelHeader(
                icon: Icons.receipt_long_outlined,
                title: 'Resumo financeiro',
                subtitle: 'Totais da lista atual de fechamentos',
              ),
              const SizedBox(height: 14),
              _TreasuryMetricLine(
                label: 'Total vendido',
                value: totalSales,
                icon: Icons.point_of_sale_outlined,
                strong: true,
              ),
              _TreasuryMetricLine(
                label: 'Sangrias',
                value: -withdrawals,
                icon: Icons.south_west,
                color: const Color(0xFFB91C1C),
              ),
              _TreasuryMetricLine(
                label: 'Suprimentos',
                value: supplies,
                icon: Icons.north_east,
                color: const Color(0xFF047857),
              ),
              const SizedBox(height: 12),
              const Divider(height: 1),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _TreasuryStatusPill(
                    label: pending == 0
                        ? 'Sem pendências'
                        : '$pending pendente(s)',
                    color: pending > 0
                        ? const Color(0xFFB45309)
                        : const Color(0xFF047857),
                    icon: pending > 0
                        ? Icons.pending_actions
                        : Icons.check_circle_outline,
                  ),
                  _TreasuryStatusPill(
                    label: divergent == 0
                        ? 'Sem divergências'
                        : '$divergent com diferença',
                    color: divergent > 0
                        ? const Color(0xFFB91C1C)
                        : const Color(0xFF047857),
                    icon: divergent > 0
                        ? Icons.warning_amber_outlined
                        : Icons.verified_outlined,
                  ),
                ],
              ),
            ],
          ),
        );
        if (wide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: payments),
              const SizedBox(width: 14),
              Expanded(flex: 2, child: operations),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [payments, const SizedBox(height: 14), operations],
        );
      },
    );
  }
}

class _TreasuryHealthLine extends StatelessWidget {
  const _TreasuryHealthLine({
    required this.label,
    required this.danger,
    required this.icon,
  });

  final String label;
  final bool danger;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final color = danger ? const Color(0xFFB45309) : const Color(0xFF047857);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _PanelHeader extends StatelessWidget {
  const _PanelHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SoftIcon(icon: icon, color: const Color(0xFF2563EB)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SoftIcon extends StatelessWidget {
  const _SoftIcon({required this.icon, required this.color});

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Icon(icon, color: color, size: 22),
      ),
    );
  }
}

class _PaymentBreakdownRow extends StatelessWidget {
  const _PaymentBreakdownRow({
    required this.label,
    required this.value,
    required this.share,
    required this.color,
  });

  final String label;
  final double value;
  final double share;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final clampedShare = share.clamp(0.0, 1.0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF334155),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                _money(value),
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          const SizedBox(height: 7),
          ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: LinearProgressIndicator(
              value: clampedShare,
              minHeight: 8,
              color: color,
              backgroundColor: color.withValues(alpha: 0.12),
            ),
          ),
        ],
      ),
    );
  }
}

class _TreasuryMetricLine extends StatelessWidget {
  const _TreasuryMetricLine({
    required this.label,
    required this.value,
    required this.icon,
    this.color = const Color(0xFF0F172A),
    this.strong = false,
  });

  final String label;
  final double value;
  final IconData icon;
  final Color color;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 19, color: color.withValues(alpha: 0.86)),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF475569),
                fontWeight: strong ? FontWeight.w900 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            _money(value),
            style: TextStyle(
              color: color,
              fontSize: strong ? 17 : 15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _TreasuryStatusPill extends StatelessWidget {
  const _TreasuryStatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        border: Border.all(color: color.withValues(alpha: 0.24)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: color),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
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
    final color = summary.color;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: color.withValues(alpha: 0.22)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
              color: color.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            ColoredBox(color: color, child: const SizedBox(width: 5)),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Row(
                  children: [
                    _SoftIcon(icon: summary.icon, color: color),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            summary.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                          Text(
                            summary.money
                                ? _money(summary.value as double)
                                : '${summary.value}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: const Color(0xFF0F172A),
                              fontSize: summary.money ? 19 : 22,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          if (summary.helper != null) ...[
                            const SizedBox(height: 3),
                            Text(
                              summary.helper!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Color(0xFF64748B),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
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
    'fiado' => 'Fiado',
    'crediario' => 'Crediário',
    'transferencia' => 'Transferência',
    _ => value,
  };
}

Color _paymentColor(String value) {
  return switch (value.toLowerCase()) {
    'dinheiro' => const Color(0xFF047857),
    'pix' => const Color(0xFF0E7490),
    'cartao_credito' || 'credito' => const Color(0xFF2563EB),
    'cartao_debito' || 'debito' => const Color(0xFF7C3AED),
    'fiado' => const Color(0xFF475569),
    'crediario' => const Color(0xFFB45309),
    'transferencia' => const Color(0xFF0891B2),
    _ => const Color(0xFF475569),
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

Map<String, double> _paymentTotals(List<CashClosing> closings) {
  final totals = <String, double>{};
  for (final closing in closings) {
    for (final payment in closing.payments) {
      final key = payment.method.toLowerCase();
      totals[key] = (totals[key] ?? 0) + payment.amount;
    }
  }
  return totals;
}

double _sumMovements(List<CashClosing> closings, String type) {
  final normalized = type.toLowerCase();
  return closings.fold<double>(0, (sum, closing) {
    return sum +
        closing.movements.fold<double>(0, (movementSum, movement) {
          if (movement.movementType.toLowerCase() != normalized) {
            return movementSum;
          }
          return movementSum + movement.amount;
        });
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

DateTime _onlyDate(DateTime value) {
  return DateTime(value.year, value.month, value.day);
}

String _dateFilterLabel(DateTime? value, String fallback) {
  return value == null ? fallback : _dateOnly(value);
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
