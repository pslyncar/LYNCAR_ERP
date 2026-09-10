import 'package:flutter/material.dart';
import '../models/company_billing.dart';

class MasterBillingReceiptsScreen extends StatelessWidget {
  const MasterBillingReceiptsScreen({
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
    final paid = values.where((item) => item.status == 'paid').toList();
    return _ReceiptPanel(values: paid, money: money, date: date, onTap: onTap);
  }
}

class _ReceiptPanel extends StatelessWidget {
  const _ReceiptPanel({
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
        const Text(
          'Recebimentos confirmados',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            color: Color(0xFF162640),
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Pagamentos identificados pelo Mercado Pago ou baixados manualmente.',
          style: TextStyle(color: Color(0xFF71839B)),
        ),
        const SizedBox(height: 16),
        if (values.isEmpty)
          const Text(
            'Nenhum recebimento encontrado.',
            style: TextStyle(color: Color(0xFF71839B)),
          )
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
                            'Pagador: ${item.mercadoPagoPayerName ?? 'Não identificado'} • ${date(item.paidAt)}',
                            style: const TextStyle(
                              color: Color(0xFF71839B),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      money(item.paidAmount ?? item.amount),
                      style: const TextStyle(
                        color: Color(0xFF008D68),
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
