// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:typed_data';

import '../models/fiscal.dart';
import '../models/sale.dart';

Future<void> printFiscalPdf({
  required String filename,
  required List<int> bytes,
  bool autoPrint = false,
}) async {
  final blob = html.Blob([Uint8List.fromList(bytes)], 'application/pdf');
  final url = html.Url.createObjectUrlFromBlob(blob);

  final overlay = html.DivElement()
    ..style.position = 'fixed'
    ..style.top = '0'
    ..style.right = '0'
    ..style.bottom = '0'
    ..style.left = '0'
    ..style.zIndex = '999999'
    ..style.background = 'rgba(15, 23, 42, .72)'
    ..style.display = 'flex'
    ..style.flexDirection = 'column'
    ..style.padding = '18px';

  final toolbar = html.DivElement()
    ..style.display = 'flex'
    ..style.alignItems = 'center'
    ..style.gap = '10px'
    ..style.padding = '12px'
    ..style.background = '#ffffff'
    ..style.borderRadius = '14px 14px 0 0'
    ..style.boxShadow = '0 12px 30px rgba(15, 23, 42, .18)';

  final title = html.DivElement()
    ..text = 'DANFE pronto para impressão'
    ..style.flex = '1'
    ..style.font = '700 16px Arial, sans-serif'
    ..style.color = '#0f172a';

  final frame = html.IFrameElement()
    ..src = url
    ..style.flex = '1'
    ..style.width = '100%'
    ..style.border = '0'
    ..style.background = '#ffffff'
    ..style.borderRadius = '0 0 14px 14px'
    ..style.boxShadow = '0 12px 30px rgba(15, 23, 42, .18)';

  var automaticPrintTriggered = false;

  void printFrame() {
    try {
      final window = frame.contentWindow;
      if (window != null) {
        final jsWindow = js.JsObject.fromBrowserObject(window);
        jsWindow.callMethod('focus');
        jsWindow.callMethod('print');
      }
    } catch (_) {
      html.window.alert(
        'Nao foi possivel acionar a impressao automatica. Use o icone de impressora do visualizador ou o botao Baixar PDF.',
      );
    }
  }

  void closeViewer() {
    overlay.remove();
    html.Url.revokeObjectUrl(url);
  }

  final printButton = _toolbarButton('Imprimir agora', '#0f766e')
    ..onClick.listen((_) => printFrame());
  final openButton = _toolbarButton('Abrir em nova aba', '#2563eb')
    ..onClick.listen((_) => html.window.open(url, '_blank'));
  final downloadButton = html.AnchorElement(href: url)
    ..text = 'Baixar PDF'
    ..download = filename
    ..style.display = 'inline-flex'
    ..style.alignItems = 'center'
    ..style.height = '36px'
    ..style.padding = '0 14px'
    ..style.borderRadius = '10px'
    ..style.background = '#475569'
    ..style.color = '#ffffff'
    ..style.font = '700 13px Arial, sans-serif'
    ..style.textDecoration = 'none';
  final closeButton = _toolbarButton('Fechar', '#991b1b')
    ..onClick.listen((_) => closeViewer());

  toolbar.append(title);
  toolbar.append(printButton);
  toolbar.append(openButton);
  toolbar.append(downloadButton);
  toolbar.append(closeButton);
  overlay.append(toolbar);
  overlay.append(frame);
  html.document.body?.append(overlay);

  if (autoPrint) {
    frame.onLoad.first.then((_) {
      if (automaticPrintTriggered) return;
      automaticPrintTriggered = true;
      Timer(const Duration(milliseconds: 350), printFrame);
    });
  }
}

html.ButtonElement _toolbarButton(String label, String color) {
  return html.ButtonElement()
    ..text = label
    ..style.height = '36px'
    ..style.padding = '0 14px'
    ..style.border = '0'
    ..style.borderRadius = '10px'
    ..style.background = color
    ..style.color = '#ffffff'
    ..style.font = '700 13px Arial, sans-serif'
    ..style.cursor = 'pointer';
}

Future<void> printFiscalNfceSaleReceipt({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) async {
  throw UnsupportedError('No navegador, imprima a NFC-e pelo DANFE/PDF.');
}
