import 'dart:io';

import '../models/fiscal.dart';
import '../models/sale.dart';

Future<void> printFiscalPdf({
  required String filename,
  required List<int> bytes,
  bool autoPrint = false,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Impressao fiscal disponivel no Windows e navegador.',
    );
  }

  final directory = await Directory.systemTemp.createTemp('lyncar-danfe-');
  final safeFilename = filename.replaceAll(RegExp(r'[<>:"/\\|?*]'), '_');
  final file = File('${directory.path}\\$safeFilename');
  await file.writeAsBytes(bytes, flush: true);

  if (!autoPrint) {
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$path='${_escapePowerShell(file.path)}'; Start-Process -FilePath \$path",
    ], mode: ProcessStartMode.detached);
    return;
  }

  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "\$path='${_escapePowerShell(file.path)}'; "
        "\$printer=Get-CimInstance Win32_Printer | Where-Object Default | Select-Object -First 1; "
        "if (\$null -eq \$printer) { Start-Process -FilePath \$path; exit 2 }; "
        "try { Start-Process -FilePath \$path -Verb Print; exit 0 } "
        "catch { Start-Process -FilePath \$path; exit 3 }",
  ]);

  if (result.exitCode != 0 && result.exitCode != 2 && result.exitCode != 3) {
    await Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      "\$path='${_escapePowerShell(file.path)}'; Start-Process -FilePath \$path",
    ], mode: ProcessStartMode.detached);
  }
}

String _escapePowerShell(String value) => value.replaceAll("'", "''");

Future<void> printFiscalNfceSaleReceipt({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) async {
  if (!Platform.isWindows) {
    throw UnsupportedError(
      'Impressao fiscal disponivel no Windows e navegador.',
    );
  }

  final directory = await Directory.systemTemp.createTemp('lyncar-nfce-');
  final file = File(
    '${directory.path}\\nfce-${document.number ?? document.id}.txt',
  );
  await file.writeAsString(
    _buildFiscalNfceText(
      document: document,
      sale: sale,
      companyName: companyName,
      companyDocument: companyDocument,
      operatorName: operatorName,
    ),
    flush: true,
  );

  final result = await Process.run('powershell.exe', [
    '-NoProfile',
    '-NonInteractive',
    '-Command',
    "\$path='${_escapePowerShell(file.path)}'; "
        "\$printer=Get-CimInstance Win32_Printer | Where-Object Default | Select-Object -First 1; "
        "if (\$null -eq \$printer) { exit 2 }; "
        "try { Start-Process -FilePath \$path -Verb Print -WindowStyle Hidden; exit 0 } "
        "catch { exit 3 }",
  ]);

  if (result.exitCode != 0) {
    throw ProcessException(
      'powershell.exe',
      const [],
      'O Windows nao confirmou o envio da NFC-e para a impressora padrao.',
      result.exitCode,
    );
  }
}

String _buildFiscalNfceText({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) {
  const width = 42;
  final lines = <String>[];
  void line([String value = '']) => lines.add(_plain(value));
  void center(String value) {
    final text = _plain(value);
    if (text.length >= width) {
      line(text);
      return;
    }
    final left = ((width - text.length) / 2).floor();
    line('${_repeat(' ', left)}$text');
  }

  final isHomologation = document.environment.toLowerCase().contains('hom');
  center(companyName.toUpperCase());
  if ((companyDocument ?? '').trim().isNotEmpty) {
    center('CNPJ ${companyDocument!.trim()}');
  }
  line(_repeat('=', width));
  center('DANFE NFC-e');
  center('Documento Auxiliar da Nota Fiscal');
  center('de Consumidor Eletronica');
  if (isHomologation) {
    center('EMITIDA EM HOMOLOGACAO');
    center('SEM VALOR FISCAL');
  }
  line(_repeat('=', width));
  line('Venda: ${sale.number ?? sale.id}');
  line(
    'NFC-e: serie ${document.series ?? '-'} num. ${document.number ?? document.id}',
  );
  line('Data: ${_date(document.authorizedAt ?? sale.soldAt)}');
  line('Operador: ${operatorName ?? sale.sellerName ?? '-'}');
  line(_repeat('-', width));
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
  line(_pair('VALOR TOTAL', _money(sale.totalAmount), width));
  line(_repeat('-', width));
  line('PAGAMENTOS');
  for (final payment in sale.payments) {
    line(_pair(_paymentLabel(payment.method), _money(payment.amount), width));
  }
  if ((document.accessKey ?? '').trim().isNotEmpty) {
    line(_repeat('-', width));
    center('Consulte pela chave de acesso');
    for (final part in _wrap(document.accessKey!.trim(), width)) {
      line(part);
    }
  }
  if ((document.sefazProtocol ?? '').trim().isNotEmpty) {
    line('Protocolo: ${document.sefazProtocol!.trim()}');
  }
  if ((document.danfeUrl ?? '').trim().isNotEmpty) {
    line();
    line('Consulta:');
    for (final part in _wrap(document.danfeUrl!.trim(), width)) {
      line(part);
    }
  }
  line(_repeat('=', width));
  center('Obrigado pela preferencia.');
  line();
  line();
  line();
  return '${lines.join('\r\n')}\r\n';
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
  };
  return value.split('').map((char) => accents[char] ?? char).join();
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
      for (var index = 0; index < word.length; index += width) {
        lines.add(word.substring(index, (index + width).clamp(0, word.length)));
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
