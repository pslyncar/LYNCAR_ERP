import 'package:flutter/material.dart';
import '../models/company_billing.dart';

class MasterBillingArrearsScreen extends StatelessWidget {
  const MasterBillingArrearsScreen({
    super.key,
    required this.values,
    required this.money,
    required this.date,
    required this.onTap,
  });
  final List<CompanyBilling> values;
  final String Function(double) money;
  final String Function(DateTime?) date;
  final ValueChanged<CompanyBilling> onTap;
  @override
  Widget build(BuildContext context) {
    final overdue = values.where((item) => item.isOverdue).toList();
    return _BillingCollection(
      title: 'Inadimplentes',
      subtitle: 'Cobranças vencidas que precisam de acompanhamento',
      empty: 'Nenhuma cobrança em atraso.',
      values: overdue,
      money: money,
      date: date,
      onTap: onTap,
      color: Colors.red,
    );
  }
}

class _BillingCollection extends StatelessWidget {
  const _BillingCollection({
    required this.title,
    required this.subtitle,
    required this.empty,
    required this.values,
    required this.money,
    required this.date,
    required this.onTap,
    required this.color,
  });
  final String title, subtitle, empty;
  final List<CompanyBilling> values;
  final String Function(double) money;
  final String Function(DateTime?) date;
  final ValueChanged<CompanyBilling> onTap;
  final Color color;
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
        Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF162640),
          ),
        ),
        const SizedBox(height: 4),
        Text(subtitle, style: const TextStyle(color: Color(0xFF71839B))),
        const SizedBox(height: 16),
        if (values.isEmpty)
          Text(empty, style: const TextStyle(color: Color(0xFF71839B)))
        else
          ...values.map(
            (item) => InkWell(
              onTap: () => onTap(item),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 13),
                decoration: const BoxDecoration(
                  border: Border(top: BorderSide(color: Color(0xFFE7EDF4))),
                ),
                child: Row(
                  children: [
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
                        ],
                      ),
                    ),
                    Text(
                      money(item.totalDue ?? item.amount),
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Icon(Icons.chevron_right, color: Color(0xFF91A1B5)),
                  ],
                ),
              ),
            ),
          ),
      ],
    ),
  );
}
