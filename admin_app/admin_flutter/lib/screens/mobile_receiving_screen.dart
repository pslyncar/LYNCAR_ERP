import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../models/stock_entry.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/error_panel.dart';
import '../widgets/mobile_scanner_assist_controls.dart';

class MobileReceivingScreen extends StatefulWidget {
  const MobileReceivingScreen({
    super.key,
    required this.session,
    this.onLogout,
  });

  final Session session;
  final VoidCallback? onLogout;

  @override
  State<MobileReceivingScreen> createState() => _MobileReceivingScreenState();
}

class _MobileReceivingScreenState extends State<MobileReceivingScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _scannerController = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    autoZoom: true,
  );
  final _manualCode = TextEditingController();

  List<StockEntry> _entries = [];
  StockEntry? _selectedEntry;
  bool _loading = true;
  bool _saving = false;
  bool _scannerPaused = false;
  bool _smallCodeMode = false;
  double _scannerZoom = 0;
  String? _error;
  String? _message;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _manualCode.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final entries = await _api.listStockEntries(
        widget.session.token,
        limit: 200,
      );
      final openEntries = entries
          .where((entry) => entry.status == 'receiving')
          .toList(growable: false);
      setState(() {
        _entries = openEntries;
        if (_selectedEntry != null &&
            _entries.any((entry) => entry.id == _selectedEntry!.id)) {
          _selectedEntry = _entries.firstWhere(
            (entry) => entry.id == _selectedEntry!.id,
          );
        } else {
          _selectedEntry = null;
        }
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar recebimentos.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _refreshSelectedEntry() async {
    final entry = _selectedEntry;
    if (entry == null) return;
    final updated = await _api.getStockEntry(widget.session.token, entry.id);
    setState(() {
      _selectedEntry = updated;
      _entries = [
        for (final current in _entries)
          current.id == updated.id ? updated : current,
      ];
    });
  }

  void _handleDetect(BarcodeCapture capture) {
    if (_scannerPaused || _saving || _selectedEntry == null) return;
    final code = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim())
        .whereType<String>()
        .where((value) => value.isNotEmpty)
        .cast<String?>()
        .firstWhere((value) => value != null, orElse: () => null);
    if (code == null) return;
    _openScannedItem(code);
  }

  Future<void> _openScannedItem(String code) async {
    if (_selectedEntry == null || _scannerPaused) return;
    setState(() {
      _scannerPaused = true;
      _error = null;
      _message = null;
    });
    await _scannerController.stop();
    try {
      Product? product;
      try {
        product = await _api.lookupProductByCode(widget.session.token, code);
      } on ApiException {
        product = null;
      }
      final entryItem = _findEntryItem(code, product);
      if (entryItem == null) {
        if (!mounted) return;
        setState(
          () => _error =
              'Este produto/codigo nao faz parte deste recebimento. Confira se selecionou a entrada correta ou envie este item para recebimento pelo computador.',
        );
        return;
      }
      await _openEntryItemSheet(entryItem, code: code, product: product);
    } finally {
      if (mounted) {
        setState(() => _scannerPaused = false);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        if (mounted) await _scannerController.start();
      }
    }
  }

  Future<void> _openEntryItemSheet(
    StockEntryItem entryItem, {
    String? code,
    Product? product,
  }) async {
    if (!mounted) return;
    Product? resolvedProduct = product;
    final lookupCode = code ?? entryItem.barcode;
    if (resolvedProduct == null &&
        lookupCode != null &&
        lookupCode.trim().isNotEmpty) {
      try {
        resolvedProduct = await _api.lookupProductByCode(
          widget.session.token,
          lookupCode,
        );
      } catch (_) {
        resolvedProduct = null;
      }
    }
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => _MobileReceiveItemSheet(
        code: code ?? entryItem.barcode ?? '',
        product: resolvedProduct,
        entryItem: entryItem,
        onSave: _saveScannedItem,
      ),
    );
    if (saved == true) {
      await _refreshSelectedEntry();
    }
  }

  StockEntryItem? _findEntryItem(String code, Product? product) {
    final entry = _selectedEntry;
    if (entry == null) return null;
    final normalizedCode = _normalizeCode(code);
    for (final item in entry.items) {
      if (_normalizeCode(item.barcode) == normalizedCode) return item;
      if (product != null && item.productId == product.id) return item;
    }
    return null;
  }

  String _normalizeCode(String? value) {
    return (value ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
  }

  Future<void> _saveScannedItem(StockEntryMobileItemPayload payload) async {
    final entry = _selectedEntry;
    if (entry == null) return;
    setState(() => _saving = true);
    try {
      await _api.receiveStockEntryMobileItem(
        widget.session.token,
        entry.id,
        payload,
      );
      if (mounted) {
        setState(() => _message = 'Item salvo. Leia o próximo código.');
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
      rethrow;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _setScannerZoom(double value) async {
    final zoom = value.clamp(0.0, 1.0);
    setState(() {
      _scannerZoom = zoom;
      _smallCodeMode = zoom >= 0.45;
    });
    try {
      await _scannerController.setZoomScale(zoom);
    } catch (_) {
      // Alguns navegadores nao suportam zoom manual da camera.
    }
  }

  Future<void> _toggleSmallCodeMode() async {
    await _setScannerZoom(_smallCodeMode ? 0 : 0.62);
  }

  Future<void> _toggleTorch() async {
    try {
      await _scannerController.toggleTorch();
    } catch (_) {
      if (mounted) {
        setState(
          () => _message = 'Lanterna nao disponivel neste aparelho/navegador.',
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _selectedEntry;
    return Scaffold(
      backgroundColor: const Color(0xFFF2F6FB),
      appBar: AppBar(
        title: Text(entry == null ? 'Recebimentos' : 'Conferir mercadoria'),
        leading: entry == null
            ? null
            : IconButton(
                tooltip: 'Voltar para recebimentos',
                onPressed: () => setState(() => _selectedEntry = null),
                icon: const Icon(Icons.arrow_back),
              ),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          if (widget.onLogout != null)
            IconButton(
              tooltip: 'Sair',
              onPressed: widget.onLogout,
              icon: const Icon(Icons.logout),
            ),
        ],
      ),
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 24),
                children: [
                  if (_error != null) ...[
                    ErrorPanel(message: _error!, onRetry: _load),
                    const SizedBox(height: 12),
                  ],
                  if (_message != null) ...[
                    _InfoBox(message: _message!),
                    const SizedBox(height: 12),
                  ],
                  if (entry == null)
                    _EntrySelector(
                      entries: _entries,
                      titleFor: _entryTitle,
                      onSelect: (entry) {
                        setState(() {
                          _selectedEntry = entry;
                          _error = null;
                          _message = null;
                        });
                      },
                    )
                  else ...[
                    _SelectedEntryHeader(
                      entry: entry,
                      title: _entryTitle(entry),
                      onChange: () => setState(() => _selectedEntry = null),
                    ),
                    const SizedBox(height: 12),
                    _ScannerBox(
                      controller: _scannerController,
                      paused: _scannerPaused,
                      onDetect: _handleDetect,
                      zoom: _scannerZoom,
                      smallCodeMode: _smallCodeMode,
                      onZoomChanged: _setScannerZoom,
                      onSmallCodeToggle: _toggleSmallCodeMode,
                      onTorchToggle: _toggleTorch,
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _manualCode,
                            decoration: const InputDecoration(
                              labelText: 'Código manual',
                              prefixIcon: Icon(Icons.qr_code_2_outlined),
                              border: OutlineInputBorder(),
                            ),
                            onSubmitted: (value) {
                              final code = value.trim();
                              if (code.isEmpty) return;
                              _manualCode.clear();
                              _openScannedItem(code);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          tooltip: 'Ler código informado',
                          onPressed: () {
                            final code = _manualCode.text.trim();
                            if (code.isEmpty) return;
                            _manualCode.clear();
                            _openScannedItem(code);
                          },
                          icon: const Icon(Icons.keyboard_return),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _EntryProgress(
                      entry: entry,
                      onTapItem: (item) => _openEntryItemSheet(item),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _saving
                          ? null
                          : () async {
                              setState(() {
                                _selectedEntry = null;
                                _message =
                                    'Leitura concluida. Finalize a conferência no computador.';
                              });
                              await _load();
                            },
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Concluir leitura'),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  String _entryTitle(StockEntry entry) {
    final supplier = entry.supplierName ?? 'Fornecedor não informado';
    final number = entry.invoiceNumber ?? 'Entrada #${entry.id}';
    return '$number - $supplier';
  }
}

class _EntrySelector extends StatelessWidget {
  const _EntrySelector({
    required this.entries,
    required this.titleFor,
    required this.onSelect,
  });

  final List<StockEntry> entries;
  final String Function(StockEntry entry) titleFor;
  final ValueChanged<StockEntry> onSelect;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const _EmptyState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Escolha o recebimento',
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 4),
        const Text(
          'A conferência pela camera abre depois da selecao.',
          style: TextStyle(
            color: Color(0xFF64748B),
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 14),
        for (final entry in entries) ...[
          _ReceivingCard(
            entry: entry,
            title: titleFor(entry),
            onTap: () => onSelect(entry),
          ),
          const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _ReceivingCard extends StatelessWidget {
  const _ReceivingCard({
    required this.entry,
    required this.title,
    required this.onTap,
  });

  final StockEntry entry;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final received = _receivedQuantity(entry);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFD8E2EF)),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.inventory_2_outlined,
                      color: Color(0xFF0A66D8),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${entry.items.length} itens na nota',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(
                    Icons.qr_code_scanner_outlined,
                    size: 18,
                    color: Color(0xFF0F766E),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Registrado: ${formatBrazilianDecimal(received)}',
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectedEntryHeader extends StatelessWidget {
  const _SelectedEntryHeader({
    required this.entry,
    required this.title,
    required this.onChange,
  });

  final StockEntry entry;
  final String title;
  final VoidCallback onChange;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFD8E2EF)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            const Icon(Icons.assignment_turned_in_outlined),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  Text(
                    '${entry.items.length} itens para conferir',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Trocar recebimento',
              onPressed: onChange,
              icon: const Icon(Icons.swap_horiz),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScannerBox extends StatelessWidget {
  const _ScannerBox({
    required this.controller,
    required this.paused,
    required this.onDetect,
    required this.zoom,
    required this.smallCodeMode,
    required this.onZoomChanged,
    required this.onSmallCodeToggle,
    required this.onTorchToggle,
  });

  final MobileScannerController controller;
  final bool paused;
  final void Function(BarcodeCapture capture) onDetect;
  final double zoom;
  final bool smallCodeMode;
  final ValueChanged<double> onZoomChanged;
  final VoidCallback onSmallCodeToggle;
  final VoidCallback onTorchToggle;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: 4 / 3,
        child: Stack(
          fit: StackFit.expand,
          children: [
            MobileScanner(controller: controller, onDetect: onDetect),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white, width: 3),
              ),
            ),
            Center(
              child: Container(
                width: 230,
                height: 120,
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFF22C55E), width: 3),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            if (paused)
              Container(
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                child: const CircularProgressIndicator(color: Colors.white),
              ),
            Positioned(
              left: 10,
              right: 10,
              bottom: 10,
              child: MobileScannerAssistControls(
                zoom: zoom,
                smallCodeMode: smallCodeMode,
                onZoomChanged: onZoomChanged,
                onSmallCodeToggle: onSmallCodeToggle,
                onTorchToggle: onTorchToggle,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MobileReceiveItemSheet extends StatefulWidget {
  const _MobileReceiveItemSheet({
    required this.code,
    required this.product,
    required this.entryItem,
    required this.onSave,
  });

  final String code;
  final Product? product;
  final StockEntryItem? entryItem;
  final Future<void> Function(StockEntryMobileItemPayload payload) onSave;

  @override
  State<_MobileReceiveItemSheet> createState() =>
      _MobileReceiveItemSheetState();
}

class _MobileReceiveItemSheetState extends State<_MobileReceiveItemSheet> {
  late final _defaultQuantity = _suggestedStockQuantity();
  late final _defaultUnit = _suggestedStockUnit();
  late final _defaultUnitCost = _suggestedUnitCost(_defaultQuantity);
  late final _conversionText = _buildConversionText();
  late final _name = TextEditingController(
    text: widget.product?.name ?? widget.entryItem?.description ?? '',
  );
  late final _quantity = TextEditingController(
    text: formatBrazilianDecimal(_defaultQuantity),
  );
  late final _unit = TextEditingController(text: _defaultUnit);
  late final _unitCost = TextEditingController(
    text: formatBrazilianMoneyInput(_defaultUnitCost),
  );
  late final _batch = TextEditingController(
    text: widget.entryItem?.batchNumber ?? '',
  );
  late final _expiration = TextEditingController(
    text: _formatDateForInput(widget.entryItem?.expirationDate),
  );
  bool _saving = false;
  String? _error;

  bool get _usesPurchaseConversion {
    final product = widget.product;
    final factor = product?.purchasePackageFactor ?? 0;
    if (product == null || !product.purchaseConversionEnabled || factor <= 0) {
      return false;
    }
    final entryUnit = (widget.entryItem?.invoiceUnit ?? widget.entryItem?.unit)
        ?.trim()
        .toLowerCase();
    final invoiceUnit = product.purchaseInvoiceUnit?.trim().toLowerCase();
    final packageBarcode = _normalizeCode(product.purchasePackageBarcode);
    final scannedCode = _normalizeCode(widget.code);
    return (invoiceUnit != null &&
            invoiceUnit.isNotEmpty &&
            entryUnit == invoiceUnit) ||
        (packageBarcode != null &&
            scannedCode != null &&
            packageBarcode == scannedCode) ||
        (widget.entryItem?.packageConversionFactor ?? 0) > 0;
  }

  double _suggestedStockQuantity() {
    final item = widget.entryItem;
    final received = item?.receivedQuantity ?? 0;
    if (received > 0) return received;
    if (item == null) return 1;
    if (_usesPurchaseConversion) {
      final factor =
          item.packageConversionFactor ??
          widget.product?.purchasePackageFactor ??
          1;
      final invoiceQuantity = item.invoiceQuantity ?? item.quantity;
      final converted = invoiceQuantity * factor;
      if (converted > 0) return converted;
    }
    return item.quantity > 0 ? item.quantity : 1;
  }

  String _suggestedStockUnit() {
    if (_usesPurchaseConversion) {
      final productUnit = widget.product?.unit.trim();
      if (productUnit != null && productUnit.isNotEmpty) return productUnit;
    }
    return widget.product?.unit ?? widget.entryItem?.unit ?? 'un';
  }

  double _suggestedUnitCost(double quantity) {
    final item = widget.entryItem;
    if (item != null && item.totalCost > 0 && quantity > 0) {
      return item.totalCost / quantity;
    }
    return item?.unitCost ??
        widget.product?.averageCost ??
        widget.product?.purchaseTotalCost ??
        0;
  }

  String? _buildConversionText() {
    final item = widget.entryItem;
    if (item == null || !_usesPurchaseConversion) return null;
    final invoiceQuantity = item.invoiceQuantity ?? item.quantity;
    final invoiceUnit =
        item.invoiceUnit ?? widget.product?.purchaseInvoiceUnit ?? item.unit;
    final factor =
        item.packageConversionFactor ??
        widget.product?.purchasePackageFactor ??
        1;
    return 'NF/XML: ${formatBrazilianDecimal(invoiceQuantity)} $invoiceUnit. '
        'Cadastro: 1 $invoiceUnit = ${formatBrazilianDecimal(factor)} $_defaultUnit. '
        'Receber no estoque: ${formatBrazilianDecimal(_defaultQuantity)} $_defaultUnit.';
  }

  String? _normalizeCode(String? value) {
    final normalized = (value ?? '').trim().toUpperCase().replaceAll(
      RegExp(r'[^A-Z0-9]'),
      '',
    );
    return normalized.isEmpty ? null : normalized;
  }

  @override
  void dispose() {
    _name.dispose();
    _quantity.dispose();
    _unit.dispose();
    _unitCost.dispose();
    _batch.dispose();
    _expiration.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final quantity = parseBrazilianNumber(_quantity.text);
    final unitCost = parseBrazilianNumber(_unitCost.text);
    final productId = widget.product?.id ?? widget.entryItem?.productId;
    if (productId == null) {
      setState(
        () => _error =
            'Produto nao cadastrado/vinculado. Cadastre em Cadastrar produto no inicio do app ou vincule pelo computador antes de receber.',
      );
      return;
    }
    if (name.length < 2 || quantity <= 0) {
      setState(() => _error = 'Informe produto e quantidade recebida.');
      return;
    }
    final expirationDate = _parseExpirationDate(_expiration.text);
    if (_expiration.text.trim().isNotEmpty && expirationDate == null) {
      setState(() => _error = 'Informe a validade como dd/mm/aaaa.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        StockEntryMobileItemPayload(
          productId: productId,
          description: name,
          barcode: widget.code,
          quantity: quantity,
          unit: _unit.text.trim().isEmpty ? 'un' : _unit.text.trim(),
          unitCost: unitCost,
          salePrice: null,
          ncm: null,
          cfop: null,
          batchNumber: _emptyToNull(_batch.text),
          expirationDate: expirationDate,
          checkNotes: null,
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar este item.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final known = widget.product != null || widget.entryItem != null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  known ? Icons.check_circle_outline : Icons.add_box_outlined,
                  color: known
                      ? const Color(0xFF0F766E)
                      : const Color(0xFFB45309),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    known ? 'Produto encontrado' : 'Produto nao vinculado',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text('Código ${widget.code}'),
            if (widget.entryItem != null)
              Text(
                'Ja registrado: ${formatBrazilianDecimal(widget.entryItem!.receivedQuantity ?? 0)} $_defaultUnit',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            if (_conversionText != null) ...[
              const SizedBox(height: 6),
              Text(
                _conversionText,
                style: const TextStyle(
                  color: Color(0xFF0F766E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_error != null) ...[
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
            ],
            TextField(
              controller: _name,
              readOnly: true,
              decoration: const InputDecoration(labelText: 'Produto'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantity,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Quantidade'),
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 92,
                  child: TextField(
                    controller: _unit,
                    readOnly: true,
                    canRequestFocus: false,
                    decoration: const InputDecoration(labelText: 'Lançar em'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _batch,
                    decoration: const InputDecoration(labelText: 'Lote'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _expiration,
                    keyboardType: TextInputType.datetime,
                    inputFormatters: const [BrazilianDateInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Validade',
                      hintText: 'dd/mm/aaaa',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Salvando...' : 'Salvar e ler próximo'),
            ),
          ],
        ),
      ),
    );
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _formatDateForInput(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final isoMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (isoMatch == null) return value;
    return '${isoMatch.group(3)}/${isoMatch.group(2)}/${isoMatch.group(1)}';
  }

  String? _parseExpirationDate(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final brMatch = RegExp(
      r'^(\d{1,2})/(\d{1,2})/(\d{4})$',
    ).firstMatch(trimmed);
    if (brMatch != null) {
      final day = int.tryParse(brMatch.group(1)!);
      final month = int.tryParse(brMatch.group(2)!);
      final year = int.tryParse(brMatch.group(3)!);
      if (day == null || month == null || year == null) return null;
      final date = DateTime(year, month, day);
      if (date.year != year || date.month != month || date.day != day) {
        return null;
      }
      return '${year.toString().padLeft(4, '0')}-'
          '${month.toString().padLeft(2, '0')}-'
          '${day.toString().padLeft(2, '0')}';
    }
    final isoMatch = RegExp(
      r'^(\d{4})-(\d{1,2})-(\d{1,2})$',
    ).firstMatch(trimmed);
    if (isoMatch == null) return null;
    final year = int.tryParse(isoMatch.group(1)!);
    final month = int.tryParse(isoMatch.group(2)!);
    final day = int.tryParse(isoMatch.group(3)!);
    if (day == null || month == null || year == null) return null;
    final date = DateTime(year, month, day);
    if (date.year != year || date.month != month || date.day != day) {
      return null;
    }
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }
}

class _EntryProgress extends StatelessWidget {
  const _EntryProgress({required this.entry, required this.onTapItem});

  final StockEntry entry;
  final ValueChanged<StockEntryItem> onTapItem;

  @override
  Widget build(BuildContext context) {
    final receivedItems = entry.items
        .where((item) => (item.receivedQuantity ?? 0) > 0)
        .toList(growable: false);
    final received = _receivedQuantity(entry);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Registrado no coletor: ${formatBrazilianDecimal(received)}',
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (receivedItems.isEmpty)
              const Text('Nenhum item recebido ainda.')
            else
              for (final item in receivedItems.take(8))
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onTapItem(item),
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      child: Row(
                        children: [
                          Expanded(child: Text(item.description)),
                          Text(
                            '${formatBrazilianDecimal(item.receivedQuantity ?? 0)} ${item.unit}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.edit_outlined, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

double _receivedQuantity(StockEntry entry) {
  return entry.items.fold<double>(
    0,
    (sum, item) => sum + (item.receivedQuantity ?? 0),
  );
}

class _InfoBox extends StatelessWidget {
  const _InfoBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        border: Border.all(color: const Color(0xFFBFDBFE)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          message,
          style: const TextStyle(
            color: Color(0xFF1E40AF),
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(24),
      child: Center(
        child: Text(
          'Nenhum recebimento aberto. Crie a entrada no computador e envie para conferência mobile.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
