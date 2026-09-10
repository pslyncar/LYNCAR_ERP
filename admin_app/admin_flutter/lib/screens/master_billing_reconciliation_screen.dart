import 'package:flutter/material.dart';

import '../models/company_billing.dart';

class MasterBillingReconciliationScreen extends StatefulWidget {
  const MasterBillingReconciliationScreen({
    super.key,
    required this.values,
    required this.money,
    required this.date,
    required this.onRefresh,
    required this.onSync,
    required this.onOpen,
  });

  final List<CompanyBilling> values;
  final String Function(double) money;
  final String Function(DateTime?) date;
  final VoidCallback onRefresh;
  final Future<void> Function(CompanyBilling billing) onSync;
  final ValueChanged<CompanyBilling> onOpen;

  @override
  State<MasterBillingReconciliationScreen> createState() =>
      _MasterBillingReconciliationScreenState();
}

enum _ReconciliationFilter { all, reconciled, divergent, pending, unidentified }

class _MasterBillingReconciliationScreenState
    extends State<MasterBillingReconciliationScreen> {
  _ReconciliationFilter _filter = _ReconciliationFilter.all;

  @override
  Widget build(BuildContext context) {
    final reconciled = widget.values.where(_isReconciled).toList();
    final divergent = widget.values.where(_isDivergent).toList();
    final pending = widget.values.where(_isPending).toList();
    final unidentified = widget.values.where(_isUnidentified).toList();
    final visible = switch (_filter) {
      _ReconciliationFilter.reconciled => reconciled,
      _ReconciliationFilter.divergent => divergent,
      _ReconciliationFilter.pending => pending,
      _ReconciliationFilter.unidentified => unidentified,
      _ReconciliationFilter.all => widget.values,
    }..sort((a, b) => b.dueDate.compareTo(a.dueDate));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _IntroCard(onRefresh: widget.onRefresh),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth < 780 ? 2 : 4;
            return GridView.count(
              crossAxisCount: columns,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: constraints.maxWidth < 780 ? 2.5 : 2.7,
              children: [
                _MetricCard(
                  'Conciliados',
                  '${reconciled.length}',
                  'status e valor conferidos',
                  const Color(0xFF008D68),
                  Icons.verified_outlined,
                ),
                _MetricCard(
                  'Divergências',
                  '${divergent.length}',
                  'revisar valor recebido',
                  const Color(0xFFD97706),
                  Icons.compare_arrows,
                ),
                _MetricCard(
                  'Aguardando',
                  '${pending.length}',
                  'sem pagamento aprovado',
                  const Color(0xFF2563EB),
                  Icons.schedule_outlined,
                ),
                _MetricCard(
                  'Sem identificação',
                  '${unidentified.length}',
                  'sem retorno do provedor',
                  const Color(0xFF64748B),
                  Icons.help_outline,
                ),
              ],
            );
          },
        ),
        const SizedBox(height: 14),
        _FilterBar(
          value: _filter,
          onChanged: (value) => setState(() => _filter = value),
        ),
        const SizedBox(height: 12),
        _ReconciliationList(
          values: visible,
          money: widget.money,
          date: widget.date,
          onSync: widget.onSync,
          onOpen: widget.onOpen,
        ),
      ],
    );
  }

  bool _isPaid(CompanyBilling item) =>
      item.status == 'paid' || item.mercadoPagoStatus == 'approved';

  bool _isReconciled(CompanyBilling item) {
    if (!_isPaid(item) || item.mercadoPagoPaymentId == null) return false;
    final paid = item.paidAmount;
    final expected = item.totalDue ?? item.amount;
    return paid == null || (paid - expected).abs() < 0.01;
  }

  bool _isDivergent(CompanyBilling item) {
    if (!_isPaid(item)) return false;
    final paid = item.paidAmount;
    final expected = item.totalDue ?? item.amount;
    return paid != null && (paid - expected).abs() >= 0.01;
  }

  bool _isPending(CompanyBilling item) =>
      !_isPaid(item) && item.status != 'canceled';

  bool _isUnidentified(CompanyBilling item) =>
      item.mercadoPagoPaymentId == null && _isPaid(item);
}

class _IntroCard extends StatelessWidget {
  const _IntroCard({required this.onRefresh});
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F0FF),
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Icon(Icons.compare_arrows, color: Color(0xFF2563EB)),
        ),
        const SizedBox(width: 14),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Conciliação de cobranças',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF162640),
                ),
              ),
              SizedBox(height: 4),
              Text(
                'Confira se o status, o valor e o retorno do Mercado Pago correspondem à cobrança do cliente.',
                style: TextStyle(color: Color(0xFF71839B)),
              ),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onRefresh,
          icon: const Icon(Icons.sync),
          label: const Text('Atualizar'),
        ),
      ],
    ),
  );
}

class _MetricCard extends StatelessWidget {
  const _MetricCard(this.label, this.value, this.detail, this.color, this.icon);
  final String label, value, detail;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Row(
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF71839B))),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                detail,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Color(0xFF71839B)),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({required this.value, required this.onChanged});
  final _ReconciliationFilter value;
  final ValueChanged<_ReconciliationFilter> onChanged;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _choice('Todas', _ReconciliationFilter.all),
        _choice('Conciliadas', _ReconciliationFilter.reconciled),
        _choice('Divergências', _ReconciliationFilter.divergent),
        _choice('Aguardando', _ReconciliationFilter.pending),
        _choice('Sem identificação', _ReconciliationFilter.unidentified),
      ],
    ),
  );

  Widget _choice(String label, _ReconciliationFilter filter) => ChoiceChip(
    label: Text(label),
    selected: value == filter,
    onSelected: (_) => onChanged(filter),
  );
}

class _ReconciliationList extends StatelessWidget {
  const _ReconciliationList({
    required this.values,
    required this.money,
    required this.date,
    required this.onSync,
    required this.onOpen,
  });
  final List<CompanyBilling> values;
  final String Function(double) money;
  final String Function(DateTime?) date;
  final Future<void> Function(CompanyBilling billing) onSync;
  final ValueChanged<CompanyBilling> onOpen;

  @override
  Widget build(BuildContext context) {
    if (values.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFDCE5F0)),
        ),
        child: const Center(
          child: Text(
            'Nenhuma cobrança neste filtro.',
            style: TextStyle(color: Color(0xFF71839B)),
          ),
        ),
      );
    }
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFDCE5F0)),
      ),
      child: Column(
        children: values.map((item) => _row(context, item)).toList(),
      ),
    );
  }

  Widget _row(BuildContext context, CompanyBilling item) {
    final paid = item.paidAmount;
    final expected = item.totalDue ?? item.amount;
    final isPaid =
        item.status == 'paid' || item.mercadoPagoStatus == 'approved';
    final divergent = isPaid && paid != null && (paid - expected).abs() >= 0.01;
    final reconciled =
        isPaid && item.mercadoPagoPaymentId != null && !divergent;
    final color = reconciled
        ? const Color(0xFF008D68)
        : divergent
        ? const Color(0xFFD97706)
        : isPaid
        ? const Color(0xFF64748B)
        : const Color(0xFF2563EB);
    final label = reconciled
        ? 'Conciliada'
        : divergent
        ? 'Divergência de valor'
        : isPaid
        ? 'Sem identificação'
        : 'Aguardando pagamento';

    return InkWell(
      onTap: () => onOpen(item),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE7EDF4))),
        ),
        child: Row(
          children: [
            Icon(
              reconciled
                  ? Icons.check_circle_outline
                  : divergent
                  ? Icons.warning_amber_outlined
                  : Icons.schedule_outlined,
              color: color,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.companyName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF1B2B43),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '${item.companyCode} • vencimento ${date(item.dueDate)}',
                    style: const TextStyle(
                      color: Color(0xFF71839B),
                      fontSize: 12,
                    ),
                  ),
                  if (item.mercadoPagoPayerName != null)
                    Text(
                      'Pagador: ${item.mercadoPagoPayerName}',
                      style: const TextStyle(
                        color: Color(0xFF71839B),
                        fontSize: 12,
                      ),
                    ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  money(paid ?? expected),
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(label, style: TextStyle(color: color, fontSize: 12)),
              ],
            ),
            const SizedBox(width: 8),
            if (!isPaid)
              IconButton(
                tooltip: 'Consultar Mercado Pago',
                onPressed: () => onSync(item),
                icon: const Icon(Icons.sync, color: Color(0xFF2563EB)),
              )
            else
              const Icon(Icons.chevron_right, color: Color(0xFF91A1B5)),
          ],
        ),
      ),
    );
  }
}
