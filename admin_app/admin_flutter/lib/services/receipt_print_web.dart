// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

import '../models/cash_closing.dart';
import '../models/client.dart';
import '../models/equipment.dart';
import '../models/fiscal.dart';
import '../models/service_order.dart';
import '../models/sale.dart';

void openServiceOrderReceipt({
  required ServiceOrder order,
  required Client? client,
  required Equipment? equipment,
}) {
  final receipt = _buildReceiptHtml(
    order: order,
    client: client,
    equipment: equipment,
  );
  final blob = html.Blob([receipt], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.window.open(url, '_blank');
  Future<void>.delayed(const Duration(seconds: 5), () {
    html.Url.revokeObjectUrl(url);
  });
}

Future<void> openNonFiscalSaleReceipt({
  required Sale sale,
  required String companyName,
  String? clientName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? operatorName,
  List<SaleInstallmentPayload> installments = const [],
  int? creditInstallmentCount,
}) async {
  final receipt = _buildNonFiscalSaleReceiptHtml(
    sale: sale,
    companyName: companyName,
    companyDocument: companyDocument,
    clientName: clientName,
    cashRegisterNumber: cashRegisterNumber,
    operatorName: operatorName,
    installments: installments,
    creditInstallmentCount: creditInstallmentCount,
  );
  final blob = html.Blob([receipt], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final frame = html.IFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.border = '0';
  html.document.body?.append(frame);
  Future<void>.delayed(const Duration(seconds: 30), () {
    frame.remove();
    html.Url.revokeObjectUrl(url);
  });
}

Future<bool> isReceiptPrinterConfigured() async => true;

Future<void> openCashDrawer({String pulseProfile = 'default'}) async {
  throw UnsupportedError(
    'Abertura de gaveta disponivel apenas no PDV Windows.',
  );
}

Future<void> printFiscalNfceSaleReceipt({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) async {
  throw UnsupportedError(
    'Impressao fiscal termica direta esta disponivel apenas no app Windows.',
  );
}

Future<void> printCashClosingReceipt({
  required CashClosing closing,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? fiscalName,
}) async {
  final rows = closing.payments
      .map(
        (payment) =>
            '<div class="between"><span>${_escape(_paymentLabel(payment.method))}</span><span>${_money(payment.amount)}</span></div>',
      )
      .join();
  final movements = closing.movements
      .map(
        (movement) =>
            '<div class="between"><span>${_escape(movement.movementType)} ${_escape(movement.reason ?? '')}</span><span>${_money(movement.amount)}</span></div>',
      )
      .join();
  await _printHtml('''
<!doctype html>
<html><head><meta charset="utf-8"><title>Fechamento de caixa</title>
<style>
body{font-family:Arial,sans-serif;width:72mm;margin:0 auto;padding:8px;color:#111}
.center{text-align:center}.between{display:flex;justify-content:space-between;gap:8px}
.line{border-top:1px dashed #111;margin:8px 0}.bold{font-weight:700}
@media print{body{width:72mm}.actions{display:none}}
</style></head><body>
<div class="actions"><button onclick="window.print()">Imprimir</button></div>
<div class="center bold">${_escape(companyName.toUpperCase())}</div>
${(companyDocument ?? '').trim().isEmpty ? '' : '<div class="center">CNPJ ${_escape(companyDocument!.trim())}</div>'}
<div class="line"></div>
<div class="center bold">FECHAMENTO DE CAIXA</div>
<div class="center">COMPROVANTE GERENCIAL - SEM VALOR FISCAL</div>
<div class="line"></div>
<div>Fechamento: ${_escape(closing.number ?? closing.id.toString())}</div>
${(cashRegisterNumber ?? closing.cashRegisterNumber ?? '').trim().isEmpty ? '' : '<div>Caixa: ${_escape((cashRegisterNumber ?? closing.cashRegisterNumber)!.trim())}</div>'}
<div>Operador: ${_escape(closing.operatorName ?? '-')}</div>
<div>Fiscal: ${_escape(fiscalName ?? '-')}</div>
<div>Data: ${_date(closing.closedAt)}</div>
<div class="line"></div>
<div class="between"><span>Qtd. vendas</span><span>${closing.totalSalesCount}</span></div>
<div class="between bold"><span>Total vendido</span><span>${_money(closing.totalSalesAmount)}</span></div>
<div class="line"></div>
$rows
<div class="line"></div>
<div class="between"><span>Fundo inicial</span><span>${_money(closing.openingAmount)}</span></div>
<div class="between"><span>Dinheiro esperado</span><span>${_money(closing.expectedCashAmount)}</span></div>
<div class="between"><span>Dinheiro contado</span><span>${_money(closing.countedCashAmount)}</span></div>
<div class="between bold"><span>Quebra/diferença</span><span>${_money(closing.cashDifferenceAmount)}</span></div>
<div class="line"></div>
<div class="between"><span>Sangrias</span><span>${_money(closing.totalWithdrawalAmount)}</span></div>
<div class="between"><span>Suprimentos</span><span>${_money(closing.totalSupplyAmount)}</span></div>
$movements
<script>window.addEventListener('load',()=>setTimeout(()=>window.print(),350));</script>
</body></html>
''');
}

Future<void> printCashMovementReceipt({
  required String type,
  required double amount,
  required DateTime createdAt,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? operatorName,
  String? fiscalName,
  String? reason,
}) async {
  final title = type == 'suprimento' ? 'SUPRIMENTO' : 'SANGRIA';
  await _printHtml('''
<!doctype html>
<html><head><meta charset="utf-8"><title>$title</title>
<style>
body{font-family:Arial,sans-serif;width:72mm;margin:0 auto;padding:8px;color:#111}
.center{text-align:center}.between{display:flex;justify-content:space-between;gap:8px}
.line{border-top:1px dashed #111;margin:8px 0}.bold{font-weight:700}
@media print{body{width:72mm}.actions{display:none}}
</style></head><body>
<div class="actions"><button onclick="window.print()">Imprimir</button></div>
<div class="center bold">${_escape(companyName.toUpperCase())}</div>
${(companyDocument ?? '').trim().isEmpty ? '' : '<div class="center">CNPJ ${_escape(companyDocument!.trim())}</div>'}
<div class="line"></div>
<div class="center bold">COMPROVANTE DE $title</div>
<div class="center">COMPROVANTE GERENCIAL - SEM VALOR FISCAL</div>
<div class="line"></div>
<div>Data: ${_date(createdAt)}</div>
${(cashRegisterNumber ?? '').trim().isEmpty ? '' : '<div>Caixa: ${_escape(cashRegisterNumber!.trim())}</div>'}
<div>Operador: ${_escape(operatorName ?? '-')}</div>
<div>Fiscal: ${_escape(fiscalName ?? '-')}</div>
<div class="line"></div>
<div class="between bold"><span>Valor</span><span>${_money(amount)}</span></div>
${(reason ?? '').trim().isEmpty ? '' : '<div>Motivo: ${_escape(reason!.trim())}</div>'}
<script>window.addEventListener('load',()=>setTimeout(()=>window.print(),350));</script>
</body></html>
''');
}

Future<void> _printHtml(String content) async {
  final blob = html.Blob([content], 'text/html;charset=utf-8');
  final url = html.Url.createObjectUrlFromBlob(blob);
  final frame = html.IFrameElement()
    ..src = url
    ..style.position = 'fixed'
    ..style.width = '1px'
    ..style.height = '1px'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.border = '0';
  html.document.body?.append(frame);
  Future<void>.delayed(const Duration(seconds: 30), () {
    frame.remove();
    html.Url.revokeObjectUrl(url);
  });
}

String _buildNonFiscalSaleReceiptHtml({
  required Sale sale,
  required String companyName,
  String? clientName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? operatorName,
  List<SaleInstallmentPayload> installments = const [],
  int? creditInstallmentCount,
}) {
  final rows = sale.items.map((item) {
    return '''
      <tr>
        <td colspan="3" class="item-name">${_escape(item.description)}</td>
      </tr>
      <tr>
        <td>${_quantity(item.quantity)} ${_escape(item.unit)}</td>
        <td class="right muted">x ${_money(item.unitPrice)}</td>
        <td class="right strong">${_money(item.totalPrice)}</td>
      </tr>
    ''';
  }).join();
  final payments = sale.payments.map((payment) {
    return '<div class="between"><span>${_escape(_paymentLabel(payment.method))}</span><span>${_money(payment.amount)}</span></div>';
  }).join();
  final installmentRows = installments.map((installment) {
    return '<div class="between"><span>${installment.number}/${installments.length} - ${_shortDate(installment.dueDate)}</span><span>${_money(installment.amount)}</span></div>';
  }).join();
  final hasCredit = sale.payments.any((payment) => payment.method == 'credito');
  final creditInstallments = hasCredit
      ? (creditInstallmentCount ?? _creditInstallmentsFromNotes(sale))
      : null;
  final creditInstallmentInfo =
      creditInstallments == null || creditInstallments <= 1
      ? ''
      : '<div class="between"><span>Parcelamento</span><span>${creditInstallments}x de ${_money(sale.totalAmount / creditInstallments)}</span></div>';
  final document = (companyDocument ?? '').trim();
  final notes = (sale.notes ?? '').trim();
  final creditClient = (clientName ?? '').trim();
  return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>Cupom não fiscal ${_escape(sale.number ?? sale.id.toString())}</title>
  <style>
    @page { size: 80mm auto; margin: 3mm; }
    * { box-sizing: border-box; }
    body { width: 72mm; margin: 0 auto; color: #111827; font: 11px/1.35 Arial, Helvetica, sans-serif; }
    .center { text-align: center; }
    .brand { font-size: 15px; font-weight: 900; text-transform: uppercase; }
    .document { margin-top: 2px; color: #374151; }
    .stamp { margin: 8px 0; padding: 6px; border: 2px solid #111827; border-radius: 2px; text-align: center; }
    .stamp-title { font-size: 13px; font-weight: 900; letter-spacing: .3px; }
    .stamp-subtitle { font-size: 9px; font-weight: 800; }
    .line { border-top: 1px dashed #111827; margin: 8px 0; }
    table { width: 100%; border-collapse: collapse; }
    td { padding: 2px 0; vertical-align: top; }
    .item-name { padding-top: 6px; font-weight: 900; }
    .right { text-align: right; }
    .between { display: flex; justify-content: space-between; margin: 2px 0; }
    .strong { font-weight: 800; }
    .total { font-size: 15px; font-weight: 900; }
    .muted { font-size: 9px; }
    .section-title { margin-bottom: 3px; font-size: 10px; font-weight: 900; text-transform: uppercase; }
    .summary { padding: 4px 0; }
    .actions { margin: 10px 0; }
    button { width: 100%; height: 34px; border: 0; border-radius: 4px; background: #0f766e; color: #fff; font-weight: 800; }
    @media print { .actions { display: none; } body { width: 72mm; } }
  </style>
</head>
<body>
  <div class="actions"><button onclick="window.print()">Imprimir cupom</button></div>
  <div class="center">
    <div class="brand">${_escape(companyName)}</div>
    ${document.isEmpty ? '' : '<div class="document">CNPJ ${_escape(_formatDocument(document))}</div>'}
  </div>
  <div class="stamp">
    <div class="stamp-title">CUPOM NÃO FISCAL</div>
    <div class="stamp-subtitle">NÃO É DOCUMENTO FISCAL</div>
  </div>
  <div class="between"><span>Venda</span><span>${_escape(sale.number ?? sale.id.toString())}</span></div>
  ${((cashRegisterNumber ?? sale.cashRegisterNumber) ?? '').trim().isEmpty ? '' : '<div>Caixa: ${_escape((cashRegisterNumber ?? sale.cashRegisterNumber)!.trim())}</div>'}
  <div class="between"><span>Data</span><span>${_date(sale.soldAt)}</span></div>
  <div class="between"><span>Operador</span><span>${_escape(operatorName ?? sale.sellerName ?? '-')}</span></div>
  <div class="line"></div>
  <table>$rows</table>
  <div class="line"></div>
  <div class="summary">
    <div class="between"><span>Subtotal</span><span>${_money(sale.subtotalAmount)}</span></div>
    ${sale.discountAmount > 0 ? '<div class="between"><span>Desconto</span><span>-${_money(sale.discountAmount)}</span></div>' : ''}
    <div class="between total"><span>TOTAL</span><span>${_money(sale.totalAmount)}</span></div>
  </div>
  <div class="line"></div>
  <div class="section-title">Pagamentos</div>
  $payments
  ${sale.payments.any((payment) => payment.method == 'crediario') && creditClient.isNotEmpty ? '<div class="between"><span>Cliente</span><span>${_escape(creditClient)}</span></div>' : ''}
  <div class="between"><span>Recebido</span><span>${_money(sale.amountPaid)}</span></div>
  ${sale.changeAmount > 0 ? '<div class="between"><span>Troco</span><span>${_money(sale.changeAmount)}</span></div>' : ''}
  $creditInstallmentInfo
  ${installmentRows.isEmpty ? '' : '<div class="line"></div><div class="section-title">Parcelas</div>$installmentRows'}
  ${notes.isEmpty ? '' : '<div class="line"></div><div>Observações: ${_escape(notes)}</div>'}
  <div class="line"></div>
  <div class="center muted">Comprovante comercial sem valor fiscal.</div>
  <div class="center">Obrigado pela preferência.</div>
  <script>window.addEventListener('load', () => setTimeout(() => window.print(), 350));</script>
</body>
</html>
''';
}

String _buildReceiptHtml({
  required ServiceOrder order,
  required Client? client,
  required Equipment? equipment,
}) {
  final code = _escape(
    order.number?.isNotEmpty == true ? order.number! : 'M${order.id}',
  );
  final openedAt = _escape(_date(order.openedAt));
  final clientName = _escape(client?.name ?? 'Cliente #${order.clientId}');
  final phone = _escape(client?.phone ?? client?.mobilePhone ?? '-');
  final equipmentName = _escape(
    order.receivedEquipment?.trim().isNotEmpty == true
        ? order.receivedEquipment!.trim()
        : equipment?.hostname ?? '-',
  );
  final request = _escape(order.requestDescription);
  final waiting = _escape(order.waitingReason ?? '');
  final status = _escape(_statusLabel(order.status));
  final priority = _escape(_priorityLabel(order.priority));

  return '''
<!doctype html>
<html>
<head>
  <meta charset="utf-8">
  <title>OS $code</title>
  <style>
    @page { size: 80mm auto; margin: 4mm; }
    * { box-sizing: border-box; }
    body {
      width: 72mm;
      margin: 0 auto;
      color: #111827;
      font-family: Arial, Helvetica, sans-serif;
      font-size: 11px;
      line-height: 1.25;
    }
    .center { text-align: center; }
    .brand { font-size: 18px; font-weight: 800; letter-spacing: .5px; }
    .title { font-size: 12px; font-weight: 700; margin-top: 2px; }
    .line { border-top: 1px dashed #111827; margin: 8px 0; }
    .row { margin: 3px 0; }
    .label { font-weight: 800; }
    .box { border: 1px solid #111827; padding: 6px; margin-top: 6px; }
    .signature { margin-top: 28px; border-top: 1px solid #111827; padding-top: 4px; text-align: center; }
    .actions { margin: 12px 0; display: flex; gap: 8px; }
    button { width: 100%; height: 34px; border: 0; border-radius: 4px; background: #0ea5e9; color: white; font-weight: 700; }
    @media print {
      .actions { display: none; }
      body { width: 72mm; }
    }
  </style>
</head>
<body>
  <div class="actions"><button onclick="window.print()">Imprimir / Salvar PDF</button></div>
  <div class="center">
    <div class="brand">PAPEZZOSYNC</div>
    <div class="title">COMPROVANTE DE ORDEM DE SERVICO</div>
  </div>
  <div class="line"></div>
  <div class="row"><span class="label">OS:</span> $code</div>
  <div class="row"><span class="label">Abertura:</span> $openedAt</div>
  <div class="row"><span class="label">Cliente:</span> $clientName</div>
  <div class="row"><span class="label">Telefone:</span> $phone</div>
  <div class="row"><span class="label">Equipamento:</span> $equipmentName</div>
  <div class="row"><span class="label">Status:</span> $status</div>
  <div class="row"><span class="label">Prioridade:</span> $priority</div>
  ${waiting.isEmpty ? '' : '<div class="row"><span class="label">Aguardando:</span> $waiting</div>'}
  <div class="line"></div>
  <div class="label">Problema informado</div>
  <div class="box">$request</div>
  <div class="line"></div>
  <div>
    Recebemos o equipamento descrito acima para avaliação técnica.
    A PapezzoSync não coleta tela, arquivos pessoais ou senhas sem consentimento.
  </div>
  <div class="signature">Assinatura do cliente</div>
  <div class="line"></div>
  <div class="center">Guarde este comprovante</div>
  <script>
    window.addEventListener('load', () => setTimeout(() => window.print(), 350));
  </script>
</body>
</html>
''';
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

String _shortDate(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year}';
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

String _quantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll('.', ',');
}

String _paymentLabel(String method) {
  const labels = {
    'dinheiro': 'Dinheiro',
    'pix': 'Pix',
    'debito': 'Débito',
    'credito': 'Crédito',
    'boleto': 'Boleto',
    'transferencia': 'Transferência',
    'crediario': 'Crediário',
    'outro': 'Outro',
  };
  return labels[method] ?? method;
}

int? _creditInstallmentsFromNotes(Sale sale) {
  for (final payment in sale.payments) {
    final notes = payment.notes ?? '';
    final match = RegExp(
      r'Cr[eé]dito\s+(\d+)x',
      caseSensitive: false,
    ).firstMatch(notes);
    if (match == null) continue;
    return int.tryParse(match.group(1) ?? '');
  }
  return null;
}

String _formatDocument(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 14) return value;
  return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}';
}

String _escape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;')
      .replaceAll('\n', '<br>');
}

String _statusLabel(String status) {
  const labels = {
    'aberta': 'Aberta',
    'em_diagnostico': 'Em diagnostico',
    'aguardando_aprovacao': 'Aguardando',
    'em_execucao': 'Em execucao',
    'concluida': 'Concluida',
    'cancelada': 'Cancelada',
  };
  return labels[status] ?? status;
}

String _priorityLabel(String priority) {
  const labels = {'baixa': 'Baixa', 'media': 'Media', 'alta': 'Alta'};
  return labels[priority] ?? priority;
}
