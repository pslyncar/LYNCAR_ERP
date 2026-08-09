import 'dart:convert';
import 'dart:io';

import '../models/cash_closing.dart';
import '../models/client.dart';
import '../models/equipment.dart';
import '../models/fiscal.dart';
import '../models/sale.dart';
import '../models/service_order.dart';

void openServiceOrderReceipt({
  required ServiceOrder order,
  required Client? client,
  required Equipment? equipment,
}) {
  throw UnsupportedError('Impressão de OS disponível no navegador.');
}

Future<void> openNonFiscalSaleReceipt({
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? operatorName,
}) async {
  if (!Platform.isWindows) return;
  await _printWindowsRaw(
    _buildReceiptBytes(
      sale: sale,
      companyName: companyName,
      companyDocument: companyDocument,
      cashRegisterNumber: cashRegisterNumber,
      operatorName: operatorName,
    ),
  );
}

Future<void> printFiscalNfceSaleReceipt({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) async {
  if (!Platform.isWindows) return;
  await _printWindowsRaw(
    _buildFiscalNfceBytes(
      document: document,
      sale: sale,
      companyName: companyName,
      companyDocument: companyDocument,
      operatorName: operatorName,
    ),
  );
}

Future<void> printCashClosingReceipt({
  required CashClosing closing,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? fiscalName,
}) async {
  if (!Platform.isWindows) return;
  await _printWindowsRaw(
    _buildCashClosingBytes(
      closing: closing,
      companyName: companyName,
      companyDocument: companyDocument,
      cashRegisterNumber: cashRegisterNumber,
      fiscalName: fiscalName,
    ),
  );
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
  if (!Platform.isWindows) return;
  await _printWindowsRaw(
    _buildCashMovementBytes(
      type: type,
      amount: amount,
      createdAt: createdAt,
      companyName: companyName,
      companyDocument: companyDocument,
      cashRegisterNumber: cashRegisterNumber,
      operatorName: operatorName,
      fiscalName: fiscalName,
      reason: reason,
    ),
  );
}

Future<bool> isReceiptPrinterConfigured() async {
  if (!Platform.isWindows) return false;
  if (await _printerMarkerFile().exists()) return true;
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    r'$printer=Get-CimInstance Win32_Printer | Where-Object Default | Select-Object -First 1; if ($null -eq $printer) { exit 1 }; Write-Output $printer.Name; exit 0',
  ]);
  return result.exitCode == 0 && result.stdout.toString().trim().isNotEmpty;
}

Future<void> openCashDrawer({String pulseProfile = 'default'}) async {
  if (!Platform.isWindows) return;
  await _printWindowsRaw(_cashDrawerPulseBytes(pulseProfile));
}

File _printerMarkerFile() {
  final appData = Platform.environment['APPDATA'] ?? Directory.systemTemp.path;
  return File('$appData\\Lyncar\\PDV\\impressora-configurada');
}

List<int> _cashDrawerPulseBytes(String pulseProfile) {
  switch (pulseProfile) {
    case 'pin2':
      return const [27, 112, 1, 25, 250];
    case 'short':
      return const [27, 112, 0, 20, 120];
    case 'strong':
      return const [27, 112, 0, 64, 240];
    case 'long':
      return const [27, 112, 0, 80, 250];
    case 'default':
    default:
      return const [27, 112, 0, 25, 250];
  }
}

Future<void> _printWindowsRaw(List<int> bytes) async {
  final payload = base64Encode(bytes);
  final script =
      StringBuffer(r'''
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class LyncarRawPrinter {
  [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
  public class DOCINFO {
    [MarshalAs(UnmanagedType.LPWStr)] public string pDocName;
    [MarshalAs(UnmanagedType.LPWStr)] public string pOutputFile;
    [MarshalAs(UnmanagedType.LPWStr)] public string pDataType;
  }

  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool GetDefaultPrinter(StringBuilder name, ref int size);
  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern bool OpenPrinter(string name, out IntPtr handle, IntPtr defaults);
  [DllImport("winspool.drv", SetLastError = true)]
  static extern bool ClosePrinter(IntPtr handle);
  [DllImport("winspool.drv", CharSet = CharSet.Unicode, SetLastError = true)]
  static extern int StartDocPrinter(IntPtr handle, int level, [In] DOCINFO info);
  [DllImport("winspool.drv", SetLastError = true)]
  static extern bool EndDocPrinter(IntPtr handle);
  [DllImport("winspool.drv", SetLastError = true)]
  static extern bool StartPagePrinter(IntPtr handle);
  [DllImport("winspool.drv", SetLastError = true)]
  static extern bool EndPagePrinter(IntPtr handle);
  [DllImport("winspool.drv", SetLastError = true)]
  static extern bool WritePrinter(IntPtr handle, byte[] data, int count, out int written);

  static string DefaultPrinter() {
    int size = 0;
    GetDefaultPrinter(null, ref size);
    if (size <= 0) return null;
    var name = new StringBuilder(size);
    return GetDefaultPrinter(name, ref size) ? name.ToString() : null;
  }

  public static bool Send(byte[] data) {
    string name = DefaultPrinter();
    if (String.IsNullOrWhiteSpace(name)) return false;
    IntPtr handle;
    if (!OpenPrinter(name, out handle, IntPtr.Zero)) return false;
    try {
      var info = new DOCINFO { pDocName = "Cupom Lyncar", pDataType = "RAW" };
      if (StartDocPrinter(handle, 1, info) == 0) return false;
      try {
        if (!StartPagePrinter(handle)) return false;
        try {
          int written;
          return WritePrinter(handle, data, data.Length, out written) && written == data.Length;
        } finally { EndPagePrinter(handle); }
      } finally { EndDocPrinter(handle); }
    } finally { ClosePrinter(handle); }
  }
}
'@
''')
        ..write(r"$data=[Convert]::FromBase64String('")
        ..write(payload)
        ..write(r"'); if(-not [LyncarRawPrinter]::Send($data)){exit 2}");
  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-EncodedCommand',
    _powerShellEncodedCommand(script.toString()),
  ]);
  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const [],
      result.stderr.toString().trim().isEmpty
          ? 'O Windows não confirmou o envio para a impressora padrão.'
          : result.stderr.toString().trim(),
      result.exitCode,
    );
  }
  final marker = _printerMarkerFile();
  await marker.parent.create(recursive: true);
  await marker.writeAsString(DateTime.now().toIso8601String(), flush: true);
}

String _powerShellEncodedCommand(String script) {
  final bytes = <int>[];
  for (final unit in script.codeUnits) {
    bytes
      ..add(unit & 0xff)
      ..add((unit >> 8) & 0xff);
  }
  return base64Encode(bytes);
}

List<int> _buildReceiptBytes({
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? operatorName,
}) {
  const width = 48;
  final bytes = <int>[27, 64, 27, 77, 0, 27, 97, 1, 27, 69, 1];
  void line([String value = '']) =>
      bytes.addAll('${_plain(value)}\n'.codeUnits);
  void command(List<int> value) => bytes.addAll(value);

  line(companyName.toUpperCase());
  command([27, 69, 0]);
  if ((companyDocument ?? '').trim().isNotEmpty) {
    line('CNPJ ${companyDocument!.trim()}');
  }
  line(_repeat('=', width));
  command([27, 69, 1]);
  line('CUPOM NAO FISCAL');
  line('NAO E DOCUMENTO FISCAL');
  command([27, 69, 0, 27, 97, 0]);
  line(_repeat('=', width));
  line('Venda: ${sale.number ?? sale.id}');
  final cashNumber = cashRegisterNumber ?? sale.cashRegisterNumber;
  if ((cashNumber ?? '').trim().isNotEmpty) {
    line('Caixa: ${cashNumber!.trim()}');
  }
  line('Data: ${_date(sale.soldAt)}');
  line('Operador: ${operatorName ?? sale.sellerName ?? '-'}');
  line(_repeat('-', width));
  for (final item in sale.items) {
    for (final part in _wrap(item.description, width)) {
      line(part);
    }
    line(
      _pair(
        '${_quantity(item.quantity)} ${item.unit.toUpperCase()} x ${_money(item.unitPrice)}',
        _money(item.totalPrice),
        width,
      ),
    );
  }
  line(_repeat('-', width));
  line(_pair('Subtotal', _money(sale.subtotalAmount), width));
  if (sale.discountAmount > 0) {
    line(_pair('Desconto', '-${_money(sale.discountAmount)}', width));
  }
  command([27, 69, 1]);
  line(_pair('TOTAL', _money(sale.totalAmount), width));
  command([27, 69, 0]);
  line(_repeat('-', width));
  line('PAGAMENTOS');
  for (final payment in sale.payments) {
    line(_pair(_paymentLabel(payment.method), _money(payment.amount), width));
  }
  line(_pair('Recebido', _money(sale.amountPaid), width));
  if (sale.changeAmount > 0) {
    line(_pair('Troco', _money(sale.changeAmount), width));
  }
  line(_repeat('-', width));
  command([27, 97, 1]);
  line('COMPROVANTE COMERCIAL SEM VALOR FISCAL');
  line('Obrigado pela preferencia.');
  command([27, 97, 0]);
  bytes.addAll([10, 10, 10, 10, 29, 86, 66, 0]);
  return bytes;
}

List<int> _buildFiscalNfceBytes({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) {
  const width = 48;
  final bytes = <int>[27, 64, 27, 77, 0, 27, 97, 1, 27, 69, 1];
  void line([String value = '']) =>
      bytes.addAll('${_plain(value)}\n'.codeUnits);
  void command(List<int> value) => bytes.addAll(value);

  final isHomologation = document.environment.toLowerCase().contains('hom');
  final consultationUrl = (document.danfeUrl ?? '').trim();

  line(companyName.toUpperCase());
  command([27, 69, 0]);
  if ((companyDocument ?? '').trim().isNotEmpty) {
    line('CNPJ ${companyDocument!.trim()}');
  }
  line(_repeat('=', width));
  command([27, 69, 1]);
  line('DANFE NFC-e');
  command([27, 69, 0]);
  line('Documento Auxiliar da Nota Fiscal');
  line('de Consumidor Eletronica');
  if (isHomologation) {
    command([27, 69, 1]);
    line('EMITIDA EM HOMOLOGACAO');
    line('SEM VALOR FISCAL');
    command([27, 69, 0]);
  }
  line(_repeat('=', width));
  line('Venda: ${sale.number ?? sale.id}');
  line(
    'NFC-e: serie ${document.series ?? '-'} num. ${document.number ?? document.id}',
  );
  line('Data: ${_date(document.authorizedAt ?? sale.soldAt)}');
  line('Operador: ${operatorName ?? sale.sellerName ?? '-'}');
  line(_repeat('-', width));
  line(_pair('CODIGO/DESCRICAO', 'TOTAL', width));
  for (final item in sale.items) {
    final code = (item.barcode ?? '').trim();
    final title = code.isEmpty ? item.description : '$code ${item.description}';
    for (final part in _wrap(title, width)) {
      line(part);
    }
    line(
      _pair(
        '${_quantity(item.quantity)} ${item.unit.toUpperCase()} x ${_money(item.unitPrice)}',
        _money(item.totalPrice),
        width,
      ),
    );
  }
  line(_repeat('-', width));
  command([27, 69, 1]);
  line(_pair('VALOR TOTAL', _money(sale.totalAmount), width));
  command([27, 69, 0]);
  line(_repeat('-', width));
  line('PAGAMENTOS');
  for (final payment in sale.payments) {
    line(_pair(_paymentLabel(payment.method), _money(payment.amount), width));
  }
  if ((document.accessKey ?? '').trim().isNotEmpty) {
    line(_repeat('-', width));
    command([27, 97, 1]);
    line('Consulte pela chave de acesso');
    for (final part in _wrap(document.accessKey!.trim(), width)) {
      line(part);
    }
  }
  if ((document.sefazProtocol ?? '').trim().isNotEmpty) {
    line('Protocolo: ${document.sefazProtocol!.trim()}');
  }
  if (consultationUrl.isNotEmpty) {
    line();
    _appendQrCode(bytes, consultationUrl);
  }
  command([27, 97, 1]);
  line();
  line('Obrigado pela preferencia.');
  command([27, 97, 0]);
  bytes.addAll([10, 10, 10, 10, 29, 86, 66, 0]);
  return bytes;
}

List<int> _buildCashClosingBytes({
  required CashClosing closing,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? fiscalName,
}) {
  const width = 48;
  final bytes = <int>[27, 64, 27, 77, 0, 27, 97, 1, 27, 69, 1];
  void line([String value = '']) =>
      bytes.addAll('${_plain(value)}\n'.codeUnits);
  void command(List<int> value) => bytes.addAll(value);

  final salesByPayment = <String, double>{};
  for (final payment in closing.payments) {
    salesByPayment[payment.method] =
        (salesByPayment[payment.method] ?? 0) + payment.amount;
  }
  final withdrawals = closing.movements
      .where((movement) => movement.movementType == 'sangria')
      .toList(growable: false);
  final supplies = closing.movements
      .where((movement) => movement.movementType == 'suprimento')
      .toList(growable: false);

  line(companyName.toUpperCase());
  command([27, 69, 0]);
  if ((companyDocument ?? '').trim().isNotEmpty) {
    line('CNPJ ${companyDocument!.trim()}');
  }
  line(_repeat('=', width));
  command([27, 69, 1]);
  line('FECHAMENTO DE CAIXA');
  command([27, 69, 0]);
  line('COMPROVANTE GERENCIAL');
  line('SEM VALOR FISCAL');
  line(_repeat('=', width));
  line('Fechamento: ${closing.number ?? closing.id}');
  final cashNumber = cashRegisterNumber ?? closing.cashRegisterNumber;
  if ((cashNumber ?? '').trim().isNotEmpty) {
    line('Caixa: ${cashNumber!.trim()}');
  }
  if (closing.openedAt != null) line('Abertura: ${_date(closing.openedAt!)}');
  line('Fechamento: ${_date(closing.closedAt)}');
  line('Operador: ${closing.operatorName ?? '-'}');
  line(
    'Fiscal: ${fiscalName?.trim().isNotEmpty == true ? fiscalName!.trim() : '-'}',
  );
  line(_repeat('-', width));
  line(_pair('Qtd. vendas', closing.totalSalesCount.toString(), width));
  line(_pair('Total vendido', _money(closing.totalSalesAmount), width));
  line(_repeat('-', width));
  line('VENDAS POR PAGAMENTO');
  if (salesByPayment.isEmpty) {
    line(_pair('Sem vendas', _money(0), width));
  } else {
    for (final entry in salesByPayment.entries) {
      line(_pair(_paymentLabel(entry.key), _money(entry.value), width));
    }
  }
  line(_repeat('-', width));
  line(_pair('Fundo inicial', _money(closing.openingAmount), width));
  line(_pair('Dinheiro esperado', _money(closing.expectedCashAmount), width));
  line(_pair('Dinheiro contado', _money(closing.countedCashAmount), width));
  command([27, 69, 1]);
  line(_pair('Quebra/diferenca', _money(closing.cashDifferenceAmount), width));
  command([27, 69, 0]);
  line(_repeat('-', width));
  line(_pair('Total sangrias', _money(closing.totalWithdrawalAmount), width));
  line(_pair('Total suprimentos', _money(closing.totalSupplyAmount), width));
  if (withdrawals.isNotEmpty) {
    line(_repeat('-', width));
    line('SANGRIAS');
    for (final movement in withdrawals) {
      line(
        _pair(
          _date(movement.createdAt ?? closing.closedAt),
          _money(movement.amount),
          width,
        ),
      );
      if ((movement.reason ?? '').trim().isNotEmpty) {
        for (final part in _wrap('Motivo: ${movement.reason!.trim()}', width)) {
          line(part);
        }
      }
    }
  }
  if (supplies.isNotEmpty) {
    line(_repeat('-', width));
    line('SUPRIMENTOS');
    for (final movement in supplies) {
      line(
        _pair(
          _date(movement.createdAt ?? closing.closedAt),
          _money(movement.amount),
          width,
        ),
      );
      if ((movement.reason ?? '').trim().isNotEmpty) {
        for (final part in _wrap('Motivo: ${movement.reason!.trim()}', width)) {
          line(part);
        }
      }
    }
  }
  if ((closing.notes ?? '').trim().isNotEmpty) {
    line(_repeat('-', width));
    for (final part in _wrap('Obs.: ${closing.notes!.trim()}', width)) {
      line(part);
    }
  }
  line(_repeat('=', width));
  command([27, 97, 1]);
  line('Assinatura operador: __________________');
  line();
  line('Assinatura fiscal: ____________________');
  command([27, 97, 0]);
  bytes.addAll([10, 10, 10, 10, 29, 86, 66, 0]);
  return bytes;
}

List<int> _buildCashMovementBytes({
  required String type,
  required double amount,
  required DateTime createdAt,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? operatorName,
  String? fiscalName,
  String? reason,
}) {
  const width = 48;
  final bytes = <int>[27, 64, 27, 77, 0, 27, 97, 1, 27, 69, 1];
  void line([String value = '']) =>
      bytes.addAll('${_plain(value)}\n'.codeUnits);
  void command(List<int> value) => bytes.addAll(value);
  final title = type == 'suprimento' ? 'SUPRIMENTO' : 'SANGRIA';

  line(companyName.toUpperCase());
  command([27, 69, 0]);
  if ((companyDocument ?? '').trim().isNotEmpty) {
    line('CNPJ ${companyDocument!.trim()}');
  }
  line(_repeat('=', width));
  command([27, 69, 1]);
  line('COMPROVANTE DE $title');
  command([27, 69, 0]);
  line('COMPROVANTE GERENCIAL');
  line('SEM VALOR FISCAL');
  line(_repeat('=', width));
  line('Data: ${_date(createdAt)}');
  if ((cashRegisterNumber ?? '').trim().isNotEmpty) {
    line('Caixa: ${cashRegisterNumber!.trim()}');
  }
  line(
    'Operador: ${operatorName?.trim().isNotEmpty == true ? operatorName!.trim() : '-'}',
  );
  line(
    'Fiscal: ${fiscalName?.trim().isNotEmpty == true ? fiscalName!.trim() : '-'}',
  );
  line(_repeat('-', width));
  command([27, 69, 1]);
  line(_pair('Valor', _money(amount), width));
  command([27, 69, 0]);
  if ((reason ?? '').trim().isNotEmpty) {
    line(_repeat('-', width));
    for (final part in _wrap('Motivo: ${reason!.trim()}', width)) {
      line(part);
    }
  }
  line(_repeat('=', width));
  command([27, 97, 1]);
  line('Assinatura operador: __________________');
  line();
  line('Assinatura fiscal: ____________________');
  command([27, 97, 0]);
  bytes.addAll([10, 10, 10, 10, 29, 86, 66, 0]);
  return bytes;
}

void _appendQrCode(List<int> bytes, String data) {
  final qr = utf8.encode(data);
  void store(List<int> payload) {
    final length = payload.length + 3;
    final pL = length % 256;
    final pH = length ~/ 256;
    bytes.addAll([29, 40, 107, pL, pH, ...payload]);
  }

  bytes.addAll([27, 97, 1]);
  store([49, 67, 6]);
  store([49, 69, 48]);
  store([49, 80, 48, ...qr]);
  store([49, 81, 48]);
  bytes.addAll([27, 97, 0]);
}

String _plain(String value) {
  const accents = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'Á': 'A',
    'À': 'A',
    'Ã': 'A',
    'Â': 'A',
    'Ä': 'A',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'É': 'E',
    'È': 'E',
    'Ê': 'E',
    'Ë': 'E',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'Í': 'I',
    'Ì': 'I',
    'Î': 'I',
    'Ï': 'I',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'Ó': 'O',
    'Ò': 'O',
    'Õ': 'O',
    'Ô': 'O',
    'Ö': 'O',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'Ú': 'U',
    'Ù': 'U',
    'Û': 'U',
    'Ü': 'U',
    'ç': 'c',
    'Ç': 'C',
    'ñ': 'n',
    'Ñ': 'N',
  };
  final normalized = value.split('').map((c) => accents[c] ?? c).join();
  return normalized.codeUnits
      .map((c) => c >= 32 && c <= 126 ? String.fromCharCode(c) : '?')
      .join();
}

List<String> _wrap(String value, int width) {
  final words = _plain(value).trim().split(RegExp(r'\s+'));
  final lines = <String>[];
  var current = '';
  for (final word in words) {
    if (word.length > width) {
      if (current.isNotEmpty) {
        lines.add(current);
        current = '';
      }
      for (var i = 0; i < word.length; i += width) {
        lines.add(word.substring(i, (i + width).clamp(0, word.length)));
      }
    } else if (current.isEmpty) {
      current = word;
    } else if (current.length + 1 + word.length <= width) {
      current = '$current $word';
    } else {
      lines.add(current);
      current = word;
    }
  }
  if (current.isNotEmpty) lines.add(current);
  return lines.isEmpty ? [''] : lines;
}

String _pair(String left, String right, int width) {
  final safeRight = right.length > width ? right.substring(0, width) : right;
  final maxLeft = (width - safeRight.length - 1).clamp(0, width).toInt();
  final safeLeft = left.length > maxLeft ? left.substring(0, maxLeft) : left;
  final spaces = (width - safeLeft.length - safeRight.length)
      .clamp(1, width)
      .toInt();
  return '$safeLeft${_repeat(' ', spaces)}$safeRight';
}

String _repeat(String value, int count) => List.filled(count, value).join();

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';

String _quantity(double value) {
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll('.', ',');
}

String _date(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

String _paymentLabel(String method) {
  const labels = {
    'dinheiro': 'Dinheiro',
    'pix': 'Pix',
    'debito': 'Debito',
    'credito': 'Credito',
    'boleto': 'Boleto',
    'transferencia': 'Transferencia',
    'crediario': 'Crediario',
    'outro': 'Outro',
  };
  return labels[method] ?? method;
}
