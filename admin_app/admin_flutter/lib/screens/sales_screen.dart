import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/pdv_operator.dart';
import '../models/pdv_terminal.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/app_session_storage.dart';
import '../services/receipt_print.dart';
import '../utils/input_formatters.dart';
import '../utils/sale_installments.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _paymentMethods = {
  'dinheiro': 'Dinheiro',
  'pix': 'Pix',
  'debito': 'Débito',
  'credito': 'Crédito',
  'boleto': 'Boleto',
  'transferencia': 'Transferência',
  'crediario': 'Crediário',
  'outro': 'Outro',
};

const _pdvScreenAppVersion = String.fromEnvironment(
  'PDV_APP_VERSION',
  defaultValue: '1.0.14',
);

class SalesScreen extends StatefulWidget {
  const SalesScreen({
    super.key,
    required this.session,
    this.pdvMode = false,
    this.fullscreen = false,
    this.onPdvCashOpenChanged,
    this.onPdvFullscreenChanged,
  });

  final Session session;
  final bool pdvMode;
  final bool fullscreen;
  final ValueChanged<bool>? onPdvCashOpenChanged;
  final ValueChanged<bool>? onPdvFullscreenChanged;

  @override
  State<SalesScreen> createState() => _SalesScreenState();
}

class _SalesScreenState extends State<SalesScreen> {
  static const _pdvCashSessionKey = 'papezzosync.pdv.cashSession';
  static const _pdvCashRegisterNumberKey = 'lyncar.pdv.cashRegisterNumber';
  static const _pdvTerminalKey = 'lyncar.pdv.terminalKey';

  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _storage = AppSessionStorage();
  final _barcode = TextEditingController();
  final _manualSearch = TextEditingController();
  final _discount = TextEditingController(text: '0,00');
  final _paymentAmount = TextEditingController(text: '0,00');
  final _notes = TextEditingController();
  final _openingCash = TextEditingController(text: '0,00');
  final _operatorCode = TextEditingController();
  final _operatorPin = TextEditingController();
  final _withdrawAmount = TextEditingController(text: '0,00');
  final _withdrawReason = TextEditingController();
  final _salesSearch = TextEditingController();
  final _sellerCode = TextEditingController();
  final _barcodeFocus = FocusNode();
  List<Client> _clients = [];
  List<Product> _products = [];
  List<Sale> _sales = [];
  List<PdvOperator> _operators = [];
  List<SaleSeller> _sellers = [];
  final List<Sale> _pdvSessionSales = [];
  final List<_CashMovement> _cashMovements = [];
  final List<_CartItem> _cart = [];
  final Map<String, double> _persistedPaymentTotals = {};
  int? _clientId;
  int? _sellerUserId;
  String? _operatorName;
  String? _cashRegisterNumber;
  String? _terminalKey;
  String _paymentMethod = 'dinheiro';
  int _installmentCount = 1;
  DateTime _firstDueDate = DateTime.now();
  String _salesStatusFilter = 'todos';
  String _salesSourceFilter = 'todos';
  String _salesPeriodFilter = 'todos';
  int _selectedSalesTab = 1;
  bool _cashOpen = false;
  DateTime? _cashOpenedAt;
  double _cashOpeningAmount = 0;
  int _persistedSaleCount = 0;
  double _persistedSessionTotal = 0;
  double _maxDiscountPercent = 100;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restorePdvLocalState();
    _load();
  }

  @override
  void dispose() {
    _barcode.dispose();
    _manualSearch.dispose();
    _discount.dispose();
    _paymentAmount.dispose();
    _notes.dispose();
    _openingCash.dispose();
    _operatorCode.dispose();
    _operatorPin.dispose();
    _withdrawAmount.dispose();
    _withdrawReason.dispose();
    _salesSearch.dispose();
    _sellerCode.dispose();
    _barcodeFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final clients = await _api.listClients(widget.session.token);
      final products = await _api.listProducts(
        widget.session.token,
        active: true,
      );
      final sales = await _api.listSales(widget.session.token);
      final operators = await _api.listPdvOperators(widget.session.token);
      final sellers = await _api.listSaleSellers(widget.session.token);
      final settings = await _api.getSalesSettings(widget.session.token);
      setState(() {
        _clients = clients;
        _products = products;
        _sales = sales;
        _operators = operators;
        _sellers = sellers;
        _maxDiscountPercent = settings.maxDiscountPercent
            .clamp(0, 100)
            .toDouble();
        _sellerUserId = _sellerUserId == null
            ? null
            : _sellers.any((seller) => seller.id == _sellerUserId)
            ? _sellerUserId
            : null;
        final selectedSeller = _sellerById(_sellerUserId);
        if (selectedSeller == null ||
            (selectedSeller.sellerCode ?? '').trim().isEmpty) {
          _sellerUserId = null;
        }
        _syncSellerCode();
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar vendas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _restorePdvLocalState() async {
    await _restoreOpenCashSession();
    // SalesScreen roda no ERP web. Terminal fixo pertence ao PDV Windows.
  }

  // ignore: unused_element
  Future<void> _restoreTerminalIdentification() async {
    if (!widget.pdvMode) return;
    final savedNumber = await _storage.read(_pdvCashRegisterNumberKey);
    var savedKey = await _storage.read(_pdvTerminalKey);
    savedKey = savedKey?.trim();
    if (savedKey == null || savedKey.isEmpty) {
      savedKey = _generateTerminalKey();
      await _storage.write(_pdvTerminalKey, savedKey);
    }
    if (!mounted) return;
    setState(() {
      _cashRegisterNumber = _normalizeCashRegisterNumber(savedNumber);
      _terminalKey = savedKey;
    });
    if (_cashRegisterNumber != null) {
      _registerTerminalSilently();
    }
  }

  // ignore: unused_element
  Future<void> _ensureCashRegisterNumber() async {
    if (!widget.pdvMode || _cashRegisterNumber != null) return;
    final controller = TextEditingController();
    try {
      while (mounted && _cashRegisterNumber == null) {
        if (!mounted) return;
        final value = await showDialog<String>(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            title: const Text('Identificar caixa'),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Informe somente o número deste caixa. Exemplo: 1, 2 ou 3.',
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Número do caixa',
                      prefixIcon: Icon(Icons.point_of_sale_outlined),
                      border: OutlineInputBorder(),
                    ),
                    onSubmitted: (_) =>
                        Navigator.of(context).pop(controller.text),
                  ),
                ],
              ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(controller.text),
                icon: const Icon(Icons.check),
                label: const Text('Salvar caixa'),
              ),
            ],
          ),
        );
        final normalized = _normalizeCashRegisterNumber(value);
        if (normalized == null) continue;
        _terminalKey ??= _generateTerminalKey();
        await _storage.write(_pdvCashRegisterNumberKey, normalized);
        await _storage.write(_pdvTerminalKey, _terminalKey!);
        if (!mounted) return;
        setState(() => _cashRegisterNumber = normalized);
        await _registerTerminalSilently();
      }
    } finally {
      controller.dispose();
    }
  }

  Future<void> _registerTerminalSilently() async {
    final cashNumber = _cashRegisterNumber;
    if (!widget.pdvMode || cashNumber == null) return;
    final terminalKey = _terminalKey ?? _generateTerminalKey();
    _terminalKey = terminalKey;
    try {
      final terminal = await _api.registerPdvTerminal(
        widget.session.token,
        PdvTerminalRegisterPayload(
          cashRegisterNumber: cashNumber,
          terminalKey: terminalKey,
          appVersion: _pdvScreenAppVersion,
          deviceLabel: widget.session.companyCode,
        ),
      );
      if (terminal.cashRegisterNumber != cashNumber) {
        await _storage.write(
          _pdvCashRegisterNumberKey,
          terminal.cashRegisterNumber,
        );
        if (mounted) {
          setState(() => _cashRegisterNumber = terminal.cashRegisterNumber);
        } else {
          _cashRegisterNumber = terminal.cashRegisterNumber;
        }
      }
    } catch (_) {
      // O terminal continua funcionando offline; o cadastro sera sincronizado
      // na proxima abertura/conexao.
    }
  }

  String _generateTerminalKey() {
    final seed =
        '${widget.session.companyCode}-${widget.session.userId}-${DateTime.now().millisecondsSinceEpoch}';
    return 'pdv-${seed.hashCode.abs()}-${DateTime.now().microsecondsSinceEpoch}';
  }

  String? _normalizeCashRegisterNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return digits.padLeft(2, '0');
  }

  String get _cashRegisterLabel => _cashRegisterNumber ?? '--';

  Future<void> _restoreOpenCashSession() async {
    if (!widget.pdvMode) return;
    final raw = await _storage.read(_pdvCashSessionKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final payments = (data['payment_totals'] as Map<String, dynamic>? ?? {})
          .map((key, value) => MapEntry(key, (value as num).toDouble()));
      final movements = ((data['cash_movements'] as List<dynamic>?) ?? [])
          .map((item) => item as Map<String, dynamic>)
          .map(
            (item) => _CashMovement(
              type: item['type'] as String,
              amount: (item['amount'] as num).toDouble(),
              reason: item['reason'] as String? ?? '',
              createdAt: DateTime.parse(item['created_at'] as String),
            ),
          )
          .toList();
      setState(() {
        _cashOpen = data['cash_open'] as bool? ?? false;
        _cashOpenedAt = DateTime.tryParse(data['opened_at'] as String? ?? '');
        _cashOpeningAmount = (data['opening_amount'] as num?)?.toDouble() ?? 0;
        _operatorName = data['operator_name'] as String?;
        _cashRegisterNumber =
            _normalizeCashRegisterNumber(
              data['cash_register_number'] as String?,
            ) ??
            _cashRegisterNumber;
        _persistedSaleCount = data['sale_count'] as int? ?? 0;
        _persistedSessionTotal =
            (data['session_total'] as num?)?.toDouble() ?? 0;
        _persistedPaymentTotals
          ..clear()
          ..addAll(payments);
        _cashMovements
          ..clear()
          ..addAll(movements);
      });
      widget.onPdvCashOpenChanged?.call(_cashOpen);
    } catch (_) {
      await _storage.remove(_pdvCashSessionKey);
    }
  }

  Future<void> _persistOpenCashSession() async {
    if (!widget.pdvMode || !_cashOpen) return;
    await _storage.write(
      _pdvCashSessionKey,
      jsonEncode({
        'cash_open': _cashOpen,
        'cash_register_number': _cashRegisterNumber,
        'opened_at': _cashOpenedAt?.toIso8601String(),
        'opening_amount': _cashOpeningAmount,
        'operator_name': _operatorName,
        'sale_count': _persistedSaleCount,
        'session_total': _persistedSessionTotal,
        'payment_totals': _persistedPaymentTotals,
        'cash_movements': [
          for (final movement in _cashMovements)
            {
              'type': movement.type,
              'amount': movement.amount,
              'reason': movement.reason,
              'created_at': movement.createdAt.toIso8601String(),
            },
        ],
      }),
    );
  }

  Future<void> _clearOpenCashSession() async {
    await _storage.remove(_pdvCashSessionKey);
  }

  Future<void> _scanCode() async {
    final code = _barcode.text.trim();
    if (code.isEmpty) return;
    try {
      final product = await _api.lookupProductByCode(
        widget.session.token,
        code,
      );
      _addProduct(product);
      _barcode.clear();
      _barcodeFocus.requestFocus();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  void _addProduct(Product product) {
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    setState(() {
      _error = null;
      if (index >= 0) {
        _cart[index].quantity += 1;
      } else {
        _cart.add(_CartItem(product: product));
      }
      _syncPaymentWithTotal();
    });
  }

  void _removeItem(_CartItem item) {
    setState(() {
      _cart.remove(item);
      _syncPaymentWithTotal();
    });
  }

  void _syncPaymentWithTotal() {
    _paymentAmount.text = formatBrazilianMoneyInput(_totalCents / 100);
  }

  void _syncSellerCode() {
    final seller = _sellerById(_sellerUserId);
    _sellerCode.text = seller?.sellerCode ?? '';
  }

  Future<List<SaleInstallmentPayload>?> _confirmInstallments() async {
    final installments = buildSaleInstallments(
      totalCents: _paidCents,
      count: _installmentCount,
      firstDueDate: _firstDueDate,
    );
    final controllers = [
      for (final installment in installments)
        TextEditingController(
          text: formatBrazilianMoneyInput(installment.amountCents / 100),
        ),
    ];
    try {
      return await showDialog<List<SaleInstallmentPayload>>(
        context: context,
        builder: (context) {
          String? error;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              int currentSum() => controllers.fold(
                0,
                (sum, controller) =>
                    sum + _moneyCents(parseBrazilianNumber(controller.text)),
              );

              final difference = currentSum() - _paidCents;
              Future<void> pickDate(int index) async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: installments[index].dueDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2100),
                  locale: const Locale('pt', 'BR'),
                );
                if (picked == null) return;
                setDialogState(() {
                  installments[index].dueDate = picked;
                });
              }

              return AlertDialog(
                title: Text(
                  'Confirmar parcelas de ${_paymentMethods[_paymentMethod]}',
                ),
                content: SizedBox(
                  width: 720,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (
                          var index = 0;
                          index < installments.length;
                          index++
                        )
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final narrow = constraints.maxWidth < 560;
                                final dueButton = OutlinedButton.icon(
                                  onPressed: () => pickDate(index),
                                  icon: const Icon(Icons.event_outlined),
                                  label: Text(
                                    formatBrazilianDate(
                                      installments[index].dueDate,
                                    ),
                                  ),
                                );
                                final amountField = TextField(
                                  controller: controllers[index],
                                  keyboardType: TextInputType.text,
                                  inputFormatters: const [
                                    BrazilianMoneyInputFormatter(),
                                  ],
                                  onChanged: (_) =>
                                      setDialogState(() => error = null),
                                  decoration: InputDecoration(
                                    labelText:
                                        'Valor ${installments[index].number}/${installments.length}',
                                    border: const OutlineInputBorder(),
                                  ),
                                );
                                if (narrow) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      dueButton,
                                      const SizedBox(height: 8),
                                      amountField,
                                    ],
                                  );
                                }
                                return Row(
                                  children: [
                                    SizedBox(width: 190, child: dueButton),
                                    const SizedBox(width: 12),
                                    Expanded(child: amountField),
                                  ],
                                );
                              },
                            ),
                          ),
                        const Divider(height: 24),
                        _SalePreviewLine(
                          'Total da venda',
                          _money(_paidCents / 100),
                        ),
                        _SalePreviewLine(
                          'Total das parcelas',
                          _money(currentSum() / 100),
                        ),
                        if (difference.abs() > 1)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              'A soma precisa fechar em ${_money(_paidCents / 100)}.',
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        if (error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              error!,
                              style: const TextStyle(color: Color(0xFFB91C1C)),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: () {
                      final sum = currentSum();
                      if ((sum - _paidCents).abs() > 1) {
                        setDialogState(() {
                          error =
                              'Ajuste os valores das parcelas antes de confirmar.';
                        });
                        return;
                      }
                      Navigator.of(context).pop([
                        for (
                          var index = 0;
                          index < installments.length;
                          index++
                        )
                          SaleInstallmentPayload(
                            number: installments[index].number,
                            dueDate: installments[index].dueDate,
                            amount:
                                _moneyCents(
                                  parseBrazilianNumber(controllers[index].text),
                                ) /
                                100,
                          ),
                      ]);
                    },
                    icon: const Icon(Icons.check_outlined),
                    label: const Text('Confirmar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      for (final controller in controllers) {
        controller.dispose();
      }
    }
  }

  Future<void> _showRequiredInfoDialog(String message) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Atenção'),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  SaleSeller? _sellerById(int? id) {
    if (id == null) return null;
    for (final seller in _sellers) {
      if (seller.id == id) return seller;
    }
    return null;
  }

  void _selectSellerByCode(String value) {
    final code = value.trim().toLowerCase();
    if (code.isEmpty) return;
    final matches = _sellers.where((seller) {
      final sellerCode = (seller.sellerCode ?? '').trim().toLowerCase();
      return sellerCode.isNotEmpty && sellerCode == code;
    }).toList();
    if (matches.isEmpty) {
      setState(
        () => _error = 'Vendedor com codigo ${value.trim()} nao encontrado.',
      );
      return;
    }
    setState(() {
      _sellerUserId = matches.first.id;
      _error = null;
    });
    _syncSellerCode();
  }

  Future<void> _openSellerPicker() async {
    final codedSellers = _sellers
        .where((seller) => (seller.sellerCode ?? '').trim().isNotEmpty)
        .toList();
    final selected = await showDialog<SaleSeller>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Selecionar vendedor'),
        children: [
          if (codedSellers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(18),
              child: Text('Nenhum vendedor com codigo cadastrado.'),
            )
          else
            for (final seller in codedSellers)
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop(seller),
                child: Text('${seller.sellerCode} - ${seller.name}'),
              ),
        ],
      ),
    );
    if (selected == null) return;
    setState(() {
      _sellerUserId = selected.id;
      _error = null;
    });
    _syncSellerCode();
  }

  Future<void> _openProductPicker() async {
    final search = TextEditingController(text: _manualSearch.text);
    try {
      final selected = await showDialog<Product>(
        context: context,
        builder: (context) {
          var term = search.text.trim().toLowerCase();
          List<Product> filtered() {
            if (term.isEmpty) return _products.take(80).toList();
            return _products
                .where(
                  (product) =>
                      product.name.toLowerCase().contains(term) ||
                      (product.internalCode ?? '').toLowerCase().contains(
                        term,
                      ) ||
                      (product.barcode ?? '').toLowerCase().contains(term),
                )
                .take(80)
                .toList();
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              final products = filtered();
              return AlertDialog(
                title: const Text('Pesquisar produto'),
                content: SizedBox(
                  width: 820,
                  height: 560,
                  child: Column(
                    children: [
                      TextField(
                        controller: search,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) => setDialogState(
                          () => term = value.trim().toLowerCase(),
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Codigo, codigo de barras ou descricao',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: products.isEmpty
                            ? const Center(
                                child: Text('Nenhum produto encontrado.'),
                              )
                            : ListView.separated(
                                itemCount: products.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final product = products[index];
                                  return ListTile(
                                    title: Text(product.name),
                                    subtitle: Text(
                                      'Codigo ${product.internalCode ?? '-'} | Barras ${product.barcode ?? '-'} | Estoque ${formatBrazilianDecimal(product.stockQuantity)} ${product.unit}',
                                    ),
                                    trailing: FilledButton.icon(
                                      onPressed: () =>
                                          Navigator.of(context).pop(product),
                                      icon: const Icon(Icons.add),
                                      label: const Text('Adicionar'),
                                    ),
                                    onTap: () =>
                                        Navigator.of(context).pop(product),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Fechar'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (selected == null) return;
      _manualSearch.text = search.text;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _addProduct(selected);
        _barcodeFocus.requestFocus();
      });
    } finally {
      WidgetsBinding.instance.addPostFrameCallback((_) => search.dispose());
    }
  }

  int get _subtotalCents => _cart.fold(
    0,
    (sum, item) => sum + _moneyCents(item.quantity * item.unitPrice),
  );
  int get _discountCents => _moneyCents(parseBrazilianNumber(_discount.text));
  bool get _canOverrideDiscount =>
      widget.session.can('sales:discount:override');
  int get _maxDiscountCents => widget.pdvMode || _canOverrideDiscount
      ? _subtotalCents
      : _moneyCents((_subtotalCents / 100) * (_maxDiscountPercent / 100));
  int get _totalCents => _nonNegativeCents(_subtotalCents - _discountCents);
  int get _paidCents => _moneyCents(parseBrazilianNumber(_paymentAmount.text));
  bool get _usesFinancialPayment =>
      _paymentMethod == 'boleto' || _paymentMethod == 'crediario';
  bool get _usesCreditInstallments => _paymentMethod == 'credito';
  bool get _paymentCoversTotal => _paidCents + 1 >= _totalCents;
  double get _withdrawTotal => _cashMovements
      .where((movement) => movement.type == 'sangria')
      .fold(0, (sum, movement) => sum + movement.amount);
  double get _cashSalesTotal => _paymentTotal('dinheiro');
  double get _expectedCashTotal =>
      (_cashSalesTotal - _withdrawTotal).clamp(0, double.infinity).toDouble();
  double get _pdvSessionTotal => _persistedSessionTotal;

  double _paymentTotal(String method) {
    return _persistedPaymentTotals[method] ?? 0;
  }

  Future<void> _openCashDrawer() async {
    final amount = parseBrazilianNumber(_openingCash.text);
    if (_operatorCode.text.trim().isEmpty || _operatorPin.text.isEmpty) {
      setState(() => _error = 'Informe código e senha do operador.');
      return;
    }
    setState(() => _saving = true);
    try {
      final authorization = await _api.authorizePdvAction(
        widget.session.token,
        code: _operatorCode.text,
        pin: _operatorPin.text,
        action: 'open_cash',
      );
      setState(() {
        _cashOpen = true;
        _cashOpenedAt = DateTime.now();
        _cashOpeningAmount = amount;
        _operatorName = authorization.operatorName;
        _cashMovements.clear();
        _pdvSessionSales.clear();
        _persistedPaymentTotals.clear();
        _persistedSaleCount = 0;
        _persistedSessionTotal = 0;
        _error = null;
        _paymentMethod = 'dinheiro';
        _paymentAmount.text = '0,00';
        _operatorPin.clear();
      });
      await _persistOpenCashSession();
      widget.onPdvCashOpenChanged?.call(true);
      _barcodeFocus.requestFocus();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _showWithdrawDialog() async {
    final authorized = await _requestFiscalAuthorization(
      action: 'withdrawal',
      title: 'Autorizar sangria',
    );
    if (!authorized) return;
    if (!mounted) return;
    _withdrawAmount.text = '0,00';
    _withdrawReason.clear();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Registrar sangria'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _withdrawAmount,
              autofocus: true,
              keyboardType: TextInputType.text,
              inputFormatters: const [BrazilianMoneyInputFormatter()],
              decoration: const InputDecoration(
                labelText: 'Valor retirado',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _withdrawReason,
              minLines: 2,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Motivo / observacao',
                hintText: 'Ex.: retirada para cofre',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.south_west),
            label: const Text('Registrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final amount = parseBrazilianNumber(_withdrawAmount.text);
    if (amount <= 0) {
      setState(() => _error = 'Informe um valor maior que zero para sangria.');
      return;
    }
    setState(() {
      _cashMovements.insert(
        0,
        _CashMovement(
          type: 'sangria',
          amount: amount,
          reason: _withdrawReason.text.trim(),
          createdAt: DateTime.now(),
        ),
      );
      _error = null;
    });
    await _persistOpenCashSession();
  }

  Future<void> _showCloseCashDialog() async {
    final countedCash = TextEditingController(
      text: formatBrazilianMoneyInput(_expectedCashTotal),
    );
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final difference =
                  parseBrazilianNumber(countedCash.text) - _expectedCashTotal;
              return AlertDialog(
                title: const Text('Fechamento do caixa'),
                content: SizedBox(
                  width: 520,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CloseCashLine('Fundo inicial', _cashOpeningAmount),
                      _CloseCashLine(
                        'Fundo retirado antes da contagem',
                        -_cashOpeningAmount,
                      ),
                      _CloseCashLine('Vendas em dinheiro', _cashSalesTotal),
                      _CloseCashLine('Sangrias', -_withdrawTotal),
                      const Divider(height: 24),
                      _CloseCashLine(
                        'Esperado após retirar o fundo',
                        _expectedCashTotal,
                        strong: true,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: countedCash,
                        keyboardType: TextInputType.text,
                        inputFormatters: const [BrazilianMoneyInputFormatter()],
                        onChanged: (_) => setDialogState(() {}),
                        decoration: const InputDecoration(
                          labelText: 'Dinheiro contado na gaveta',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _CloseCashLine('Diferenca', difference, strong: true),
                      const SizedBox(height: 12),
                      const Text(
                        'Fiscal NFC-e/NF-e: área preparada. A emissão real vai usar Certificado Digital A1 da empresa, XML assinado e autorização SEFAZ.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Voltar'),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.lock_outline),
                    label: const Text('Fechar caixa'),
                  ),
                ],
              );
            },
          );
        },
      );
      if (confirmed != true) return;
    } finally {
      countedCash.dispose();
    }
    setState(() {
      _cashOpen = false;
      _cashOpenedAt = null;
      _cashOpeningAmount = 0;
      _operatorName = null;
      _cashMovements.clear();
      _pdvSessionSales.clear();
      _persistedPaymentTotals.clear();
      _persistedSaleCount = 0;
      _persistedSessionTotal = 0;
      _cart.clear();
      _discount.text = '0,00';
      _paymentAmount.text = '0,00';
      _notes.clear();
      _clientId = null;
    });
    await _clearOpenCashSession();
    widget.onPdvCashOpenChanged?.call(false);
    widget.onPdvFullscreenChanged?.call(false);
  }

  Future<void> _finishSale() async {
    if (_cart.isEmpty) {
      setState(() => _error = 'Adicione pelo menos um item.');
      return;
    }
    if (!widget.pdvMode &&
        (_sellerById(_sellerUserId)?.sellerCode ?? '').trim().isEmpty) {
      await _showRequiredInfoDialog(
        'Informe um vendedor com código cadastrado para finalizar a venda.',
      );
      return;
    }
    if (!_paymentCoversTotal) {
      setState(() => _error = 'Pagamento menor que o total.');
      return;
    }
    if (!widget.pdvMode &&
        !_canOverrideDiscount &&
        _discountCents > _maxDiscountCents + 1) {
      setState(
        () => _error =
            'Desconto acima do limite permitido. Máximo: ${_money(_maxDiscountCents / 100)} (${formatBrazilianMoneyInput(_maxDiscountPercent)}%).',
      );
      return;
    }
    if (_usesFinancialPayment && _clientId == null) {
      await _showRequiredInfoDialog(
        'Boleto e crediário exigem cliente cadastrado. Selecione um cliente antes de finalizar.',
      );
      return;
    }
    final installments = _usesFinancialPayment
        ? await _confirmInstallments()
        : const <SaleInstallmentPayload>[];
    if (!mounted || installments == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final sale = await _api.createSale(
        widget.session.token,
        SalePayload(
          clientId: _clientId,
          sellerUserId: _sellerUserId,
          source: widget.pdvMode ? 'pdv' : 'venda',
          cashRegisterNumber: widget.pdvMode ? _cashRegisterNumber : null,
          status: 'finalizada',
          discountAmount: _discountCents / 100,
          notes: _notes.text,
          items: [
            for (final item in _cart)
              SaleItemPayload(
                productId: item.product.id,
                barcode: item.product.barcode,
                description: item.product.name,
                quantity: item.quantity,
                unitPrice: item.unitPrice,
                discountAmount: 0,
              ),
          ],
          payments: [
            SalePaymentPayload(
              method: _paymentMethod,
              amount: _paidCents / 100,
              notes: _usesCreditInstallments
                  ? 'Crédito ${_installmentCount}x'
                  : null,
            ),
          ],
          installments: installments,
        ),
      );
      if (!mounted) return;
      setState(() {
        _sales = [sale, ..._sales];
        if (widget.pdvMode) {
          _persistedSaleCount += 1;
          _persistedSessionTotal += sale.totalAmount;
          for (final payment in sale.payments) {
            _persistedPaymentTotals[payment.method] =
                (_persistedPaymentTotals[payment.method] ?? 0) + payment.amount;
          }
        }
        _cart.clear();
        _discount.text = '0,00';
        _paymentAmount.text = '0,00';
        _notes.clear();
        _clientId = null;
      });
      await _persistOpenCashSession();
      if (!mounted) return;
      await _emitNonFiscalReceiptAfterSale(
        sale,
        installments: installments,
        creditInstallmentCount: _usesCreditInstallments
            ? _installmentCount
            : null,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Venda ${sale.number ?? sale.id} finalizada.')),
      );
      await _load();
      _barcodeFocus.requestFocus();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível finalizar a venda.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelSale(Sale sale) async {
    final authorized = await _requestFiscalAuthorization(
      action: 'cancel_sale',
      title: 'Autorizar cancelamento',
    );
    if (!authorized) return;
    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Cancelar ${sale.number ?? 'venda'}?'),
        content: const Text('O estoque dos produtos será devolvido.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Não'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar venda'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    await _api.cancelSale(widget.session.token, sale.id);
    await _load();
  }

  Future<void> _editSalePayments(Sale sale) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _SalePaymentsDialog(
        api: _api,
        token: widget.session.token,
        sale: sale,
      ),
    );
    if (changed == true) await _load();
  }

  void _reprintNonFiscalReceipt(Sale sale) {
    openNonFiscalSaleReceipt(
      sale: sale,
      companyName: widget.session.companyName,
      cashRegisterNumber: sale.cashRegisterNumber,
      operatorName: sale.sellerName,
    );
  }

  Future<void> _emitNonFiscalReceiptAfterSale(
    Sale sale, {
    List<SaleInstallmentPayload> installments = const [],
    int? creditInstallmentCount,
  }) async {
    try {
      await openNonFiscalSaleReceipt(
        sale: sale,
        companyName: widget.session.companyName,
        cashRegisterNumber: sale.cashRegisterNumber,
        operatorName: sale.sellerName,
        installments: installments,
        creditInstallmentCount: creditInstallmentCount,
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Falha ao imprimir: $error')));
    }
  }

  Future<bool> _requestFiscalAuthorization({
    required String action,
    required String title,
  }) async {
    final code = TextEditingController();
    final pin = TextEditingController();
    String? error;
    var loading = false;
    try {
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> authorize() async {
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                await _api.authorizePdvAction(
                  widget.session.token,
                  code: code.text,
                  pin: pin.text,
                  action: action,
                );
                if (context.mounted) Navigator.of(context).pop(true);
              } on ApiException catch (apiError) {
                setDialogState(() => error = apiError.message);
              } catch (_) {
                setDialogState(() => error = 'Não foi possível autorizar.');
              } finally {
                setDialogState(() => loading = false);
              }
            }

            return AlertDialog(
              title: Text(title),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Informe código e senha de um fiscal autorizado.',
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: code,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Código do fiscal',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => authorize(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pin,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Senha/PIN',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => authorize(),
                    ),
                    if (error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        error!,
                        style: const TextStyle(color: Color(0xFFB91C1C)),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: loading
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: loading ? null : authorize,
                  icon: const Icon(Icons.verified_user_outlined),
                  label: Text(loading ? 'Validando...' : 'Autorizar'),
                ),
              ],
            );
          },
        ),
      );
      return result == true;
    } finally {
      code.dispose();
      pin.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canViewSales = widget.session.can('sales:view');
    final canCreateSale = widget.session.can('sales:create');
    final canCancelSale = widget.session.can('sales:cancel');
    final tabs = [
      if (canCreateSale)
        const ButtonSegment<int>(
          value: 1,
          icon: Icon(Icons.add_shopping_cart),
          label: Text('Nova venda'),
        ),
      if (canViewSales)
        const ButtonSegment<int>(
          value: 0,
          icon: Icon(Icons.history),
          label: Text('Historico'),
        ),
    ];
    final availableTabs = tabs.map((tab) => tab.value).toSet();
    if (availableTabs.isNotEmpty &&
        !availableTabs.contains(_selectedSalesTab)) {
      _selectedSalesTab = availableTabs.first;
    }
    final showHistory = _selectedSalesTab == 0 && canViewSales;
    final showManualSale = _selectedSalesTab == 1 && canCreateSale;
    final filteredSales = _filteredSales();
    if (widget.pdvMode) {
      return _buildPdvView();
    }

    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vendas',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Gestão de vendas, clientes, pagamentos, cancelamentos e histórico',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Atualizar',
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (tabs.length > 1) ...[
              Align(
                alignment: Alignment.centerLeft,
                child: SegmentedButton<int>(
                  selected: {_selectedSalesTab},
                  segments: tabs,
                  onSelectionChanged: (value) =>
                      setState(() => _selectedSalesTab = value.first),
                ),
              ),
              const SizedBox(height: 18),
            ],
            if (showHistory)
              _SalesSearchPanel(
                search: _salesSearch,
                statusFilter: _salesStatusFilter,
                sourceFilter: _salesSourceFilter,
                periodFilter: _salesPeriodFilter,
                onChanged: () => setState(() {}),
                onStatusChanged: (value) =>
                    setState(() => _salesStatusFilter = value ?? 'todos'),
                onSourceChanged: (value) =>
                    setState(() => _salesSourceFilter = value ?? 'todos'),
                onPeriodChanged: (value) =>
                    setState(() => _salesPeriodFilter = value ?? 'todos'),
                onClear: () => setState(() {
                  _salesSearch.clear();
                  _salesStatusFilter = 'todos';
                  _salesSourceFilter = 'todos';
                  _salesPeriodFilter = 'todos';
                }),
              ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
            if (showManualSale)
              LayoutBuilder(
                builder: (context, constraints) {
                  final wide = constraints.maxWidth >= 1020;
                  final pdv = _PdvPanel(
                    compact: true,
                    barcode: _barcode,
                    barcodeFocus: _barcodeFocus,
                    onScan: _scanCode,
                    sellerCode: _sellerCode,
                    selectedSeller: _sellerById(_sellerUserId),
                    onSellerCodeSubmitted: _selectSellerByCode,
                    onOpenSellerPicker: _openSellerPicker,
                    onOpenProductPicker: _openProductPicker,
                    clients: _clients,
                    clientId: _clientId,
                    onClientChanged: (value) =>
                        setState(() => _clientId = value),
                    notes: _notes,
                  );
                  final cart = _CartPanel(
                    pdvMode: false,
                    items: _cart,
                    discount: _discount,
                    paymentAmount: _paymentAmount,
                    paymentMethod: _paymentMethod,
                    installmentCount: _installmentCount,
                    firstDueDate: _firstDueDate,
                    maxDiscountPercent: _maxDiscountPercent,
                    maxDiscountCents: _maxDiscountCents,
                    canOverrideDiscount: _canOverrideDiscount,
                    onPaymentMethodChanged: (value) {
                      setState(() => _paymentMethod = value);
                      _syncPaymentWithTotal();
                    },
                    onInstallmentCountChanged: (value) =>
                        setState(() => _installmentCount = value),
                    onFirstDueDateChanged: (value) =>
                        setState(() => _firstDueDate = value),
                    subtotalCents: _subtotalCents,
                    saving: _saving,
                    onCartChanged: () {
                      setState(() {});
                      _syncPaymentWithTotal();
                    },
                    onAmountChanged: () => setState(() {}),
                    onRemove: _removeItem,
                    onFinish: _finishSale,
                  );
                  if (!wide) {
                    return Column(
                      children: [pdv, const SizedBox(height: 14), cart],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 5, child: pdv),
                      const SizedBox(width: 14),
                      Expanded(flex: 4, child: cart),
                    ],
                  );
                },
              ),
            if (showHistory) ...[
              const SizedBox(height: 18),
              _SalesHistory(
                sales: filteredSales,
                clients: _clients,
                canCancel: canCancelSale,
                onCancel: _cancelSale,
                onEditPayments: _editSalePayments,
                onReprintNonFiscalReceipt: _reprintNonFiscalReceipt,
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Sale> _filteredSales() {
    final term = _normalize(_salesSearch.text);
    final now = DateTime.now();
    return _sales.where((sale) {
      if (_salesStatusFilter != 'todos' && sale.status != _salesStatusFilter) {
        return false;
      }
      if (_salesSourceFilter != 'todos' && sale.source != _salesSourceFilter) {
        return false;
      }
      if (_salesPeriodFilter == 'hoje' &&
          !_sameDay(sale.soldAt.toLocal(), now)) {
        return false;
      }
      if (_salesPeriodFilter == '7dias' &&
          sale.soldAt.isBefore(now.subtract(const Duration(days: 7)))) {
        return false;
      }
      if (_salesPeriodFilter == '30dias' &&
          sale.soldAt.isBefore(now.subtract(const Duration(days: 30)))) {
        return false;
      }
      if (term.isEmpty) return true;
      final client = _clientName(sale.clientId);
      final haystack = _normalize(
        [
          sale.number,
          sale.id.toString(),
          sale.consumerCpf,
          sale.notes,
          sale.status,
          sale.source,
          client,
          for (final item in sale.items) item.description,
          for (final item in sale.items) item.barcode,
          for (final payment in sale.payments) payment.method,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }

  String? _clientName(int? clientId) {
    if (clientId == null) return null;
    for (final client in _clients) {
      if (client.id == clientId) return client.name;
    }
    return null;
  }

  Widget _buildPdvView() {
    if (!_cashOpen) {
      return _PdvOpenCashScreen(
        openingCash: _openingCash,
        operatorCode: _operatorCode,
        operatorPin: _operatorPin,
        operators: _operators,
        saving: _saving,
        onOpen: widget.session.can('sales:create') ? _openCashDrawer : null,
      );
    }

    return Container(
      color: const Color(0xFFEFF3F8),
      child: Column(
        children: [
          _PdvTopBar(
            openedAt: _cashOpenedAt,
            operatorName: _operatorName,
            cashRegisterNumber: _cashRegisterLabel,
            sessionTotal: _pdvSessionTotal,
            expectedCash: _expectedCashTotal,
            fullscreen: widget.fullscreen,
            onFullscreenChanged: widget.onPdvFullscreenChanged,
            onRefresh: _load,
            onWithdraw: _showWithdrawDialog,
            onCloseCash: _showCloseCashDialog,
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
              child: ErrorPanel(message: _error!, onRetry: _load),
            ),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1080;
                final pdv = _PdvPanel(
                  compact: false,
                  barcode: _barcode,
                  barcodeFocus: _barcodeFocus,
                  onScan: _scanCode,
                  sellerCode: _sellerCode,
                  selectedSeller: _sellerById(_sellerUserId),
                  onSellerCodeSubmitted: _selectSellerByCode,
                  onOpenSellerPicker: _openSellerPicker,
                  onOpenProductPicker: _openProductPicker,
                  clients: _clients,
                  clientId: _clientId,
                  onClientChanged: (value) => setState(() => _clientId = value),
                  notes: _notes,
                );
                final cart = _CartPanel(
                  pdvMode: true,
                  items: _cart,
                  discount: _discount,
                  paymentAmount: _paymentAmount,
                  paymentMethod: _paymentMethod,
                  installmentCount: _installmentCount,
                  firstDueDate: _firstDueDate,
                  maxDiscountPercent: _maxDiscountPercent,
                  maxDiscountCents: _maxDiscountCents,
                  canOverrideDiscount: _canOverrideDiscount,
                  onPaymentMethodChanged: (value) {
                    setState(() => _paymentMethod = value);
                    _syncPaymentWithTotal();
                  },
                  onInstallmentCountChanged: (value) =>
                      setState(() => _installmentCount = value),
                  onFirstDueDateChanged: (value) =>
                      setState(() => _firstDueDate = value),
                  subtotalCents: _subtotalCents,
                  saving: _saving,
                  onCartChanged: () {
                    setState(() {});
                    _syncPaymentWithTotal();
                  },
                  onAmountChanged: () => setState(() {}),
                  onRemove: _removeItem,
                  onFinish: widget.session.can('sales:create')
                      ? _finishSale
                      : null,
                );
                final fiscal = _FiscalPreparationPanel(
                  paymentTotals: {
                    for (final entry in _paymentMethods.entries)
                      entry.value: _paymentTotal(entry.key),
                  },
                  saleCount: _persistedSaleCount,
                  withdrawals: _cashMovements,
                );

                return Padding(
                  padding: const EdgeInsets.all(14),
                  child: wide
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 5, child: pdv),
                            const SizedBox(width: 14),
                            Expanded(flex: 4, child: cart),
                            const SizedBox(width: 14),
                            SizedBox(width: 300, child: fiscal),
                          ],
                        )
                      : ListView(
                          children: [
                            pdv,
                            const SizedBox(height: 14),
                            cart,
                            const SizedBox(height: 14),
                            fiscal,
                          ],
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PdvOpenCashScreen extends StatelessWidget {
  const _PdvOpenCashScreen({
    required this.openingCash,
    required this.operatorCode,
    required this.operatorPin,
    required this.operators,
    required this.saving,
    required this.onOpen,
  });

  final TextEditingController openingCash;
  final TextEditingController operatorCode;
  final TextEditingController operatorPin;
  final List<PdvOperator> operators;
  final bool saving;
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0F172A),
      padding: const EdgeInsets.all(28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: AppCard(
            padding: const EdgeInsets.all(30),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Image.asset(
                      'assets/brand/LogoPGN.PNG',
                      width: 72,
                      height: 72,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(width: 16),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Abrir caixa',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            'Informe o operador e o fundo inicial para iniciar o PDV.',
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                TextField(
                  controller: operatorCode,
                  decoration: const InputDecoration(
                    labelText: 'Código do operador',
                    prefixIcon: Icon(Icons.badge_outlined),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onOpen?.call(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: operatorPin,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha/PIN do operador',
                    prefixIcon: Icon(Icons.lock_outline),
                    border: OutlineInputBorder(),
                  ),
                  onSubmitted: (_) => onOpen?.call(),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: openingCash,
                  autofocus: true,
                  keyboardType: TextInputType.text,
                  inputFormatters: const [BrazilianMoneyInputFormatter()],
                  onSubmitted: (_) => onOpen?.call(),
                  decoration: const InputDecoration(
                    labelText: 'Fundo de caixa',
                    prefixIcon: Icon(Icons.savings_outlined),
                    border: OutlineInputBorder(),
                  ),
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: saving ? null : onOpen,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: Text(saving ? 'Validando...' : 'Abrir PDV'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    textStyle: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  operators.isEmpty
                      ? 'Cadastre um operador PDV antes de abrir o caixa.'
                      : 'Acoes como sangria e cancelamento exigem autorização de fiscal.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PdvTopBar extends StatelessWidget {
  const _PdvTopBar({
    required this.openedAt,
    required this.operatorName,
    required this.cashRegisterNumber,
    required this.sessionTotal,
    required this.expectedCash,
    required this.fullscreen,
    required this.onFullscreenChanged,
    required this.onRefresh,
    required this.onWithdraw,
    required this.onCloseCash,
  });

  final DateTime? openedAt;
  final String? operatorName;
  final String cashRegisterNumber;
  final double sessionTotal;
  final double expectedCash;
  final bool fullscreen;
  final ValueChanged<bool>? onFullscreenChanged;
  final VoidCallback onRefresh;
  final VoidCallback onWithdraw;
  final VoidCallback onCloseCash;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 14),
      decoration: const BoxDecoration(
        color: Color(0xFF0F172A),
        border: Border(bottom: BorderSide(color: Color(0xFF1D4ED8))),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Image.asset('assets/brand/LogoPGN.PNG', fit: BoxFit.contain),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'PDV Caixa',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 25,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  'Caixa $cashRegisterNumber | Operador ${operatorName ?? '-'} | Aberto ${openedAt == null ? '-' : _dateTime(openedAt!)} | Vendas ${_money(sessionTotal)} | Dinheiro esperado ${_money(expectedCash)}',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFFCBD5E1)),
                ),
              ],
            ),
          ),
          IconButton.outlined(
            tooltip: 'Atualizar produtos',
            onPressed: onRefresh,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
            ),
            icon: const Icon(Icons.refresh),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onFullscreenChanged == null
                ? null
                : () => onFullscreenChanged!(!fullscreen),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: Icon(
              fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              size: 18,
            ),
            label: Text(fullscreen ? 'Sair tela cheia' : 'Tela cheia'),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onWithdraw,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Color(0xFF334155)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            icon: const Icon(Icons.south_west, size: 18),
            label: const Text('Sangria'),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: onCloseCash,
            icon: const Icon(Icons.lock_outline, size: 18),
            label: const Text('Fechar caixa'),
          ),
        ],
      ),
    );
  }
}

class _FiscalPreparationPanel extends StatelessWidget {
  const _FiscalPreparationPanel({
    required this.paymentTotals,
    required this.saleCount,
    required this.withdrawals,
  });

  final Map<String, double> paymentTotals;
  final int saleCount;
  final List<_CashMovement> withdrawals;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            children: [
              Icon(Icons.receipt_long_outlined, color: Color(0xFF1D4ED8)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Fiscal / caixa',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _PdvMiniMetric(label: 'Vendas no turno', value: '$saleCount'),
          const SizedBox(height: 8),
          for (final entry in paymentTotals.entries)
            if (entry.value > 0)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: _PdvMiniMetric(
                  label: entry.key,
                  value: _money(entry.value),
                ),
              ),
          const Divider(height: 24),
          const Text(
            'Fiscal NFC-e / NF-e',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          const Text(
            'Preparado para NFC-e/NF-e com Certificado Digital A1. Por enquanto a venda baixa estoque e registra pagamento; assinatura XML e autorização SEFAZ entram na homologacao fiscal.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: null,
            icon: const Icon(Icons.receipt_outlined),
            label: const Text('Preparar NFC-e/NF-e em breve'),
          ),
          const Divider(height: 24),
          const Text('Sangrias', style: TextStyle(fontWeight: FontWeight.w900)),
          const SizedBox(height: 6),
          if (withdrawals.isEmpty)
            const Text(
              'Nenhuma sangria registrada.',
              style: TextStyle(color: Color(0xFF64748B)),
            )
          else
            for (final movement in withdrawals.take(4))
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  '${_dateTime(movement.createdAt)} | ${_money(movement.amount)} | ${movement.reason.isEmpty ? '-' : movement.reason}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
        ],
      ),
    );
  }
}

class _PdvMiniMetric extends StatelessWidget {
  const _PdvMiniMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(child: Text(label)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.w900)),
      ],
    );
  }
}

class _CloseCashLine extends StatelessWidget {
  const _CloseCashLine(this.label, this.value, {this.strong = false});

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: strong ? 18 : 14,
              fontWeight: strong ? FontWeight.w900 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _PdvPanel extends StatelessWidget {
  const _PdvPanel({
    required this.compact,
    required this.barcode,
    required this.barcodeFocus,
    required this.onScan,
    required this.sellerCode,
    required this.selectedSeller,
    required this.onSellerCodeSubmitted,
    required this.onOpenSellerPicker,
    required this.onOpenProductPicker,
    required this.clients,
    required this.clientId,
    required this.onClientChanged,
    required this.notes,
  });

  final bool compact;
  final TextEditingController barcode;
  final FocusNode barcodeFocus;
  final VoidCallback onScan;
  final TextEditingController sellerCode;
  final SaleSeller? selectedSeller;
  final ValueChanged<String> onSellerCodeSubmitted;
  final VoidCallback onOpenSellerPicker;
  final VoidCallback onOpenProductPicker;
  final List<Client> clients;
  final int? clientId;
  final ValueChanged<int?> onClientChanged;
  final TextEditingController notes;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Leitura de produtos',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: compact ? 180 : 220,
                child: TextField(
                  controller: sellerCode,
                  textInputAction: TextInputAction.search,
                  onSubmitted: onSellerCodeSubmitted,
                  decoration: InputDecoration(
                    labelText: 'Codigo vendedor',
                    hintText: 'Ex.: V001',
                    prefixIcon: const Icon(Icons.badge_outlined),
                    suffixIcon: IconButton(
                      tooltip: 'Pesquisar vendedor',
                      onPressed: onOpenSellerPicker,
                      icon: const Icon(Icons.search),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Vendedor selecionado',
                    border: OutlineInputBorder(),
                  ),
                  child: Text(
                    selectedSeller == null
                        ? 'Nenhum vendedor selecionado'
                        : selectedSeller!.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selectedSeller == null
                          ? const Color(0xFF64748B)
                          : const Color(0xFF0F172A),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<int?>(
            initialValue: clientId,
            decoration: const InputDecoration(
              labelText: 'Cliente',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Consumidor final'),
              ),
              for (final client in clients)
                DropdownMenuItem(value: client.id, child: Text(client.name)),
            ],
            onChanged: onClientChanged,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: barcode,
            focusNode: barcodeFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onScan(),
            decoration: InputDecoration(
              labelText: 'Leitor de código de barras',
              hintText: 'Bipe o produto ou digite o código e aperte Enter',
              prefixIcon: const Icon(Icons.qr_code_scanner_outlined),
              suffixIcon: IconButton(
                tooltip: 'Adicionar pelo código',
                onPressed: onScan,
                icon: const Icon(Icons.keyboard_return),
              ),
              border: const OutlineInputBorder(),
            ),
            style: TextStyle(
              fontSize: compact ? 16 : 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onOpenProductPicker,
            icon: const Icon(Icons.search),
            label: const Text('Pesquisar produto'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: notes,
            minLines: 2,
            maxLines: compact ? 4 : 2,
            decoration: const InputDecoration(
              labelText: 'Observações da venda',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    this.pdvMode = false,
    required this.items,
    required this.discount,
    required this.paymentAmount,
    required this.paymentMethod,
    required this.installmentCount,
    required this.firstDueDate,
    required this.maxDiscountPercent,
    required this.maxDiscountCents,
    required this.canOverrideDiscount,
    required this.onPaymentMethodChanged,
    required this.onInstallmentCountChanged,
    required this.onFirstDueDateChanged,
    required this.subtotalCents,
    required this.saving,
    required this.onCartChanged,
    required this.onAmountChanged,
    required this.onRemove,
    required this.onFinish,
  });

  final bool pdvMode;
  final List<_CartItem> items;
  final TextEditingController discount;
  final TextEditingController paymentAmount;
  final String paymentMethod;
  final int installmentCount;
  final DateTime firstDueDate;
  final double maxDiscountPercent;
  final int maxDiscountCents;
  final bool canOverrideDiscount;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<int> onInstallmentCountChanged;
  final ValueChanged<DateTime> onFirstDueDateChanged;
  final int subtotalCents;
  final bool saving;
  final VoidCallback onCartChanged;
  final VoidCallback onAmountChanged;
  final ValueChanged<_CartItem> onRemove;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    final currentDiscountCents = _moneyCents(
      parseBrazilianNumber(discount.text),
    );
    final currentPaidCents = _moneyCents(
      parseBrazilianNumber(paymentAmount.text),
    );
    final currentTotalCents = _nonNegativeCents(
      subtotalCents - currentDiscountCents,
    );
    final manualDiscountTooHigh =
        !pdvMode &&
        !canOverrideDiscount &&
        currentDiscountCents > maxDiscountCents + 1;
    final currentChangeCents = _nonNegativeCents(
      currentPaidCents - currentTotalCents,
    );
    final usesReceivableInstallments =
        paymentMethod == 'boleto' || paymentMethod == 'crediario';
    final usesInstallments =
        usesReceivableInstallments || paymentMethod == 'credito';
    final previewInstallments = buildSaleInstallments(
      totalCents: currentPaidCents,
      count: installmentCount,
      firstDueDate: firstDueDate,
    );
    return AppCard(
      padding: EdgeInsets.all(pdvMode ? 24 : 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Carrinho',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('Nenhum item na venda.'),
            )
          else
            for (final item in items)
              _CartItemTile(
                item: item,
                onChanged: onCartChanged,
                onRemove: onRemove,
              ),
          const Divider(height: 26),
          _MoneyRow('Subtotal', subtotalCents / 100),
          const SizedBox(height: 10),
          TextField(
            controller: discount,
            keyboardType: TextInputType.text,
            inputFormatters: const [BrazilianMoneyInputFormatter()],
            onChanged: (_) => onAmountChanged(),
            decoration: InputDecoration(
              labelText: 'Desconto',
              helperText: pdvMode
                  ? null
                  : canOverrideDiscount
                  ? 'Desconto livre para este perfil.'
                  : 'Máximo permitido: ${_money(maxDiscountCents / 100)} (${formatBrazilianMoneyInput(maxDiscountPercent)}%)',
              errorText: manualDiscountTooHigh
                  ? 'Desconto acima do limite permitido'
                  : null,
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Forma de pagamento',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final entry in _paymentMethods.entries)
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            ],
            onChanged: (value) => onPaymentMethodChanged(value ?? 'pix'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: paymentAmount,
            keyboardType: TextInputType.text,
            inputFormatters: const [BrazilianMoneyInputFormatter()],
            onChanged: (_) => onAmountChanged(),
            decoration: const InputDecoration(
              labelText: 'Valor recebido',
              border: OutlineInputBorder(),
            ),
          ),
          if (usesInstallments) ...[
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final narrow = constraints.maxWidth < 520;
                final countField = DropdownButtonFormField<int>(
                  initialValue: installmentCount,
                  decoration: const InputDecoration(
                    labelText: 'Parcelas',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (var count = 1; count <= 12; count++)
                      DropdownMenuItem(value: count, child: Text('${count}x')),
                  ],
                  onChanged: (value) => onInstallmentCountChanged(value ?? 1),
                );
                final dateButton = usesReceivableInstallments
                    ? OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: firstDueDate,
                            firstDate: DateTime(2020),
                            lastDate: DateTime(2100),
                            locale: const Locale('pt', 'BR'),
                          );
                          if (picked != null) onFirstDueDateChanged(picked);
                        },
                        icon: const Icon(Icons.event_outlined),
                        label: Text(
                          '1º vencimento ${formatBrazilianDate(firstDueDate)}',
                        ),
                      )
                    : null;
                final installmentValue = previewInstallments.isEmpty
                    ? _money(0)
                    : _money(previewInstallments.first.amountCents / 100);
                final valueLabel = Align(
                  alignment: narrow ? Alignment.centerLeft : Alignment.center,
                  child: Text(
                    'Parcela: $installmentValue',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                );
                if (narrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      countField,
                      if (dateButton != null) ...[
                        const SizedBox(height: 8),
                        dateButton,
                      ],
                      const SizedBox(height: 8),
                      valueLabel,
                    ],
                  );
                }
                return Row(
                  children: [
                    SizedBox(width: 130, child: countField),
                    if (dateButton != null) ...[
                      const SizedBox(width: 10),
                      Expanded(child: dateButton),
                    ],
                    const SizedBox(width: 10),
                    valueLabel,
                  ],
                );
              },
            ),
          ],
          const SizedBox(height: 14),
          _MoneyRow(
            'Total',
            currentTotalCents / 100,
            large: true,
            pdvMode: pdvMode,
          ),
          _MoneyRow('Recebido', currentPaidCents / 100),
          _MoneyRow('Troco', currentChangeCents / 100),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: saving || onFinish == null ? null : onFinish,
            icon: const Icon(Icons.point_of_sale_outlined),
            label: Text(saving ? 'Finalizando...' : 'Finalizar venda'),
          ),
        ],
      ),
    );
  }
}

class _CartItemTile extends StatelessWidget {
  const _CartItemTile({
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final _CartItem item;
  final VoidCallback onChanged;
  final ValueChanged<_CartItem> onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.name,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '${formatBrazilianDecimal(item.quantity)} x ${_money(item.unitPrice)}',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Diminuir',
            onPressed: () {
              if (item.quantity > 1) item.quantity -= 1;
              onChanged();
            },
            icon: const Icon(Icons.remove_circle_outline),
          ),
          Text(formatBrazilianDecimal(item.quantity)),
          IconButton(
            tooltip: 'Aumentar',
            onPressed: () {
              item.quantity += 1;
              onChanged();
            },
            icon: const Icon(Icons.add_circle_outline),
          ),
          IconButton(
            tooltip: 'Remover',
            onPressed: () => onRemove(item),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }
}

class _SalesSearchPanel extends StatelessWidget {
  const _SalesSearchPanel({
    required this.search,
    required this.statusFilter,
    required this.sourceFilter,
    required this.periodFilter,
    required this.onChanged,
    required this.onStatusChanged,
    required this.onSourceChanged,
    required this.onPeriodChanged,
    required this.onClear,
  });

  final TextEditingController search;
  final String statusFilter;
  final String sourceFilter;
  final String periodFilter;
  final VoidCallback onChanged;
  final ValueChanged<String?> onStatusChanged;
  final ValueChanged<String?> onSourceChanged;
  final ValueChanged<String?> onPeriodChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          final searchField = TextField(
            controller: search,
            onChanged: (_) => onChanged(),
            decoration: const InputDecoration(
              labelText: 'Buscar vendas',
              hintText: 'Número, cliente, CPF, produto, forma de pagamento...',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          );
          final filters = [
            DropdownButtonFormField<String>(
              initialValue: statusFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Status',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'todos', child: Text('Todos')),
                DropdownMenuItem(
                  value: 'finalizada',
                  child: Text('Finalizada'),
                ),
                DropdownMenuItem(value: 'cancelada', child: Text('Cancelada')),
              ],
              onChanged: onStatusChanged,
            ),
            DropdownButtonFormField<String>(
              initialValue: sourceFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Origem',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'todos', child: Text('Todas')),
                DropdownMenuItem(value: 'venda', child: Text('Vendas')),
                DropdownMenuItem(value: 'pdv', child: Text('PDV')),
              ],
              onChanged: onSourceChanged,
            ),
            DropdownButtonFormField<String>(
              initialValue: periodFilter,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Periodo',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(value: 'todos', child: Text('Todos')),
                DropdownMenuItem(value: 'hoje', child: Text('Hoje')),
                DropdownMenuItem(value: '7dias', child: Text('Ultimos 7 dias')),
                DropdownMenuItem(
                  value: '30dias',
                  child: Text('Ultimos 30 dias'),
                ),
              ],
              onChanged: onPeriodChanged,
            ),
          ];
          if (compact) {
            return Column(
              children: [
                searchField,
                const SizedBox(height: 12),
                for (final filter in filters) ...[
                  filter,
                  const SizedBox(height: 10),
                ],
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: onClear,
                    icon: const Icon(Icons.clear),
                    label: const Text('Limpar'),
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: searchField),
              const SizedBox(width: 12),
              for (final filter in filters) ...[
                SizedBox(width: 190, child: filter),
                const SizedBox(width: 10),
              ],
              IconButton.outlined(
                tooltip: 'Limpar busca',
                onPressed: onClear,
                icon: const Icon(Icons.clear),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SalesHistory extends StatelessWidget {
  const _SalesHistory({
    required this.sales,
    required this.clients,
    required this.canCancel,
    required this.onCancel,
    required this.onEditPayments,
    required this.onReprintNonFiscalReceipt,
  });

  final List<Sale> sales;
  final List<Client> clients;
  final bool canCancel;
  final ValueChanged<Sale> onCancel;
  final ValueChanged<Sale> onEditPayments;
  final ValueChanged<Sale> onReprintNonFiscalReceipt;

  @override
  Widget build(BuildContext context) {
    final clientById = {for (final client in clients) client.id: client};
    return AppCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.centerLeft,
            decoration: const BoxDecoration(
              color: Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Text(
              'Historico de vendas',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
          if (sales.isEmpty)
            const Padding(
              padding: EdgeInsets.all(22),
              child: Text('Nenhuma venda registrada.'),
            )
          else
            for (final sale in sales)
              ListTile(
                title: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      '${sale.number ?? 'V${sale.id}'} - ${_money(sale.totalAmount)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    Chip(
                      label: Text(_saleSourceLabel(sale.source)),
                      visualDensity: VisualDensity.compact,
                    ),
                  ],
                ),
                subtitle: Text(
                  '${clientById[sale.clientId]?.name ?? 'Consumidor final'} | ${_dateTime(sale.soldAt)} | ${sale.status}',
                ),
                trailing: sale.status == 'cancelada'
                    ? const Text('Cancelada')
                    : Wrap(
                        spacing: 4,
                        children: [
                          if (!sale.hasAuthorizedFiscalDocument)
                            IconButton(
                              tooltip: 'Reimprimir cupom nao fiscal',
                              onPressed: () => onReprintNonFiscalReceipt(sale),
                              icon: const Icon(Icons.print_outlined),
                            )
                          else
                            const Tooltip(
                              message:
                                  'Venda com nota fiscal autorizada. Imprima em Notas fiscais.',
                              child: Icon(
                                Icons.receipt_long_outlined,
                                color: Color(0xFF64748B),
                              ),
                            ),
                          IconButton(
                            tooltip: sale.hasAuthorizedFiscalDocument
                                ? 'Venda com nota fiscal autorizada'
                                : 'Alterar forma de pagamento',
                            onPressed: sale.hasAuthorizedFiscalDocument
                                ? null
                                : () => onEditPayments(sale),
                            icon: const Icon(Icons.payments_outlined),
                          ),
                          if (canCancel)
                            IconButton(
                              tooltip: sale.hasAuthorizedFiscalDocument
                                  ? 'Cancele a nota fiscal antes de cancelar a venda'
                                  : 'Cancelar venda',
                              onPressed: () => onCancel(sale),
                              icon: const Icon(Icons.cancel_outlined),
                            ),
                        ],
                      ),
              ),
        ],
      ),
    );
  }
}

String _saleSourceLabel(String source) {
  return switch (source) {
    'pdv' => 'PDV',
    'venda' => 'Venda manual',
    'os' => 'OS',
    'teste' => 'Teste',
    _ => source,
  };
}

class _SalePaymentsDialog extends StatefulWidget {
  const _SalePaymentsDialog({
    required this.api,
    required this.token,
    required this.sale,
  });

  final ApiClient api;
  final String token;
  final Sale sale;

  @override
  State<_SalePaymentsDialog> createState() => _SalePaymentsDialogState();
}

class _SalePaymentsDialogState extends State<_SalePaymentsDialog> {
  late final List<String> _methods = [
    for (final payment in widget.sale.payments) payment.method,
  ];
  bool _saving = false;
  String? _error;

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateSalePayments(widget.token, widget.sale.id, [
        for (var index = 0; index < widget.sale.payments.length; index++)
          SalePaymentPayload(
            method: _methods[index],
            amount: widget.sale.payments[index].amount,
            authorizationCode: widget.sale.payments[index].authorizationCode,
            notes: widget.sale.payments[index].notes,
          ),
      ]);
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Nao foi possivel alterar o pagamento.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Alterar pagamento ${widget.sale.number ?? 'V${widget.sale.id}'}',
      ),
      content: SizedBox(
        width: 520,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Altere apenas a forma de pagamento. O valor da venda nao sera modificado.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            for (var index = 0; index < widget.sale.payments.length; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        initialValue: _methods[index],
                        decoration: InputDecoration(
                          labelText: 'Pagamento ${index + 1}',
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          for (final entry in _paymentMethods.entries)
                            DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                        ],
                        onChanged: _saving
                            ? null
                            : (value) => setState(
                                () => _methods[index] = value ?? 'dinheiro',
                              ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: Text(
                        _money(widget.sale.payments[index].amount),
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ],
                ),
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: const Icon(Icons.save_outlined),
          label: Text(_saving ? 'Salvando...' : 'Salvar pagamento'),
        ),
      ],
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(
    this.label,
    this.value, {
    this.large = false,
    this.pdvMode = false,
  });
  final String label;
  final double value;
  final bool large;
  final bool pdvMode;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: large ? (pdvMode ? 34 : 24) : 15,
              fontWeight: large ? FontWeight.w900 : FontWeight.w800,
              color: large && pdvMode
                  ? const Color(0xFF1D4ED8)
                  : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _SalePreviewLine extends StatelessWidget {
  const _SalePreviewLine(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}

class _CartItem {
  _CartItem({required this.product})
    : unitPrice = product.effectiveSalePrice,
      quantity = 1;

  final Product product;
  double quantity;
  final double unitPrice;
}

class _CashMovement {
  const _CashMovement({
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAt,
  });

  final String type;
  final double amount;
  final String reason;
  final DateTime createdAt;
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';

int _moneyCents(double value) => (value * 100).round();

int _nonNegativeCents(int value) => value < 0 ? 0 : value;

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}

bool _sameDay(DateTime first, DateTime second) {
  return first.year == second.year &&
      first.month == second.month &&
      first.day == second.day;
}

String _normalize(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'õ': 'o',
    'ô': 'o',
    'ú': 'u',
    'ç': 'c',
  };
  var normalized = value.toLowerCase().trim();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}
