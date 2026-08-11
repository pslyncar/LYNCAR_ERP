// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/cash_closing.dart';
import '../models/client.dart';
import '../models/fiscal.dart';
import '../models/pdv_operator.dart';
import '../models/pdv_terminal.dart';
import '../models/product.dart';
import '../models/sale.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/app_session_storage.dart';
import '../services/fiscal_print.dart' as fiscal_print;
import '../services/receipt_print.dart' as receipt_print;
import '../utils/input_formatters.dart';
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

String _pdvText(String? value, {String fallback = ''}) {
  final text = value?.trim() ?? '';
  if (text.isEmpty) return fallback;
  final hasMojibake =
      text.contains('\u00C3') ||
      text.contains('\u00C2') ||
      text.contains('\u00E2') ||
      text.contains('\uFFFD');
  if (!hasMojibake) return text;
  try {
    final fixed = utf8.decode(latin1.encode(text), allowMalformed: true);
    int score(String input) => input.runes.where((rune) {
      return rune == 0x00C3 ||
          rune == 0x00C2 ||
          rune == 0x00E2 ||
          rune == 0xFFFD;
    }).length;
    return score(fixed) <= score(text) ? fixed : text;
  } catch (_) {
    return text;
  }
}

class PdvScreen extends StatefulWidget {
  const PdvScreen({
    super.key,
    required this.session,
    this.pdvMode = true,
    this.fullscreen = false,
    this.windowsAppMode = false,
    this.onEnsurePdvToken,
    this.onPdvCashOpenChanged,
    this.onPdvFullscreenChanged,
  });

  final Session session;
  final bool pdvMode;
  final bool fullscreen;
  final bool windowsAppMode;
  final Future<String?> Function()? onEnsurePdvToken;
  final ValueChanged<bool>? onPdvCashOpenChanged;
  final ValueChanged<bool>? onPdvFullscreenChanged;

  @override
  State<PdvScreen> createState() => _PdvScreenState();
}

class _PdvScreenState extends State<PdvScreen> {
  static const _pdvCashSessionKey = 'papezzosync.pdv.cashSession';
  static const _pdvProductCacheKey = 'papezzosync.pdv.productCache';
  static const _pdvFiscalSettingsCacheKey = 'papezzosync.pdv.fiscalSettings';
  static const _pdvOfflineSalesKey = 'papezzosync.pdv.offlineSales';
  static const _pdvDrawerPulseKey = 'papezzosync.pdv.drawerPulseProfile';
  static const _pdvCashRegisterNumberKey = 'lyncar.pdv.cashRegisterNumber';
  static const _pdvTerminalKey = 'lyncar.pdv.terminalKey';

  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _storage = AppSessionStorage();
  final _barcode = TextEditingController();
  final _manualSearch = TextEditingController();
  final _clientSearch = TextEditingController();
  final _discount = TextEditingController(text: '0,00');
  final _paymentAmount = TextEditingController(text: '0,00');
  final _notes = TextEditingController();
  final _openingCash = TextEditingController(text: '0,00');
  final _operatorCode = TextEditingController();
  final _operatorPin = TextEditingController();
  final _withdrawAmount = TextEditingController(text: '0,00');
  final _withdrawReason = TextEditingController();
  final _barcodeFocus = FocusNode();
  List<Client> _clients = [];
  List<Product> _products = [];
  List<Sale> _sales = [];
  List<PdvOperator> _operators = [];
  List<SaleSeller> _sellers = [];
  CompanyFiscalSetting? _fiscalSettings;
  final List<Sale> _pdvSessionSales = [];
  final List<_CashMovement> _cashMovements = [];
  final List<_CartItem> _cart = [];
  final Map<String, double> _persistedPaymentTotals = {};
  int? _clientId;
  int? _sellerUserId;
  double _scanQuantity = 1;
  String? _operatorName;
  String? _cashRegisterNumber;
  String? _terminalKey;
  String _paymentMethod = 'dinheiro';
  String? _consumerCpf;
  bool _consumerDocumentAsked = false;
  bool _cashOpen = false;
  bool _cashPaused = false;
  DateTime? _cashPausedAt;
  bool _cashOpeningAuthorized = false;
  DateTime? _cashOpenedAt;
  double _cashOpeningAmount = 0;
  int _persistedSaleCount = 0;
  double _persistedSessionTotal = 0;
  bool _loading = true;
  bool _saving = false;
  bool _paymentDialogOpen = false;
  bool _productSearchDialogOpen = false;
  bool _clientSearchDialogOpen = false;
  bool _authorizationDialogOpen = false;
  bool _sensitiveActionOpen = false;
  bool _pauseCashDialogOpen = false;
  bool _printerConfigured = false;
  String _drawerPulseProfile = 'default';
  PdvAuthorization? _lastFiscalAuthorization;
  String? _error;
  String? _productsLoadError;
  OverlayEntry? _pdvNoticeOverlay;
  Timer? _pdvNoticeTimer;
  Timer? _terminalHeartbeatTimer;

  bool get _usesFixedTerminal =>
      widget.pdvMode && widget.windowsAppMode && !kIsWeb;

  Client? get _selectedClient {
    final id = _clientId;
    if (id == null) return null;
    for (final client in _clients) {
      if (client.id == id) return client;
    }
    return null;
  }

  String? _crediarioBlockReason([Client? client]) {
    final selected = client ?? _selectedClient;
    if (selected == null) {
      return 'Selecione um cliente para vender no crediário.';
    }
    if (!selected.active) {
      return 'Cliente inativo não pode comprar no crediário.';
    }
    if (!selected.allowCredit) {
      return 'Crediário desativado para este cliente.';
    }
    if (selected.creditStatus != 'liberado') {
      return 'Cliente bloqueado para crediário.';
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleGlobalPdvKey);
    _discount.addListener(_persistOpenCashSession);
    _paymentAmount.addListener(_persistOpenCashSession);
    _notes.addListener(_persistOpenCashSession);
    unawaited(_restoreTerminalIdentification());
    unawaited(_restoreOpenCashSession());
    unawaited(_loadCachedPdvProducts());
    unawaited(_loadCachedFiscalSettings());
    unawaited(_loadDrawerPulseProfile());
    unawaited(_refreshPrinterStatus());
    _load();
  }

  Future<void> _refreshPrinterStatus() async {
    final configured = await receipt_print.isReceiptPrinterConfigured();
    if (!mounted) return;
    setState(() => _printerConfigured = configured);
  }

  String get _pdvDrawerPulseStorageKey {
    return '$_pdvDrawerPulseKey.${widget.session.companyCode}';
  }

  Future<void> _loadDrawerPulseProfile() async {
    final raw = await _storage.read(_pdvDrawerPulseStorageKey);
    if (!mounted || raw == null || raw.trim().isEmpty) return;
    setState(() => _drawerPulseProfile = raw.trim());
  }

  Future<void> _setDrawerPulseProfile(String value) async {
    setState(() => _drawerPulseProfile = value);
    await _storage.write(_pdvDrawerPulseStorageKey, value);
  }

  @override
  void dispose() {
    _terminalHeartbeatTimer?.cancel();
    _pdvNoticeTimer?.cancel();
    _pdvNoticeOverlay?.remove();
    _discount.removeListener(_persistOpenCashSession);
    _paymentAmount.removeListener(_persistOpenCashSession);
    _notes.removeListener(_persistOpenCashSession);
    _barcode.dispose();
    _manualSearch.dispose();
    _clientSearch.dispose();
    _discount.dispose();
    _paymentAmount.dispose();
    _notes.dispose();
    _openingCash.dispose();
    _operatorCode.dispose();
    _operatorPin.dispose();
    _withdrawAmount.dispose();
    _withdrawReason.dispose();
    _barcodeFocus.dispose();
    HardwareKeyboard.instance.removeHandler(_handleGlobalPdvKey);
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
      unawaited(_persistPdvProductsCache(products));
      if (mounted) {
        setState(() {
          _products = products;
          _productsLoadError = null;
        });
      }
      final sales = widget.session.can('sales:view')
          ? await _api.listSales(widget.session.token)
          : <Sale>[];
      final operators = await _api.listPdvOperators(widget.session.token);
      final sellers = await _api.listSaleSellers(widget.session.token);
      final fiscalSettings = widget.session.can('fiscal:view')
          ? await _api.getFiscalSettings(widget.session.token)
          : null;
      if (fiscalSettings != null) {
        unawaited(_persistFiscalSettingsCache(fiscalSettings));
      }
      setState(() {
        _clients = clients;
        _sales = sales;
        _operators = operators;
        _sellers = sellers;
        _sellerUserId ??= widget.session.userId;
        if (!_sellers.any((seller) => seller.id == _sellerUserId)) {
          _sellerUserId = _sellers.isNotEmpty ? _sellers.first.id : null;
        }
        _fiscalSettings = fiscalSettings;
      });
      unawaited(_syncPendingOfflineSales());
    } on ApiException catch (error) {
      await _loadCachedPdvProducts();
      await _loadCachedFiscalSettings();
      setState(() => _error = error.message);
    } catch (error) {
      if (!mounted) return;
      await _loadCachedPdvProducts();
      await _loadCachedFiscalSettings();
      if (!mounted) return;
      final message = error is ApiException
          ? error.message
          : 'Não foi possível carregar os dados do PDV.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      setState(() => _error = 'Não foi possível carregar vendas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _reloadProductsForPdv() async {
    try {
      final products = await _api.listProducts(
        widget.session.token,
        active: true,
      );
      unawaited(_persistPdvProductsCache(products));
      if (!mounted) return;
      setState(() {
        _products = products;
        _productsLoadError = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      await _loadCachedPdvProducts();
      setState(() => _productsLoadError = error.message);
    } catch (_) {
      if (!mounted) return;
      await _loadCachedPdvProducts();
      setState(
        () => _productsLoadError = 'Não foi possível carregar os produtos.',
      );
    }
  }

  void _mergeProductsIntoCache(List<Product> products) {
    if (products.isEmpty) return;
    final byId = <int, Product>{
      for (final product in _products) product.id: product,
    };
    for (final product in products) {
      byId[product.id] = product;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => _pdvText(a.name).compareTo(_pdvText(b.name)));
    if (!mounted) return;
    setState(() => _products = merged);
    unawaited(_persistPdvProductsCache(merged));
  }

  void _mergeClientsIntoCache(List<Client> clients) {
    if (clients.isEmpty) return;
    final byId = <int, Client>{
      for (final client in _clients) client.id: client,
    };
    for (final client in clients) {
      byId[client.id] = client;
    }
    final merged = byId.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    if (!mounted) return;
    setState(() => _clients = merged);
  }

  Future<List<Product>> _searchProductsForPdv(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return _products.take(50).toList(growable: false);
    }
    try {
      final online = await _api.listProducts(
        widget.session.token,
        active: true,
        query: trimmed,
        limit: 100,
      );
      _mergeProductsIntoCache(online);
      return online.take(50).toList(growable: false);
    } catch (_) {
      final normalized = trimmed.toLowerCase();
      return _products
          .where((product) {
            final haystack = [
              _pdvText(product.name),
              product.internalCode,
              product.barcode,
              product.purchasePackageBarcode,
              product.ncm,
            ].whereType<String>().join(' ').toLowerCase();
            return haystack.contains(normalized);
          })
          .take(50)
          .toList(growable: false);
    }
  }

  Future<List<Client>> _searchClientsForPdv(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) {
      return _clients.take(80).toList(growable: false);
    }
    try {
      final online = await _api.listClients(
        widget.session.token,
        query: trimmed,
        limit: 100,
      );
      _mergeClientsIntoCache(online);
      return online.take(80).toList(growable: false);
    } catch (_) {
      final normalized = trimmed.toLowerCase();
      return _clients
          .where((client) {
            final haystack = [
              client.name,
              client.documentNumber,
              client.phone,
              client.mobilePhone,
              client.email,
            ].whereType<String>().join(' ').toLowerCase();
            return haystack.contains(normalized);
          })
          .take(80)
          .toList(growable: false);
    }
  }

  Future<void> _refreshAfterSale(Sale sale) async {
    try {
      final products = await _api.listProducts(
        widget.session.token,
        active: true,
      );
      unawaited(_persistPdvProductsCache(products));
      final sales = widget.session.can('sales:view')
          ? await _api.listSales(widget.session.token)
          : _sales;
      if (!mounted) return;
      setState(() {
        _products = products;
        _sales = sales;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(
        () => _error =
            'Venda ${sale.number ?? sale.id} finalizada, mas não foi possível atualizar a tela: ${error.message}',
      );
    } catch (_) {
      if (!mounted) return;
      setState(
        () => _error =
            'Venda ${sale.number ?? sale.id} finalizada, mas não foi possível atualizar a tela.',
      );
    }
  }

  void _showPdvNotice(String message, {bool danger = false}) {
    if (!mounted || message.trim().isEmpty) return;
    _pdvNoticeTimer?.cancel();
    _pdvNoticeOverlay?.remove();
    _pdvNoticeOverlay = OverlayEntry(
      builder: (context) => Positioned(
        top: widget.windowsAppMode ? 82 : 18,
        left: 24,
        right: 24,
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: danger
                        ? const Color(0xFFE11D48)
                        : const Color(0xFF0F766E),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        blurRadius: 18,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 14,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          danger
                              ? Icons.error_outline
                              : Icons.check_circle_outline,
                          color: Colors.white,
                          size: 26,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            message,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                              decoration: TextDecoration.none,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_pdvNoticeOverlay!);
    _pdvNoticeTimer = Timer(const Duration(seconds: 3), () {
      _pdvNoticeOverlay?.remove();
      _pdvNoticeOverlay = null;
    });
    _barcodeFocus.requestFocus();
  }

  void _showRegularNotice(String message, {bool danger = false}) {
    if (!mounted || message.trim().isEmpty) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              danger ? Icons.error_outline : Icons.check_circle_outline,
              color: Colors.white,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        backgroundColor: danger
            ? const Color(0xFFB91C1C)
            : const Color(0xFF135A77),
        margin: const EdgeInsets.fromLTRB(20, 0, 20, 82),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  void _emitPendingPdvErrorNotice() {
    final message = _error;
    if (message == null || message.trim().isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _error != message) return;
      _showPdvNotice(message, danger: true);
      if (mounted && _error == message) {
        setState(() => _error = null);
      }
    });
  }

  Future<bool> _emitFiscalDocumentAfterSale(Sale sale) async {
    if (!_shouldAskConsumerCpf || !widget.session.can('fiscal:emit')) {
      return true;
    }
    try {
      final document = await _api.prepareFiscalDocument(
        widget.session.token,
        saleId: sale.id,
        documentType: 'nfce',
        consumerCpf: sale.consumerCpf,
      );
      final authorized = await _api.authorizeFiscalDocument(
        widget.session.token,
        document.id,
      );
      if (!mounted) return true;
      if (authorized.status == 'authorized' ||
          authorized.status == 'contingency_offline') {
        try {
          if (kIsWeb) {
            final danfe = await _api.getFiscalDanfe(
              widget.session.token,
              authorized.id,
            );
            await fiscal_print.printFiscalPdf(
              filename:
                  'danfe-${authorized.documentType}-${authorized.number ?? authorized.id}.pdf',
              bytes: danfe,
              autoPrint: true,
            );
          } else {
            await fiscal_print.printFiscalNfceSaleReceipt(
              document: authorized,
              sale: sale,
              companyName:
                  _fiscalSettings?.tradeName ??
                  _fiscalSettings?.legalName ??
                  widget.session.companyName,
              companyDocument: _fiscalSettings?.cnpj,
              operatorName: _operatorName,
            );
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  authorized.status == 'authorized'
                      ? 'NFC-e autorizada, mas a impressão automática fiscal falhou. Imprimindo comprovante não fiscal.'
                      : 'NFC-e em contingência, mas a impressão automática fiscal falhou. Imprimindo comprovante não fiscal.',
                ),
              ),
            );
          }
          await _emitNonFiscalReceiptAfterSale(sale);
        }
      }
      final message = authorized.status == 'authorized'
          ? 'NFC-e autorizada: ${authorized.sefazProtocol ?? authorized.accessKey ?? authorized.id}'
          : authorized.status == 'contingency_offline'
          ? 'NFC-e em contingencia offline: imprimir DANFE e transmitir depois em Notas fiscais.'
          : 'NFC-e ${authorized.sefazStatusCode ?? ''}: ${authorized.sefazMessage ?? 'retorno da SEFAZ'}';
      if (!mounted) return true;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return authorized.status == 'authorized' ||
          authorized.status == 'contingency_offline';
    } catch (_) {
      // A venda não deve ser perdida por falha na etapa fiscal preparatoria.
      return false;
    }
  }

  Future<void> _emitNonFiscalReceiptAfterSale(Sale sale) async {
    if (!widget.pdvMode) return;
    await receipt_print.openNonFiscalSaleReceipt(
      sale: sale,
      companyName:
          _fiscalSettings?.tradeName ??
          _fiscalSettings?.legalName ??
          widget.session.companyName,
      companyDocument: _fiscalSettings?.cnpj,
      cashRegisterNumber: sale.cashRegisterNumber ?? _cashRegisterNumber,
      operatorName: _operatorName,
    );
  }

  bool _shouldOpenDrawerForPayments(List<SalePaymentPayload> payments) {
    return widget.pdvMode &&
        payments.any(
          (payment) => payment.method == 'dinheiro' && payment.amount > 0,
        );
  }

  Future<void> _openCashDrawerSilentlyIfNeeded(
    List<SalePaymentPayload> payments,
  ) async {
    if (!_shouldOpenDrawerForPayments(payments)) return;
    try {
      await receipt_print.openCashDrawer(pulseProfile: _drawerPulseProfile);
      await _refreshPrinterStatus();
    } catch (_) {
      // Sem gaveta, sem cabo ou sem suporte do driver: o caixa segue normal.
    }
  }

  Future<void> _openCashDrawerWithFiscalAuthorization() async {
    if (_sensitiveActionOpen || _paymentDialogOpen) return;
    setState(() => _sensitiveActionOpen = true);
    try {
      final authorized = await _requestFiscalAuthorization(
        action: 'authorize_open_cash',
        title: 'Autorizar abertura da gaveta',
      );
      if (!authorized) return;
      try {
        await receipt_print.openCashDrawer(pulseProfile: _drawerPulseProfile);
        await _refreshPrinterStatus();
        if (mounted) {
          _showPdvNotice('Pulso enviado para a gaveta.');
        }
      } catch (_) {
        if (mounted) {
          _showPdvNotice(
            'Nao foi possivel enviar o pulso para a impressora padrao.',
            danger: true,
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _sensitiveActionOpen = false);
      } else {
        _sensitiveActionOpen = false;
      }
    }
  }

  Future<void> _reprintNonFiscalReceipt(Sale sale) async {
    await receipt_print.openNonFiscalSaleReceipt(
      sale: sale,
      companyName:
          _fiscalSettings?.tradeName ??
          _fiscalSettings?.legalName ??
          widget.session.companyName,
      companyDocument: _fiscalSettings?.cnpj,
      cashRegisterNumber: sale.cashRegisterNumber ?? _cashRegisterNumber,
      operatorName: sale.sellerName ?? _operatorName,
    );
  }

  Future<void> _showPrinterDialog() async {
    await _showPrinterAndDrawerDialog();
  }

  Future<void> _showPrinterAndDrawerDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Impressora e gaveta do caixa'),
          content: SizedBox(
            width: 560,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'O PDV Windows imprime na impressora padrao do Windows. '
                  'Para usar a GS-T80C, instale o driver da Goldensky e marque '
                  'ela como impressora padrao em Impressoras e scanners do Windows.\n\n'
                  'A gaveta deve ficar conectada na entrada da impressora. '
                  'O PDV envia um pulso ESC/POS para a impressora abrir a gaveta.',
                ),
                const SizedBox(height: 14),
                Text(
                  'Status: ${_printerConfigured ? 'impressora padrao encontrada' : 'nenhuma impressora padrao encontrada'}.',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 14),
                DropdownButtonFormField<String>(
                  initialValue: _drawerPulseProfile,
                  decoration: const InputDecoration(
                    labelText: 'Pulso da gaveta',
                    border: OutlineInputBorder(),
                    helperText:
                        'Use Padrao primeiro. Se nao abrir, teste Forte, Longo ou Pino 2.',
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'default',
                      child: Text('Padrao - maioria das impressoras'),
                    ),
                    DropdownMenuItem(
                      value: 'strong',
                      child: Text('Forte - gaveta mais pesada'),
                    ),
                    DropdownMenuItem(
                      value: 'long',
                      child: Text('Longo - modelos mais lentos'),
                    ),
                    DropdownMenuItem(
                      value: 'short',
                      child: Text('Curto - modelos sensiveis'),
                    ),
                    DropdownMenuItem(
                      value: 'pin2',
                      child: Text('Pino 2 - alguns modelos'),
                    ),
                  ],
                  onChanged: (value) async {
                    if (value == null) return;
                    setDialogState(() => _drawerPulseProfile = value);
                    await _setDrawerPulseProfile(value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_openCashDrawerWithFiscalAuthorization());
              },
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text('Testar gaveta'),
            ),
            FilledButton.icon(
              onPressed: () async {
                final sale = _buildLocalOfflineSale(
                  localNumber: 'TESTE',
                  payload: SalePayload(
                    clientId: null,
                    source: 'pdv',
                    status: 'finalizada',
                    discountAmount: 0,
                    notes: 'Teste de impressora',
                    items: const [
                      SaleItemPayload(
                        productId: null,
                        barcode: null,
                        description: 'TESTE IMPRESSORA LYNCAR',
                        quantity: 1,
                        unitPrice: 0,
                        discountAmount: 0,
                      ),
                    ],
                    payments: const [
                      SalePaymentPayload(method: 'dinheiro', amount: 0),
                    ],
                  ),
                  payments: const [
                    SalePaymentPayload(method: 'dinheiro', amount: 0),
                  ],
                );
                try {
                  await _emitNonFiscalReceiptAfterSale(sale);
                  await _refreshPrinterStatus();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Teste enviado para a impressora padrao.',
                        ),
                      ),
                    );
                  }
                } catch (error) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Falha ao imprimir: $error')),
                    );
                  }
                }
              },
              icon: const Icon(Icons.print_outlined),
              label: const Text('Imprimir teste'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showLegacyPrinterDialog() async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Impressora do caixa'),
        content: Text(
          'O PDV Windows imprime na impressora padrão do Windows. '
          'Para usar a GS-T80C, instale o driver da Goldensky e marque ela '
          'como impressora padrão em Impressoras e scanners do Windows. '
          'Depois use o botão abaixo para imprimir um teste.\n\n'
          'Status atual: ${_printerConfigured ? 'impressora padrão encontrada' : 'nenhuma impressora padrão encontrada'}.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: () async {
              final sale = _buildLocalOfflineSale(
                localNumber: 'TESTE',
                payload: SalePayload(
                  clientId: null,
                  source: 'pdv',
                  status: 'finalizada',
                  discountAmount: 0,
                  notes: 'Teste de impressora',
                  items: const [
                    SaleItemPayload(
                      productId: null,
                      barcode: null,
                      description: 'TESTE IMPRESSORA LYNCAR',
                      quantity: 1,
                      unitPrice: 0,
                      discountAmount: 0,
                    ),
                  ],
                  payments: const [
                    SalePaymentPayload(method: 'dinheiro', amount: 0),
                  ],
                ),
                payments: const [
                  SalePaymentPayload(method: 'dinheiro', amount: 0),
                ],
              );
              try {
                await _emitNonFiscalReceiptAfterSale(sale);
                await _refreshPrinterStatus();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Teste enviado para a impressora padrão.'),
                    ),
                  );
                }
              } catch (error) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Falha ao imprimir: $error')),
                  );
                }
              }
            },
            icon: const Icon(Icons.print_outlined),
            label: const Text('Imprimir teste'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadCachedPdvProducts() async {
    final raw = await _storage.read(_pdvProductCacheStorageKey);
    if (raw == null) return;
    try {
      final data = jsonDecode(raw) as List<dynamic>;
      final products = data
          .map((item) => Product.fromJson(item as Map<String, dynamic>))
          .where((product) => product.active)
          .toList();
      if (!mounted || products.isEmpty) return;
      setState(() {
        if (_products.isEmpty) {
          _products = products;
        }
      });
    } catch (_) {
      unawaited(_storage.remove(_pdvProductCacheStorageKey));
    }
  }

  Future<void> _persistPdvProductsCache(List<Product> products) async {
    if (!widget.pdvMode || products.isEmpty) return;
    await _storage.write(
      _pdvProductCacheStorageKey,
      jsonEncode([
        for (final product in products) _productToStorageJson(product),
      ]),
    );
  }

  Future<void> _loadCachedFiscalSettings() async {
    final raw = await _storage.read(_pdvFiscalSettingsStorageKey);
    if (raw == null) return;
    try {
      final settings = CompanyFiscalSetting.fromJson(
        jsonDecode(raw) as Map<String, dynamic>,
      );
      if (!mounted) return;
      setState(() => _fiscalSettings ??= settings);
    } catch (_) {
      unawaited(_storage.remove(_pdvFiscalSettingsStorageKey));
    }
  }

  Future<void> _persistFiscalSettingsCache(
    CompanyFiscalSetting settings,
  ) async {
    await _storage.write(
      _pdvFiscalSettingsStorageKey,
      jsonEncode(_fiscalSettingsToStorageJson(settings)),
    );
  }

  void _applyLocalStockOut(SalePayload payload) {
    if (_products.isEmpty) return;
    final quantityByProduct = <int, double>{};
    for (final item in payload.items) {
      final productId = item.productId;
      if (productId == null || item.quantity <= 0) continue;
      quantityByProduct[productId] =
          (quantityByProduct[productId] ?? 0) + item.quantity;
    }
    if (quantityByProduct.isEmpty) return;
    _products = [
      for (final product in _products)
        if (!quantityByProduct.containsKey(product.id))
          product
        else
          Product.fromJson({
            ..._productToStorageJson(product),
            'stock_quantity':
                product.stockQuantity - quantityByProduct[product.id]!,
          }),
    ];
    unawaited(_persistPdvProductsCache(_products));
  }

  Future<List<Map<String, dynamic>>> _readPendingOfflineSales() async {
    final raw = await _storage.read(_pdvOfflineSalesStorageKey);
    if (raw == null) return [];
    try {
      return ((jsonDecode(raw) as List<dynamic>?) ?? [])
          .map((item) => item as Map<String, dynamic>)
          .toList();
    } catch (_) {
      await _storage.remove(_pdvOfflineSalesStorageKey);
      return [];
    }
  }

  Future<void> _writePendingOfflineSales(
    List<Map<String, dynamic>> sales,
  ) async {
    if (sales.isEmpty) {
      await _storage.remove(_pdvOfflineSalesStorageKey);
      return;
    }
    await _storage.write(_pdvOfflineSalesStorageKey, jsonEncode(sales));
  }

  Future<void> _queueOfflineSale({
    required SalePayload payload,
    required List<SalePaymentPayload> payments,
    required bool fiscalPending,
  }) async {
    final pendingSales = await _readPendingOfflineSales();
    final localNumber =
        'OFF-${DateTime.now().millisecondsSinceEpoch.toString()}';
    final offlineClientId =
        '${widget.session.companyCode}-${widget.session.userId ?? 'pdv'}-$localNumber';
    final payloadWithOfflineId = SalePayload(
      clientId: payload.clientId,
      sellerUserId: payload.sellerUserId,
      source: payload.source,
      cashRegisterNumber: payload.cashRegisterNumber,
      status: payload.status,
      discountAmount: payload.discountAmount,
      consumerCpf: payload.consumerCpf,
      notes: payload.notes,
      items: payload.items,
      payments: payload.payments,
      offlineClientId: offlineClientId,
    );
    pendingSales.add({
      'local_number': localNumber,
      'offline_client_id': offlineClientId,
      'created_at': DateTime.now().toIso8601String(),
      'fiscal_pending': fiscalPending,
      'payload': payloadWithOfflineId.toJson(),
    });
    await _writePendingOfflineSales(pendingSales);
    if (!mounted) return;

    final localSale = _buildLocalOfflineSale(
      localNumber: localNumber,
      payload: payloadWithOfflineId,
      payments: payments,
    );
    setState(() {
      _sales = [localSale, ..._sales];
      _applyLocalStockOut(payloadWithOfflineId);
      if (widget.pdvMode) {
        _persistedSaleCount += 1;
        _persistedSessionTotal += localSale.totalAmount;
        for (final payment in payments) {
          _persistedPaymentTotals[payment.method] =
              (_persistedPaymentTotals[payment.method] ?? 0) + payment.amount;
        }
      }
      _cart.clear();
      _discount.text = '0,00';
      _paymentAmount.text = '0,00';
      _notes.clear();
      _clientId = null;
      _consumerCpf = null;
      _consumerDocumentAsked = false;
    });
    _persistOpenCashSession();
    unawaited(_sendTerminalHeartbeat());
    unawaited(_emitNonFiscalReceiptAfterSale(localSale));
    unawaited(_openCashDrawerSilentlyIfNeeded(payments));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          fiscalPending
              ? 'Venda $localNumber salva offline. A NFC-e sera enviada quando a API voltar.'
              : 'Venda $localNumber salva offline. Ela sera sincronizada quando a API voltar.',
        ),
      ),
    );
  }

  Future<void> _syncPendingOfflineSales() async {
    final pendingSales = await _readPendingOfflineSales();
    if (pendingSales.isEmpty) return;
    final remaining = <Map<String, dynamic>>[];
    var synced = 0;
    for (final item in pendingSales) {
      try {
        final payload = _salePayloadFromJson(
          item['payload'] as Map<String, dynamic>,
        );
        final sale = await _api.createSale(widget.session.token, payload);
        final fiscalPending = item['fiscal_pending'] as bool? ?? false;
        if (fiscalPending) {
          final fiscalOk = await _emitFiscalDocumentAfterSale(sale);
          if (!fiscalOk) {
            remaining.add(item);
            continue;
          }
        }
        synced += 1;
      } catch (_) {
        remaining.add(item);
      }
    }
    await _writePendingOfflineSales(remaining);
    if (!mounted || synced == 0) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$synced venda(s) offline sincronizada(s).')),
    );
  }

  Future<void> _restoreOpenCashSession() async {
    if (!widget.pdvMode) return;
    await _storage.remove(_pdvCashSessionKey);
    final raw = await _storage.read(_pdvCashSessionStorageKey);
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
              authorizedByOperatorId: item['authorized_by_operator_id'] as int?,
              authorizedByOperatorName:
                  item['authorized_by_operator_name'] as String?,
            ),
          )
          .toList();
      final cart = ((data['cart'] as List<dynamic>?) ?? [])
          .map((item) => item as Map<String, dynamic>)
          .map((item) {
            try {
              return _CartItem.fromStorageJson(item);
            } catch (_) {
              return null;
            }
          })
          .whereType<_CartItem>()
          .toList();
      if (!mounted) return;
      setState(() {
        _cashOpen = data['cash_open'] as bool? ?? false;
        _cashPaused = data['cash_paused'] as bool? ?? false;
        _cashPausedAt = DateTime.tryParse(
          data['cash_paused_at'] as String? ?? '',
        );
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
        _cart
          ..clear()
          ..addAll(cart);
        _paymentMethod = data['payment_method'] as String? ?? _paymentMethod;
        _clientId = data['client_id'] as int?;
        _sellerUserId = data['seller_user_id'] as int? ?? _sellerUserId;
        _consumerCpf = data['consumer_cpf'] as String?;
        _consumerDocumentAsked =
            data['consumer_document_asked'] as bool? ?? false;
        _discount.text = data['discount_text'] as String? ?? _discount.text;
        _paymentAmount.text =
            data['payment_amount_text'] as String? ?? _paymentAmount.text;
        _notes.text = data['notes'] as String? ?? '';
      });
      widget.onPdvCashOpenChanged?.call(_cashOpen);
    } catch (_) {
      unawaited(_storage.remove(_pdvCashSessionStorageKey));
    }
  }

  void _persistOpenCashSession() {
    if (!widget.pdvMode || !_cashOpen) return;
    unawaited(
      _storage.write(
        _pdvCashSessionStorageKey,
        jsonEncode({
          'cash_open': _cashOpen,
          'cash_register_number': _cashRegisterNumber,
          'cash_paused': _cashPaused,
          'cash_paused_at': _cashPausedAt?.toIso8601String(),
          'opened_at': _cashOpenedAt?.toIso8601String(),
          'opening_amount': _cashOpeningAmount,
          'operator_name': _operatorName,
          'payment_method': _paymentMethod,
          'client_id': _clientId,
          'seller_user_id': _sellerUserId,
          'consumer_cpf': _consumerCpf,
          'consumer_document_asked': _consumerDocumentAsked,
          'discount_text': _discount.text,
          'payment_amount_text': _paymentAmount.text,
          'notes': _notes.text,
          'sale_count': _persistedSaleCount,
          'session_total': _persistedSessionTotal,
          'payment_totals': _persistedPaymentTotals,
          'cart': [for (final item in _cart) item.toStorageJson()],
          'cash_movements': [
            for (final movement in _cashMovements)
              {
                'type': movement.type,
                'amount': movement.amount,
                'reason': movement.reason,
                'created_at': movement.createdAt.toIso8601String(),
                'authorized_by_operator_id': movement.authorizedByOperatorId,
                'authorized_by_operator_name':
                    movement.authorizedByOperatorName,
              },
          ],
        }),
      ),
    );
  }

  void _clearOpenCashSession() {
    unawaited(_storage.remove(_pdvCashSessionStorageKey));
  }

  Future<void> _scanCode() async {
    final parsed = _parseScanInput(_barcode.text);
    if (parsed.code == null) {
      setState(() {
        _scanQuantity = parsed.quantity;
        _error =
            'Quantidade ${formatBrazilianDecimal(parsed.quantity)} pronta para o próximo bip.';
      });
      _barcode.clear();
      _barcodeFocus.requestFocus();
      return;
    }
    final code = parsed.code!;
    if (code.isEmpty) return;
    if (_isScaleBarcode(code) && _products.isEmpty) {
      await _reloadProductsForPdv();
      if (!mounted) return;
    }
    final scaleResult = _parseScaleBarcode(code);
    if (scaleResult != null) {
      await _addProduct(
        scaleResult.product,
        quantity: scaleResult.quantity,
        askWeightedQuantity: false,
      );
      _barcode.clear();
      _barcodeFocus.requestFocus();
      setState(() {
        _error =
            'Etiqueta de balança: ${formatBrazilianDecimal(scaleResult.quantity)} ${scaleResult.product.unit} de ${_pdvText(scaleResult.product.name)}.';
      });
      return;
    }
    try {
      final product = await _api.lookupProductByCode(
        widget.session.token,
        code,
      );
      await _addProduct(
        product,
        quantity: parsed.quantity,
        askWeightedQuantity: !parsed.hasExplicitQuantity,
      );
      _barcode.clear();
      _barcodeFocus.requestFocus();
    } on ApiException catch (error) {
      final cachedProduct = _findCachedProductByCode(code);
      if (cachedProduct != null) {
        await _addProduct(
          cachedProduct,
          quantity: parsed.quantity,
          askWeightedQuantity: !parsed.hasExplicitQuantity,
        );
        _barcode.clear();
        _barcodeFocus.requestFocus();
        _showPdvNotice(
          'Produto encontrado no cache local. Finalize quando a conexão estiver ativa.',
        );
        return;
      }
      _showPdvNotice(error.message, danger: true);
      _barcodeFocus.requestFocus();
    }
  }

  Product? _findCachedProductByCode(String code) {
    final normalized = code.trim().toLowerCase();
    if (normalized.isEmpty) return null;
    for (final product in _products) {
      final values = [
        product.barcode,
        product.internalCode,
        product.purchasePackageBarcode,
      ];
      if (values.any(
        (value) => value != null && value.trim().toLowerCase() == normalized,
      )) {
        return product;
      }
    }
    return null;
  }

  Future<void> _addProduct(
    Product product, {
    double? quantity,
    bool askWeightedQuantity = true,
  }) async {
    var amount = quantity ?? _scanQuantity;
    if (askWeightedQuantity && _isWeightedProduct(product)) {
      final informed = await _showWeightedQuantityDialog(product);
      if (!mounted || informed == null) {
        _barcodeFocus.requestFocus();
        return;
      }
      amount = informed;
    }
    final index = _cart.indexWhere((item) => item.product.id == product.id);
    final wasEmpty = _cart.isEmpty;
    setState(() {
      _error = null;
      if (index >= 0) {
        _cart[index].quantity += amount;
      } else {
        _cart.add(_CartItem(product: product, quantity: amount));
      }
      _scanQuantity = 1;
      _syncPaymentWithTotalIfNeeded();
    });
    if (wasEmpty) {
      unawaited(_askConsumerCpfIfNeeded());
    }
    _persistOpenCashSession();
  }

  bool _isWeightedProduct(Product product) {
    final unit = product.unit.trim().toLowerCase();
    return unit == 'kg' ||
        unit == 'kgs' ||
        unit == 'quilo' ||
        unit == 'quilos' ||
        unit == 'kilograma' ||
        unit == 'kilogramas';
  }

  Future<double?> _showWeightedQuantityDialog(Product product) async {
    final controller = TextEditingController();
    try {
      return showDialog<double>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          String? error;
          void confirm(StateSetter setDialogState) {
            final quantity = parseBrazilianNumber(controller.text);
            if (quantity <= 0) {
              setDialogState(() => error = 'Informe o peso em KG.');
              return;
            }
            Navigator.of(context).pop(quantity);
          }

          return StatefulBuilder(
            builder: (context, setDialogState) {
              return AlertDialog(
                title: const Text('Informar peso do produto'),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _pdvText(product.name),
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Produto vendido por KG. Informe quantos KG entram na venda.',
                        style: TextStyle(color: Colors.blueGrey.shade700),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: controller,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        inputFormatters: const [
                          BrazilianDecimalInputFormatter(),
                        ],
                        onSubmitted: (_) => confirm(setDialogState),
                        decoration: InputDecoration(
                          labelText: 'Peso em KG',
                          hintText: 'Ex.: 0,350',
                          suffixText: 'kg',
                          border: const OutlineInputBorder(),
                          errorText: error,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Preco: ${_money(product.salePrice)} por kg.',
                        style: const TextStyle(
                          color: Color(0xFF0F766E),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  FilledButton(
                    onPressed: () => confirm(setDialogState),
                    child: const Text('Adicionar'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      controller.dispose();
    }
  }

  void _removeItem(_CartItem item) {
    setState(() {
      _cart.remove(item);
      _syncPaymentWithTotalIfNeeded();
    });
    _persistOpenCashSession();
  }

  void _syncPaymentWithTotalIfNeeded() {
    if (_paymentMethod != 'dinheiro') {
      _paymentAmount.text = formatBrazilianMoneyInput(_total);
      return;
    }
  }

  _ScanInput _parseScanInput(String value) {
    final text = value.trim();
    if (text.isEmpty) return const _ScanInput(quantity: 1);
    final withCode = RegExp(
      r'^([0-9]+(?:[,.][0-9]+)?)\s*(?:x|\*)\s*(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (withCode != null) {
      final quantity = parseBrazilianNumber(withCode.group(1)!);
      return _ScanInput(
        quantity: quantity > 0 ? quantity : 1,
        code: withCode.group(2)!.trim(),
        hasExplicitQuantity: true,
      );
    }
    final spaced = RegExp(
      r'^([0-9]+(?:[,.][0-9]+)?)\s+(.+)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (spaced != null) {
      final quantity = parseBrazilianNumber(spaced.group(1)!);
      return _ScanInput(
        quantity: quantity > 0 ? quantity : 1,
        code: spaced.group(2)!.trim(),
        hasExplicitQuantity: true,
      );
    }
    final quantityOnly = RegExp(
      r'^([0-9]+(?:[,.][0-9]+)?)\s*(?:x|\*)$',
      caseSensitive: false,
    ).firstMatch(text);
    if (quantityOnly != null) {
      final quantity = parseBrazilianNumber(quantityOnly.group(1)!);
      return _ScanInput(
        quantity: quantity > 0 ? quantity : 1,
        hasExplicitQuantity: true,
      );
    }
    return _ScanInput(quantity: _scanQuantity, code: text);
  }

  bool _isScaleBarcode(String code) {
    final digits = code.trim();
    return RegExp(r'^\d{13}$').hasMatch(digits) && digits.startsWith('2');
  }

  _ScaleBarcodeResult? _parseScaleBarcode(String code) {
    final digits = code.trim();
    if (!_isScaleBarcode(digits)) return null;
    final candidates = <String>[
      digits.substring(1, 6),
      digits.substring(1, 7),
      digits.substring(1, 5),
      digits.substring(1, 8),
    ];
    for (final candidate in candidates) {
      final product =
          _findCachedProductByCode(candidate) ??
          _findCachedProductByCode(_stripLeadingZeros(candidate));
      if (product == null || !_isWeightedProduct(product)) continue;
      final valueStart = 1 + candidate.length;
      if (valueStart + 5 > digits.length - 1) continue;
      final encoded = double.tryParse(
        digits.substring(valueStart, valueStart + 5),
      );
      if (encoded == null || encoded <= 0) continue;
      final quantityByWeight = encoded / 1000;
      final quantityByPrice = product.salePrice > 0
          ? (encoded / 100) / product.salePrice
          : quantityByWeight;
      final quantity =
          quantityByWeight > 30 && quantityByPrice > 0 && quantityByPrice <= 30
          ? quantityByPrice
          : quantityByWeight;
      if (quantity > 0) {
        return _ScaleBarcodeResult(product: product, quantity: quantity);
      }
    }
    return null;
  }

  String _stripLeadingZeros(String value) {
    final stripped = value.replaceFirst(RegExp(r'^0+'), '');
    return stripped.isEmpty ? '0' : stripped;
  }

  void _focusBarcode() {
    _barcodeFocus.requestFocus();
  }

  bool get _shortcutBlocked {
    return _paymentDialogOpen ||
        _authorizationDialogOpen ||
        _sensitiveActionOpen ||
        _pauseCashDialogOpen ||
        _saving;
  }

  String get _pdvCashSessionStorageKey {
    final userId = widget.session.userId?.toString() ?? 'anonymous';
    return '$_pdvCashSessionKey.${widget.session.companyCode}.$userId';
  }

  String get _pdvCashRegisterNumberStorageKey {
    return '$_pdvCashRegisterNumberKey.${widget.session.companyCode}';
  }

  String get _pdvTerminalStorageKey {
    return '$_pdvTerminalKey.${widget.session.companyCode}';
  }

  String get _cashRegisterLabel => _cashRegisterNumber ?? '--';

  Future<void> _restoreTerminalIdentification() async {
    if (!_usesFixedTerminal) return;
    final savedNumber = await _storage.read(_pdvCashRegisterNumberStorageKey);
    var savedKey = await _storage.read(_pdvTerminalStorageKey);
    savedKey = savedKey?.trim();
    if (savedKey == null || savedKey.isEmpty) {
      savedKey = _generateTerminalKey();
      await _storage.write(_pdvTerminalStorageKey, savedKey);
    }
    if (!mounted) return;
    setState(() {
      _terminalKey = savedKey;
      _cashRegisterNumber = _normalizeCashRegisterNumber(savedNumber);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_ensureCashRegisterNumber());
    });
    if (_cashRegisterNumber != null) {
      unawaited(_registerTerminalSilently());
    }
    _startTerminalHeartbeat();
  }

  void _startTerminalHeartbeat() {
    if (!_usesFixedTerminal || _terminalHeartbeatTimer != null) return;
    _terminalHeartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      unawaited(_sendTerminalHeartbeat());
    });
    unawaited(_sendTerminalHeartbeat());
  }

  String get _terminalCurrentStatus {
    if (!_cashOpen) return 'closed';
    if (_cashPaused) return 'paused';
    return 'open';
  }

  Future<void> _sendTerminalHeartbeat() async {
    final terminalKey = _terminalKey;
    if (!_usesFixedTerminal || terminalKey == null || terminalKey.isEmpty) {
      return;
    }
    try {
      final terminal = await _api.sendPdvTerminalHeartbeat(
        widget.session.token,
        PdvTerminalHeartbeatPayload(
          terminalKey: terminalKey,
          appVersion: _pdvScreenAppVersion,
          deviceLabel: widget.windowsAppMode ? 'PDV Windows' : 'PDV Web',
          currentStatus: _terminalCurrentStatus,
          currentOperatorName: _operatorName,
          cashOpenedAt: _cashOpenedAt,
          currentSessionTotalAmount: _pdvSessionTotal,
        ),
      );
      if (terminal.cashRegisterNumber != _cashRegisterNumber) {
        await _storage.write(
          _pdvCashRegisterNumberStorageKey,
          terminal.cashRegisterNumber,
        );
        if (mounted) {
          setState(() => _cashRegisterNumber = terminal.cashRegisterNumber);
        } else {
          _cashRegisterNumber = terminal.cashRegisterNumber;
        }
      }
    } catch (_) {
      // Heartbeat nao bloqueia o PDV. Se a internet cair, tenta novamente.
    }
  }

  Future<void> _ensureCashRegisterNumber() async {
    if (!_usesFixedTerminal || _cashRegisterNumber != null) return;
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
        await _storage.write(_pdvCashRegisterNumberStorageKey, normalized);
        await _storage.write(_pdvTerminalStorageKey, _terminalKey!);
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
    if (!_usesFixedTerminal || cashNumber == null) return;
    final terminalKey = _terminalKey ?? _generateTerminalKey();
    _terminalKey = terminalKey;
    try {
      final terminal = await _api.registerPdvTerminal(
        widget.session.token,
        PdvTerminalRegisterPayload(
          cashRegisterNumber: cashNumber,
          terminalKey: terminalKey,
          appVersion: _pdvScreenAppVersion,
          deviceLabel: widget.windowsAppMode ? 'PDV Windows' : 'PDV Web',
        ),
      );
      if (terminal.cashRegisterNumber != cashNumber) {
        await _storage.write(
          _pdvCashRegisterNumberStorageKey,
          terminal.cashRegisterNumber,
        );
        if (mounted) {
          setState(() => _cashRegisterNumber = terminal.cashRegisterNumber);
        } else {
          _cashRegisterNumber = terminal.cashRegisterNumber;
        }
      }
      unawaited(_sendTerminalHeartbeat());
    } catch (_) {
      // Nao bloqueia o caixa: se estiver offline, registra na proxima abertura.
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

  String get _pdvProductCacheStorageKey {
    return '$_pdvProductCacheKey.${widget.session.companyCode}';
  }

  String get _pdvFiscalSettingsStorageKey {
    return '$_pdvFiscalSettingsCacheKey.${widget.session.companyCode}';
  }

  String get _pdvOfflineSalesStorageKey {
    final userId = widget.session.userId?.toString() ?? 'anonymous';
    return '$_pdvOfflineSalesKey.${widget.session.companyCode}.$userId';
  }

  bool _handleGlobalPdvKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.pdvMode ||
        !_cashOpen ||
        _shortcutBlocked ||
        !mounted) {
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.f8) {
      if (HardwareKeyboard.instance.isControlPressed) {
        if (!_cashPaused) _showCloseCashDialog();
      } else {
        _cashPaused ? _resumeCash() : _pauseCash();
      }
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyL &&
        HardwareKeyboard.instance.isControlPressed &&
        !_cashPaused) {
      _openClientSearchDialog();
      return true;
    }
    if (_cashPaused) return false;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.f1:
        _openProductSearchDialog();
        return true;
      case LogicalKeyboardKey.f2:
        _focusBarcode();
        return true;
      case LogicalKeyboardKey.f3:
        _openConsumerDocumentDialog();
        return true;
      case LogicalKeyboardKey.f4:
        _applyFiscalDiscount();
        return true;
      case LogicalKeyboardKey.f5:
        _cancelItemWithFiscalSelection();
        return true;
      case LogicalKeyboardKey.f6:
      case LogicalKeyboardKey.f12:
        _openPaymentDialog();
        return true;
      case LogicalKeyboardKey.f7:
        _showWithdrawDialog();
        return true;
      case LogicalKeyboardKey.f9:
        _openCashDrawerWithFiscalAuthorization();
        return true;
      case LogicalKeyboardKey.f11:
        _cancelCurrentSaleWithFiscalAuthorization();
        return true;
      case LogicalKeyboardKey.f10:
        _cancelItemWithFiscalSelection();
        return true;
    }
    return false;
  }

  Future<void> _openPaymentDialog() async {
    if (_paymentDialogOpen) return;
    if (_cart.isEmpty) {
      if (widget.windowsAppMode) {
        _showPdvNotice(
          'Adicione itens antes de finalizar a venda.',
          danger: true,
        );
        _barcodeFocus.requestFocus();
        return;
      }
      setState(() => _error = 'Adicione itens antes de finalizar a venda.');
      _barcodeFocus.requestFocus();
      return;
    }
    setState(() => _paymentDialogOpen = true);
    try {
      final cpfConfirmed = await _askConsumerCpfIfNeeded();
      if (!cpfConfirmed) {
        _barcodeFocus.requestFocus();
        return;
      }
      if (!mounted) return;
      final payments = <SalePaymentPayload>[];
      var paidTotalCents = 0;
      final totalCents = _moneyToCents(_total);
      var nextMethod =
          {
            'dinheiro',
            'pix',
            'debito',
            'credito',
            'crediario',
          }.contains(_paymentMethod)
          ? _paymentMethod
          : 'dinheiro';

      while (paidTotalCents < totalCents) {
        final remainingCents = totalCents - paidTotalCents;
        final remaining = remainingCents / 100;
        final step = payments.length + 1;
        final result = await _showPaymentStepDialog(
          step: step,
          total: _total,
          previousPaid: paidTotalCents / 100,
          remaining: remaining,
          initialMethod: nextMethod,
        );
        if (result == null) {
          _barcodeFocus.requestFocus();
          return;
        }
        payments.add(result.payment);
        paidTotalCents += result.amountCents;
        nextMethod = result.method == 'dinheiro' ? 'pix' : 'dinheiro';
      }

      final crediarioReason =
          payments.any((payment) => payment.method == 'crediario')
          ? _crediarioBlockReason()
          : null;
      if (crediarioReason != null) {
        setState(() => _error = crediarioReason);
        _barcodeFocus.requestFocus();
        return;
      }
      setState(() {
        _paymentMethod = payments.map((payment) => payment.method).join(' + ');
        _paymentAmount.text = formatBrazilianMoneyInput(paidTotalCents / 100);
      });
      _persistOpenCashSession();
      await _finishSale(payments: payments);
    } finally {
      if (mounted) {
        setState(() => _paymentDialogOpen = false);
      } else {
        _paymentDialogOpen = false;
      }
    }
  }

  Future<_PaymentStepDialogResult?> _showPaymentStepDialog({
    required int step,
    required double total,
    required double previousPaid,
    required double remaining,
    required String initialMethod,
  }) async {
    final paymentController = TextEditingController();
    try {
      return await showDialog<_PaymentStepDialogResult>(
        context: context,
        builder: (context) {
          var method = initialMethod;
          var dialogSubmitting = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              final amount = parseBrazilianNumber(paymentController.text);
              final amountCents = _moneyToCents(amount);
              final remainingCents = _moneyToCents(remaining);
              final selectedPaidCents =
                  _moneyToCents(previousPaid) + amountCents;
              final totalCents = _moneyToCents(total);
              final change = method == 'dinheiro'
                  ? _nonNegativeCents(selectedPaidCents - totalCents) / 100
                  : 0.0;
              final nextRemaining =
                  _nonNegativeCents(totalCents - selectedPaidCents) / 100;
              final crediarioReason = method == 'crediario'
                  ? _crediarioBlockReason()
                  : null;
              final exceedsRemaining =
                  method != 'dinheiro' && amountCents > remainingCents;
              final canConfirm =
                  amountCents > 0 &&
                  crediarioReason == null &&
                  !exceedsRemaining &&
                  !dialogSubmitting;

              void selectMethod(String value) {
                setDialogState(() => method = value);
              }

              void confirmPayment() {
                if (!canConfirm) return;
                setDialogState(() => dialogSubmitting = true);
                Navigator.of(context).pop(
                  _PaymentStepDialogResult(
                    method: method,
                    amountCents: amountCents,
                    payment: SalePaymentPayload(
                      method: method,
                      amount: amountCents / 100,
                    ),
                  ),
                );
              }

              return CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.f1): () =>
                      selectMethod('dinheiro'),
                  const SingleActivator(LogicalKeyboardKey.f2): () =>
                      selectMethod('pix'),
                  const SingleActivator(LogicalKeyboardKey.f3): () =>
                      selectMethod('debito'),
                  const SingleActivator(LogicalKeyboardKey.f4): () =>
                      selectMethod('credito'),
                  const SingleActivator(LogicalKeyboardKey.f7): () =>
                      selectMethod('crediario'),
                  const SingleActivator(LogicalKeyboardKey.enter):
                      confirmPayment,
                  const SingleActivator(LogicalKeyboardKey.escape): () =>
                      Navigator.of(context).pop(null),
                },
                child: FocusScope(
                  autofocus: true,
                  child: AlertDialog(
                    title: Text(step == 1 ? 'Pagamento' : 'Pagamento $step'),
                    content: SizedBox(
                      width: 560,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _PaymentTotalLine('Total', total, strong: true),
                          if (previousPaid > 0)
                            _PaymentTotalLine('Já recebido', previousPaid),
                          _PaymentTotalLine('Falta', remaining),
                          if (amount > 0)
                            _PaymentTotalLine('Recebendo agora', amount),
                          if (nextRemaining > 0)
                            _PaymentTotalLine('Restante depois', nextRemaining),
                          _PaymentTotalLine('Troco', change),
                          const SizedBox(height: 18),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(
                                value: 'dinheiro',
                                label: Text('F1 Dinheiro'),
                              ),
                              ButtonSegment(
                                value: 'pix',
                                label: Text('F2 Pix'),
                              ),
                              ButtonSegment(
                                value: 'debito',
                                label: Text('F3 Débito'),
                              ),
                              ButtonSegment(
                                value: 'credito',
                                label: Text('F4 Crédito'),
                              ),
                              ButtonSegment(
                                value: 'crediario',
                                label: Text('F7 Crediário'),
                              ),
                            ],
                            selected: {method},
                            onSelectionChanged: (values) =>
                                selectMethod(values.first),
                          ),
                          if (crediarioReason != null) ...[
                            const SizedBox(height: 10),
                            Text(
                              crediarioReason,
                              style: const TextStyle(
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          if (exceedsRemaining) ...[
                            const SizedBox(height: 10),
                            const Text(
                              'Troco só é permitido em dinheiro.',
                              style: TextStyle(
                                color: Color(0xFFB91C1C),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                          const SizedBox(height: 14),
                          TextField(
                            controller: paymentController,
                            autofocus: true,
                            keyboardType: TextInputType.text,
                            inputFormatters: const [
                              BrazilianMoneyInputFormatter(),
                            ],
                            onChanged: (_) => setDialogState(() {}),
                            decoration: InputDecoration(
                              labelText: method == 'crediario'
                                  ? 'Valor do crediário'
                                  : 'Valor recebido',
                              prefixIcon: const Icon(Icons.payments_outlined),
                              border: const OutlineInputBorder(),
                            ),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Enter confirma este pagamento. Esc cancela. F1 dinheiro, F2 pix, F3 débito, F4 crédito, F7 crediário.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.icon(
                        onPressed: canConfirm ? confirmPayment : null,
                        icon: const Icon(Icons.keyboard_return),
                        label: Text(
                          nextRemaining > 0 ? 'Confirmar' : 'Finalizar',
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      );
    } finally {
      paymentController.dispose();
    }
  }

  bool get _shouldAskConsumerCpf {
    final settings = _fiscalSettings;
    return widget.pdvMode &&
        settings != null &&
        settings.nfceEnabled &&
        settings.pdvNfceEnabled &&
        settings.hasCertificate;
  }

  Future<bool> _askConsumerCpfIfNeeded() async {
    if (!_shouldAskConsumerCpf) {
      _consumerCpf = null;
      _persistOpenCashSession();
      return true;
    }
    if (_consumerDocumentAsked) return true;
    _consumerDocumentAsked = true;
    _persistOpenCashSession();
    return _openConsumerDocumentDialog();
  }

  Future<bool> _openConsumerDocumentDialog() async {
    if (!_shouldAskConsumerCpf) {
      _consumerCpf = null;
      _persistOpenCashSession();
      return true;
    }
    final controller = TextEditingController(text: _consumerCpf ?? '');
    try {
      final result = await showDialog<String?>(
        context: context,
        builder: (context) {
          void confirm() {
            final digits = controller.text.replaceAll(RegExp(r'\D'), '');
            if (digits.isNotEmpty &&
                digits.length != 11 &&
                digits.length != 14) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('CPF/CNPJ deve ter 11 ou 14 dígitos.'),
                ),
              );
              return;
            }
            Navigator.of(context).pop(digits);
          }

          return CallbackShortcuts(
            bindings: {
              const SingleActivator(LogicalKeyboardKey.enter): confirm,
            },
            child: AlertDialog(
              title: const Text('CPF/CNPJ na nota?'),
              content: TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => confirm(),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(14),
                ],
                decoration: const InputDecoration(
                  labelText: 'CPF ou CNPJ do consumidor (opcional)',
                  prefixIcon: Icon(Icons.badge_outlined),
                  border: OutlineInputBorder(),
                  helperText:
                      'Enter confirma. Deixe em branco para emitir sem destinatário.',
                ),
              ),
              actions: [
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(''),
                  child: const Text('Sem CPF/CNPJ'),
                ),
                FilledButton(
                  onPressed: confirm,
                  child: const Text('Confirmar'),
                ),
              ],
            ),
          );
        },
      );
      if (result == null) {
        _consumerCpf = null;
        _persistOpenCashSession();
        return true;
      }
      _consumerCpf = result.isEmpty ? null : result;
      _persistOpenCashSession();
      return true;
    } finally {
      controller.dispose();
    }
  }

  Future<void> _openClientSearchDialog() async {
    if (_clientSearchDialogOpen) return;
    _clientSearchDialogOpen = true;
    _clientSearch.clear();
    var selectedIndex = 0;
    var dialogClients = _clients.take(80).toList(growable: false);
    var searchLoading = false;
    var dialogActive = true;
    var searchSequence = 0;
    Timer? searchDebounce;

    Future<void> runClientSearch(
      String value,
      StateSetter setDialogState,
    ) async {
      final sequence = ++searchSequence;
      setDialogState(() => searchLoading = true);
      final result = await _searchClientsForPdv(value);
      if (!dialogActive || sequence != searchSequence) return;
      setDialogState(() {
        dialogClients = result;
        selectedIndex = 0;
        searchLoading = false;
      });
    }

    try {
      final selected = await showDialog<int?>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            final options = <Client?>[null, ...dialogClients];
            if (selectedIndex >= options.length) {
              selectedIndex = options.isEmpty ? 0 : options.length - 1;
            }

            void move(int delta) {
              if (options.isEmpty) return;
              setDialogState(() {
                selectedIndex = (selectedIndex + delta)
                    .clamp(0, options.length - 1)
                    .toInt();
              });
            }

            void confirm() {
              if (options.isEmpty) return;
              Navigator.of(context).pop(options[selectedIndex]?.id);
            }

            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () =>
                    Navigator.of(context).pop(_clientId),
                const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
                    move(1),
                const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
                    move(-1),
                const SingleActivator(LogicalKeyboardKey.enter): confirm,
                const SingleActivator(LogicalKeyboardKey.numpadEnter): confirm,
              },
              child: AlertDialog(
                title: const Text('Selecionar cliente'),
                content: SizedBox(
                  width: 620,
                  height: 460,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _clientSearch,
                        autofocus: true,
                        textInputAction: TextInputAction.search,
                        onChanged: (value) {
                          setDialogState(() => selectedIndex = 0);
                          searchDebounce?.cancel();
                          searchDebounce = Timer(
                            const Duration(milliseconds: 220),
                            () => runClientSearch(value, setDialogState),
                          );
                        },
                        onTap: () {
                          if (_clientSearch.text.trim().isEmpty) return;
                          unawaited(
                            runClientSearch(_clientSearch.text, setDialogState),
                          );
                        },
                        onSubmitted: (_) => confirm(),
                        decoration: const InputDecoration(
                          labelText: 'Buscar por nome, CPF/CNPJ ou telefone',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          helperText:
                              'Ctrl+L abre. Setas navegam. Enter seleciona. Esc cancela.',
                        ),
                      ),
                      if (searchLoading) ...[
                        const SizedBox(height: 8),
                        const LinearProgressIndicator(minHeight: 2),
                      ],
                      const SizedBox(height: 12),
                      Expanded(
                        child: ListView.builder(
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final client = options[index];
                            final selected = index == selectedIndex;
                            return Card(
                              elevation: selected ? 3 : 0,
                              color: selected
                                  ? const Color(0xFFE0F2FE)
                                  : Colors.white,
                              child: ListTile(
                                selected: selected,
                                leading: Icon(
                                  client == null
                                      ? Icons.person_outline
                                      : Icons.person,
                                ),
                                title: Text(
                                  client?.name ?? 'Consumidor final',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                                subtitle: client == null
                                    ? const Text('Venda sem cliente vinculado')
                                    : Text(
                                        [
                                          client.documentNumber,
                                          client.phone,
                                          client.email,
                                        ].whereType<String>().join(' • '),
                                      ),
                                trailing: selected
                                    ? const Icon(Icons.keyboard_return)
                                    : null,
                                onTap: () =>
                                    Navigator.of(context).pop(client?.id),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(_clientId),
                    child: const Text('Esc  Cancelar'),
                  ),
                  FilledButton.icon(
                    onPressed: confirm,
                    icon: const Icon(Icons.keyboard_return),
                    label: const Text('Enter  Selecionar'),
                  ),
                ],
              ),
            );
          },
        ),
      );
      if (!mounted) return;
      setState(() => _clientId = selected);
      _persistOpenCashSession();
    } finally {
      dialogActive = false;
      searchDebounce?.cancel();
      _clientSearchDialogOpen = false;
      _clientSearch.clear();
      _barcodeFocus.requestFocus();
    }
  }

  Future<void> _openProductSearchDialog() async {
    if (_productSearchDialogOpen) return;
    if (_products.isEmpty) {
      await _reloadProductsForPdv();
      if (!mounted) return;
    }
    if (_products.isEmpty && _productsLoadError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_productsLoadError!)));
      _barcodeFocus.requestFocus();
      return;
    }
    _productSearchDialogOpen = true;
    _manualSearch.clear();
    var dialogProducts = _products.take(50).toList(growable: false);
    var searchLoading = false;
    var dialogActive = true;
    var searchSequence = 0;
    Timer? searchDebounce;

    Future<void> runProductSearch(
      String value,
      StateSetter setDialogState,
    ) async {
      final sequence = ++searchSequence;
      setDialogState(() => searchLoading = true);
      final result = await _searchProductsForPdv(value);
      if (!dialogActive || sequence != searchSequence) return;
      setDialogState(() {
        dialogProducts = result;
        searchLoading = false;
      });
    }

    try {
      final selected = await showDialog<Product>(
        context: context,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Pesquisar produto'),
              content: SizedBox(
                width: 680,
                height: 520,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _manualSearch,
                      autofocus: true,
                      onChanged: (value) {
                        searchDebounce?.cancel();
                        searchDebounce = Timer(
                          const Duration(milliseconds: 220),
                          () => runProductSearch(value, setDialogState),
                        );
                      },
                      onTap: () {
                        if (_manualSearch.text.trim().isEmpty) return;
                        unawaited(
                          runProductSearch(_manualSearch.text, setDialogState),
                        );
                      },
                      decoration: const InputDecoration(
                        labelText: 'Nome, código interno ou código de barras',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    if (searchLoading) ...[
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(minHeight: 2),
                    ],
                    const SizedBox(height: 12),
                    Expanded(
                      child: dialogProducts.isEmpty
                          ? const Center(
                              child: Text('Nenhum produto encontrado.'),
                            )
                          : ListView.separated(
                              itemCount: dialogProducts.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final product = dialogProducts[index];
                                return ListTile(
                                  title: Text(
                                    _pdvText(product.name),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${product.internalCode ?? '-'} | ${product.barcode ?? '-'} | Estoque ${formatBrazilianDecimal(product.stockQuantity)} ${product.unit}',
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
        ),
      );
      if (selected == null || !mounted) return;
      await _addProduct(selected);
    } finally {
      dialogActive = false;
      searchDebounce?.cancel();
      _productSearchDialogOpen = false;
      _manualSearch.clear();
      _barcodeFocus.requestFocus();
    }
  }

  Future<void> _applyFiscalDiscount() async {
    if (_sensitiveActionOpen || _paymentDialogOpen) return;
    if (_cart.isEmpty) {
      if (widget.windowsAppMode) {
        _barcodeFocus.requestFocus();
        return;
      }
      setState(() => _error = 'Adicione itens antes de aplicar desconto.');
      return;
    }
    setState(() => _sensitiveActionOpen = true);
    TextEditingController? controller;
    try {
      final authorized = await _requestFiscalAuthorization(
        action: 'discount',
        title: 'Autorizar desconto',
      );
      if (!authorized || !mounted) return;
      controller = TextEditingController(text: _discount.text);
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Desconto da venda'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.text,
            inputFormatters: const [BrazilianDecimalInputFormatter()],
            decoration: const InputDecoration(
              labelText: 'Valor do desconto',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Aplicar'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final discount = parseBrazilianNumber(controller.text);
      if (discount > _subtotal) {
        setState(() => _error = 'Desconto maior que o subtotal.');
        return;
      }
      setState(() {
        _discount.text = formatBrazilianMoneyInput(discount);
        _error = null;
        _syncPaymentWithTotalIfNeeded();
      });
    } finally {
      controller?.dispose();
      if (mounted) {
        setState(() => _sensitiveActionOpen = false);
      } else {
        _sensitiveActionOpen = false;
      }
    }
  }

  Future<void> _removeItemWithFiscalAuthorization(_CartItem item) async {
    if (_sensitiveActionOpen || _paymentDialogOpen) return;
    setState(() => _sensitiveActionOpen = true);
    try {
      final authorized = await _requestFiscalAuthorization(
        action: 'cancel_sale',
        title: 'Autorizar cancelamento de item',
      );
      if (!authorized || !mounted) return;
      _removeItem(item);
    } finally {
      if (mounted) {
        setState(() => _sensitiveActionOpen = false);
      } else {
        _sensitiveActionOpen = false;
      }
    }
  }

  Future<void> _cancelItemWithFiscalSelection() async {
    if (_sensitiveActionOpen || _paymentDialogOpen) return;
    if (_cart.isEmpty) {
      if (widget.windowsAppMode) {
        _barcodeFocus.requestFocus();
        return;
      }
      setState(() => _error = 'Não ha item para cancelar.');
      _barcodeFocus.requestFocus();
      return;
    }
    setState(() => _sensitiveActionOpen = true);
    try {
      final authorized = await _requestFiscalAuthorization(
        action: 'cancel_sale',
        title: 'Autorizar cancelamento de item',
      );
      if (!authorized || !mounted) return;
      final item = await showDialog<_CartItem>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Cancelar item'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < _cart.length; index++)
                  ListTile(
                    leading: CircleAvatar(child: Text('${index + 1}')),
                    title: Text(_pdvText(_cart[index].product.name)),
                    subtitle: Text(
                      '${formatBrazilianDecimal(_cart[index].quantity)} x ${_money(_cart[index].unitPrice)}',
                    ),
                    trailing: Text(
                      _money(_cart[index].quantity * _cart[index].unitPrice),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    onTap: () => Navigator.of(context).pop(_cart[index]),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Voltar'),
            ),
          ],
        ),
      );
      if (item == null || !mounted) return;
      _removeItem(item);
      _barcodeFocus.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _sensitiveActionOpen = false);
      } else {
        _sensitiveActionOpen = false;
      }
    }
  }

  Future<void> _cancelCurrentSaleWithFiscalAuthorization() async {
    if (_sensitiveActionOpen || _paymentDialogOpen) return;
    if (_cart.isEmpty && _discountValue <= 0) return;
    setState(() => _sensitiveActionOpen = true);
    try {
      final authorized = await _requestFiscalAuthorization(
        action: 'cancel_sale',
        title: 'Autorizar cancelamento da venda',
      );
      if (!authorized || !mounted) return;
      setState(() {
        _cart.clear();
        _discount.text = '0,00';
        _paymentAmount.text = '0,00';
        _notes.clear();
        _clientId = null;
        _consumerCpf = null;
        _consumerDocumentAsked = false;
        _error = null;
      });
      _persistOpenCashSession();
      _barcodeFocus.requestFocus();
    } finally {
      if (mounted) {
        setState(() => _sensitiveActionOpen = false);
      } else {
        _sensitiveActionOpen = false;
      }
    }
  }

  int get _subtotalCents => _cart.fold(
    0,
    (sum, item) => sum + _moneyToCents(item.quantity * item.unitPrice),
  );
  int get _discountCents => _moneyToCents(parseBrazilianNumber(_discount.text));
  int get _totalCents => _nonNegativeCents(_subtotalCents - _discountCents);
  double get _subtotal => _subtotalCents / 100;
  double get _discountValue => parseBrazilianNumber(_discount.text);
  double get _total => _totalCents / 100;
  double get _paid => parseBrazilianNumber(_paymentAmount.text);
  double get _change => (_paid - _total).clamp(0, double.infinity);
  double get _withdrawTotal => _cashMovements
      .where((movement) => movement.type == 'sangria')
      .fold(0, (sum, movement) => sum + movement.amount);
  double get _cashSalesTotal => _paymentTotal('dinheiro');
  double get _expectedCashTotal =>
      (_cashSalesTotal - _withdrawTotal).clamp(0, double.infinity).toDouble();
  double get _pdvSessionTotal => _persistedSessionTotal;

  String get _receiptCompanyName {
    final tradeName = _fiscalSettings?.tradeName?.trim();
    if (tradeName != null && tradeName.isNotEmpty) return tradeName;
    final legalName = _fiscalSettings?.legalName?.trim();
    if (legalName != null && legalName.isNotEmpty) return legalName;
    return widget.session.companyName;
  }

  double _paymentTotal(String method) {
    return _persistedPaymentTotals[method] ?? 0;
  }

  Future<void> _openCashDrawer() async {
    if (!_cashOpeningAuthorized) {
      setState(
        () =>
            _error = 'Libere a abertura com um fiscal antes de abrir o caixa.',
      );
      return;
    }
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
      await Future<void>.delayed(Duration.zero);
      if (!mounted) return;
      setState(() {
        _cashOpen = true;
        _cashPaused = false;
        _cashPausedAt = null;
        _cashOpeningAuthorized = false;
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
      _persistOpenCashSession();
      unawaited(_sendTerminalHeartbeat());
      widget.onPdvCashOpenChanged?.call(true);
      _focusBarcode();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _authorizeCashOpening() async {
    final authorized = await _requestFiscalAuthorization(
      action: 'authorize_open_cash',
      title: 'Liberar abertura do caixa',
    );
    if (!authorized || !mounted) return;
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    setState(() {
      _cashOpeningAuthorized = true;
      _error = null;
    });
  }

  Future<void> _showWithdrawDialog() async {
    if (_sensitiveActionOpen || _paymentDialogOpen) return;
    setState(() => _sensitiveActionOpen = true);
    try {
      final authorized = await _requestFiscalAuthorization(
        action: 'withdrawal',
        title: 'Autorizar sangria',
      );
      if (!authorized) return;
      final fiscalAuthorization = _lastFiscalAuthorization;
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
                  labelText: 'Motivo / observação',
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
        setState(
          () => _error = 'Informe um valor maior que zero para sangria.',
        );
        return;
      }
      final movement = _CashMovement(
        type: 'sangria',
        amount: amount,
        reason: _withdrawReason.text.trim(),
        createdAt: DateTime.now(),
        authorizedByOperatorId: fiscalAuthorization?.operatorId,
        authorizedByOperatorName: fiscalAuthorization?.operatorName,
      );
      setState(() {
        _cashMovements.insert(0, movement);
        _error = null;
      });
      _persistOpenCashSession();
      unawaited(
        receipt_print
            .printCashMovementReceipt(
              type: movement.type,
              amount: movement.amount,
              createdAt: movement.createdAt,
              companyName: _receiptCompanyName,
              companyDocument: _fiscalSettings?.cnpj,
              cashRegisterNumber: _cashRegisterNumber,
              operatorName: _operatorName,
              fiscalName: movement.authorizedByOperatorName,
              reason: movement.reason,
            )
            .catchError((_) {}),
      );
    } finally {
      if (mounted) {
        setState(() => _sensitiveActionOpen = false);
      } else {
        _sensitiveActionOpen = false;
      }
    }
  }

  Future<void> _pauseCash() async {
    if (_cashPaused || !_cashOpen || _shortcutBlocked || _pauseCashDialogOpen) {
      return;
    }
    if (_cart.isNotEmpty) {
      setState(
        () => _error =
            'Finalize ou cancele a venda atual antes de fechar temporariamente o caixa.',
      );
      return;
    }
    _pauseCashDialogOpen = true;
    bool? confirmed;
    final dialogFocus = FocusNode();
    try {
      confirmed = await showDialog<bool>(
        context: context,
        requestFocus: true,
        builder: (dialogContext) => KeyboardListener(
          focusNode: dialogFocus,
          autofocus: true,
          onKeyEvent: (event) {
            if (event is! KeyDownEvent) return;
            final key = event.logicalKey;
            if (key == LogicalKeyboardKey.escape) {
              Navigator.of(dialogContext).pop(false);
            } else if (key == LogicalKeyboardKey.enter ||
                key == LogicalKeyboardKey.numpadEnter ||
                key == LogicalKeyboardKey.f8) {
              Navigator.of(dialogContext).pop(true);
            }
          },
          child: AlertDialog(
            title: const Text('Fechar temporariamente o caixa?'),
            content: const Text(
              'Use esta opção para almoço, intervalo ou troca rápida. '
              'O movimento continuará aberto e não será enviado para fechamento.\n\n'
              'Atalhos: Enter ou F8 confirma, Esc cancela.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(false),
                child: const Text('Esc  Cancelar'),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(dialogContext).pop(true),
                icon: const Icon(Icons.lock_clock_outlined),
                label: const Text('Enter/F8  Fechar temporariamente'),
              ),
            ],
          ),
        ),
      );
    } finally {
      _pauseCashDialogOpen = false;
      dialogFocus.dispose();
    }
    if (confirmed != true || !mounted) return;
    setState(() {
      _cashPaused = true;
      _cashPausedAt = DateTime.now();
      _error = null;
    });
    _persistOpenCashSession();
    unawaited(_sendTerminalHeartbeat());
  }

  Future<void> _resumeCash() async {
    if (!_cashPaused || _authorizationDialogOpen) return;
    setState(() => _authorizationDialogOpen = true);
    final code = TextEditingController();
    final pin = TextEditingController();
    String? error;
    var loading = false;
    try {
      final authorization = await showDialog<PdvAuthorization>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> resume() async {
              if (loading) return;
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                final token =
                    await widget.onEnsurePdvToken?.call() ??
                    widget.session.token;
                if (token.trim().isEmpty) {
                  error = 'Sessão do PDV expirada. Entre novamente.';
                  return;
                }
                final result = await _api.authorizePdvAction(
                  token,
                  code: code.text,
                  pin: pin.text,
                  action: 'open_cash',
                );
                if (context.mounted) Navigator.of(context).pop(result);
              } on ApiException catch (apiError) {
                setDialogState(() => error = apiError.message);
              } finally {
                if (context.mounted) setDialogState(() => loading = false);
              }
            }

            return AlertDialog(
              title: const Text('Reabrir caixa'),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Informe o código e o PIN do operador para continuar o mesmo movimento.',
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: code,
                      autofocus: true,
                      decoration: const InputDecoration(
                        labelText: 'Código do operador',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: pin,
                      obscureText: true,
                      onSubmitted: (_) => resume(),
                      decoration: const InputDecoration(
                        labelText: 'Senha/PIN',
                        border: OutlineInputBorder(),
                      ),
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
                FilledButton.icon(
                  onPressed: loading ? null : resume,
                  icon: const Icon(Icons.lock_open_outlined),
                  label: Text(loading ? 'Validando...' : 'Reabrir (F8)'),
                ),
              ],
            );
          },
        ),
      );
      if (authorization == null || !mounted) return;
      setState(() {
        _cashPaused = false;
        _cashPausedAt = null;
        _operatorName = authorization.operatorName;
        _error = null;
      });
      _persistOpenCashSession();
      unawaited(_sendTerminalHeartbeat());
      _focusBarcode();
    } finally {
      code.dispose();
      pin.dispose();
      if (mounted) {
        setState(() => _authorizationDialogOpen = false);
      } else {
        _authorizationDialogOpen = false;
      }
    }
  }

  Future<void> _showCloseCashDialog() async {
    final authorized = await _requestFiscalAuthorization(
      action: 'authorize_close_cash',
      title: 'Liberar fechamento do caixa',
    );
    if (!authorized || !mounted) return;
    final fiscalAuthorization = _lastFiscalAuthorization;

    final countedCash = TextEditingController();
    final closingNotes = TextEditingController();
    var askedRecount = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> confirmClose() async {
              final countedAmount = parseBrazilianNumber(countedCash.text);
              final countedCents = _moneyToCents(countedAmount);
              final expectedCents = _moneyToCents(_expectedCashTotal);
              final hasDifference = countedCents != expectedCents;

              if (hasDifference && !askedRecount) {
                askedRecount = true;
                countedCash.clear();
                setDialogState(() {});
                await _showCashRecountDialog(context);
                return;
              }

              if (context.mounted) Navigator.of(context).pop(true);
            }

            return AlertDialog(
              title: const Text('Fechamento do caixa'),
              content: SizedBox(
                width: 520,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Informe somente o dinheiro do movimento. O fundo inicial fica registrado, mas não entra na contagem do fechamento.',
                        style: TextStyle(color: Color(0xFF475569)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: countedCash,
                      autofocus: true,
                      keyboardType: TextInputType.text,
                      inputFormatters: const [BrazilianMoneyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Dinheiro do movimento',
                        border: OutlineInputBorder(),
                      ),
                      onSubmitted: (_) => confirmClose(),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: closingNotes,
                      minLines: 2,
                      maxLines: 3,
                      decoration: const InputDecoration(
                        labelText: 'Observação do fechamento',
                        border: OutlineInputBorder(),
                      ),
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
                  onPressed: confirmClose,
                  icon: const Icon(Icons.lock_outline),
                  label: const Text('Fechar caixa'),
                ),
              ],
            );
          },
        );
      },
    );
    if (confirmed != true) {
      countedCash.dispose();
      closingNotes.dispose();
      return;
    }
    final countedAmount = parseBrazilianNumber(countedCash.text);
    setState(() => _saving = true);
    try {
      final closing = await _api.createCashClosing(
        widget.session.token,
        CashClosingPayload(
          cashRegisterNumber: _cashRegisterNumber,
          operatorName: _operatorName,
          openedAt: _cashOpenedAt,
          openingAmount: _cashOpeningAmount,
          expectedCashAmount: _expectedCashTotal,
          countedCashAmount: countedAmount,
          totalSalesAmount: _pdvSessionTotal,
          totalSalesCount: _persistedSaleCount,
          totalWithdrawalAmount: _withdrawTotal,
          totalSupplyAmount: 0,
          authorizedByOperatorId: fiscalAuthorization?.operatorId,
          authorizedByOperatorName: fiscalAuthorization?.operatorName,
          notes: closingNotes.text,
          payments: [
            for (final entry in _persistedPaymentTotals.entries)
              CashClosingPaymentPayload(method: entry.key, amount: entry.value),
          ],
          movements: [
            for (final movement in _cashMovements)
              CashClosingMovementPayload(
                movementType: movement.type,
                amount: movement.amount,
                reason: movement.reason,
                createdAt: movement.createdAt,
                authorizedByOperatorId: movement.authorizedByOperatorId,
                authorizedByOperatorName: movement.authorizedByOperatorName,
              ),
          ],
        ),
      );
      unawaited(
        receipt_print
            .printCashClosingReceipt(
              closing: closing,
              companyName: _receiptCompanyName,
              companyDocument: _fiscalSettings?.cnpj,
              cashRegisterNumber: _cashRegisterNumber,
              fiscalName:
                  closing.authorizedByOperatorName ??
                  fiscalAuthorization?.operatorName,
            )
            .catchError((_) {}),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Fechamento ${closing.number ?? closing.id} enviado para conferência.',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
      countedCash.dispose();
      closingNotes.dispose();
      return;
    } catch (_) {
      setState(() => _error = 'Não foi possível registrar o fechamento.');
      countedCash.dispose();
      closingNotes.dispose();
      return;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    countedCash.dispose();
    closingNotes.dispose();
    setState(() {
      _cashOpen = false;
      _cashPaused = false;
      _cashPausedAt = null;
      _cashOpeningAuthorized = false;
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
      _consumerCpf = null;
      _consumerDocumentAsked = false;
    });
    _clearOpenCashSession();
    unawaited(_sendTerminalHeartbeat());
    widget.onPdvCashOpenChanged?.call(false);
    if (!widget.windowsAppMode) {
      widget.onPdvFullscreenChanged?.call(false);
    }
  }

  Future<void> _showCashRecountDialog(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar recontagem'),
        content: const Text('Conte novamente o dinheiro da gaveta.'),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Recontar'),
          ),
        ],
      ),
    );
  }

  Future<void> _showPdvDiagnostics() {
    final certificateStatus = _fiscalSettings == null
        ? 'Sem acesso fiscal neste usuário'
        : _fiscalSettings!.hasCertificate
        ? 'Certificado A1 configurado'
        : 'Certificado A1 pendente';
    return showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Diagnóstico do PDV'),
        content: SizedBox(
          width: 440,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _DiagnosticLine(
                icon: Icons.wifi_outlined,
                label: 'Internet / API',
                value: _error == null ? 'Online' : 'Verificar conexão',
                ok: _error == null,
              ),
              _DiagnosticLine(
                icon: Icons.print_outlined,
                label: 'Impressora',
                value: 'Preparado para impressora térmica',
                ok: true,
              ),
              _DiagnosticLine(
                icon: Icons.payment_outlined,
                label: 'TEF',
                value: 'Preparado para integração',
                ok: true,
              ),
              _DiagnosticLine(
                icon: Icons.workspace_premium_outlined,
                label: 'Fiscal',
                value: certificateStatus,
                ok: _fiscalSettings?.hasCertificate == true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Fechar'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              _load();
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Verificar agora'),
          ),
        ],
      ),
    );
  }

  Future<void> _finishSale({List<SalePaymentPayload>? payments}) async {
    if (_cart.isEmpty) {
      setState(() => _error = 'Adicione pelo menos um item.');
      return;
    }
    final salePayments =
        payments ?? [SalePaymentPayload(method: _paymentMethod, amount: _paid)];
    final amountPaidCents = salePayments.fold<int>(
      0,
      (sum, payment) => sum + _moneyToCents(payment.amount),
    );
    final totalCents = _moneyToCents(_total);
    if (amountPaidCents < totalCents) {
      setState(() => _error = 'Pagamento menor que o total.');
      return;
    }
    final crediarioReason =
        salePayments.any((payment) => payment.method == 'crediario')
        ? _crediarioBlockReason()
        : null;
    if (crediarioReason != null) {
      setState(() => _error = crediarioReason);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = SalePayload(
      clientId: _clientId,
      sellerUserId: widget.pdvMode ? null : _sellerUserId,
      source: widget.pdvMode ? 'pdv' : 'venda',
      cashRegisterNumber: widget.pdvMode ? _cashRegisterNumber : null,
      status: 'finalizada',
      discountAmount: _discountValue,
      consumerCpf: _consumerCpf,
      notes: widget.pdvMode ? '' : _notes.text,
      items: [
        for (final item in _cart)
          SaleItemPayload(
            productId: item.product.id,
            barcode: item.product.barcode,
            description: _pdvText(item.product.name),
            quantity: item.quantity,
            unitPrice: item.unitPrice,
            discountAmount: 0,
          ),
      ],
      payments: salePayments,
    );
    try {
      final sale = await _api.createSale(widget.session.token, payload);
      if (!mounted) return;
      setState(() {
        _sales = [sale, ..._sales];
        if (widget.pdvMode) {
          _persistedSaleCount += 1;
          _persistedSessionTotal += sale.totalAmount;
          var remainingChange = sale.changeAmount;
          for (final payment in sale.payments) {
            var amountForClosing = payment.amount;
            if (payment.method == 'dinheiro' && remainingChange > 0) {
              final changeApplied = remainingChange > amountForClosing
                  ? amountForClosing
                  : remainingChange;
              amountForClosing -= changeApplied;
              remainingChange -= changeApplied;
            }
            _persistedPaymentTotals[payment.method] =
                (_persistedPaymentTotals[payment.method] ?? 0) +
                amountForClosing;
          }
        }
        _cart.clear();
        _discount.text = '0,00';
        _paymentAmount.text = '0,00';
        _notes.clear();
        _clientId = null;
        _consumerCpf = null;
        _consumerDocumentAsked = false;
      });
      _persistOpenCashSession();
      unawaited(_sendTerminalHeartbeat());
      if (!mounted) return;
      if (_shouldAskConsumerCpf && widget.session.can('fiscal:emit')) {
        unawaited(
          _emitFiscalDocumentAfterSale(sale).then((fiscalPrinted) async {
            if (!fiscalPrinted) {
              await _emitNonFiscalReceiptAfterSale(sale);
            }
          }),
        );
      } else {
        unawaited(_emitNonFiscalReceiptAfterSale(sale));
      }
      unawaited(_openCashDrawerSilentlyIfNeeded(salePayments));
      unawaited(_refreshAfterSale(sale));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Venda ${sale.number ?? sale.id} finalizada.')),
      );
      _barcodeFocus.requestFocus();
    } on ApiException catch (error) {
      if (widget.pdvMode && error.message.toLowerCase().contains('conex')) {
        await _queueOfflineSale(
          payload: payload,
          payments: salePayments,
          fiscalPending:
              _shouldAskConsumerCpf && widget.session.can('fiscal:emit'),
        );
        return;
      }
      setState(() => _error = error.message);
    } catch (_) {
      if (widget.pdvMode) {
        await _queueOfflineSale(
          payload: payload,
          payments: salePayments,
          fiscalPending:
              _shouldAskConsumerCpf && widget.session.can('fiscal:emit'),
        );
        return;
      }
      setState(() => _error = 'Não foi possível finalizar a venda.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _cancelSale(Sale sale) async {
    if (_sensitiveActionOpen || _paymentDialogOpen) return;
    setState(() => _sensitiveActionOpen = true);
    try {
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
    } finally {
      if (mounted) {
        setState(() => _sensitiveActionOpen = false);
      } else {
        _sensitiveActionOpen = false;
      }
    }
  }

  Future<bool> _requestFiscalAuthorization({
    required String action,
    required String title,
  }) async {
    if (_authorizationDialogOpen) return false;
    setState(() => _authorizationDialogOpen = true);
    final code = TextEditingController();
    final pin = TextEditingController();
    String? error;
    var loading = false;
    try {
      _lastFiscalAuthorization = null;
      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => StatefulBuilder(
          builder: (context, setDialogState) {
            Future<void> authorize() async {
              if (loading) return;
              setDialogState(() {
                loading = true;
                error = null;
              });
              try {
                final authorization = await _api.authorizePdvAction(
                  widget.session.token,
                  code: code.text,
                  pin: pin.text,
                  action: action,
                );
                _lastFiscalAuthorization = authorization;
                if (context.mounted) Navigator.of(context).pop(true);
              } on ApiException catch (apiError) {
                setDialogState(() => error = apiError.message);
              } catch (_) {
                setDialogState(() => error = 'Não foi possível autorizar.');
              } finally {
                if (context.mounted) {
                  setDialogState(() => loading = false);
                }
              }
            }

            return CallbackShortcuts(
              bindings: {
                const SingleActivator(LogicalKeyboardKey.escape): () {
                  if (!loading) Navigator.of(context).pop(false);
                },
              },
              child: FocusScope(
                autofocus: true,
                child: AlertDialog(
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
                ),
              ),
            );
          },
        ),
      );
      return result == true;
    } finally {
      if (mounted) {
        setState(() => _authorizationDialogOpen = false);
      } else {
        _authorizationDialogOpen = false;
      }
      code.dispose();
      pin.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreateSale = widget.session.can('sales:create');
    final canCancelSale = widget.session.can('sales:cancel');
    final filteredProducts = _products
        .where((product) {
          final query = _manualSearch.text.trim().toLowerCase();
          if (query.isEmpty) return true;
          return _pdvText(product.name).toLowerCase().contains(query) ||
              (product.barcode ?? '').toLowerCase().contains(query) ||
              (product.internalCode ?? '').toLowerCase().contains(query);
        })
        .take(8)
        .toList();

    if (widget.pdvMode) {
      return _buildPdvView(filteredProducts);
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
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 1020;
                final pdv = _PdvPanel(
                  pdvMode: false,
                  compact: true,
                  barcode: _barcode,
                  barcodeFocus: _barcodeFocus,
                  onScan: _scanCode,
                  manualSearch: _manualSearch,
                  onManualChanged: (_) => setState(() {}),
                  onOpenProductSearch: _openProductSearchDialog,
                  products: filteredProducts,
                  onAddProduct: _addProduct,
                  clients: _clients,
                  clientId: _clientId,
                  onClientChanged: (value) {
                    setState(() => _clientId = value);
                    _persistOpenCashSession();
                  },
                  sellers: _sellers,
                  sellerUserId: _sellerUserId,
                  onSellerChanged: (value) {
                    setState(() => _sellerUserId = value);
                    _persistOpenCashSession();
                  },
                  notes: _notes,
                );
                final cart = _CartPanel(
                  pdvMode: false,
                  compact: true,
                  items: _cart,
                  discount: _discount,
                  paymentMethod: _paymentMethod,
                  subtotal: _subtotal,
                  total: _total,
                  paid: _paid,
                  change: _change,
                  saving: _saving,
                  onChanged: () {
                    setState(() {});
                    _syncPaymentWithTotalIfNeeded();
                    _persistOpenCashSession();
                  },
                  onDiscount: _applyFiscalDiscount,
                  onCancelSale: _cancelCurrentSaleWithFiscalAuthorization,
                  onRemove: _removeItemWithFiscalAuthorization,
                  onFinish: canCreateSale ? _finishSale : null,
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
            const SizedBox(height: 18),
            _SalesHistory(
              sales: _sales,
              clients: _clients,
              canCancel: canCancelSale,
              onCancel: _cancelSale,
              onReprintNonFiscalReceipt: _reprintNonFiscalReceipt,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPdvView(List<Product> filteredProducts) {
    _emitPendingPdvErrorNotice();
    if (!_cashOpen) {
      return _PdvOpenCashScreen(
        windowsAppMode: widget.windowsAppMode,
        openingCash: _openingCash,
        operatorCode: _operatorCode,
        operatorPin: _operatorPin,
        operators: _operators,
        fiscalAuthorized: _cashOpeningAuthorized,
        onAuthorizeFiscal: _authorizeCashOpening,
        saving: _saving,
        onOpen: widget.session.can('sales:create') ? _openCashDrawer : null,
      );
    }
    if (_cashPaused) {
      return _PdvPausedScreen(
        windowsAppMode: widget.windowsAppMode,
        operatorName: _operatorName,
        pausedAt: _cashPausedAt,
        onResume: _resumeCash,
        onCloseCash: _showCloseCashDialog,
      );
    }

    return Container(
      color: widget.windowsAppMode
          ? const Color(0xFFE7EEF8)
          : const Color(0xFFEFF3F8),
      child: Column(
        children: [
          _PdvTopBar(
            windowsAppMode: widget.windowsAppMode,
            openedAt: _cashOpenedAt,
            operatorName: _operatorName,
            cashRegisterNumber: _cashRegisterLabel,
            fullscreen: widget.fullscreen,
            onFullscreenChanged: widget.onPdvFullscreenChanged,
            onRefresh: _load,
            onWithdraw: _showWithdrawDialog,
            onPrinterTap: _showPrinterDialog,
            printerConfigured: _printerConfigured,
            onPauseCash: _pauseCash,
            onCloseCash: _showCloseCashDialog,
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 3),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final wide = constraints.maxWidth >= 900;
                final compact =
                    constraints.maxWidth < 1180 || constraints.maxHeight < 680;
                final pdv = _PdvPanel(
                  pdvMode: true,
                  compact: compact,
                  barcode: _barcode,
                  barcodeFocus: _barcodeFocus,
                  onScan: _scanCode,
                  manualSearch: _manualSearch,
                  onManualChanged: (_) => setState(() {}),
                  onOpenProductSearch: _openProductSearchDialog,
                  products: filteredProducts,
                  onAddProduct: _addProduct,
                  clients: _clients,
                  clientId: _clientId,
                  onClientChanged: (value) {
                    setState(() => _clientId = value);
                    _persistOpenCashSession();
                  },
                  sellers: _sellers,
                  sellerUserId: _sellerUserId,
                  onSellerChanged: (value) {
                    setState(() => _sellerUserId = value);
                    _persistOpenCashSession();
                  },
                  notes: _notes,
                );
                final cart = _CartPanel(
                  pdvMode: true,
                  compact: compact,
                  items: _cart,
                  discount: _discount,
                  paymentMethod: _paymentMethod,
                  subtotal: _subtotal,
                  total: _total,
                  paid: _paid,
                  change: _change,
                  saving: _saving,
                  onChanged: () {
                    setState(() {});
                    _syncPaymentWithTotalIfNeeded();
                    _persistOpenCashSession();
                  },
                  onDiscount: _applyFiscalDiscount,
                  onCancelSale: _cancelCurrentSaleWithFiscalAuthorization,
                  onRemove: _removeItemWithFiscalAuthorization,
                  onFinish: widget.session.can('sales:create')
                      ? _openPaymentDialog
                      : null,
                );
                final commands = _PdvCommandBar(
                  windowsAppMode: widget.windowsAppMode,
                  canFinish: widget.session.can('sales:create') && !_saving,
                  onFocusBarcode: _focusBarcode,
                  onSearchProduct: _openProductSearchDialog,
                  onClientSearch: _openClientSearchDialog,
                  onPayment: _openPaymentDialog,
                  onConsumerDocument: _openConsumerDocumentDialog,
                  onDiscount: _applyFiscalDiscount,
                  onWithdraw: _showWithdrawDialog,
                  onOpenDrawer: _openCashDrawerWithFiscalAuthorization,
                  onPauseCash: _pauseCash,
                  onCloseCash: _showCloseCashDialog,
                  onCancelItem: _cancelItemWithFiscalSelection,
                  onCancelSale: _cancelCurrentSaleWithFiscalAuthorization,
                );
                final padding = compact ? 10.0 : 14.0;
                final Widget content;
                if (widget.windowsAppMode) {
                  final salePanel = _WindowsSalePanel(
                    items: _cart,
                    subtotal: _subtotal,
                    discount: parseBrazilianNumber(_discount.text),
                    total: _total,
                    paid: _paid,
                    change: _change,
                    saving: _saving,
                    onChanged: () {
                      setState(() {});
                      _syncPaymentWithTotalIfNeeded();
                      _persistOpenCashSession();
                    },
                    onRemove: _removeItemWithFiscalAuthorization,
                  );
                  final operationPanel = _WindowsOperationPanel(
                    compact: compact,
                    barcode: _barcode,
                    barcodeFocus: _barcodeFocus,
                    onScan: _scanCode,
                    onOpenProductSearch: _openProductSearchDialog,
                    clients: _clients,
                    clientId: _clientId,
                    onOpenClientSearch: _openClientSearchDialog,
                    total: _total,
                    onPayment: widget.session.can('sales:create')
                        ? _openPaymentDialog
                        : null,
                  );
                  content = wide
                      ? Padding(
                          padding: EdgeInsets.all(padding),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 5, child: operationPanel),
                              SizedBox(width: padding),
                              Expanded(flex: 7, child: salePanel),
                            ],
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.all(padding),
                          children: [
                            operationPanel,
                            SizedBox(height: padding),
                            salePanel,
                          ],
                        );
                } else {
                  content = wide
                      ? Padding(
                          padding: EdgeInsets.all(padding),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Expanded(flex: 6, child: pdv),
                              SizedBox(width: padding),
                              Expanded(flex: 5, child: cart),
                            ],
                          ),
                        )
                      : ListView(
                          padding: EdgeInsets.all(padding),
                          children: [
                            pdv,
                            SizedBox(height: padding),
                            cart,
                          ],
                        );
                }
                final pdvBody = Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.f1):
                        _OpenProductSearchIntent(),
                    SingleActivator(LogicalKeyboardKey.f2):
                        _FocusBarcodeIntent(),
                    SingleActivator(LogicalKeyboardKey.keyL, control: true):
                        _ClientSearchIntent(),
                    SingleActivator(LogicalKeyboardKey.f3):
                        _ConsumerDocumentIntent(),
                    SingleActivator(LogicalKeyboardKey.f4): _DiscountIntent(),
                    SingleActivator(LogicalKeyboardKey.f5): _CancelItemIntent(),
                    SingleActivator(LogicalKeyboardKey.f6): _PaymentIntent(),
                    SingleActivator(LogicalKeyboardKey.f7): _WithdrawIntent(),
                    SingleActivator(LogicalKeyboardKey.f8): _PauseCashIntent(),
                    SingleActivator(LogicalKeyboardKey.f8, control: true):
                        _CloseCashIntent(),
                    SingleActivator(LogicalKeyboardKey.f9): _CancelSaleIntent(),
                    SingleActivator(LogicalKeyboardKey.f10):
                        _CancelItemIntent(),
                    SingleActivator(LogicalKeyboardKey.f11):
                        _CancelSaleIntent(),
                    SingleActivator(LogicalKeyboardKey.f12): _PaymentIntent(),
                  },
                  child: Actions(
                    actions: {
                      _OpenProductSearchIntent:
                          CallbackAction<_OpenProductSearchIntent>(
                            onInvoke: (_) {
                              if (_shortcutBlocked) return null;
                              _openProductSearchDialog();
                              return null;
                            },
                          ),
                      _FocusBarcodeIntent: CallbackAction<_FocusBarcodeIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _focusBarcode();
                          return null;
                        },
                      ),
                      _ClientSearchIntent: CallbackAction<_ClientSearchIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _openClientSearchDialog();
                          return null;
                        },
                      ),
                      _PaymentIntent: CallbackAction<_PaymentIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _openPaymentDialog();
                          return null;
                        },
                      ),
                      _DiscountIntent: CallbackAction<_DiscountIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _applyFiscalDiscount();
                          return null;
                        },
                      ),
                      _ConsumerDocumentIntent:
                          CallbackAction<_ConsumerDocumentIntent>(
                            onInvoke: (_) {
                              if (_shortcutBlocked) return null;
                              _openConsumerDocumentDialog();
                              return null;
                            },
                          ),
                      _CancelItemIntent: CallbackAction<_CancelItemIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _cancelItemWithFiscalSelection();
                          return null;
                        },
                      ),
                      _CancelSaleIntent: CallbackAction<_CancelSaleIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _cancelCurrentSaleWithFiscalAuthorization();
                          return null;
                        },
                      ),
                      _WithdrawIntent: CallbackAction<_WithdrawIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _showWithdrawDialog();
                          return null;
                        },
                      ),
                      _PauseCashIntent: CallbackAction<_PauseCashIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _pauseCash();
                          return null;
                        },
                      ),
                      _CloseCashIntent: CallbackAction<_CloseCashIntent>(
                        onInvoke: (_) {
                          if (_shortcutBlocked) return null;
                          _showCloseCashDialog();
                          return null;
                        },
                      ),
                    },
                    child: Column(
                      children: [
                        Expanded(child: content),
                        commands,
                      ],
                    ),
                  ),
                );
                if (widget.windowsAppMode) {
                  return Material(
                    color: const Color(0xFFF2F6FB),
                    child: DefaultTextStyle.merge(
                      style: GoogleFonts.inter(
                        color: const Color(0xFF0F172A),
                        decoration: TextDecoration.none,
                      ),
                      child: pdvBody,
                    ),
                  );
                }
                return pdvBody;
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _PdvPausedScreen extends StatelessWidget {
  const _PdvPausedScreen({
    required this.windowsAppMode,
    required this.operatorName,
    required this.pausedAt,
    required this.onResume,
    required this.onCloseCash,
  });

  final bool windowsAppMode;
  final String? operatorName;
  final DateTime? pausedAt;
  final VoidCallback onResume;
  final VoidCallback onCloseCash;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.f8): onResume,
        const SingleActivator(LogicalKeyboardKey.f8, control: true):
            onCloseCash,
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: const Color(0xFF07111F),
          body: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 660),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/brand/lyncar_logo_clean.png',
                      width: 250,
                      height: 88,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 24),
                    const Icon(
                      Icons.lock_clock_outlined,
                      color: Color(0xFF38BDF8),
                      size: 64,
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'CAIXA FECHADO',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 38,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      'Movimento preservado • Operador ${operatorName ?? '-'}'
                      '${pausedAt == null ? '' : ' • ${_dateTime(pausedAt!)}'}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFCBD5E1),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Nenhuma venda pode ser feita enquanto o caixa estiver fechado temporariamente.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Color(0xFF94A3B8)),
                    ),
                    const SizedBox(height: 28),
                    FilledButton.icon(
                      onPressed: onResume,
                      icon: const Icon(Icons.lock_open_outlined),
                      label: const Text('Reabrir caixa — F8'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(250, 54),
                        textStyle: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton.icon(
                      onPressed: onCloseCash,
                      icon: const Icon(Icons.point_of_sale_outlined),
                      label: const Text('Encerrar movimento — Ctrl+F8'),
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFFCA5A5),
                      ),
                    ),
                    if (windowsAppMode) ...[
                      const SizedBox(height: 18),
                      const Text(
                        'A janela continua protegida. Use os controles no topo para minimizar ou sair.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PdvOpenCashScreen extends StatelessWidget {
  const _PdvOpenCashScreen({
    required this.windowsAppMode,
    required this.openingCash,
    required this.operatorCode,
    required this.operatorPin,
    required this.operators,
    required this.fiscalAuthorized,
    required this.onAuthorizeFiscal,
    required this.saving,
    required this.onOpen,
  });

  final bool windowsAppMode;
  final TextEditingController openingCash;
  final TextEditingController operatorCode;
  final TextEditingController operatorPin;
  final List<PdvOperator> operators;
  final bool fiscalAuthorized;
  final Future<void> Function() onAuthorizeFiscal;
  final bool saving;
  final Future<void> Function()? onOpen;

  @override
  Widget build(BuildContext context) {
    if (windowsAppMode && !fiscalAuthorized) {
      return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): _PaymentIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): _PaymentIntent(),
        },
        child: Actions(
          actions: {
            _PaymentIntent: CallbackAction<_PaymentIntent>(
              onInvoke: (_) {
                if (!saving) onAuthorizeFiscal();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Container(
              color: const Color(0xFF07111F),
              alignment: Alignment.center,
              child: InkWell(
                focusColor: Colors.transparent,
                hoverColor: Colors.transparent,
                highlightColor: Colors.transparent,
                splashColor: Colors.transparent,
                onTap: saving ? null : onAuthorizeFiscal,
                child: Text(
                  saving ? 'VALIDANDO...' : 'CAIXA FECHADO',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    final shellColor = windowsAppMode
        ? const Color(0xFF07111F)
        : const Color(0xFF0F172A);
    if (windowsAppMode && fiscalAuthorized) {
      return Shortcuts(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): _PaymentIntent(),
          SingleActivator(LogicalKeyboardKey.numpadEnter): _PaymentIntent(),
        },
        child: Actions(
          actions: {
            _PaymentIntent: CallbackAction<_PaymentIntent>(
              onInvoke: (_) {
                if (!saving) onOpen?.call();
                return null;
              },
            ),
          },
          child: Focus(
            autofocus: true,
            child: Container(
              color: shellColor,
              padding: const EdgeInsets.all(28),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 520),
                  child: AppCard(
                    padding: const EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'ABRIR CAIXA',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: operatorCode,
                          autofocus: true,
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
                          keyboardType: TextInputType.text,
                          inputFormatters: const [
                            BrazilianMoneyInputFormatter(),
                          ],
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
                          icon: const Icon(Icons.point_of_sale_outlined),
                          label: Text(saving ? 'Validando...' : 'Abrir caixa'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): _PaymentIntent(),
        SingleActivator(LogicalKeyboardKey.numpadEnter): _PaymentIntent(),
      },
      child: Actions(
        actions: {
          _PaymentIntent: CallbackAction<_PaymentIntent>(
            onInvoke: (_) {
              if (saving) return null;
              if (!fiscalAuthorized) {
                onAuthorizeFiscal();
              } else {
                onOpen?.call();
              }
              return null;
            },
          ),
        },
        child: Focus(
          autofocus: true,
          child: Container(
            color: shellColor,
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
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  windowsAppMode
                                      ? 'ABRIR CAIXA'
                                      : 'Abrir caixa',
                                  style: TextStyle(
                                    fontSize: 30,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  windowsAppMode
                                      ? 'Informe operador e fundo inicial.'
                                      : 'Primeiro libere com um fiscal. Depois informe operador e fundo inicial.',
                                  style: TextStyle(color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      if (!fiscalAuthorized) ...[
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Row(
                                children: [
                                  Icon(
                                    Icons.verified_user_outlined,
                                    color: Color(0xFF2563EB),
                                  ),
                                  SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      'Autorização do fiscal obrigatória para abrir o caixa.',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 14),
                              FilledButton.icon(
                                onPressed: saving ? null : onAuthorizeFiscal,
                                icon: const Icon(Icons.lock_open_outlined),
                                label: Text(
                                  saving
                                      ? 'Validando...'
                                      : 'Liberar com fiscal',
                                ),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(50),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        TextField(
                          controller: operatorCode,
                          autofocus: true,
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
                          keyboardType: TextInputType.text,
                          inputFormatters: const [
                            BrazilianMoneyInputFormatter(),
                          ],
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
                          icon: const Icon(Icons.point_of_sale_outlined),
                          label: Text(saving ? 'Validando...' : 'Abrir caixa'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(54),
                            textStyle: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 14),
                      Text(
                        operators.isEmpty
                            ? 'Cadastre um operador PDV antes de abrir o caixa.'
                            : 'Ações como sangria e cancelamento exigem autorização de fiscal.',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PdvTopBar extends StatelessWidget {
  const _PdvTopBar({
    required this.windowsAppMode,
    required this.openedAt,
    required this.operatorName,
    required this.cashRegisterNumber,
    required this.fullscreen,
    required this.onFullscreenChanged,
    required this.onRefresh,
    required this.onWithdraw,
    required this.onPrinterTap,
    required this.printerConfigured,
    required this.onPauseCash,
    required this.onCloseCash,
  });

  final bool windowsAppMode;
  final DateTime? openedAt;
  final String? operatorName;
  final String cashRegisterNumber;
  final bool fullscreen;
  final ValueChanged<bool>? onFullscreenChanged;
  final VoidCallback onRefresh;
  final VoidCallback onWithdraw;
  final VoidCallback onPrinterTap;
  final bool printerConfigured;
  final VoidCallback onPauseCash;
  final VoidCallback onCloseCash;

  @override
  Widget build(BuildContext context) {
    if (windowsAppMode) {
      return Container(
        height: 72,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: Color(0xFFD8E2EF))),
        ),
        child: Row(
          children: [
            const _WindowsLyncarLogo(),
            const SizedBox(width: 24),
            Text(
              'PDV',
              style: GoogleFonts.inter(
                color: const Color(0xFF60A5FA),
                fontSize: 24,
                fontWeight: FontWeight.w900,
                decoration: TextDecoration.none,
              ),
            ),
            const SizedBox(width: 24),
            _WindowsTopInfo('CAIXA', cashRegisterNumber),
            const SizedBox(width: 18),
            _WindowsTopInfo('OPERADOR', operatorName ?? '-'),
            const Spacer(),
            _WindowsTopInfo(
              'ABERTO',
              openedAt == null ? '-' : _dateTime(openedAt!),
            ),
            const SizedBox(width: 16),
            _WindowsStatusChip(
              Icons.print_outlined,
              'IMPRESSORA',
              active: printerConfigured,
              onTap: onPrinterTap,
            ),
            const SizedBox(width: 10),
            const _WindowsStatusChip(
              Icons.credit_card_outlined,
              'TEF',
              active: false,
            ),
          ],
        ),
      );
    }
    final logo = Container(
      width: 58,
      height: 58,
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Image.asset('assets/brand/LogoPGN.PNG', fit: BoxFit.contain),
    );
    final title = Expanded(
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
            '${windowsAppMode ? 'Aplicativo Windows | ' : ''}Operador ${operatorName ?? '-'} | Caixa aberto em ${openedAt == null ? '-' : _dateTime(openedAt!)}',
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFFCBD5E1)),
          ),
        ],
      ),
    );
    final actions = [
      IconButton.outlined(
        tooltip: 'Atualizar produtos',
        onPressed: onRefresh,
        style: IconButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF334155)),
        ),
        icon: const Icon(Icons.refresh),
      ),
      OutlinedButton.icon(
        onPressed: onFullscreenChanged == null
            ? null
            : () => onFullscreenChanged!(!fullscreen),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF334155)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: Icon(
          fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
          size: 18,
        ),
        label: Text(fullscreen ? 'Sair tela cheia' : 'Tela cheia'),
      ),
      OutlinedButton.icon(
        onPressed: onWithdraw,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF334155)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.south_west, size: 18),
        label: const Text('Sangria'),
      ),
      FilledButton.icon(
        onPressed: onPauseCash,
        icon: const Icon(Icons.lock_clock_outlined, size: 18),
        label: const Text('Caixa fechado (F8)'),
      ),
      OutlinedButton.icon(
        onPressed: onCloseCash,
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Color(0xFF334155)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        icon: const Icon(Icons.point_of_sale_outlined, size: 18),
        label: const Text('Encerrar (Ctrl+F8)'),
      ),
    ];
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 10),
      decoration: BoxDecoration(
        color: windowsAppMode
            ? const Color(0xFF07111F)
            : const Color(0xFF0F172A),
        border: Border(
          bottom: BorderSide(
            color: windowsAppMode
                ? const Color(0xFF15C8D8)
                : const Color(0xFF1D4ED8),
            width: windowsAppMode ? 2 : 1,
          ),
        ),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [logo, const SizedBox(width: 14), title]),
                const SizedBox(height: 10),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final action in actions) ...[
                        action,
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
              ],
            );
          }
          return Row(
            children: [
              logo,
              const SizedBox(width: 14),
              title,
              for (final action in actions) ...[
                const SizedBox(width: 8),
                action,
              ],
            ],
          );
        },
      ),
    );
  }
}

class _PdvDesktopScanBar extends StatelessWidget {
  const _PdvDesktopScanBar({
    required this.barcode,
    required this.barcodeFocus,
    required this.onScan,
    required this.onOpenProductSearch,
  });

  final TextEditingController barcode;
  final FocusNode barcodeFocus;
  final VoidCallback onScan;
  final VoidCallback onOpenProductSearch;

  @override
  Widget build(BuildContext context) {
    return _PdvDarkPanel(
      padding: const EdgeInsets.all(10),
      child: Row(
        children: [
          const Icon(
            Icons.qr_code_scanner_outlined,
            color: Color(0xFF1E3A8A),
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: barcode,
              focusNode: barcodeFocus,
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => onScan(),
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
              decoration: _pdvInputDecoration(
                hintText:
                    'Digite o código de barras, código ou nome do produto...',
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: onScan,
            icon: const Icon(Icons.keyboard_return),
            label: const Text('Enter'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(94, 48),
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filledTonal(
            tooltip: 'Pesquisar produto',
            onPressed: onOpenProductSearch,
            icon: const Icon(Icons.search),
          ),
        ],
      ),
    );
  }
}

class _PdvDesktopSummary extends StatelessWidget {
  const _PdvDesktopSummary({
    required this.clients,
    required this.clientId,
    required this.onClientChanged,
    required this.discount,
    required this.paymentMethod,
    required this.subtotal,
    required this.total,
    required this.paid,
    required this.change,
    required this.saving,
    required this.onPayment,
    required this.onDiscount,
    required this.onCancelSale,
  });

  final List<Client> clients;
  final int? clientId;
  final ValueChanged<int?> onClientChanged;
  final TextEditingController discount;
  final String paymentMethod;
  final double subtotal;
  final double total;
  final double paid;
  final double change;
  final bool saving;
  final VoidCallback? onPayment;
  final VoidCallback onDiscount;
  final VoidCallback onCancelSale;

  @override
  Widget build(BuildContext context) {
    return _PdvDarkPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Cliente', style: _pdvPanelLabelStyle),
          const SizedBox(height: 8),
          DropdownButtonFormField<int?>(
            initialValue: clientId,
            dropdownColor: Colors.white,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
            decoration: _pdvInputDecoration(),
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
          const Divider(height: 20, color: Color(0xFFE2E8F0)),
          _PdvTotalLine('Subtotal', subtotal),
          _PdvTotalLine('Desconto', parseBrazilianNumber(discount.text)),
          const Divider(height: 20, color: Color(0xFFE2E8F0)),
          const Text('Total', style: _pdvPanelLabelStyle),
          Text(
            _money(total),
            textAlign: TextAlign.right,
            style: const TextStyle(
              color: Color(0xFF3B82F6),
              fontSize: 34,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          _PdvTotalLine(
            'Forma atual',
            0,
            textValue: _paymentMethodLabel(paymentMethod),
          ),
          if (paid > 0 || change > 0) ...[
            _PdvTotalLine('Recebido', paid),
            _PdvTotalLine('Troco', change),
          ],
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onPayment,
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Pagamento'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              backgroundColor: const Color(0xFF16A34A),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onDiscount,
                  icon: const Icon(Icons.percent),
                  label: const Text('Desconto'),
                  style: _pdvOutlineButtonStyle(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCancelSale,
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Cancelar'),
                  style: _pdvOutlineButtonStyle(),
                ),
              ),
            ],
          ),
          if (saving) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _PdvDesktopItemsPanel extends StatelessWidget {
  const _PdvDesktopItemsPanel({
    required this.items,
    required this.onChanged,
    required this.onRemove,
  });

  final List<_CartItem> items;
  final VoidCallback onChanged;
  final ValueChanged<_CartItem> onRemove;

  @override
  Widget build(BuildContext context) {
    return _PdvDarkPanel(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          Container(
            height: 50,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Row(
              children: [
                SizedBox(
                  width: 70,
                  child: Text('Qtd', style: _pdvTableHeadStyle),
                ),
                SizedBox(
                  width: 130,
                  child: Text('Código', style: _pdvTableHeadStyle),
                ),
                Expanded(child: Text('Descrição', style: _pdvTableHeadStyle)),
                SizedBox(
                  width: 110,
                  child: Text('Unitário', style: _pdvTableHeadStyle),
                ),
                SizedBox(
                  width: 120,
                  child: Text('Total', style: _pdvTableHeadStyle),
                ),
                SizedBox(width: 48),
              ],
            ),
          ),
          Expanded(
            child: items.isEmpty
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shopping_cart_outlined,
                          color: Color(0xFFCBD5E1),
                          size: 82,
                        ),
                        SizedBox(height: 12),
                        Text(
                          'Nenhum item adicionado',
                          style: TextStyle(
                            color: Color(0xFF0F172A),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Digite o código de barras ou pesquise um produto.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    itemCount: items.length,
                    separatorBuilder: (_, _) =>
                        const Divider(color: Color(0xFFE2E8F0), height: 1),
                    itemBuilder: (context, index) {
                      final item = items[index];
                      return _PdvDesktopItemRow(
                        item: item,
                        onChanged: onChanged,
                        onRemove: onRemove,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PdvDesktopItemRow extends StatelessWidget {
  const _PdvDesktopItemRow({
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final _CartItem item;
  final VoidCallback onChanged;
  final ValueChanged<_CartItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final code = item.product.barcode ?? item.product.internalCode ?? '-';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              formatBrazilianDecimal(item.quantity),
              style: _pdvTableTextStyle,
            ),
          ),
          SizedBox(width: 130, child: Text(code, style: _pdvTableTextStyle)),
          Expanded(
            child: Text(_pdvText(item.product.name), style: _pdvTableTextStyle),
          ),
          SizedBox(
            width: 110,
            child: Text(_money(item.unitPrice), style: _pdvTableTextStyle),
          ),
          SizedBox(
            width: 120,
            child: Text(
              _money(item.quantity * item.unitPrice),
              style: _pdvTableTextStyle,
            ),
          ),
          SizedBox(
            width: 48,
            child: IconButton(
              tooltip: 'Cancelar item',
              onPressed: () => onRemove(item),
              icon: const Icon(Icons.delete_outline),
              color: const Color(0xFFFCA5A5),
            ),
          ),
        ],
      ),
    );
  }
}

class _PdvDarkPanel extends StatelessWidget {
  const _PdvDarkPanel({
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD6E0EA)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _PdvTotalLine extends StatelessWidget {
  const _PdvTotalLine(this.label, this.value, {this.textValue});

  final String label;
  final double value;
  final String? textValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFCBD5E1),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Text(
            textValue ?? _money(value),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({
    required this.icon,
    required this.label,
    required this.value,
    required this.ok,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(
        icon,
        color: ok ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
      ),
      title: Text(label),
      subtitle: Text(value),
      trailing: Icon(
        ok ? Icons.check_circle_outline : Icons.info_outline,
        color: ok ? const Color(0xFF16A34A) : const Color(0xFFF59E0B),
      ),
    );
  }
}

class _WindowsTopInfo extends StatelessWidget {
  const _WindowsTopInfo(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF64748B),
            fontSize: 10,
            fontWeight: FontWeight.w900,
          ),
        ),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF0F172A),
            fontSize: 14,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }
}

class _WindowsLyncarLogo extends StatelessWidget {
  const _WindowsLyncarLogo();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 150,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ShaderMask(
            shaderCallback: (bounds) => const LinearGradient(
              colors: [Color(0xFF0A66D8), Color(0xFF15C8D8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ).createShader(bounds),
            child: Text(
              'Ly',
              style: GoogleFonts.inter(
                color: Colors.white,
                fontSize: 31,
                height: 1,
                fontWeight: FontWeight.w900,
                letterSpacing: -2.2,
                decoration: TextDecoration.none,
              ),
            ),
          ),
          Text(
            'ncar',
            style: GoogleFonts.inter(
              color: const Color(0xFF17233B),
              fontSize: 31,
              height: 1,
              fontWeight: FontWeight.w900,
              letterSpacing: -2.2,
              decoration: TextDecoration.none,
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowsStatusChip extends StatelessWidget {
  const _WindowsStatusChip(
    this.icon,
    this.label, {
    required this.active,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: active ? const Color(0xFFEFFCF5) : const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: active ? const Color(0xFF86EFAC) : const Color(0xFFD8E2EF),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            color: active ? const Color(0xFF16A34A) : const Color(0xFF64748B),
            size: 18,
          ),
          const SizedBox(width: 7),
          Icon(
            Icons.circle,
            color: active ? const Color(0xFF22C55E) : const Color(0xFF94A3B8),
            size: 8,
          ),
          const SizedBox(width: 5),
          Text(
            active ? label : '$label não configurado',
            style: TextStyle(
              color: active ? const Color(0xFF166534) : const Color(0xFF475569),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return content;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: content,
    );
  }
}

class _WindowsSalePanel extends StatelessWidget {
  const _WindowsSalePanel({
    required this.items,
    required this.subtotal,
    required this.discount,
    required this.total,
    required this.paid,
    required this.change,
    required this.saving,
    required this.onChanged,
    required this.onRemove,
  });

  final List<_CartItem> items;
  final double subtotal;
  final double discount;
  final double total;
  final double paid;
  final double change;
  final bool saving;
  final VoidCallback onChanged;
  final ValueChanged<_CartItem> onRemove;

  @override
  Widget build(BuildContext context) {
    return _WindowsPdvPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _WindowsSectionTitle('ITENS DA VENDA'),
          const SizedBox(height: 10),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFF8FBFF),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFB9CBE2), width: 1.1),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF1E3A5F).withValues(alpha: 0.06),
                    blurRadius: 12,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const _WindowsItemsHeader(),
                  Expanded(
                    child: items.isEmpty
                        ? const Center(
                            child: Text(
                              'SEM ITENS',
                              style: TextStyle(
                                color: Color(0xFF94A3B8),
                                fontSize: 28,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          )
                        : ListView.separated(
                            itemCount: items.length,
                            separatorBuilder: (context, index) => const Divider(
                              height: 1,
                              color: Color(0xFFE2E8F0),
                            ),
                            itemBuilder: (context, index) {
                              final item = items[index];
                              return _WindowsItemRow(
                                item: item,
                                onChanged: onChanged,
                                onRemove: onRemove,
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _WindowsSmallTotal('ITENS', items.length.toString()),
              const SizedBox(width: 10),
              _WindowsSmallTotal(
                'SUBTOTAL',
                _money(subtotal),
                alignRight: true,
              ),
              if (discount > 0) ...[
                const SizedBox(width: 10),
                _WindowsSmallTotal(
                  'DESCONTO',
                  _money(discount),
                  alignRight: true,
                ),
              ],
              const SizedBox(width: 10),
              Expanded(
                child: _WindowsSmallTotal(
                  'TOTAL',
                  _money(total),
                  alignRight: true,
                  strong: true,
                ),
              ),
            ],
          ),
          if (paid > 0 || change > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _WindowsSmallTotal(
                    'RECEBIDO',
                    _money(paid),
                    alignRight: true,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _WindowsSmallTotal(
                    'TROCO',
                    _money(change),
                    alignRight: true,
                  ),
                ),
              ],
            ),
          ],
          if (saving) ...[
            const SizedBox(height: 10),
            const LinearProgressIndicator(minHeight: 3),
          ],
        ],
      ),
    );
  }
}

class _WindowsOperationPanel extends StatelessWidget {
  const _WindowsOperationPanel({
    required this.compact,
    required this.barcode,
    required this.barcodeFocus,
    required this.onScan,
    required this.onOpenProductSearch,
    required this.clients,
    required this.clientId,
    required this.onOpenClientSearch,
    required this.total,
    required this.onPayment,
  });

  final bool compact;
  final TextEditingController barcode;
  final FocusNode barcodeFocus;
  final VoidCallback onScan;
  final VoidCallback onOpenProductSearch;
  final List<Client> clients;
  final int? clientId;
  final VoidCallback onOpenClientSearch;
  final double total;
  final VoidCallback? onPayment;

  @override
  Widget build(BuildContext context) {
    return _WindowsPdvPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _WindowsSectionTitle('CÓDIGO / BUSCA'),
          const SizedBox(height: 10),
          TextField(
            controller: barcode,
            focusNode: barcodeFocus,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => onScan(),
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
            decoration: _windowsInputDecoration(
              hintText: 'Bipe ou digite o produto',
              prefixIcon: Icons.qr_code_scanner_outlined,
              suffixIcon: IconButton(
                tooltip: 'Confirmar',
                onPressed: onScan,
                icon: const Icon(Icons.keyboard_return),
              ),
            ),
          ),
          const SizedBox(height: 10),
          OutlinedButton.icon(
            onPressed: onOpenProductSearch,
            icon: const Icon(Icons.search),
            label: const Text('F1  PESQUISAR PRODUTO'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: const Color(0xFF1D4ED8),
              side: const BorderSide(color: Color(0xFF2563EB)),
              textStyle: const TextStyle(fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _WindowsClientSelector(
            clients: clients,
            clientId: clientId,
            onOpen: onOpenClientSearch,
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            decoration: BoxDecoration(
              color: const Color(0xFFF3F7FC),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFC8D8EA)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'TOTAL DA VENDA',
                  style: TextStyle(
                    color: Color(0xFF1D4ED8),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  _money(total),
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 48,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: onPayment,
            icon: const Icon(Icons.point_of_sale_outlined),
            label: const Text('F12  FINALIZAR / PAGAMENTO'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              backgroundColor: const Color(0xFF1D4ED8),
              foregroundColor: Colors.white,
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w900,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowsClientSelector extends StatelessWidget {
  const _WindowsClientSelector({
    required this.clients,
    required this.clientId,
    required this.onOpen,
  });

  final List<Client> clients;
  final int? clientId;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    Client? selected;
    for (final client in clients) {
      if (client.id == clientId) {
        selected = client;
        break;
      }
    }
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: _windowsInputDecoration(
          labelText: 'Cliente  •  Ctrl+L',
          suffixIcon: const Icon(Icons.keyboard_arrow_down),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.person_outline,
              size: 18,
              color: Color(0xFF64748B),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                selected?.name ?? 'Consumidor final',
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF0F172A),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowsPdvPanel extends StatelessWidget {
  const _WindowsPdvPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFFBFDFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFB9CBE2), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF1E3A5F).withValues(alpha: 0.13),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _WindowsSectionTitle extends StatelessWidget {
  const _WindowsSectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF1D4ED8),
        fontSize: 16,
        fontWeight: FontWeight.w900,
      ),
    );
  }
}

class _WindowsItemsHeader extends StatelessWidget {
  const _WindowsItemsHeader();

  @override
  Widget build(BuildContext context) {
    const style = TextStyle(
      color: Color(0xFF334155),
      fontSize: 12,
      fontWeight: FontWeight.w900,
    );
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: const BoxDecoration(
        color: Color(0xFFDCEBFF),
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: Color(0xFFC2D4EA))),
      ),
      child: const Row(
        children: [
          SizedBox(width: 110, child: Text('CÓDIGO', style: style)),
          Expanded(flex: 4, child: Text('PRODUTO', style: style)),
          SizedBox(width: 90, child: Text('QTDE.', style: style)),
          SizedBox(width: 100, child: Text('UNIT.', style: style)),
          SizedBox(
            width: 110,
            child: Text('TOTAL', textAlign: TextAlign.right, style: style),
          ),
          SizedBox(width: 42),
        ],
      ),
    );
  }
}

class _WindowsItemRow extends StatelessWidget {
  const _WindowsItemRow({
    required this.item,
    required this.onChanged,
    required this.onRemove,
  });

  final _CartItem item;
  final VoidCallback onChanged;
  final ValueChanged<_CartItem> onRemove;

  @override
  Widget build(BuildContext context) {
    final code = item.product.barcode?.isNotEmpty == true
        ? item.product.barcode!
        : item.product.internalCode ?? '-';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          SizedBox(
            width: 110,
            child: Text(code, style: const TextStyle(color: Color(0xFF0F172A))),
          ),
          Expanded(
            flex: 4,
            child: Text(
              _pdvText(item.product.name),
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          SizedBox(
            width: 90,
            child: Row(
              children: [
                InkWell(
                  onTap: () {
                    if (item.quantity > 1) item.quantity -= 1;
                    onChanged();
                  },
                  child: const Icon(
                    Icons.remove,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                ),
                Expanded(
                  child: Text(
                    formatBrazilianDecimal(item.quantity),
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Color(0xFF0F172A)),
                  ),
                ),
                InkWell(
                  onTap: () {
                    item.quantity += 1;
                    onChanged();
                  },
                  child: const Icon(
                    Icons.add,
                    size: 18,
                    color: Color(0xFF2563EB),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            width: 100,
            child: Text(
              _money(item.unitPrice),
              style: const TextStyle(color: Color(0xFF0F172A)),
            ),
          ),
          SizedBox(
            width: 110,
            child: Text(
              _money(item.quantity * item.unitPrice),
              textAlign: TextAlign.right,
              style: const TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: IconButton(
              tooltip: 'F10 cancelar item',
              onPressed: () => onRemove(item),
              icon: const Icon(Icons.close, color: Color(0xFFF87171)),
            ),
          ),
        ],
      ),
    );
  }
}

class _WindowsSmallTotal extends StatelessWidget {
  const _WindowsSmallTotal(
    this.label,
    this.value, {
    this.alignRight = false,
    this.strong = false,
  });

  final String label;
  final String value;
  final bool alignRight;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: strong ? const Color(0xFFEAF2FF) : const Color(0xFFF3F7FC),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: strong ? const Color(0xFF93BDF8) : const Color(0xFFC8D8EA),
          width: strong ? 1.4 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: alignRight
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF94A3B8),
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: strong ? const Color(0xFF2563EB) : const Color(0xFF0F172A),
              fontSize: strong ? 20 : 16,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

InputDecoration _windowsInputDecoration({
  String? labelText,
  String? hintText,
  IconData? prefixIcon,
  Widget? suffixIcon,
}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    prefixIcon: prefixIcon == null ? null : Icon(prefixIcon),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: const Color(0xFFF8FAFC),
    labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
    hintStyle: const TextStyle(color: Color(0xFF94A3B8)),
    prefixIconColor: const Color(0xFF2563EB),
    suffixIconColor: const Color(0xFF2563EB),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFD8E2EF)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF60A5FA), width: 1.5),
    ),
  );
}

class _PdvCommandBar extends StatelessWidget {
  const _PdvCommandBar({
    required this.windowsAppMode,
    required this.canFinish,
    required this.onFocusBarcode,
    required this.onSearchProduct,
    required this.onClientSearch,
    required this.onPayment,
    required this.onConsumerDocument,
    required this.onDiscount,
    required this.onWithdraw,
    required this.onOpenDrawer,
    required this.onPauseCash,
    required this.onCloseCash,
    required this.onCancelItem,
    required this.onCancelSale,
  });

  final bool windowsAppMode;
  final bool canFinish;
  final VoidCallback onFocusBarcode;
  final VoidCallback onSearchProduct;
  final VoidCallback onClientSearch;
  final VoidCallback onPayment;
  final VoidCallback onConsumerDocument;
  final VoidCallback onDiscount;
  final VoidCallback onWithdraw;
  final VoidCallback onOpenDrawer;
  final VoidCallback onPauseCash;
  final VoidCallback onCloseCash;
  final VoidCallback onCancelItem;
  final VoidCallback onCancelSale;

  @override
  Widget build(BuildContext context) {
    if (windowsAppMode) {
      return Container(
        padding: const EdgeInsets.fromLTRB(14, 7, 14, 8),
        decoration: const BoxDecoration(
          color: Color(0xFFEAF2FF),
          border: Border(top: BorderSide(color: Color(0xFFD8E2EF))),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _CommandChip(
                shortcut: 'F1',
                label: 'Produto',
                color: const Color(0xFF2563EB),
                onPressed: onSearchProduct,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F2',
                label: 'Código',
                color: const Color(0xFF0EA5E9),
                onPressed: onFocusBarcode,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'Ctrl+L',
                label: 'Cliente',
                color: const Color(0xFF0284C7),
                onPressed: onClientSearch,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F3',
                label: 'CPF/CNPJ',
                color: const Color(0xFF6366F1),
                onPressed: onConsumerDocument,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F4',
                label: 'Desconto',
                color: const Color(0xFFF59E0B),
                onPressed: onDiscount,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F6/F12',
                label: 'Pagamento',
                color: const Color(0xFF22C55E),
                onPressed: canFinish ? onPayment : null,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F7',
                label: 'Sangria',
                color: const Color(0xFF0F766E),
                onPressed: onWithdraw,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F9',
                label: 'Gaveta',
                color: const Color(0xFF0E7490),
                onPressed: onOpenDrawer,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F8',
                label: 'Caixa fechado',
                color: const Color(0xFF155E75),
                onPressed: onPauseCash,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'Ctrl+F8',
                label: 'Encerrar',
                color: const Color(0xFF7F1D1D),
                onPressed: onCloseCash,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F10',
                label: 'Canc. item',
                color: const Color(0xFFEF4444),
                onPressed: onCancelItem,
                compact: true,
              ),
              _CommandChip(
                shortcut: 'F11',
                label: 'Canc. venda',
                color: const Color(0xFFB91C1C),
                onPressed: onCancelSale,
                compact: true,
              ),
            ],
          ),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      decoration: const BoxDecoration(
        color: Color(0xFF07111F),
        border: Border(top: BorderSide(color: Color(0xFF1E3A5F))),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _CommandChip(
              shortcut: 'F2',
              label: 'Produto',
              color: const Color(0xFF0EA5E9),
              onPressed: onFocusBarcode,
            ),
            _CommandChip(
              shortcut: 'F3',
              label: 'CPF/CNPJ',
              color: const Color(0xFF6366F1),
              onPressed: onConsumerDocument,
            ),
            _CommandChip(
              shortcut: 'F4',
              label: 'Desconto',
              color: const Color(0xFFF59E0B),
              onPressed: onDiscount,
            ),
            _CommandChip(
              shortcut: 'F5',
              label: 'Cancelar item',
              color: const Color(0xFFEF4444),
              onPressed: onCancelItem,
            ),
            _CommandChip(
              shortcut: 'F6',
              label: 'Pagamento',
              color: const Color(0xFF22C55E),
              onPressed: canFinish ? onPayment : null,
            ),
            _CommandChip(
              shortcut: 'F9',
              label: 'Cancelar venda',
              color: const Color(0xFFB91C1C),
              onPressed: onCancelSale,
            ),
            _CommandChip(
              shortcut: 'F8',
              label: 'Caixa fechado',
              color: const Color(0xFF155E75),
              onPressed: onPauseCash,
            ),
            _CommandChip(
              shortcut: 'Ctrl+F8',
              label: 'Encerrar caixa',
              color: const Color(0xFF7F1D1D),
              onPressed: onCloseCash,
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandChip extends StatelessWidget {
  const _CommandChip({
    required this.shortcut,
    required this.label,
    required this.color,
    required this.onPressed,
    this.compact = false,
  });

  final String shortcut;
  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          disabledBackgroundColor: const Color(0xFF334155),
          foregroundColor: Colors.white,
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 10 : 14,
            vertical: compact ? 8 : 10,
          ),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  shortcut,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ),
            SizedBox(width: compact ? 7 : 9),
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: compact ? 12 : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PaymentTotalLine extends StatelessWidget {
  const _PaymentTotalLine(this.label, this.value, {this.strong = false});

  final String label;
  final double value;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: const Color(0xFF475569),
                fontSize: strong ? 18 : 14,
              ),
            ),
          ),
          Text(
            _money(value),
            style: TextStyle(
              fontSize: strong ? 28 : 16,
              fontWeight: FontWeight.w900,
              color: strong ? const Color(0xFF1D4ED8) : const Color(0xFF0F172A),
            ),
          ),
        ],
      ),
    );
  }
}

class _FocusBarcodeIntent extends Intent {
  const _FocusBarcodeIntent();
}

class _OpenProductSearchIntent extends Intent {
  const _OpenProductSearchIntent();
}

class _ClientSearchIntent extends Intent {
  const _ClientSearchIntent();
}

class _PaymentIntent extends Intent {
  const _PaymentIntent();
}

class _WithdrawIntent extends Intent {
  const _WithdrawIntent();
}

class _CloseCashIntent extends Intent {
  const _CloseCashIntent();
}

class _PauseCashIntent extends Intent {
  const _PauseCashIntent();
}

class _DiscountIntent extends Intent {
  const _DiscountIntent();
}

class _ConsumerDocumentIntent extends Intent {
  const _ConsumerDocumentIntent();
}

class _CancelItemIntent extends Intent {
  const _CancelItemIntent();
}

class _CancelSaleIntent extends Intent {
  const _CancelSaleIntent();
}

class _PaymentStepDialogResult {
  const _PaymentStepDialogResult({
    required this.method,
    required this.amountCents,
    required this.payment,
  });

  final String method;
  final int amountCents;
  final SalePaymentPayload payment;
}

class _PdvPanel extends StatelessWidget {
  const _PdvPanel({
    required this.pdvMode,
    required this.compact,
    required this.barcode,
    required this.barcodeFocus,
    required this.onScan,
    required this.manualSearch,
    required this.onManualChanged,
    required this.onOpenProductSearch,
    required this.products,
    required this.onAddProduct,
    required this.clients,
    required this.clientId,
    required this.onClientChanged,
    required this.sellers,
    required this.sellerUserId,
    required this.onSellerChanged,
    required this.notes,
  });

  final bool pdvMode;
  final bool compact;
  final TextEditingController barcode;
  final FocusNode barcodeFocus;
  final VoidCallback onScan;
  final TextEditingController manualSearch;
  final ValueChanged<String> onManualChanged;
  final VoidCallback onOpenProductSearch;
  final List<Product> products;
  final ValueChanged<Product> onAddProduct;
  final List<Client> clients;
  final int? clientId;
  final ValueChanged<int?> onClientChanged;
  final List<SaleSeller> sellers;
  final int? sellerUserId;
  final ValueChanged<int?> onSellerChanged;
  final TextEditingController notes;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(compact ? 18 : 24),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Leitura de produtos',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
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
                hintText: 'Use 3*código, 3xcódigo ou 3* antes de bipar',
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
            if (!pdvMode) ...[
              const SizedBox(height: 12),
              DropdownButtonFormField<int?>(
                initialValue: sellerUserId,
                decoration: const InputDecoration(
                  labelText: 'Vendedor',
                  border: OutlineInputBorder(),
                ),
                items: [
                  for (final seller in sellers)
                    DropdownMenuItem(
                      value: seller.id,
                      child: Text(
                        '${seller.sellerCode ?? 'V${seller.id}'} - ${seller.name}',
                      ),
                    ),
                ],
                onChanged: sellers.isEmpty ? null : onSellerChanged,
              ),
            ],
            const SizedBox(height: 12),
            if (pdvMode) ...[
              OutlinedButton.icon(
                onPressed: onOpenProductSearch,
                icon: const Icon(Icons.search),
                label: const Text('Pesquisar produto no estoque'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  alignment: Alignment.centerLeft,
                  textStyle: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ] else ...[
              TextField(
                controller: manualSearch,
                onChanged: onManualChanged,
                decoration: const InputDecoration(
                  labelText: 'Buscar produto manualmente',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              for (final product in products)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(_pdvText(product.name)),
                  subtitle: Text(
                    '${product.internalCode ?? '-'} | ${product.barcode ?? '-'} | Estoque ${formatBrazilianDecimal(product.stockQuantity)} ${product.unit}',
                  ),
                  trailing: FilledButton.icon(
                    onPressed: () => onAddProduct(product),
                    icon: const Icon(Icons.add),
                    label: const Text('Adicionar'),
                  ),
                ),
            ],
            if (!pdvMode) ...[
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
          ],
        ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    this.pdvMode = false,
    this.compact = false,
    required this.items,
    required this.discount,
    required this.paymentMethod,
    required this.subtotal,
    required this.total,
    required this.paid,
    required this.change,
    required this.saving,
    required this.onChanged,
    required this.onDiscount,
    required this.onCancelSale,
    required this.onRemove,
    required this.onFinish,
  });

  final bool pdvMode;
  final bool compact;
  final List<_CartItem> items;
  final TextEditingController discount;
  final String paymentMethod;
  final double subtotal;
  final double total;
  final double paid;
  final double change;
  final bool saving;
  final VoidCallback onChanged;
  final VoidCallback onDiscount;
  final VoidCallback onCancelSale;
  final ValueChanged<_CartItem> onRemove;
  final VoidCallback? onFinish;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: EdgeInsets.all(compact ? 16 : (pdvMode ? 24 : 18)),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Venda atual',
              style: TextStyle(
                fontSize: compact ? 18 : 22,
                fontWeight: FontWeight.w900,
              ),
            ),
            SizedBox(height: compact ? 8 : 10),
            if (items.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('Nenhum item na venda.'),
              )
            else
              for (final item in items)
                _CartItemTile(
                  item: item,
                  onChanged: onChanged,
                  onRemove: onRemove,
                ),
            Divider(height: compact ? 18 : 26),
            _MoneyRow('Subtotal', subtotal),
            if (parseBrazilianNumber(discount.text) > 0)
              _MoneyRow('Desconto', -parseBrazilianNumber(discount.text)),
            SizedBox(height: compact ? 10 : 14),
            _MoneyRow('Total', total, large: true, pdvMode: pdvMode),
            _MoneyRow(
              'Forma atual',
              0,
              textValue: _paymentMethodLabel(paymentMethod),
            ),
            const SizedBox(height: 8),
            _PdvHintLine(
              icon: Icons.keyboard_outlined,
              text: 'F3 CPF/CNPJ. F6 pagamento. F4 desconto. F5 cancela item.',
            ),
            if (paid > 0 || change > 0) ...[
              const SizedBox(height: 10),
              _MoneyRow('Ultimo recebido', paid),
              _MoneyRow('Troco', change),
            ],
            if (saving) ...[
              const SizedBox(height: 14),
              const LinearProgressIndicator(minHeight: 3),
              const SizedBox(height: 8),
              const Text(
                'Finalizando venda...',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PdvHintLine extends StatelessWidget {
  const _PdvHintLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: const Color(0xFF64748B)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
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
                  _pdvText(item.product.name),
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
            tooltip: 'Cancelar item com autorização fiscal',
            onPressed: () => onRemove(item),
            icon: const Icon(Icons.do_not_disturb_on_outlined),
          ),
        ],
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
    required this.onReprintNonFiscalReceipt,
  });

  final List<Sale> sales;
  final List<Client> clients;
  final bool canCancel;
  final ValueChanged<Sale> onCancel;
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
              'Ultimas vendas',
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
                title: Text(
                  '${sale.number ?? 'V${sale.id}'} - ${_money(sale.totalAmount)}',
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
                              tooltip: 'Reimprimir cupom não fiscal',
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

class _MoneyRow extends StatelessWidget {
  const _MoneyRow(
    this.label,
    this.value, {
    this.large = false,
    this.pdvMode = false,
    this.textValue,
  });
  final String label;
  final double value;
  final bool large;
  final bool pdvMode;
  final String? textValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          Text(
            textValue ?? _money(value),
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

class _CartItem {
  _CartItem({required this.product, this.quantity = 1, double? unitPrice})
    : unitPrice = unitPrice ?? product.effectiveSalePrice,
      assert(quantity > 0);

  factory _CartItem.fromStorageJson(Map<String, dynamic> json) {
    final productJson = json['product'] as Map<String, dynamic>?;
    if (productJson == null) {
      throw const FormatException('Produto do carrinho ausente.');
    }
    return _CartItem(
      product: Product.fromJson(productJson),
      quantity: (json['quantity'] as num?)?.toDouble() ?? 1,
      unitPrice: (json['unit_price'] as num?)?.toDouble(),
    );
  }

  final Product product;
  double quantity;
  final double unitPrice;

  Map<String, dynamic> toStorageJson() {
    return {
      'product': _productToStorageJson(product),
      'quantity': quantity,
      'unit_price': unitPrice,
    };
  }
}

Map<String, dynamic> _productToStorageJson(Product product) {
  return {
    'id': product.id,
    'name': product.name,
    'product_type': product.productType,
    'internal_code': product.internalCode,
    'barcode': product.barcode,
    'image_url': product.imageUrl,
    'description': product.description,
    'brand': product.brand,
    'model': product.model,
    'category': product.category,
    'stock_location': product.stockLocation,
    'tracks_batch': product.tracksBatch,
    'initial_batch_number': product.initialBatchNumber,
    'initial_expiration_date': product.initialExpirationDate,
    'sale_price': product.salePrice,
    'offer_price': product.offerPrice,
    'offer_start_at': product.offerStartAt?.toIso8601String(),
    'offer_end_at': product.offerEndAt?.toIso8601String(),
    'purchase_total_cost': product.purchaseTotalCost,
    'purchase_quantity': product.purchaseQuantity,
    'purchase_conversion_enabled': product.purchaseConversionEnabled,
    'purchase_invoice_unit': product.purchaseInvoiceUnit,
    'purchase_package_factor': product.purchasePackageFactor,
    'purchase_package_barcode': product.purchasePackageBarcode,
    'average_cost': product.averageCost,
    'stock_value': product.stockValue,
    'margin_percent': product.marginPercent,
    'stock_quantity': product.stockQuantity,
    'minimum_stock': product.minimumStock,
    'unit': product.unit,
    'ncm': product.ncm,
    'cest': product.cest,
    'cfop_sale': product.cfopSale,
    'origin': product.origin,
    'cst': product.cst,
    'csosn': product.csosn,
    'icms_rate': product.icmsRate,
    'pis_rate': product.pisRate,
    'cofins_rate': product.cofinsRate,
    'ipi_rate': product.ipiRate,
    'iss_rate': product.issRate,
    'municipal_service_code': product.municipalServiceCode,
    'tax_rate': product.taxRate,
    'fiscal_notes': product.fiscalNotes,
    'ibs_cbs_cst': product.ibsCbsCst,
    'ibs_cbs_classification': product.ibsCbsClassification,
    'cbs_rate': product.cbsRate,
    'ibs_state_rate': product.ibsStateRate,
    'ibs_city_rate': product.ibsCityRate,
    'selective_tax_cst': product.selectiveTaxCst,
    'selective_tax_classification': product.selectiveTaxClassification,
    'selective_tax_rate': product.selectiveTaxRate,
    'new_tax_system': product.newTaxSystem,
    'old_tax_system_notes': product.oldTaxSystemNotes,
    'new_tax_system_notes': product.newTaxSystemNotes,
    'nearest_batch_number': product.nearestBatchNumber,
    'nearest_expiration_date': product.nearestExpirationDate,
    'last_receipt_supplier_name': product.lastReceiptSupplierName,
    'last_receipt_invoice_number': product.lastReceiptInvoiceNumber,
    'active': product.active,
  };
}

Map<String, dynamic> _fiscalSettingsToStorageJson(
  CompanyFiscalSetting settings,
) {
  return {
    'id': settings.id,
    'environment': settings.environment,
    'nfce_enabled': settings.nfceEnabled,
    'pdv_nfce_enabled': settings.pdvNfceEnabled,
    'nfe_enabled': settings.nfeEnabled,
    'has_certificate': settings.hasCertificate,
    'nfce_series': settings.nfceSeries,
    'nfce_next_number': settings.nfceNextNumber,
    'nfe_series': settings.nfeSeries,
    'nfe_next_number': settings.nfeNextNumber,
    'has_nfce_csc': settings.hasNfceCsc,
    'legal_name': settings.legalName,
    'trade_name': settings.tradeName,
    'cnpj': settings.cnpj,
    'state_registration': settings.stateRegistration,
    'crt': settings.crt,
    'uf': settings.uf,
    'city_code': settings.cityCode,
    'address_line': settings.addressLine,
    'address_number': settings.addressNumber,
    'neighborhood': settings.neighborhood,
    'city': settings.city,
    'zip_code': settings.zipCode,
    'certificate_name': settings.certificateName,
    'certificate_file_sha256': settings.certificateFileSha256,
    'nfce_csc_id': settings.nfceCscId,
    'certificate_expires_at': settings.certificateExpiresAt?.toIso8601String(),
    'notes': settings.notes,
  };
}

Sale _buildLocalOfflineSale({
  required String localNumber,
  required SalePayload payload,
  required List<SalePaymentPayload> payments,
}) {
  final subtotal = payload.items.fold<double>(
    0,
    (sum, item) => sum + (item.quantity * item.unitPrice),
  );
  final total = (subtotal - payload.discountAmount)
      .clamp(0, double.infinity)
      .toDouble();
  final paidCents = payments.fold<int>(
    0,
    (sum, payment) => sum + _moneyToCents(payment.amount),
  );
  final totalCents = _moneyToCents(total);
  final paid = paidCents / 100;
  final change = _nonNegativeCents(paidCents - totalCents) / 100;
  return Sale(
    id: -DateTime.now().millisecondsSinceEpoch,
    number: localNumber,
    clientId: payload.clientId,
    offlineClientId: payload.offlineClientId,
    cashRegisterNumber: payload.cashRegisterNumber,
    sellerUserId: payload.sellerUserId,
    sellerName: 'PDV offline',
    consumerCpf: payload.consumerCpf,
    source: payload.source,
    status: 'pendente_offline',
    subtotalAmount: subtotal,
    discountAmount: payload.discountAmount,
    totalAmount: total,
    amountPaid: paid,
    changeAmount: change,
    notes: payload.notes,
    soldAt: DateTime.now(),
    items: [
      for (var index = 0; index < payload.items.length; index++)
        SaleItem(
          id: -(index + 1),
          productId: payload.items[index].productId,
          barcode: payload.items[index].barcode,
          description: payload.items[index].description,
          quantity: payload.items[index].quantity,
          unit: 'un',
          unitPrice: payload.items[index].unitPrice,
          discountAmount: payload.items[index].discountAmount,
          totalPrice:
              (payload.items[index].quantity * payload.items[index].unitPrice) -
              payload.items[index].discountAmount,
        ),
    ],
    payments: [
      for (var index = 0; index < payments.length; index++)
        SalePayment(
          id: -(index + 1),
          method: payments[index].method,
          amount: payments[index].amount,
          authorizationCode: payments[index].authorizationCode,
          notes: payments[index].notes,
        ),
    ],
  );
}

SalePayload _salePayloadFromJson(Map<String, dynamic> json) {
  return SalePayload(
    clientId: json['client_id'] as int?,
    offlineClientId: json['offline_client_id'] as String?,
    cashRegisterNumber: json['cash_register_number'] as String?,
    sellerUserId: json['seller_user_id'] as int?,
    source: json['source'] as String? ?? 'pdv',
    status: json['status'] as String? ?? 'finalizada',
    discountAmount: (json['discount_amount'] as num?)?.toDouble() ?? 0,
    consumerCpf: json['consumer_cpf'] as String?,
    notes: json['notes'] as String? ?? '',
    items: [
      for (final item in ((json['items'] as List<dynamic>?) ?? []))
        SaleItemPayload(
          productId: (item as Map<String, dynamic>)['product_id'] as int?,
          barcode: item['barcode'] as String?,
          description: item['description'] as String? ?? '',
          quantity: (item['quantity'] as num?)?.toDouble() ?? 0,
          unitPrice: (item['unit_price'] as num?)?.toDouble() ?? 0,
          discountAmount: (item['discount_amount'] as num?)?.toDouble() ?? 0,
        ),
    ],
    payments: [
      for (final payment in ((json['payments'] as List<dynamic>?) ?? []))
        SalePaymentPayload(
          method: (payment as Map<String, dynamic>)['method'] as String,
          amount: (payment['amount'] as num?)?.toDouble() ?? 0,
          authorizationCode: payment['authorization_code'] as String?,
          notes: payment['notes'] as String?,
        ),
    ],
  );
}

class _ScanInput {
  const _ScanInput({
    required this.quantity,
    this.code,
    this.hasExplicitQuantity = false,
  });

  final double quantity;
  final String? code;
  final bool hasExplicitQuantity;
}

class _ScaleBarcodeResult {
  const _ScaleBarcodeResult({required this.product, required this.quantity});

  final Product product;
  final double quantity;
}

class _CashMovement {
  const _CashMovement({
    required this.type,
    required this.amount,
    required this.reason,
    required this.createdAt,
    this.authorizedByOperatorId,
    this.authorizedByOperatorName,
  });

  final String type;
  final double amount;
  final String reason;
  final DateTime createdAt;
  final int? authorizedByOperatorId;
  final String? authorizedByOperatorName;
}

String _paymentMethodLabel(String value) {
  if (value.contains(' + ')) {
    return value
        .split(' + ')
        .map((method) => _paymentMethods[method] ?? method)
        .join(' + ');
  }
  return _paymentMethods[value] ?? value;
}

const _pdvHeaderTitleStyle = TextStyle(
  color: Colors.white,
  fontSize: 25,
  fontWeight: FontWeight.w900,
);

const _pdvPanelLabelStyle = TextStyle(
  color: Color(0xFF2563EB),
  fontSize: 14,
  fontWeight: FontWeight.w900,
);

const _pdvTableHeadStyle = TextStyle(
  color: Color(0xFF2563EB),
  fontSize: 13,
  fontWeight: FontWeight.w900,
);

const _pdvTableTextStyle = TextStyle(
  color: Color(0xFF0F172A),
  fontSize: 14,
  fontWeight: FontWeight.w700,
);

InputDecoration _pdvInputDecoration({String? labelText, String? hintText}) {
  return InputDecoration(
    labelText: labelText,
    hintText: hintText,
    filled: true,
    fillColor: Colors.white,
    labelStyle: const TextStyle(color: Color(0xFF64748B)),
    hintStyle: const TextStyle(color: Color(0xFF64748B)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFF3B82F6), width: 1.5),
    ),
  );
}

ButtonStyle _pdvOutlineButtonStyle() {
  return OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF0F172A),
    side: const BorderSide(color: Color(0xFFCBD5E1)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
  );
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';

int _moneyToCents(double value) => (value * 100).round();

int _nonNegativeCents(int value) => value < 0 ? 0 : value;

String _dateTime(DateTime value) {
  final local = value.toLocal();
  String two(int number) => number.toString().padLeft(2, '0');
  return '${two(local.day)}/${two(local.month)}/${local.year} ${two(local.hour)}:${two(local.minute)}';
}
