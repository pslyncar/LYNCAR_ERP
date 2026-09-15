import '../../domain/models/operation_order.dart';
import '../../domain/models/terminal_session.dart';
import '../../domain/models/local_catalog.dart';
import '../../domain/models/sync_issue.dart';
import '../services/edge_api_service.dart';
import '../services/saved_login_store.dart';
import '../services/terminal_credentials_store.dart';

class OperationsRepository {
  OperationsRepository({
    required this.edgeApi,
    required this.credentials,
    SavedLoginStore? savedLogins,
  }) : savedLogins = savedLogins ?? SavedLoginStore();
  final EdgeApiService edgeApi;
  final TerminalCredentialsStore credentials;
  final SavedLoginStore savedLogins;
  Future<String?> savedToken() => credentials.readToken();
  Future<TerminalSession> session(String token) async =>
      TerminalSession.fromJson(await edgeApi.session(token));
  Future<({TerminalSession session, String token})> pair({
    String? adminKey,
    String? terminalKey,
    String? pairingCode,
  }) async {
    final payload = await edgeApi.pair(
      adminKey: adminKey,
      terminalKey: terminalKey,
      pairingCode: pairingCode,
    );
    final token = '${payload['local_token']}';
    await credentials.saveToken(token);
    return (session: await session(token), token: token);
  }

  Future<
    ({
      TerminalSession? session,
      String? token,
      List<Map<String, dynamic>> terminals,
    })
  >
  login({
    required String email,
    required String password,
    int? terminalId,
  }) async {
    final payload = await edgeApi.login(
      email: email,
      password: password,
      terminalId: terminalId,
    );
    if (payload['selection_required'] == true) {
      return (
        session: null,
        token: null,
        terminals: (payload['terminals'] as List<dynamic>? ?? const [])
            .whereType<Map<String, dynamic>>()
            .toList(growable: false),
      );
    }
    final token = '${payload['local_token']}';
    await credentials.saveToken(token);
    return (
      session: await session(token),
      token: token,
      terminals: const <Map<String, dynamic>>[],
    );
  }

  Future<List<OperationOrder>> orders(String token) async {
    final result = (await edgeApi.orders(
      token,
    )).map(OperationOrder.fromJson).toList();
    result.sort(
      (a, b) =>
          (a.createdAt ?? DateTime(0)).compareTo(b.createdAt ?? DateTime(0)),
    );
    return result;
  }

  Future<void> transition(String token, String orderId, String status) =>
      edgeApi.transition(token, orderId, status);
  Future<Map<String, dynamic>> checkout(
    String token,
    String orderId, {
    required String method,
    required double amountPaid,
    String? authorizationCode,
  }) => edgeApi.checkout(token, orderId, {
    'payment_method': method,
    'amount_paid': amountPaid,
    'authorization_code': authorizationCode,
  });
  Future<Map<String, dynamic>?> openCashSession(String token) =>
      edgeApi.openCashSession(token);
  Future<Map<String, dynamic>> openCash(
    String token, {
    required int operatorId,
    required String operatorName,
    required String operatorType,
    required String register,
    required double openingAmount,
  }) => edgeApi.openCash(
    token,
    operatorId: operatorId,
    operatorName: operatorName,
    operatorType: operatorType,
    register: register,
    openingAmount: openingAmount,
  );
  Future<Map<String, dynamic>> closeCash(
    String token, {
    required String code,
    required String pin,
    required double countedCashAmount,
    String? notes,
  }) => edgeApi.closeCash(
    token,
    code: code,
    pin: pin,
    countedCashAmount: countedCashAmount,
    notes: notes,
  );
  Future<LocalCatalog> catalog(String token) async =>
      LocalCatalog.fromJson(await edgeApi.catalog(token));
  Future<List<SyncIssue>> syncIssues(String token) async =>
      (await edgeApi.syncIssues(
        token,
      )).map(SyncIssue.fromJson).toList(growable: false);
  Future<Map<String, dynamic>> printers(String token) =>
      edgeApi.printers(token);
  Future<Map<String, dynamic>> savePrinterBinding(
    String token,
    Map<String, dynamic> payload,
  ) => edgeApi.savePrinterBinding(token, payload);
  Future<void> testPrinter(
    String token, {
    required String printerName,
    required String logicalName,
  }) async {
    await edgeApi.testPrinter(
      token,
      printerName: printerName,
      logicalName: logicalName,
    );
  }

  Future<OperationOrder> createStaffOrder(
    String token, {
    required String sourceChannel,
    required String table,
    required String command,
    required String customer,
    required List<StaffCartLine> lines,
  }) async => OperationOrder.fromJson(
    await edgeApi.createStaffOrder(token, {
      'source_channel': sourceChannel,
      'table_label': table.trim().isEmpty ? null : table.trim(),
      'command_label': command.trim().isEmpty ? null : command.trim(),
      'customer_name': customer.trim().isEmpty
          ? 'Consumidor no local'
          : customer.trim(),
      'items': lines.map((line) => line.toJson()).toList(growable: false),
    }),
  );
  Future<void> forgetTerminal() => credentials.clear();
}
