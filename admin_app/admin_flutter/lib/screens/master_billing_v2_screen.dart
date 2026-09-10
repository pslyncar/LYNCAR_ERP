import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../models/company.dart';
import '../models/company_billing.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import 'master_billing_arrears_screen.dart';
import 'master_billing_overview_screen.dart';
import 'master_billing_reconciliation_screen.dart';
import 'master_billing_receipts_screen.dart';
import 'master_billing_settings_screen.dart';

/// Nova visão de cobranças do Master.
///
/// A tela antiga permanece em master_billing_screen.dart e também foi salva em
/// backups/. Esta tela só reorganiza a experiência visual; os mesmos endpoints
/// de cobrança e Mercado Pago continuam sendo usados.
class MasterBillingV2Screen extends StatefulWidget {
  const MasterBillingV2Screen({
    super.key,
    required this.session,
    this.initialSection = 1,
  });

  final Session session;
  final int initialSection;

  @override
  State<MasterBillingV2Screen> createState() => _MasterBillingV2ScreenState();
}

class _MasterBillingV2ScreenState extends State<MasterBillingV2Screen> {
  late final _api = ApiClient(widget.session.apiBaseUrl);
  final _searchController = TextEditingController();

  List<CompanyBilling> _billings = const [];
  List<Company> _companies = const [];
  bool _loading = true;
  String? _error;
  String _status = 'Todos';
  late int _section;
  int _page = 0;
  static const _pageSize = 50;

  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    _searchController.addListener(_resetPage);
    _load();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_resetPage)
      ..dispose();
    super.dispose();
  }

  void _resetPage() {
    if (mounted && _page != 0) setState(() => _page = 0);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await Future.wait([
        _api.listMasterBillings(widget.session.token),
        _api.listCompanies(widget.session.token),
      ]);
      if (!mounted) return;
      setState(() {
        _billings = result[0] as List<CompanyBilling>;
        _companies = result[1] as List<Company>;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  List<CompanyBilling> get _filtered {
    final query = _searchController.text.trim().toLowerCase();
    return _billings.where((billing) {
      final matchesQuery =
          query.isEmpty ||
          billing.companyName.toLowerCase().contains(query) ||
          billing.companyCode.toLowerCase().contains(query) ||
          billing.referenceMonth.toLowerCase().contains(query) ||
          (billing.mercadoPagoPayerName ?? '').toLowerCase().contains(query) ||
          (billing.mercadoPagoPayerEmail ?? '').toLowerCase().contains(query);
      final matchesStatus = switch (_status) {
        'Pagas' => billing.status == 'paid',
        'Pendentes' => billing.status == 'pending' && !billing.isOverdue,
        'Em atraso' => billing.isOverdue,
        'Canceladas' => billing.status == 'canceled',
        _ => true,
      };
      return matchesQuery && matchesStatus;
    }).toList()..sort((a, b) => b.dueDate.compareTo(a.dueDate));
  }

  List<CompanyBilling> get _visible {
    final values = _filtered;
    final start = _page * _pageSize;
    if (start >= values.length && _page > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _page = 0);
      });
      return const [];
    }
    return values.skip(start).take(_pageSize).toList();
  }

  String _money(double value) =>
      'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

  String _date(DateTime? value) => value == null
      ? '—'
      : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  String _statusLabel(CompanyBilling billing) {
    if (billing.status == 'paid') return 'Paga';
    if (billing.status == 'canceled') return 'Cancelada';
    if (billing.isOverdue) return 'Em atraso';
    return 'Pendente';
  }

  Future<void> _generateCurrent() async {
    await _runAction(
      'Gerando cobranças do mês…',
      () => _api.generateCurrentMasterBillings(widget.session.token),
    );
  }

  Future<void> _runAction(
    String message,
    Future<Object> Function() action,
  ) async {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
    try {
      await action();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Operação concluída.')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(error.toString().replaceFirst('Exception: ', '')),
        ),
      );
    }
  }

  void _openDetails(CompanyBilling billing) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar detalhes',
      barrierColor: const Color(0x990B1730),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return Align(
          alignment: Alignment.centerRight,
          child: Material(
            color: Colors.transparent,
            child: _BillingDetailsPanel(
              billing: billing,
              money: _money,
              date: _date,
              statusLabel: _statusLabel,
              onEdit: () {
                Navigator.of(context).pop();
                _editBilling(billing);
              },
              onSync: () async {
                Navigator.of(context).pop();
                await _runAction(
                  'Consultando Mercado Pago…',
                  () => _api.syncMasterBillingPayment(
                    widget.session.token,
                    billing.id,
                  ),
                );
              },
              onPix: billing.pixQrCode == null ? null : () => _showPix(billing),
              onGeneratePix: () async {
                Navigator.of(context).pop();
                await _runAction(
                  'Gerando PIX atualizado…',
                  () => _api.generateMasterBillingPix(
                    widget.session.token,
                    billing.id,
                  ),
                );
              },
              onWaive: billing.status == 'paid'
                  ? null
                  : () async {
                      final reason = await _askReason();
                      if (reason == null) return;
                      if (context.mounted) Navigator.of(context).pop();
                      await _runAction(
                        'Atualizando encargos…',
                        () => _api.waiveMasterBillingCharges(
                          widget.session.token,
                          billing.id,
                          reason,
                        ),
                      );
                    },
              onMarkPaid: billing.status == 'paid'
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await _runAction(
                        'Baixando cobrança…',
                        () => _api.payMasterBilling(
                          widget.session.token,
                          billing.id,
                        ),
                      );
                    },
              onCancel: billing.status == 'canceled'
                  ? null
                  : () async {
                      Navigator.of(context).pop();
                      await _runAction(
                        'Cancelando cobrança…',
                        () => _api.cancelMasterBilling(
                          widget.session.token,
                          billing.id,
                        ),
                      );
                    },
            ),
          ),
        );
      },
    );
  }

  Future<String?> _askReason() async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Perdoar encargos'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Motivo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    controller.dispose();
    return reason == null || reason.length < 3 ? null : reason;
  }

  void _showPix(CompanyBilling billing) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('PIX da cobrança'),
        content: SelectableText(billing.pixQrCode ?? 'PIX ainda não gerado.'),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: billing.pixQrCode ?? ''),
              );
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text('Copiar código'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Fechar'),
          ),
        ],
      ),
    );
  }

  Future<void> _createBilling() async {
    if (_companies.isEmpty) return;
    final result = await showDialog<_BillingFormResult>(
      context: context,
      builder: (context) => _BillingFormDialog(companies: _companies),
    );
    if (result == null) return;
    await _runAction(
      'Criando cobrança…',
      () => _api.createMasterBilling(
        widget.session.token,
        CompanyBillingCreate(
          companyId: result.companyId,
          referenceMonth: result.referenceMonth,
          dueDate: result.dueDate,
          amount: result.amount,
          paymentMethod: result.paymentMethod,
          notes: result.notes,
        ),
      ),
    );
  }

  Future<void> _editBilling(CompanyBilling billing) async {
    final input = await showDialog<CompanyBillingUpdate>(
      context: context,
      builder: (context) => _BillingEditDialog(billing: billing),
    );
    if (input == null) return;
    await _runAction(
      'Salvando alterações…',
      () => _api.updateMasterBilling(widget.session.token, billing.id, input),
    );
  }

  @override
  Widget build(BuildContext context) {
    final values = _filtered;
    final pages = (values.length / _pageSize).ceil().clamp(1, 9999);
    return Scaffold(
      backgroundColor: const Color(0xFFF4F7FB),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 900;
            return ListView(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 32,
                28,
                compact ? 16 : 32,
                40,
              ),
              children: [
                _Header(
                  compact: compact,
                  onRefresh: _load,
                  onGenerate: _generateCurrent,
                  onCreate: _createBilling,
                ),
                const Gap(18),
                _SectionTabs(
                  selected: _section,
                  onChanged: (value) => setState(() => _section = value),
                ),
                const Gap(18),
                if (_section == 0)
                  MasterBillingOverviewScreen(values: _billings, money: _money)
                else if (_section == 2)
                  MasterBillingArrearsScreen(
                    values: _billings,
                    money: _money,
                    date: _date,
                    onTap: _openDetails,
                  )
                else if (_section == 3)
                  MasterBillingReceiptsScreen(
                    values: _billings,
                    money: _money,
                    date: _date,
                    onTap: _openDetails,
                  )
                else if (_section == 4)
                  MasterBillingReconciliationScreen(
                    values: _billings,
                    money: _money,
                    date: _date,
                    onRefresh: _load,
                    onOpen: _openDetails,
                    onSync: (billing) async {
                      await _runAction(
                        'Consultando Mercado Pago…',
                        () => _api.syncMasterBillingPayment(
                          widget.session.token,
                          billing.id,
                        ),
                      );
                    },
                  )
                else if (_section == 5)
                  const MasterBillingSettingsScreen()
                else ...[
                  _Summary(values: _billings, money: _money),
                  const Gap(18),
                  _Toolbar(
                    controller: _searchController,
                    status: _status,
                    onStatusChanged: (value) => setState(() {
                      _status = value;
                      _page = 0;
                    }),
                  ),
                  const Gap(12),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(36),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    _ErrorState(message: _error!, onRetry: _load)
                  else if (values.isEmpty)
                    const _EmptyState()
                  else
                    _BillingList(
                      compact: compact,
                      values: _visible,
                      money: _money,
                      date: _date,
                      statusLabel: _statusLabel,
                      onTap: _openDetails,
                    ),
                  if (!_loading && _error == null && values.isNotEmpty) ...[
                    const Gap(10),
                    _Pagination(
                      page: _page,
                      pages: pages,
                      total: values.length,
                      onPrevious: _page == 0
                          ? null
                          : () => setState(() => _page--),
                      onNext: _page + 1 >= pages
                          ? null
                          : () => setState(() => _page++),
                    ),
                  ],
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.compact,
    required this.onRefresh,
    required this.onGenerate,
    required this.onCreate,
  });
  final bool compact;
  final VoidCallback onRefresh;
  final VoidCallback onGenerate;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        alignment: WrapAlignment.spaceBetween,
        runSpacing: 14,
        spacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Cobranças',
                style: TextStyle(
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF14243D),
                ),
              ),
              Gap(5),
              Text(
                'Mensalidades, recebimentos e conciliação financeira',
                style: TextStyle(color: Color(0xFF6B7D96), fontSize: 15),
              ),
            ],
          ),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Atualizar'),
              ),
              OutlinedButton.icon(
                onPressed: onGenerate,
                icon: const Icon(Icons.auto_awesome),
                label: const Text('Gerar mês atual'),
              ),
              FilledButton.icon(
                onPressed: onCreate,
                icon: const Icon(Icons.add),
                label: const Text('Nova cobrança'),
              ),
            ],
          ),
        ],
      ),
      if (compact) const Gap(4),
    ],
  );
}

class _SectionTabs extends StatelessWidget {
  const _SectionTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Visão geral',
      'Cobranças',
      'Inadimplentes',
      'Recebimentos',
      'Conciliação',
      'Configurações',
    ];
    const icons = [
      Icons.dashboard_outlined,
      Icons.receipt_long_outlined,
      Icons.warning_amber_outlined,
      Icons.payments_outlined,
      Icons.sync_outlined,
      Icons.settings_outlined,
    ];
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5F0)),
      ),
      child: Wrap(
        spacing: 4,
        runSpacing: 4,
        children: [
          for (var index = 0; index < labels.length; index++)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: ChoiceChip(
                selected: selected == index,
                label: Text(labels[index]),
                avatar: Icon(icons[index], size: 17),
                onSelected: (_) => onChanged(index),
                selectedColor: const Color(0xFFE4F0FA),
                labelStyle: TextStyle(
                  color: selected == index
                      ? const Color(0xFF0D6387)
                      : const Color(0xFF52657E),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
                side: BorderSide.none,
              ),
            ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.values, required this.money});
  final List<CompanyBilling> values;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final pending = values.where((value) => value.status == 'pending');
    final paid = values.where((value) => value.status == 'paid');
    final overdue = pending.where((value) => value.isOverdue).length;
    final received = paid.fold<double>(
      0,
      (sum, value) => sum + (value.paidAmount ?? value.amount),
    );
    final open = pending.fold<double>(
      0,
      (sum, value) => sum + (value.totalDue ?? value.amount),
    );
    final metrics = [
      _Metric(
        label: 'Em aberto',
        value: money(open),
        detail: '${pending.length} cobranças',
        color: const Color(0xFF0D6E8A),
        icon: Icons.account_balance_wallet_outlined,
      ),
      _Metric(
        label: 'Recebido',
        value: money(received),
        detail: '${paid.length} pagamentos confirmados',
        color: const Color(0xFF008D68),
        icon: Icons.check_circle_outline,
      ),
      _Metric(
        label: 'Em atraso',
        value: '$overdue',
        detail: 'precisam de atenção',
        color: const Color(0xFFD97706),
        icon: Icons.schedule_outlined,
      ),
      _Metric(
        label: 'Empresas inadimplentes',
        value:
            '${pending.where((value) => value.isOverdue).map((value) => value.companyId).toSet().length}',
        detail: 'clientes com pendência vencida',
        color: const Color(0xFFDC3B4B),
        icon: Icons.warning_amber_rounded,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 1120
            ? 4
            : constraints.maxWidth >= 640
            ? 2
            : 1;
        final gap = 12.0;
        final itemWidth = columns == 1
            ? constraints.maxWidth
            : (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: metrics
              .map((metric) => SizedBox(width: itemWidth, child: metric))
              .toList(),
        );
      },
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
    required this.icon,
  });
  final String label;
  final String value;
  final String detail;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: const BoxConstraints(minWidth: 0),
    child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFDCE5F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A152B45),
            blurRadius: 18,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color),
          ),
          const Gap(12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF687B95),
                    fontSize: 13,
                  ),
                ),
                const Gap(3),
                Text(
                  value,
                  style: const TextStyle(
                    color: Color(0xFF162640),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const Gap(2),
                Text(
                  detail,
                  style: TextStyle(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.controller,
    required this.status,
    required this.onStatusChanged,
  });
  final TextEditingController controller;
  final String status;
  final ValueChanged<String> onStatusChanged;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        SizedBox(
          width: 460,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search),
              hintText: 'Buscar empresa, código, mês ou pagador',
              suffixIcon: controller.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: controller.clear,
                      icon: const Icon(Icons.close),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              isDense: true,
            ),
          ),
        ),
        DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: status,
            items:
                const ['Todos', 'Pendentes', 'Pagas', 'Em atraso', 'Canceladas']
                    .map(
                      (value) =>
                          DropdownMenuItem(value: value, child: Text(value)),
                    )
                    .toList(),
            onChanged: (value) {
              if (value != null) onStatusChanged(value);
            },
          ),
        ),
      ],
    ),
  );
}

class _BillingList extends StatelessWidget {
  const _BillingList({
    required this.compact,
    required this.values,
    required this.money,
    required this.date,
    required this.statusLabel,
    required this.onTap,
  });
  final bool compact;
  final List<CompanyBilling> values;
  final String Function(double) money;
  final String Function(DateTime?) date;
  final String Function(CompanyBilling) statusLabel;
  final ValueChanged<CompanyBilling> onTap;

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        if (!compact) const _ListHeader(),
        ...values.map(
          (billing) => _BillingRow(
            billing: billing,
            compact: compact,
            money: money,
            date: date,
            statusLabel: statusLabel,
            onTap: () => onTap(billing),
          ),
        ),
      ],
    ),
  );
}

class _ListHeader extends StatelessWidget {
  const _ListHeader();
  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.fromLTRB(20, 15, 16, 12),
    child: Row(
      children: [
        Expanded(flex: 3, child: Text('Cliente / referência')),
        Expanded(child: Text('Vencimento')),
        Expanded(child: Text('Valor')),
        Expanded(child: Text('Pagador')),
        SizedBox(width: 110, child: Text('Status')),
        SizedBox(width: 38),
      ],
    ),
  );
}

class _BillingRow extends StatelessWidget {
  const _BillingRow({
    required this.billing,
    required this.compact,
    required this.money,
    required this.date,
    required this.statusLabel,
    required this.onTap,
  });
  final CompanyBilling billing;
  final bool compact;
  final String Function(double) money;
  final String Function(DateTime?) date;
  final String Function(CompanyBilling) statusLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = statusLabel(billing);
    final color = status == 'Paga'
        ? const Color(0xFF008D68)
        : status == 'Em atraso'
        ? const Color(0xFFD97706)
        : status == 'Cancelada'
        ? const Color(0xFF6B7280)
        : const Color(0xFF2563EB);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: EdgeInsets.fromLTRB(compact ? 16 : 20, 16, 12, 16),
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Color(0xFFE8EEF5))),
        ),
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _TitleLine(
                    billing: billing,
                    status: status,
                    color: color,
                    onTap: onTap,
                  ),
                  const Gap(12),
                  Wrap(
                    spacing: 26,
                    runSpacing: 10,
                    children: [
                      _Info(label: 'Vencimento', value: date(billing.dueDate)),
                      _Info(
                        label: 'Valor',
                        value: money(billing.totalDue ?? billing.amount),
                      ),
                      _Info(
                        label: 'Pagador',
                        value: billing.mercadoPagoPayerName ?? 'Não informado',
                      ),
                    ],
                  ),
                ],
              )
            : Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: _TitleLine(
                      billing: billing,
                      status: status,
                      color: color,
                      onTap: onTap,
                    ),
                  ),
                  Expanded(child: Text(date(billing.dueDate))),
                  Expanded(
                    child: Text(
                      money(billing.totalDue ?? billing.amount),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      billing.mercadoPagoPayerName ?? '—',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SizedBox(
                    width: 110,
                    child: _StatusChip(text: status, color: color),
                  ),
                  const SizedBox(
                    width: 38,
                    child: Icon(Icons.chevron_right, color: Color(0xFF91A1B5)),
                  ),
                ],
              ),
      ),
    );
  }
}

class _TitleLine extends StatelessWidget {
  const _TitleLine({
    required this.billing,
    required this.status,
    required this.color,
    required this.onTap,
  });
  final CompanyBilling billing;
  final String status;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              billing.companyName,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1B2B43),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const Gap(3),
            Text(
              '${billing.companyCode}  •  ${billing.referenceMonth}',
              style: const TextStyle(color: Color(0xFF71839B), fontSize: 12),
            ),
          ],
        ),
      ),
      _StatusChip(text: status, color: color),
      if (MediaQuery.sizeOf(context).width < 900)
        const Icon(Icons.chevron_right, color: Color(0xFF91A1B5)),
    ],
  );
}

class _Info extends StatelessWidget {
  const _Info({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF7A8BA2), fontSize: 11),
        ),
        const Gap(3),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF1E3049),
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    ),
  );
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text, required this.color});
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: 11),
    ),
  );
}

class _Pagination extends StatelessWidget {
  const _Pagination({
    required this.page,
    required this.pages,
    required this.total,
    required this.onPrevious,
    required this.onNext,
  });
  final int page;
  final int pages;
  final int total;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisAlignment: MainAxisAlignment.end,
    children: [
      Text(
        '$total cobranças',
        style: const TextStyle(color: Color(0xFF71839B), fontSize: 12),
      ),
      const Gap(12),
      IconButton(onPressed: onPrevious, icon: const Icon(Icons.chevron_left)),
      Text(
        '${page + 1} / $pages',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      IconButton(onPressed: onNext, icon: const Icon(Icons.chevron_right)),
    ],
  );
}

class _BillingDetailsPanel extends StatelessWidget {
  const _BillingDetailsPanel({
    required this.billing,
    required this.money,
    required this.date,
    required this.statusLabel,
    required this.onEdit,
    required this.onSync,
    required this.onPix,
    required this.onGeneratePix,
    required this.onWaive,
    required this.onMarkPaid,
    required this.onCancel,
  });
  final CompanyBilling billing;
  final String Function(double) money;
  final String Function(DateTime?) date;
  final String Function(CompanyBilling) statusLabel;
  final VoidCallback onEdit;
  final VoidCallback onSync;
  final VoidCallback? onPix;
  final VoidCallback onGeneratePix;
  final VoidCallback? onWaive;
  final VoidCallback? onMarkPaid;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Container(
      width: width < 650 ? width : 520,
      height: double.infinity,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 20, 12, 18),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Detalhes da cobrança',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF162640),
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_outlined, size: 17),
                    label: const Text('Editar'),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 0, 22, 24),
                children: [
                  _DetailHero(
                    billing: billing,
                    status: statusLabel(billing),
                    money: money,
                  ),
                  const Gap(20),
                  const _SectionTitle('Cobrança'),
                  _DetailGrid(
                    items: {
                      'Cliente': billing.companyName,
                      'Código': billing.companyCode,
                      'Referência': billing.referenceMonth,
                      'Vencimento': date(billing.dueDate),
                      'Valor original': money(billing.amount),
                      'Total atualizado': money(
                        billing.totalDue ?? billing.amount,
                      ),
                      'Forma de pagamento': billing.paymentMethod ?? 'PIX',
                    },
                  ),
                  const Gap(20),
                  const _SectionTitle('Pagador identificado'),
                  _DetailGrid(
                    items: {
                      'Nome':
                          billing.mercadoPagoPayerName ?? 'Ainda não informado',
                      'E-mail': billing.mercadoPagoPayerEmail ?? '—',
                      'Documento': billing.mercadoPagoPayerDocument ?? '—',
                      'Pago em': date(billing.paidAt),
                      'ID Mercado Pago': billing.mercadoPagoPaymentId ?? '—',
                      'Status Mercado Pago': billing.mercadoPagoStatus ?? '—',
                    },
                  ),
                  if (billing.interestAmount > 0 ||
                      billing.lateFeeAmount > 0) ...[
                    const Gap(20),
                    const _SectionTitle('Encargos'),
                    _DetailGrid(
                      items: {
                        'Juros': money(billing.interestAmount),
                        'Multa': money(billing.lateFeeAmount),
                        'Correção': money(billing.monetaryCorrectionAmount),
                        'Desconto concedido': money(billing.waivedAmount),
                      },
                    ),
                  ],
                  const Gap(22),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: onSync,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar pagamento'),
                      ),
                      OutlinedButton.icon(
                        onPressed: onGeneratePix,
                        icon: const Icon(Icons.qr_code_2),
                        label: Text(
                          onPix == null ? 'Gerar PIX' : 'Atualizar PIX',
                        ),
                      ),
                      if (onPix != null)
                        OutlinedButton.icon(
                          onPressed: onPix,
                          icon: const Icon(Icons.content_copy),
                          label: const Text('Ver código'),
                        ),
                      if (onWaive != null)
                        OutlinedButton.icon(
                          onPressed: onWaive,
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('Perdoar encargos'),
                        ),
                      if (onMarkPaid != null)
                        FilledButton.icon(
                          onPressed: onMarkPaid,
                          icon: const Icon(Icons.check),
                          label: const Text('Marcar como paga'),
                        ),
                      if (onCancel != null)
                        TextButton.icon(
                          onPressed: onCancel,
                          icon: const Icon(Icons.block),
                          label: const Text('Cancelar'),
                        ),
                    ],
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

class _DetailHero extends StatelessWidget {
  const _DetailHero({
    required this.billing,
    required this.status,
    required this.money,
  });
  final CompanyBilling billing;
  final String status;
  final String Function(double) money;
  @override
  Widget build(BuildContext context) {
    final color = status == 'Paga'
        ? const Color(0xFF008D68)
        : status == 'Em atraso'
        ? const Color(0xFFD97706)
        : const Color(0xFF2563EB);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF4F8FD),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            billing.companyName,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w800,
              color: Color(0xFF182943),
            ),
          ),
          const Gap(4),
          Text(
            'Cobrança ${billing.referenceMonth}',
            style: const TextStyle(color: Color(0xFF6D8098)),
          ),
          const Gap(14),
          Row(
            children: [
              Expanded(
                child: Text(
                  money(billing.totalDue ?? billing.amount),
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFF0B6B88),
                  ),
                ),
              ),
              _StatusChip(text: status, color: color),
            ],
          ),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: Color(0xFF1F3552),
      ),
    ),
  );
}

class _DetailGrid extends StatelessWidget {
  const _DetailGrid({required this.items});
  final Map<String, String> items;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      border: Border.all(color: const Color(0xFFE0E8F2)),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Wrap(
      spacing: 18,
      runSpacing: 14,
      children: items.entries
          .map(
            (item) => SizedBox(
              width: 210,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.key,
                    style: const TextStyle(
                      color: Color(0xFF8191A6),
                      fontSize: 11,
                    ),
                  ),
                  const Gap(3),
                  Text(
                    item.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF233750),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(),
    ),
  );
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => _StateCard(
    icon: Icons.error_outline,
    title: 'Não foi possível carregar as cobranças',
    detail: message,
    action: OutlinedButton.icon(
      onPressed: onRetry,
      icon: const Icon(Icons.refresh),
      label: const Text('Tentar novamente'),
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const _StateCard(
    icon: Icons.receipt_long_outlined,
    title: 'Nenhuma cobrança encontrada',
    detail: 'Ajuste os filtros ou gere as cobranças do mês atual.',
  );
}

class _StateCard extends StatelessWidget {
  const _StateCard({
    required this.icon,
    required this.title,
    required this.detail,
    this.action,
  });
  final IconData icon;
  final String title;
  final String detail;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(34),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Column(
      children: [
        Icon(icon, size: 38, color: const Color(0xFF2472C8)),
        const Gap(10),
        Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
        ),
        const Gap(5),
        Text(
          detail,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Color(0xFF71839B)),
        ),
        if (action != null) ...[const Gap(16), action!],
      ],
    ),
  );
}

class _BillingEditDialog extends StatefulWidget {
  const _BillingEditDialog({required this.billing});

  final CompanyBilling billing;

  @override
  State<_BillingEditDialog> createState() => _BillingEditDialogState();
}

class _BillingEditDialogState extends State<_BillingEditDialog> {
  late final TextEditingController _amount;
  late final TextEditingController _notes;
  late DateTime _dueDate;
  late String _paymentMethod;
  late String _status;

  @override
  void initState() {
    super.initState();
    final billing = widget.billing;
    _amount = TextEditingController(
      text: billing.amount.toStringAsFixed(2).replaceAll('.', ','),
    );
    _notes = TextEditingController(text: billing.notes ?? '');
    _dueDate = billing.dueDate;
    _paymentMethod = billing.paymentMethod ?? 'pix';
    _status = billing.status == 'canceled' ? 'canceled' : 'pending';
  }

  @override
  void dispose() {
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double _amountValue() {
    final value = _amount.text.trim().replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(value) ?? 0;
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('Editar cobrança')),
          Chip(label: Text(widget.billing.referenceMonth)),
        ],
      ),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _EditSection(
                title: 'Identificação',
                icon: Icons.business_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.billing.companyName,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${widget.billing.companyCode}  •  Referência ${widget.billing.referenceMonth}',
                      style: const TextStyle(color: Color(0xFF71839B)),
                    ),
                  ],
                ),
              ),
              const Gap(12),
              _EditSection(
                title: 'Valores e vencimento',
                icon: Icons.calendar_month_outlined,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 480;
                    final fields = [
                      Expanded(
                        child: TextField(
                          controller: _amount,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor original',
                            prefixText: 'R\$ ',
                          ),
                        ),
                      ),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final picked = await showDatePicker(
                              context: context,
                              initialDate: _dueDate,
                              firstDate: DateTime(2020),
                              lastDate: DateTime(2100),
                            );
                            if (picked != null) {
                              setState(() => _dueDate = picked);
                            }
                          },
                          icon: const Icon(Icons.event_outlined),
                          label: Text('Vencimento ${_date(_dueDate)}'),
                        ),
                      ),
                    ];
                    return stacked
                        ? Column(
                            children: [
                              fields[0],
                              const SizedBox(height: 12),
                              fields[1],
                            ],
                          )
                        : Row(
                            children: [
                              fields[0],
                              const SizedBox(width: 12),
                              fields[1],
                            ],
                          );
                  },
                ),
              ),
              const Gap(12),
              _EditSection(
                title: 'Pagamento e situação',
                icon: Icons.payments_outlined,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 480;
                    final fields = [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Forma de pagamento',
                          ),
                          items: const [
                            DropdownMenuItem(value: 'pix', child: Text('PIX')),
                            DropdownMenuItem(
                              value: 'boleto',
                              child: Text('Boleto'),
                            ),
                            DropdownMenuItem(
                              value: 'manual',
                              child: Text('Manual'),
                            ),
                            DropdownMenuItem(
                              value: 'cash',
                              child: Text('Dinheiro'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _paymentMethod = value);
                            }
                          },
                        ),
                      ),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _status,
                          decoration: const InputDecoration(
                            labelText: 'Situação',
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'pending',
                              child: Text('Pendente'),
                            ),
                            DropdownMenuItem(
                              value: 'canceled',
                              child: Text('Cancelada'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) setState(() => _status = value);
                          },
                        ),
                      ),
                    ];
                    return stacked
                        ? Column(
                            children: [
                              fields[0],
                              const SizedBox(height: 12),
                              fields[1],
                            ],
                          )
                        : Row(
                            children: [
                              fields[0],
                              const SizedBox(width: 12),
                              fields[1],
                            ],
                          );
                  },
                ),
              ),
              const Gap(12),
              _EditSection(
                title: 'Observações',
                icon: Icons.notes_outlined,
                child: TextField(
                  controller: _notes,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    hintText: 'Adicione uma observação interna',
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _amountValue() <= 0
              ? null
              : () => Navigator.pop(
                  context,
                  CompanyBillingUpdate(
                    dueDate: _dueDate,
                    amount: _amountValue(),
                    paymentMethod: _paymentMethod,
                    status: _status,
                    notes: _notes.text.trim().isEmpty
                        ? null
                        : _notes.text.trim(),
                  ),
                ),
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar alterações'),
        ),
      ],
    );
  }
}

class _EditSection extends StatelessWidget {
  const _EditSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: const Color(0xFFF7FAFE),
      border: Border.all(color: const Color(0xFFDCE5F0)),
      borderRadius: BorderRadius.circular(14),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 19, color: const Color(0xFF176B93)),
            const Gap(8),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1D3553),
              ),
            ),
          ],
        ),
        const Gap(14),
        child,
      ],
    ),
  );
}

class _BillingFormResult {
  const _BillingFormResult({
    required this.companyId,
    required this.referenceMonth,
    required this.dueDate,
    required this.amount,
    required this.paymentMethod,
    required this.notes,
  });
  final int companyId;
  final String referenceMonth;
  final DateTime dueDate;
  final double amount;
  final String paymentMethod;
  final String notes;
}

class _BillingFormDialog extends StatefulWidget {
  const _BillingFormDialog({required this.companies});
  final List<Company> companies;
  @override
  State<_BillingFormDialog> createState() => _BillingFormDialogState();
}

class _BillingFormDialogState extends State<_BillingFormDialog> {
  late int _companyId = widget.companies.first.id;
  final _month = TextEditingController(
    text:
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}',
  );
  final _due = TextEditingController(
    text: _dateText(DateTime.now().add(const Duration(days: 10))),
  );
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  String _payment = 'pix';

  @override
  void dispose() {
    _month.dispose();
    _due.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nova cobrança'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: _companyId,
                decoration: const InputDecoration(labelText: 'Empresa'),
                items: widget.companies
                    .map(
                      (company) => DropdownMenuItem(
                        value: company.id,
                        child: Text(
                          company.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) setState(() => _companyId = value);
                },
              ),
              const Gap(14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _month,
                      decoration: const InputDecoration(
                        labelText: 'Referência',
                        hintText: 'AAAA-MM',
                      ),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: TextField(
                      controller: _due,
                      decoration: const InputDecoration(
                        labelText: 'Vencimento',
                        hintText: 'DD/MM/AAAA',
                      ),
                    ),
                  ),
                ],
              ),
              const Gap(14),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amount,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(labelText: 'Valor'),
                    ),
                  ),
                  const Gap(12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _payment,
                      decoration: const InputDecoration(labelText: 'Pagamento'),
                      items: const [
                        DropdownMenuItem(value: 'pix', child: Text('PIX')),
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text('Manual'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) setState(() => _payment = value);
                      },
                    ),
                  ),
                ],
              ),
              const Gap(14),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Criar cobrança')),
      ],
    );
  }

  void _submit() {
    final amount = double.tryParse(_amount.text.replaceAll(',', '.'));
    final parts = _due.text.split('/');
    final due = parts.length == 3
        ? DateTime.tryParse('${parts[2]}-${parts[1]}-${parts[0]}')
        : null;
    if (amount == null ||
        amount <= 0 ||
        due == null ||
        _month.text.trim().isEmpty)
      {
        return;
      }
    Navigator.pop(
      context,
      _BillingFormResult(
        companyId: _companyId,
        referenceMonth: _month.text.trim(),
        dueDate: due,
        amount: amount,
        paymentMethod: _payment,
        notes: _notes.text.trim(),
      ),
    );
  }
}

String _dateText(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year}';
