import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/product.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';

class MobileProductFormSheet extends StatefulWidget {
  const MobileProductFormSheet({
    super.key,
    required this.api,
    required this.token,
    this.initialBarcode,
    this.initialName,
    this.initialUnit,
    this.initialStockQuantity,
  });

  final ApiClient api;
  final String token;
  final String? initialBarcode;
  final String? initialName;
  final String? initialUnit;
  final double? initialStockQuantity;

  @override
  State<MobileProductFormSheet> createState() => _MobileProductFormSheetState();
}

class _MobileProductFormSheetState extends State<MobileProductFormSheet> {
  late final _name = TextEditingController(text: widget.initialName ?? '');
  late final _barcode = TextEditingController(
    text: widget.initialBarcode ?? '',
  );
  final _internalCode = TextEditingController();
  final _brand = TextEditingController();
  final _category = TextEditingController();
  final _stock = TextEditingController();
  final _minimumStock = TextEditingController(text: '0');
  final _salePrice = TextEditingController(text: '0,00');
  final _purchaseTotal = TextEditingController();
  final _purchaseQuantity = TextEditingController();
  final _purchasePackageFactor = TextEditingController(text: '1');
  final _purchasePackageBarcode = TextEditingController();
  final _ncm = TextEditingController();
  final _cfop = TextEditingController();
  final _description = TextEditingController();

  String _productType = 'produto';
  String _purchaseInvoiceUnit = 'pc';
  late String _unit = widget.initialUnit?.trim().isNotEmpty == true
      ? widget.initialUnit!.trim().toLowerCase()
      : 'un';
  bool _purchaseConversionEnabled = false;
  bool _saving = false;
  String? _error;

  static const _units = ['un', 'pc', 'pct', 'cx', 'kg', 'g', 'l', 'ml'];
  static const _types = {
    'produto': 'Produto',
    'produto_acabado': 'Produto acabado',
    'mercadoria': 'Mercadoria/revenda',
    'materia_prima': 'Materia-prima',
    'embalagem': 'Embalagem',
    'peca': 'Peca',
    'servico': 'Servico',
    'insumo': 'Insumo',
  };

  @override
  void initState() {
    super.initState();
    _stock.text = formatBrazilianDecimal(widget.initialStockQuantity ?? 0);
    if (!_units.contains(_unit)) _unit = 'un';
  }

  @override
  void dispose() {
    _name.dispose();
    _barcode.dispose();
    _internalCode.dispose();
    _brand.dispose();
    _category.dispose();
    _stock.dispose();
    _minimumStock.dispose();
    _salePrice.dispose();
    _purchaseTotal.dispose();
    _purchaseQuantity.dispose();
    _purchasePackageFactor.dispose();
    _purchasePackageBarcode.dispose();
    _ncm.dispose();
    _cfop.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.length < 2) {
      setState(() => _error = 'Informe o nome do produto.');
      return;
    }
    final stock = parseBrazilianNumber(_stock.text);
    final minimumStock = parseBrazilianNumber(_minimumStock.text);
    final salePrice = parseBrazilianNumber(_salePrice.text);
    final packageFactor = parseBrazilianNumber(_purchasePackageFactor.text);
    if (_purchaseConversionEnabled && packageFactor <= 0) {
      setState(
        () => _error =
            'Informe quantas unidades entram em cada pacote/embalagem.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final product = await widget.api.createProduct(
        widget.token,
        ProductPayload(
          name: name,
          productType: _productType,
          salePrice: salePrice,
          stockQuantity: stock,
          minimumStock: minimumStock,
          unit: _unit,
          active: true,
          internalCode: _emptyToNull(_internalCode.text),
          barcode: _emptyToNull(_barcode.text),
          brand: _emptyToNull(_brand.text),
          category: _emptyToNull(_category.text),
          description: _emptyToNull(_description.text),
          purchaseTotalCost: _nullableNumber(_purchaseTotal.text),
          purchaseQuantity: _nullableNumber(_purchaseQuantity.text),
          purchaseConversionEnabled: _purchaseConversionEnabled,
          purchaseInvoiceUnit: _purchaseConversionEnabled
              ? _purchaseInvoiceUnit
              : null,
          purchasePackageFactor: _purchaseConversionEnabled
              ? packageFactor
              : null,
          purchasePackageBarcode: _purchaseConversionEnabled
              ? _emptyToNull(_purchasePackageBarcode.text)
              : null,
          ncm: _emptyToNull(_ncm.text),
          cfopSale: _emptyToNull(_cfop.text),
        ),
      );
      if (mounted) Navigator.of(context).pop(product);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Nao foi possivel cadastrar o produto.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _scanBarcode() async {
    final code = await showDialog<String>(
      context: context,
      builder: (context) => const _MobileProductBarcodeScannerDialog(),
    );
    if (code == null || code.trim().isEmpty || !mounted) return;
    setState(() => _barcode.text = code.trim());
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.add_business_outlined),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Cadastrar produto',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'O cadastro sera gravado somente na empresa conectada neste app.',
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: const TextStyle(
                  color: Color(0xFFB91C1C),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
            const SizedBox(height: 14),
            TextField(
              controller: _name,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Nome do produto'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _barcode,
              textInputAction: TextInputAction.next,
              decoration: InputDecoration(
                labelText: 'Codigo de barras / EAN',
                suffixIcon: IconButton(
                  tooltip: 'Escanear codigo',
                  onPressed: _saving ? null : _scanBarcode,
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                ),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _internalCode,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(labelText: 'Codigo interno'),
            ),
            const SizedBox(height: 10),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Converter pacote/caixa para unidade',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'Use quando a nota vem por pacote, caixa ou fardo, mas o estoque vende por unidade.',
              ),
              value: _purchaseConversionEnabled,
              onChanged: _saving
                  ? null
                  : (value) =>
                        setState(() => _purchaseConversionEnabled = value),
            ),
            if (_purchaseConversionEnabled) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _purchaseInvoiceUnit,
                      decoration: const InputDecoration(
                        labelText: 'Unidade da nota/XML',
                      ),
                      items: [
                        for (final unit in _units)
                          DropdownMenuItem(value: unit, child: Text(unit)),
                      ],
                      onChanged: _saving
                          ? null
                          : (value) {
                              if (value != null) {
                                setState(() => _purchaseInvoiceUnit = value);
                              }
                            },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _purchasePackageFactor,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [BrazilianDecimalInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Unidades por embalagem',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _purchasePackageBarcode,
                decoration: const InputDecoration(
                  labelText: 'Codigo do pacote/caixa/embalagem',
                ),
              ),
              const SizedBox(height: 10),
            ],
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _productType,
                    decoration: const InputDecoration(labelText: 'Tipo'),
                    items: [
                      for (final entry in _types.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) {
                              setState(() => _productType = value);
                            }
                          },
                  ),
                ),
                const SizedBox(width: 10),
                SizedBox(
                  width: 116,
                  child: DropdownButtonFormField<String>(
                    initialValue: _unit,
                    decoration: const InputDecoration(labelText: 'Unidade'),
                    items: [
                      for (final unit in _units)
                        DropdownMenuItem(value: unit, child: Text(unit)),
                    ],
                    onChanged: _saving
                        ? null
                        : (value) {
                            if (value != null) setState(() => _unit = value);
                          },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _stock,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianDecimalInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Estoque atual',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _minimumStock,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianDecimalInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Estoque minimo',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _salePrice,
              keyboardType: TextInputType.number,
              inputFormatters: const [BrazilianDecimalInputFormatter()],
              decoration: const InputDecoration(labelText: 'Preco de venda'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _purchaseTotal,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianMoneyInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Valor da compra',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _purchaseQuantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianDecimalInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Qtd. comprada',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _brand,
                    decoration: const InputDecoration(labelText: 'Marca'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _category,
                    decoration: const InputDecoration(labelText: 'Categoria'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _ncm,
                    decoration: const InputDecoration(labelText: 'NCM'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _cfop,
                    decoration: const InputDecoration(labelText: 'CFOP venda'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: 'Descricao'),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save_outlined),
              label: Text(_saving ? 'Salvando...' : 'Salvar produto'),
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

  double? _nullableNumber(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return parseBrazilianNumber(trimmed);
  }
}

class _MobileProductBarcodeScannerDialog extends StatefulWidget {
  const _MobileProductBarcodeScannerDialog();

  @override
  State<_MobileProductBarcodeScannerDialog> createState() =>
      _MobileProductBarcodeScannerDialogState();
}

class _MobileProductBarcodeScannerDialogState
    extends State<_MobileProductBarcodeScannerDialog> {
  late final MobileScannerController _controller;
  bool _done = false;
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    _controller = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [
        BarcodeFormat.ean13,
        BarcodeFormat.ean8,
        BarcodeFormat.upcA,
        BarcodeFormat.upcE,
        BarcodeFormat.code128,
        BarcodeFormat.code39,
        BarcodeFormat.itf14,
        BarcodeFormat.qrCode,
      ],
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    String? code;
    for (final barcode in capture.barcodes) {
      final value = barcode.rawValue?.trim();
      if (value != null && value.isNotEmpty) {
        code = value;
        break;
      }
    }
    if (code == null) return;
    _done = true;
    Navigator.of(context).pop(code);
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(
        width: 420,
        height: 520,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Escanear codigo',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 260,
                            height: 150,
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.9),
                                width: 3,
                              ),
                              borderRadius: BorderRadius.circular(18),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.58),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.all(10),
                            child: Text(
                              'Aponte a camera para o codigo de barras.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await _controller.toggleTorch();
                        if (!mounted) return;
                        setState(() => _torchOn = !_torchOn);
                      },
                      icon: Icon(_torchOn ? Icons.flash_on : Icons.flash_off),
                      label: const Text('Lanterna'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancelar'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
