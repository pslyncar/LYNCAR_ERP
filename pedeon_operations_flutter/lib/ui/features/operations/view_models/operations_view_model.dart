import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../../data/repositories/operations_repository.dart';
import '../../../../domain/models/operation_order.dart';
import '../../../../domain/models/terminal_session.dart';
import '../../../../domain/models/local_catalog.dart';
import '../../../../domain/models/sync_issue.dart';
import '../../../../data/services/saved_login_store.dart';

enum OperationsPhase { starting, pairing, ready, failed }

class OperationsViewModel extends ChangeNotifier {
  OperationsViewModel(this._repository);
  final OperationsRepository _repository;
  OperationsPhase phase = OperationsPhase.starting;
  TerminalSession? session;
  List<OperationOrder> orders = const [];
  LocalCatalog? catalog;
  final List<StaffCartLine> cart = [];
  List<SyncIssue> syncIssues = const [];
  Map<String, dynamic>? cashSession;
  bool submittingOrder = false;
  String? error;
  List<Map<String, dynamic>> terminalChoices = const [];
  List<SavedLogin> savedLogins = const [];
  String? _token;
  Timer? _timer;

  Future<void> initialize() async {
    try {
      savedLogins = await _repository.savedLogins.read();
      final token = await _repository.savedToken();
      if (token == null || token.isEmpty) {
        phase = OperationsPhase.pairing;
      } else {
        _token = token;
        session = await _repository.session(token);
        phase = OperationsPhase.ready;
        await refresh();
        await loadCatalog();
        _startRefresh();
      }
    } catch (exception) {
      error = _friendlyError(exception);
      phase = OperationsPhase.pairing;
    }
    notifyListeners();
  }

  Future<void> pair(String adminKey, String terminalKey) async {
    phase = OperationsPhase.starting;
    error = null;
    notifyListeners();
    try {
      final paired = await _repository.pair(
        adminKey: adminKey,
        terminalKey: terminalKey,
      );
      _token = paired.token;
      session = paired.session;
      phase = OperationsPhase.ready;
      await refresh();
      await loadCatalog();
      _startRefresh();
    } catch (exception) {
      error = _friendlyError(exception);
      phase = OperationsPhase.pairing;
    }
    notifyListeners();
  }

  Future<void> pairWithCode(String pairingCode) async {
    phase = OperationsPhase.starting;
    error = null;
    notifyListeners();
    try {
      final paired = await _repository.pair(pairingCode: pairingCode);
      _token = paired.token;
      session = paired.session;
      phase = OperationsPhase.ready;
      await refresh();
      await loadCatalog();
      _startRefresh();
    } catch (exception) {
      error = _friendlyError(exception);
      phase = OperationsPhase.pairing;
    }
    notifyListeners();
  }

  Future<void> login(String email, String password, {int? terminalId}) async {
    phase = OperationsPhase.starting;
    error = null;
    notifyListeners();
    try {
      final result = await _repository.login(
        email: email,
        password: password,
        terminalId: terminalId,
      );
      if (result.token == null || result.session == null) {
        terminalChoices = result.terminals;
        phase = OperationsPhase.pairing;
        notifyListeners();
        return;
      }
      terminalChoices = const [];
      _token = result.token;
      session = result.session;
      phase = OperationsPhase.ready;
      await refresh();
      await loadCatalog();
      _startRefresh();
    } catch (exception) {
      error = '$exception';
      phase = OperationsPhase.pairing;
    }
    notifyListeners();
  }

  Future<void> rememberLogin({
    required String email,
    required String password,
    required bool remember,
  }) async {
    if (email.isEmpty) return;
    if (remember) {
      await _repository.savedLogins.save(
        SavedLogin(email: email, password: password),
      );
    } else {
      await _repository.savedLogins.remove(email);
    }
    savedLogins = await _repository.savedLogins.read();
    notifyListeners();
  }

  Future<void> removeSavedLogin(String email) async {
    await _repository.savedLogins.remove(email);
    savedLogins = await _repository.savedLogins.read();
    notifyListeners();
  }

  Future<void> refresh() async {
    final token = _token;
    if (token == null) return;
    try {
      final refreshedCatalog = await _repository.catalog(token);
      final refreshedOrders = await _repository.orders(token);
      final refreshedSyncIssues = await _repository.syncIssues(token);
      catalog = refreshedCatalog;
      orders = refreshedOrders;
      syncIssues = refreshedSyncIssues;
      if (session?.capabilities.contains('checkout') == true) {
        cashSession = await _repository.openCashSession(token);
      }
      error = null;
    } catch (exception) {
      error = '$exception';
    }
    notifyListeners();
  }

  Future<void> loadCatalog() async {
    final token = _token;
    if (token == null) return;
    try {
      catalog = await _repository.catalog(token);
      error = null;
    } catch (exception) {
      error = '$exception';
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> loadPrinters() async {
    final token = _token;
    if (token == null) return null;
    try {
      return await _repository.printers(token);
    } catch (exception) {
      error = '$exception';
      notifyListeners();
      return null;
    }
  }

  Future<bool> savePrinterBinding({
    required String logicalKey,
    required String logicalName,
    required String printerName,
    required int copies,
    required bool autoPrint,
  }) async {
    final token = _token;
    if (token == null) return false;
    try {
      await _repository.savePrinterBinding(token, {
        'logical_key': logicalKey,
        'logical_name': logicalName,
        'printer_name': printerName,
        'copies': copies,
        'auto_print': autoPrint,
      });
      error = null;
      notifyListeners();
      return true;
    } catch (exception) {
      error = '$exception';
      notifyListeners();
      return false;
    }
  }

  Future<bool> testPrinter(String printerName, String logicalName) async {
    final token = _token;
    if (token == null) return false;
    try {
      await _repository.testPrinter(
        token,
        printerName: printerName,
        logicalName: logicalName,
      );
      return true;
    } catch (exception) {
      error = '$exception';
      notifyListeners();
      return false;
    }
  }

  void addToCart(StaffCartLine line) {
    cart.add(line);
    notifyListeners();
  }

  void removeFromCart(int index) {
    cart.removeAt(index);
    notifyListeners();
  }

  void changeCartQuantity(int index, int delta) {
    if (index < 0 || index >= cart.length || delta == 0) return;
    final current = cart[index];
    final quantity = current.quantity + delta;
    if (quantity <= 0) {
      cart.removeAt(index);
    } else {
      cart[index] = StaffCartLine(
        product: current.product,
        quantity: quantity,
        optionIds: current.optionIds,
        notes: current.notes,
      );
    }
    notifyListeners();
  }

  double get cartTotal => cart.fold(0, (sum, line) => sum + line.total);

  Future<bool> createStaffOrder({
    String sourceChannel = 'onsite_waiter',
    required String table,
    required String command,
    required String customer,
  }) async {
    return await createStaffOrderAndReturn(
          sourceChannel: sourceChannel,
          table: table,
          command: command,
          customer: customer,
        ) !=
        null;
  }

  Future<OperationOrder?> createStaffOrderAndReturn({
    String sourceChannel = 'onsite_waiter',
    required String table,
    required String command,
    required String customer,
  }) async {
    final token = _token;
    if (token == null || cart.isEmpty || submittingOrder) return null;
    submittingOrder = true;
    error = null;
    notifyListeners();
    try {
      final order = await _repository.createStaffOrder(
        token,
        sourceChannel: sourceChannel,
        table: table,
        command: command,
        customer: customer,
        lines: List.of(cart),
      );
      orders = [...orders, order];
      cart.clear();
      return order;
    } catch (exception) {
      error = '$exception';
      return null;
    } finally {
      submittingOrder = false;
      notifyListeners();
    }
  }

  Future<void> transition(OperationOrder order, String status) async {
    final token = _token;
    if (token == null) return;
    try {
      await _repository.transition(token, order.publicId, status);
      orders = [
        for (final current in orders)
          if (current.publicId == order.publicId)
            OperationOrder(
              publicId: current.publicId,
              number: current.number,
              status: status,
              paymentStatus: current.paymentStatus,
              source: current.source,
              fulfillment: current.fulfillment,
              customerName: current.customerName,
              createdAt: current.createdAt,
              notes: current.notes,
              items: current.items,
              total: current.total,
              tableLabel: current.tableLabel,
              commandLabel: current.commandLabel,
            )
          else
            current,
      ];
      error = null;
    } catch (exception) {
      error = '$exception';
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>?> checkout(
    OperationOrder order, {
    required String method,
    required double amountPaid,
    String? authorizationCode,
  }) async {
    final token = _token;
    if (token == null) return null;
    try {
      final result = await _repository.checkout(
        token,
        order.publicId,
        method: method,
        amountPaid: amountPaid,
        authorizationCode: authorizationCode,
      );
      orders = [
        for (final current in orders)
          if (current.publicId != order.publicId) current,
      ];
      error = null;
      notifyListeners();
      return result;
    } catch (exception) {
      error = '$exception';
      notifyListeners();
      return null;
    }
  }

  Future<bool> checkoutAccount(
    List<OperationOrder> accountOrders, {
    required String method,
    required double amountPaid,
    String? authorizationCode,
  }) async {
    final payable = accountOrders
        .where((order) => order.paymentStatus != 'confirmed')
        .toList(growable: false);
    if (payable.isEmpty) {
      error = 'Esta conta já foi recebida.';
      notifyListeners();
      return false;
    }
    final total = payable.fold<double>(0, (sum, order) => sum + order.total);
    if (amountPaid < total || (method != 'dinheiro' && amountPaid != total)) {
      error = method == 'dinheiro'
          ? 'O valor recebido é menor que o total da conta.'
          : 'No cartão ou Pix, o valor deve ser igual ao total da conta.';
      notifyListeners();
      return false;
    }
    for (var index = 0; index < payable.length; index++) {
      final order = payable[index];
      final isLast = index == payable.length - 1;
      final paidForOrder = method == 'dinheiro' && isLast
          ? order.total + (amountPaid - total)
          : order.total;
      final result = await checkout(
        order,
        method: method,
        amountPaid: paidForOrder,
        authorizationCode: authorizationCode,
      );
      if (result == null) return false;
    }
    return true;
  }

  Future<bool> openCash({
    required String register,
    required double openingAmount,
  }) async {
    final token = _token;
    if (token == null) return false;
    try {
      cashSession = await _repository.openCash(
        token,
        operatorId: session?.userId ?? 0,
        operatorName: session?.userName ?? 'Usuário PedeOn',
        operatorType: session?.userType ?? 'erp_owner',
        register: register,
        openingAmount: openingAmount,
      );
      error = null;
      notifyListeners();
      return true;
    } catch (exception) {
      error = '$exception';
      notifyListeners();
      return false;
    }
  }

  Future<bool> closeCash({
    required String code,
    required String pin,
    required double countedCashAmount,
    String? notes,
  }) async {
    final token = _token;
    if (token == null || cashSession == null) return false;
    try {
      await _repository.closeCash(
        token,
        code: code,
        pin: pin,
        countedCashAmount: countedCashAmount,
        notes: notes,
      );
      cashSession = null;
      error = null;
      notifyListeners();
      return true;
    } catch (exception) {
      error = '$exception';
      notifyListeners();
      return false;
    }
  }

  Future<void> unpair() async {
    await logout();
  }

  Future<void> logout() async {
    _timer?.cancel();
    await _repository.forgetTerminal();
    _token = null;
    session = null;
    orders = const [];
    catalog = null;
    syncIssues = const [];
    cashSession = null;
    error = null;
    phase = OperationsPhase.pairing;
    notifyListeners();
  }

  void _startRefresh() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 3), (_) => refresh());
  }

  String _friendlyError(Object exception) {
    final message = '$exception';
    if (message.contains('127.0.0.1:8765') ||
        message.contains('Connection refused') ||
        message.contains('conexão de rede')) {
      return 'Lyncar Edge não está iniciado neste computador. Configure o Edge e tente novamente.';
    }
    return message;
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
