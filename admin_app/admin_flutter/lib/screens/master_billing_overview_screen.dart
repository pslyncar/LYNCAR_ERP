import 'package:flutter/material.dart';
import '../models/company_billing.dart';

class MasterBillingOverviewScreen extends StatelessWidget {
  const MasterBillingOverviewScreen({
    super.key,
    required this.values,
    required this.money,
  });
  final List<CompanyBilling> values;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    final paid = values.where((item) => item.status == 'paid').toList();
    final pending = values.where((item) => item.status == 'pending').toList();
    final overdue = pending.where((item) => item.isOverdue).toList();
    final received = paid.fold<double>(
      0,
      (sum, item) => sum + (item.paidAmount ?? item.amount),
    );
    final open = pending.fold<double>(
      0,
      (sum, item) => sum + (item.totalDue ?? item.amount),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OverviewGrid(
          items: [
            _OverviewMetric(
              'Recebido no período',
              money(received),
              '${paid.length} pagamentos',
              Colors.green,
              Icons.check_circle_outline,
            ),
            _OverviewMetric(
              'Em aberto',
              money(open),
              '${pending.length} cobranças',
              const Color(0xFF0D6E8A),
              Icons.account_balance_wallet_outlined,
            ),
            _OverviewMetric(
              'Vencido',
              '${overdue.length}',
              'cobranças em atraso',
              Colors.orange,
              Icons.schedule_outlined,
            ),
            _OverviewMetric(
              'Clientes em atenção',
              '${overdue.map((item) => item.companyId).toSet().length}',
              'precisam de contato',
              Colors.red,
              Icons.warning_amber_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Acompanhamento financeiro',
          icon: Icons.insights_outlined,
          children: [
            _InfoLine('Cobranças cadastradas', '${values.length}'),
            _InfoLine(
              'Com identificação do pagador',
              '${values.where((item) => (item.mercadoPagoPayerName ?? '').isNotEmpty).length}',
            ),
            _InfoLine(
              'Com PIX gerado',
              '${values.where((item) => (item.pixQrCode ?? '').isNotEmpty).length}',
            ),
          ],
        ),
      ],
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  const _OverviewGrid({required this.items});
  final List<Widget> items;
  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 1100
          ? 4
          : constraints.maxWidth >= 620
          ? 2
          : 1;
      final width = columns == 1
          ? constraints.maxWidth
          : (constraints.maxWidth - (columns - 1) * 12) / columns;
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: items
            .map((item) => SizedBox(width: width, child: item))
            .toList(),
      );
    },
  );
}

class _OverviewMetric extends StatelessWidget {
  const _OverviewMetric(
    this.label,
    this.value,
    this.detail,
    this.color,
    this.icon,
  );
  final String label, value, detail;
  final Color color;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: color, size: 21),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF71839B), fontSize: 12),
              ),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFF162640),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                detail,
                style: TextStyle(
                  color: color,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: const Color(0xFFDCE5F0)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF176B93)),
            const SizedBox(width: 9),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: Color(0xFF1F3552),
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Wrap(spacing: 32, runSpacing: 12, children: children),
      ],
    ),
  );
}

class _InfoLine extends StatelessWidget {
  const _InfoLine(this.label, this.value);
  final String label, value;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 220,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Color(0xFF71839B), fontSize: 12),
        ),
        const SizedBox(height: 3),
        Text(
          value,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF162640),
          ),
        ),
      ],
    ),
  );
}
