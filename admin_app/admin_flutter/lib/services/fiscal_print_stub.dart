import 'file_download.dart';
import '../models/fiscal.dart';
import '../models/sale.dart';

Future<void> printFiscalPdf({
  required String filename,
  required List<int> bytes,
  bool autoPrint = false,
}) async {
  downloadBytesFile(
    filename: filename,
    bytes: bytes,
    mimeType: 'application/pdf',
  );
}

Future<void> printFiscalNfceSaleReceipt({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) async {
  throw UnsupportedError('Impressao fiscal NFC-e disponivel no Windows.');
}
