import '../models/client.dart';
import '../models/cash_closing.dart';
import '../models/equipment.dart';
import '../models/fiscal.dart';
import '../models/service_order.dart';
import '../models/sale.dart';

void openServiceOrderReceipt({
  required ServiceOrder order,
  required Client? client,
  required Equipment? equipment,
}) {
  throw UnsupportedError('Impressao pelo navegador disponivel apenas no Web.');
}

Future<void> openNonFiscalSaleReceipt({
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? operatorName,
  List<SaleInstallmentPayload> installments = const [],
  int? creditInstallmentCount,
}) async {
  // A impressão térmica nativa do app Windows será ligada ao driver local.
}

Future<void> printFiscalNfceSaleReceipt({
  required FiscalDocument document,
  required Sale sale,
  required String companyName,
  String? companyDocument,
  String? operatorName,
}) async {}

Future<void> printCashClosingReceipt({
  required CashClosing closing,
  required String companyName,
  String? companyDocument,
  String? cashRegisterNumber,
  String? fiscalName,
}) async {}

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
}) async {}

Future<bool> isReceiptPrinterConfigured() async => false;

Future<void> openCashDrawer({String pulseProfile = 'default'}) async {}
