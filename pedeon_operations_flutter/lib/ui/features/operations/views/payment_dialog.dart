import 'package:flutter/material.dart';

class PaymentInput {
  const PaymentInput(this.method, this.amount, this.authorization);

  final String method;
  final double amount;
  final String? authorization;
}

Future<PaymentInput?> showPaymentDialog(
  BuildContext context, {
  required double total,
  String title = 'Receber pagamento',
}) => showDialog<PaymentInput>(
  context: context,
  builder: (_) => _PaymentDialog(total: total, title: title),
);

class _PaymentDialog extends StatefulWidget {
  const _PaymentDialog({required this.total, required this.title});

  final double total;
  final String title;

  @override
  State<_PaymentDialog> createState() => _PaymentDialogState();
}

class _PaymentDialogState extends State<_PaymentDialog> {
  String method = 'dinheiro';
  late final TextEditingController amount;
  final authorization = TextEditingController();

  @override
  void initState() {
    super.initState();
    amount = TextEditingController(
      text: widget.total.toStringAsFixed(2).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    amount.dispose();
    authorization.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: SizedBox(
      width: 460,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DropdownButtonFormField<String>(
            initialValue: method,
            decoration: const InputDecoration(labelText: 'Forma de pagamento'),
            items: const [
              DropdownMenuItem(value: 'dinheiro', child: Text('Dinheiro')),
              DropdownMenuItem(value: 'pix', child: Text('Pix')),
              DropdownMenuItem(
                value: 'debito',
                child: Text('Cartão de débito'),
              ),
              DropdownMenuItem(
                value: 'credito',
                child: Text('Cartão de crédito'),
              ),
            ],
            onChanged: (value) => setState(() => method = value ?? method),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: method == 'dinheiro' ? 'Valor recebido' : 'Valor',
              prefixText: 'R\$ ',
            ),
          ),
          if (method == 'debito' || method == 'credito') ...[
            const SizedBox(height: 12),
            TextField(
              controller: authorization,
              decoration: const InputDecoration(
                labelText: 'NSU/autorização (opcional)',
              ),
            ),
          ],
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancelar'),
      ),
      FilledButton(
        onPressed: () {
          final paid = double.tryParse(amount.text.replaceAll(',', '.'));
          if (paid == null || paid <= 0) return;
          Navigator.pop(
            context,
            PaymentInput(
              method,
              paid,
              authorization.text.trim().isEmpty
                  ? null
                  : authorization.text.trim(),
            ),
          );
        },
        child: const Text('Confirmar pagamento'),
      ),
    ],
  );
}
