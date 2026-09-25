import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../models/stock_entry.dart';
import '../services/api_client.dart';
import 'product_from_xml_dialog.dart';

class _ProductAssociationSelection {
  const _ProductAssociationSelection({
    required this.product,
    required this.stockUnit,
    required this.conversionFactor,
  });

  final Product product;
  final String stockUnit;
  final double? conversionFactor;
}

class ReceivingConferenceScreen extends StatefulWidget {
  const ReceivingConferenceScreen({
    super.key,
    required this.session,
    required this.entryId,
  });

  final Session session;
  final int entryId;

  @override
  State<ReceivingConferenceScreen> createState() =>
      _ReceivingConferenceScreenState();
}

class _ReceivingConferenceScreenState extends State<ReceivingConferenceScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  StockEntry? _entry;
  bool _loading = true;
  bool _saving = false;
  bool _returnAll = false;
  String? _error;
  final Map<int, TextEditingController> _quantities = {};
  final Map<int, TextEditingController> _batches = {};
  final Map<int, TextEditingController> _expirationDates = {};
  final Map<int, TextEditingController> _manufacturingDates = {};
  final Map<int, TextEditingController> _temperatures = {};
  final Map<int, TextEditingController> _notes = {};
  final Map<int, String> _statuses = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in _quantities.values) {
      controller.dispose();
    }
    for (final controllers in [
      _batches,
      _expirationDates,
      _manufacturingDates,
      _temperatures,
      _notes,
    ]) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final entry = await _api.getStockEntry(
        widget.session.token,
        widget.entryId,
      );
      if (!mounted) return;
      for (final item in entry.items) {
        final itemId = item.id;
        if (itemId == null) {
          continue;
        }
        _quantities[itemId] ??= TextEditingController(
          text: _number(item.receivedQuantity ?? 0),
        );
        _batches[itemId] ??= TextEditingController(
          text: item.batchNumber ?? '',
        );
        _expirationDates[itemId] ??= TextEditingController(
          text: _displayDate(item.expirationDate),
        );
        _manufacturingDates[itemId] ??= TextEditingController(
          text: _displayDate(item.manufacturingDate),
        );
        _temperatures[itemId] ??= TextEditingController(
          text: item.temperatureCelsius?.toString() ?? '',
        );
        _notes[itemId] ??= TextEditingController(
          text: _notesFromSavedCheck(item.checkNotes),
        );
        _statuses[itemId] ??= item.checkStatus == 'return'
            ? 'return'
            : 'accepted';
      }
      setState(() {
        _entry = entry;
        _loading = false;
        _error = null;
      });
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = error.message;
        });
      }
    }
  }

  Future<void> _saveQuantity(StockEntryItem item) async {
    final itemId = item.id;
    if (itemId == null) {
      _notice('Não foi possível identificar este item da entrada.');
      return;
    }
    final value = double.tryParse(
      (_quantities[itemId]?.text ?? '').replaceAll(',', '.'),
    );
    if (value == null || value < 0) {
      _notice('Informe uma quantidade válida.');
      return;
    }
    final expected = item.invoiceQuantity ?? item.quantity;
    if (value > 0 &&
        value != expected &&
        (_notes[itemId]?.text.trim().isEmpty ?? true)) {
      _notice('Informe a justificativa da divergência antes de salvar o item.');
      return;
    }
    final expirationDate = _storageDate(_expirationDates[itemId]?.text ?? '');
    if ((_expirationDates[itemId]?.text.trim().isNotEmpty ?? false) &&
        expirationDate == null) {
      _notice('Use uma validade no formato DD/MM/AAAA.');
      return;
    }
    final manufacturingDate = _storageDate(
      _manufacturingDates[itemId]?.text ?? '',
    );
    if ((_manufacturingDates[itemId]?.text.trim().isNotEmpty ?? false) &&
        manufacturingDate == null) {
      _notice('Use uma fabricação no formato DD/MM/AAAA.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.receiveStockEntryMobileItem(
        widget.session.token,
        widget.entryId,
        StockEntryMobileItemPayload(
          productId: item.productId,
          description: item.description,
          barcode: item.barcode,
          quantity: value,
          unit: item.unit,
          unitCost: item.unitCost,
          ncm: item.ncm,
          cfop: item.cfop,
          batchNumber: _batches[itemId]?.text.trim(),
          expirationDate: expirationDate,
          manufacturingDate: manufacturingDate,
          temperatureCelsius: double.tryParse(
            (_temperatures[itemId]?.text ?? '').replaceAll(',', '.'),
          ),
          checkStatus: _statuses[itemId] ?? 'accepted',
          checkNotes: _buildCheckNotes(itemId),
        ),
      );
      await _load();
    } on ApiException catch (error) {
      _notice(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _matchProduct(StockEntryItem item) async {
    if (item.id == null) return;
    final suggestions = await _api.suggestProductsForStockEntryItem(
      widget.session.token,
      widget.entryId,
      item.id!,
    );
    if (!mounted) return;
    final selected = await showDialog<_ProductAssociationSelection>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Associar produto ao item do XML'),
        content: SizedBox(
          width: 560,
          height: 360,
          child: suggestions.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhum produto compatível. Cadastre o produto ou revise os códigos do XML.',
                  ),
                )
              : ListView.builder(
                  itemCount: suggestions.length,
                  itemBuilder: (_, index) {
                    final suggestion = suggestions[index];
                    final product = Product.fromJson({
                      ...suggestion,
                      'id': suggestion['product_id'],
                      'product_type': 'mercadoria',
                      'sale_price': 0,
                      'minimum_stock': 0,
                      'stock_quantity': 0,
                      'stock_value': 0,
                      'active': true,
                      'purchase_conversion_enabled':
                          suggestion['purchase_conversion_enabled'] ?? false,
                      'purchase_package_factor':
                          suggestion['purchase_package_factor'],
                      'purchase_package_barcode':
                          suggestion['purchase_package_barcode'],
                      'purchase_invoice_unit':
                          suggestion['purchase_invoice_unit'],
                    });
                    return Card(
                      child: ListTile(
                        title: Text(product.name),
                        subtitle: Text(
                          '${product.internalCode ?? 'Sem código interno'} • '
                          '${product.barcode ?? 'Sem GTIN unidade'}\n'
                          '${suggestion['warning'] ?? 'Correspondência por código/GTIN'}',
                        ),
                        isThreeLine: true,
                        onTap: () async {
                          final confirmed = await _confirmProductAssociation(
                            product,
                            suggestion,
                            item,
                          );
                          if (confirmed != null && mounted) {
                            Navigator.pop(context, confirmed);
                          }
                        },
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
        ],
      ),
    );
    if (selected == null || item.id == null) return;
    setState(() => _saving = true);
    try {
      await _api.matchStockEntryItem(
        widget.session.token,
        widget.entryId,
        item.id!,
        selected.product.id,
        supplierProductCode: item.supplierProductCode ?? item.barcode,
        commercialGtin: item.barcode,
        taxGtin: item.taxGtin,
        supplierDescription: item.description,
        supplierUnit: item.invoiceUnit ?? item.unit,
        stockUnit: selected.stockUnit,
        conversionFactor: selected.conversionFactor,
      );
      await _load();
    } on ApiException catch (error) {
      _notice(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<_ProductAssociationSelection?> _confirmProductAssociation(
    Product product,
    Map<String, dynamic> suggestion,
    StockEntryItem item,
  ) {
    var currentProduct = product;
    final descriptionController = TextEditingController(
      text: product.description?.trim().isNotEmpty == true
          ? product.description
          : product.name,
    );
    final internalCodeController = TextEditingController(
      text: product.internalCode ?? '',
    );
    final unitGtinController = TextEditingController(
      text: product.barcode ?? '',
    );
    final packageGtinController = TextEditingController(
      text: product.purchasePackageBarcode ?? '',
    );
    var savingProduct = false;
    var productEditsDirty = false;
    var useXmlDescription = false;
    var useXmlUnitGtin = false;
    var useXmlPackageGtin = false;
    final xmlGtin = item.barcode;
    final xmlUnit = (item.invoiceUnit ?? item.unit).trim().toLowerCase();
    final xmlQuantity = item.invoiceQuantity ?? item.quantity;
    String digits(String? value) => value?.replaceAll(RegExp(r'\D'), '') ?? '';
    final packageByGtin =
        xmlGtin != null &&
        currentProduct.purchasePackageBarcode != null &&
        digits(xmlGtin) == digits(currentProduct.purchasePackageBarcode);
    final packageUnits = {'cx', 'caixa', 'fd', 'fardo', 'pack', 'pct'};
    var isPackage = packageByGtin || packageUnits.contains(xmlUnit);
    final factorController = TextEditingController(
      text: _number(currentProduct.purchasePackageFactor ?? 1),
    );

    String? xmlUnitGtin() {
      if (item.barcode == null || item.barcode!.trim().isEmpty) return null;
      return isPackage ? item.taxGtin : item.barcode;
    }

    String? xmlPackageGtin() {
      if (item.barcode == null || item.barcode!.trim().isEmpty) return null;
      return isPackage ? item.barcode : null;
    }

    return showDialog<_ProductAssociationSelection>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          final factor =
              double.tryParse(
                factorController.text.replaceAll(',', '.').trim(),
              ) ??
              0;
          final stockQuantity = xmlQuantity * (isPackage ? factor : 1);
          return AlertDialog(
            title: const Text('Conferir associação e embalagem'),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      currentProduct.name,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _associationSection('Dados recebidos no XML', [
                      _productDetail('Descrição', item.description),
                      _productDetail(
                        'Código do fornecedor (cProd)',
                        item.supplierProductCode,
                      ),
                      _productDetail('GTIN comercial (cEAN)', item.barcode),
                      _productDetail(
                        'GTIN tributável (cEANTrib)',
                        item.taxGtin,
                      ),
                      _productDetail(
                        'Quantidade comercial',
                        '${_number(xmlQuantity)} ${item.invoiceUnit ?? item.unit}',
                      ),
                    ]),
                    const SizedBox(height: 10),
                    _associationSection(
                      'Produto cadastrado no estoque — editável',
                      [
                        TextFormField(
                          controller: descriptionController,
                          decoration: const InputDecoration(
                            labelText: 'Descrição do produto',
                          ),
                          onChanged: (_) => productEditsDirty = true,
                        ),
                        _overrideOption(
                          value: useXmlDescription,
                          label: 'Usar descrição da nota',
                          enabled: item.description.trim().isNotEmpty,
                          onChanged: (value) {
                            setDialogState(() {
                              useXmlDescription = value;
                              descriptionController.text = value
                                  ? item.description.trim()
                                  : (product.description?.trim().isNotEmpty ==
                                            true
                                        ? product.description!
                                        : product.name);
                              productEditsDirty = true;
                            });
                          },
                        ),
                        TextFormField(
                          controller: internalCodeController,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'Código interno',
                            helperText: 'Código definido pelo sistema.',
                          ),
                        ),
                        TextFormField(
                          controller: unitGtinController,
                          decoration: const InputDecoration(
                            labelText: 'GTIN da unidade / PDV',
                          ),
                          onChanged: (_) => productEditsDirty = true,
                        ),
                        _overrideOption(
                          value: useXmlUnitGtin,
                          label: 'Usar GTIN da nota como GTIN da unidade',
                          enabled: xmlUnitGtin()?.trim().isNotEmpty == true,
                          onChanged: (value) {
                            setDialogState(() {
                              useXmlUnitGtin = value;
                              unitGtinController.text = value
                                  ? xmlUnitGtin()!.trim()
                                  : (product.barcode ?? '');
                              productEditsDirty = true;
                            });
                          },
                        ),
                        TextFormField(
                          controller: packageGtinController,
                          decoration: const InputDecoration(
                            labelText: 'GTIN da caixa',
                          ),
                          onChanged: (_) => productEditsDirty = true,
                        ),
                        _overrideOption(
                          value: useXmlPackageGtin,
                          label: 'Usar GTIN da nota como GTIN da caixa',
                          enabled: xmlPackageGtin()?.trim().isNotEmpty == true,
                          onChanged: (value) {
                            setDialogState(() {
                              useXmlPackageGtin = value;
                              packageGtinController.text = value
                                  ? xmlPackageGtin()!.trim()
                                  : (product.purchasePackageBarcode ?? '');
                              productEditsDirty = true;
                            });
                          },
                        ),
                        _productDetail(
                          'Unidade do estoque',
                          currentProduct.unit,
                        ),
                        _productDetail(
                          'Localização',
                          currentProduct.stockLocation,
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: savingProduct
                              ? null
                              : () async {
                                  final factorValue = double.tryParse(
                                    factorController.text
                                        .replaceAll(',', '.')
                                        .trim(),
                                  );
                                  setDialogState(() => savingProduct = true);
                                  try {
                                    currentProduct = await _api
                                        .updateProductIdentifiers(
                                          widget.session.token,
                                          currentProduct.id,
                                          description: descriptionController
                                              .text
                                              .trim(),
                                          internalCode: internalCodeController
                                              .text
                                              .trim(),
                                          barcode: unitGtinController.text
                                              .trim(),
                                          purchasePackageBarcode:
                                              packageGtinController.text.trim(),
                                          purchasePackageFactor: factorValue,
                                          purchaseConversionEnabled:
                                              packageGtinController.text
                                                  .trim()
                                                  .isNotEmpty,
                                          purchaseInvoiceUnit: 'cx',
                                        );
                                    productEditsDirty = false;
                                    setDialogState(() {});
                                    _notice('Cadastro do produto atualizado.');
                                  } on ApiException catch (error) {
                                    _notice(error.message);
                                  } finally {
                                    if (mounted) {
                                      setDialogState(
                                        () => savingProduct = false,
                                      );
                                    }
                                  }
                                },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Salvar alterações no cadastro'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Como esta nota será lançada',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<bool>(
                      initialValue: isPackage,
                      decoration: const InputDecoration(
                        labelText: 'Embalagem do XML',
                      ),
                      items: const [
                        DropdownMenuItem(value: false, child: Text('Unidade')),
                        DropdownMenuItem(
                          value: true,
                          child: Text('Caixa / fardo / pacote'),
                        ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => isPackage = value ?? false),
                    ),
                    if (isPackage) ...[
                      const SizedBox(height: 8),
                      TextFormField(
                        controller: factorController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Unidades por embalagem',
                          helperText:
                              'Usado somente para converter a caixa em unidades no estoque.',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      color: const Color(0xffeaf5ff),
                      child: Text(
                        'Quantidade que entrará no estoque: ${_number(stockQuantity)} ${currentProduct.unit}.\n'
                        'O GTIN da unidade/PDV só muda se você editar e salvar o campo acima. O GTIN da caixa ficará como referência de recebimento.',
                      ),
                    ),
                    if (suggestion['warning'] != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        color: const Color(0xfffff4e5),
                        child: Text(suggestion['warning'].toString()),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Voltar'),
              ),
              FilledButton.icon(
                onPressed: isPackage && factor <= 0
                    ? null
                    : () async {
                        if (productEditsDirty && !savingProduct) {
                          setDialogState(() => savingProduct = true);
                          try {
                            currentProduct = await _api
                                .updateProductIdentifiers(
                                  widget.session.token,
                                  currentProduct.id,
                                  description: descriptionController.text
                                      .trim(),
                                  internalCode: internalCodeController.text
                                      .trim(),
                                  barcode: unitGtinController.text.trim(),
                                  purchasePackageBarcode: packageGtinController
                                      .text
                                      .trim(),
                                  purchasePackageFactor: double.tryParse(
                                    factorController.text
                                        .replaceAll(',', '.')
                                        .trim(),
                                  ),
                                  purchaseConversionEnabled:
                                      packageGtinController.text
                                          .trim()
                                          .isNotEmpty,
                                  purchaseInvoiceUnit: 'cx',
                                );
                            productEditsDirty = false;
                          } on ApiException catch (error) {
                            setDialogState(() => savingProduct = false);
                            _notice(error.message);
                            return;
                          }
                        }
                        if (!dialogContext.mounted) return;
                        Navigator.pop(
                          dialogContext,
                          _ProductAssociationSelection(
                            product: currentProduct,
                            stockUnit: currentProduct.unit,
                            conversionFactor: isPackage ? factor : null,
                          ),
                        );
                      },

                icon: const Icon(Icons.link),
                label: Text(
                  savingProduct ? 'Salvando…' : 'Confirmar e associar',
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _associationSection(String title, List<Widget> children) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfff6f8fc),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: const Color(0xffd9e1ef)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 8),
        ...children,
      ],
    ),
  );

  Widget _productDetail(String label, String? value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      '$label: ${value?.trim().isNotEmpty == true ? value : 'Não informado'}',
    ),
  );

  Widget _overrideOption({
    required bool value,
    required String label,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) => CheckboxListTile(
    dense: true,
    contentPadding: EdgeInsets.zero,
    value: value,
    onChanged: enabled ? (next) => onChanged(next ?? false) : null,
    title: Text(label),
    subtitle: enabled
        ? const Text('Se desmarcado, o valor atual do estoque é preservado.')
        : const Text('Este valor não foi informado no XML.'),
    controlAffinity: ListTileControlAffinity.leading,
  );

  Future<void> _createAndMatchProduct(StockEntryItem item) async {
    final result = await showDialog<NewProductFromXml>(
      context: context,
      builder: (_) => ProductFromXmlDialog(item: item),
    );
    if (result == null || item.id == null) return;

    setState(() => _saving = true);
    try {
      final product = await _api.createProduct(
        widget.session.token,
        ProductPayload(
          name: result.name,
          description: result.description,
          productType: 'mercadoria',
          salePrice: 0,
          minimumStock: result.minimumStock,
          unit: result.stockUnit,
          barcode: result.barcode,
          category: result.category,
          stockLocation: result.stockLocation,
          tracksBatch: result.tracksBatch,
          purchaseConversionEnabled: result.purchaseConversionEnabled,
          purchaseInvoiceUnit: item.invoiceUnit ?? item.unit,
          purchasePackageFactor: result.purchasePackageFactor,
          purchasePackageBarcode: result.purchasePackageBarcode,
          ncm: item.ncm,
          active: true,
        ),
      );
      await _api.matchStockEntryItem(
        widget.session.token,
        widget.entryId,
        item.id!,
        product.id,
        supplierProductCode: item.supplierProductCode ?? item.barcode,
        commercialGtin: item.barcode,
        taxGtin: item.taxGtin,
        supplierDescription: item.description,
        supplierUnit: item.invoiceUnit ?? item.unit,
        stockUnit: product.unit,
        conversionFactor: result.purchasePackageFactor,
      );
      await _load();
      _notice('Produto cadastrado e associado a este fornecedor.');
    } on ApiException catch (error) {
      _notice(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirm() async {
    final entry = _entry;
    if (entry == null) return;
    if (entry.items.any((item) => item.productId == null)) {
      _notice('Vincule todos os produtos antes de confirmar o recebimento.');
      return;
    }
    final partialReturns = entry.items.where((item) {
      final expected = item.invoiceQuantity ?? item.quantity;
      final received = item.receivedQuantity ?? 0;
      return !_returnAll && received < expected && item.checkStatus != 'return';
    }).toList();
    if (_returnAll ||
        partialReturns.isNotEmpty ||
        entry.items.any((item) => item.checkStatus == 'return')) {
      final message = _returnAll
          ? 'A nota inteira será encaminhada para devolução e não movimentará o estoque.'
          : 'Há itens ou quantidades para devolução. O sistema preparará a devolução no computador e dará entrada somente no que foi conferido.';
      final proceed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Devolução identificada'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Voltar e revisar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Finalizar recebimento'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }
    setState(() => _saving = true);
    try {
      await _api.confirmOpenStockEntry(
        widget.session.token,
        entry.id,
        returnAll: _returnAll,
      );
      if (_returnAll ||
          partialReturns.isNotEmpty ||
          entry.items.any((item) => item.checkStatus == 'return')) {
        final devolutionDraft = await _api.createStockDevolutionDraft(
          widget.session.token,
          entry.id,
          mode: _returnAll ? 'full' : 'partial',
        );
        await _api.authorizeFiscalDocument(
          widget.session.token,
          devolutionDraft['fiscal_document_id'] as int,
        );
      }
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (error) {
      _notice(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _notice(String message) {
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  String _number(double value) =>
      value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(3);

  String _displayDate(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final parsed = DateTime.tryParse(value);
    if (parsed == null) return value;
    return '${parsed.day.toString().padLeft(2, '0')}/${parsed.month.toString().padLeft(2, '0')}/${parsed.year}';
  }

  String? _storageDate(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final match = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(normalized);
    if (match == null) return null;
    final parsed = DateTime(
      int.parse(match.group(3)!),
      int.parse(match.group(2)!),
      int.parse(match.group(1)!),
    );
    if (parsed.day != int.parse(match.group(1)!) ||
        parsed.month != int.parse(match.group(2)!)) {
      return null;
    }
    return '${parsed.year.toString().padLeft(4, '0')}-${parsed.month.toString().padLeft(2, '0')}-${parsed.day.toString().padLeft(2, '0')}';
  }

  String _notesFromSavedCheck(String? notes) {
    final cleaned =
        notes
            ?.replaceFirst(
              RegExp(r'^Condição: [^\n]+\n?', caseSensitive: false),
              '',
            )
            .trim() ??
        '';
    if (cleaned == 'Recebida por XML. Conferência iniciada pelo usuário.' ||
        cleaned == 'Conferido manualmente no recebimento.') {
      return '';
    }
    return cleaned;
  }

  String _buildCheckNotes(int itemId) => _notes[itemId]?.text.trim() ?? '';

  Future<void> _pickExpirationDate(int itemId) async {
    final parsed = _storageDate(_expirationDates[itemId]?.text ?? '');
    final selected = await showDatePicker(
      context: context,
      initialDate: parsed == null ? DateTime.now() : DateTime.parse(parsed),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Selecione a validade',
    );
    if (selected != null && mounted) {
      setState(() {
        _expirationDates[itemId]?.text =
            '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
      });
    }
  }

  Future<void> _pickManufacturingDate(int itemId) async {
    final parsed = _storageDate(_manufacturingDates[itemId]?.text ?? '');
    final selected = await showDatePicker(
      context: context,
      initialDate: parsed == null ? DateTime.now() : DateTime.parse(parsed),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Selecione a fabricação',
    );
    if (selected != null && mounted) {
      setState(() {
        _manufacturingDates[itemId]?.text =
            '${selected.day.toString().padLeft(2, '0')}/${selected.month.toString().padLeft(2, '0')}/${selected.year}';
      });
    }
  }

  Future<void> _addLot(StockEntryItem item) async {
    final itemId = item.id;
    if (itemId == null) return;
    final lot = TextEditingController();
    final quantity = TextEditingController();
    final expiration = TextEditingController();
    final manufacturing = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Adicionar lote'),
        content: SizedBox(
          width: 460,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: lot,
                decoration: const InputDecoration(labelText: 'Lote'),
              ),
              TextField(
                controller: quantity,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Quantidade conferida',
                ),
              ),
              TextField(
                controller: manufacturing,
                decoration: const InputDecoration(
                  labelText: 'Fabricação (AAAA-MM-DD)',
                ),
              ),
              TextField(
                controller: expiration,
                decoration: const InputDecoration(
                  labelText: 'Validade (AAAA-MM-DD)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Adicionar'),
          ),
        ],
      ),
    );
    final lotNumber = lot.text.trim();
    final lotQuantity = double.tryParse(
      quantity.text.trim().replaceAll(',', '.'),
    );
    final manufacturingDate = manufacturing.text.trim().isEmpty
        ? null
        : manufacturing.text.trim();
    final expirationDate = expiration.text.trim().isEmpty
        ? null
        : expiration.text.trim();
    lot.dispose();
    quantity.dispose();
    expiration.dispose();
    manufacturing.dispose();
    if (result != true || lotQuantity == null || lotQuantity <= 0) {
      if (result == true) _notice('Informe uma quantidade válida para o lote.');
      return;
    }
    setState(() => _saving = true);
    try {
      await _api.addStockEntryItemLot(
        widget.session.token,
        widget.entryId,
        itemId,
        lotNumber: lotNumber.isEmpty ? null : lotNumber,
        manufacturingDate: manufacturingDate,
        expirationDate: expirationDate,
        quantity: lotQuantity,
      );
      await _load();
    } on ApiException catch (error) {
      _notice(error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final entry = _entry;
    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text('Recebimento de mercadorias'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xff172b4d),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : entry == null
          ? const SizedBox()
          : LayoutBuilder(
              builder: (context, constraints) {
                final items = entry.items;
                final counted = items
                    .where((item) => (item.receivedQuantity ?? 0) > 0)
                    .length;
                final missing = items
                    .where((item) => item.productId == null)
                    .length;
                final hasDifferences = items.any((item) {
                  final expected = item.invoiceQuantity ?? item.quantity;
                  return (item.receivedQuantity ?? 0) < expected ||
                      item.checkStatus == 'return';
                });
                return Stack(
                  children: [
                    Column(
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            padding: EdgeInsets.all(
                              constraints.maxWidth > 700 ? 24 : 12,
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Wrap(
                                      spacing: 28,
                                      runSpacing: 12,
                                      children: [
                                        Text(
                                          'NF ${entry.invoiceNumber ?? entry.id}',
                                          style: const TextStyle(
                                            fontSize: 22,
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        Text(
                                          entry.supplierName ??
                                              'Fornecedor não identificado',
                                        ),
                                        Text(
                                          'CNPJ ${entry.supplierDocument ?? '—'}',
                                        ),
                                        Chip(
                                          label: const Text(
                                            'Aguardando recebimento',
                                          ),
                                          backgroundColor: const Color(
                                            0xffe0f2fe,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Wrap(
                                  spacing: 12,
                                  runSpacing: 10,
                                  children: [
                                    _summary('Itens', '${items.length}'),
                                    _summary('Conferidos', '$counted'),
                                    _summary(
                                      'Produtos não associados',
                                      '$missing',
                                    ),
                                    OutlinedButton.icon(
                                      onPressed: _saving ? null : _load,
                                      icon: const Icon(Icons.sync),
                                      label: const Text('Atualizar coletor'),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                if (hasDifferences ||
                                    widget.session.can('stock:entries:return'))
                                  Card(
                                    color: const Color(0xfffff7ed),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(
                                            Icons.warning_amber_outlined,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              hasDifferences
                                                  ? 'Foram encontradas diferenças. O sistema preparará automaticamente a devolução dos itens/quantidades não recebidos.'
                                                  : 'Se necessário, marque a nota inteira para devolução. Nenhuma emissão será feita pelo celular.',
                                            ),
                                          ),
                                          if (widget.session.can(
                                            'stock:entries:return',
                                          ))
                                            Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Text(
                                                  'Devolver nota inteira',
                                                ),
                                                Checkbox(
                                                  value: _returnAll,
                                                  onChanged: _saving
                                                      ? null
                                                      : (value) => setState(
                                                          () => _returnAll =
                                                              value ?? false,
                                                        ),
                                                ),
                                              ],
                                            ),
                                        ],
                                      ),
                                    ),
                                  ),
                                if (hasDifferences ||
                                    widget.session.can('stock:entries:return'))
                                  const SizedBox(height: 12),
                                Card(
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Column(
                                      children: [
                                        for (
                                          var index = 0;
                                          index < items.length;
                                          index++
                                        ) ...[
                                          if (index > 0) const Divider(),
                                          _itemRow(items[index]),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              constraints.maxWidth > 700 ? 24 : 12,
                              0,
                              constraints.maxWidth > 700 ? 24 : 12,
                              constraints.maxWidth > 700 ? 16 : 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton(
                                  onPressed: _saving
                                      ? null
                                      : () => Navigator.pop(context),
                                  child: const Text('Voltar'),
                                ),
                                const SizedBox(width: 10),
                                FilledButton.icon(
                                  onPressed: _saving ? null : _confirm,
                                  icon: const Icon(Icons.check_circle_outline),
                                  label: Text(
                                    _saving
                                        ? 'Processando...'
                                        : 'Confirmar recebimento',
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_saving)
                      Positioned.fill(
                        child: ColoredBox(
                          color: Color(0x990f172a),
                          child: Center(
                            child: Card(
                              child: Padding(
                                padding: EdgeInsets.symmetric(
                                  horizontal: 28,
                                  vertical: 24,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      width: 34,
                                      height: 34,
                                      child: CircularProgressIndicator(),
                                    ),
                                    SizedBox(height: 16),
                                    Text(
                                      'Processando recebimento',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(height: 6),
                                    Text(
                                      'Preparando e enviando a devolução para autorização...',
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  Widget _summary(String label, String value) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(10),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xff64748b))),
        Text(
          value,
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );

  Widget _itemRow(StockEntryItem item) {
    final itemId = item.id;
    if (itemId == null) return const SizedBox.shrink();
    final pending = item.productId == null;
    final expected = item.invoiceQuantity ?? item.quantity;
    final enteredCount = double.tryParse(
      (_quantities[itemId]?.text ?? '').replaceAll(',', '.'),
    );
    final counted = enteredCount ?? (item.receivedQuantity ?? 0);
    final difference = counted - expected;
    final hasCount = counted > 0;
    final needsJustification = hasCount && difference != 0;
    return Card(
      elevation: 0,
      color: const Color(0xfffafbff),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 12,
              runSpacing: 8,
              children: [
                SizedBox(
                  width: 330,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.description,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Fornecedor: ${item.supplierProductCode ?? 'sem código'} • GTIN: ${item.barcode ?? 'não informado'}${item.taxGtin == null ? '' : ' • GTIN trib.: ${item.taxGtin}'}',
                        style: const TextStyle(color: Color(0xff64748b)),
                      ),
                    ],
                  ),
                ),
                Chip(label: Text('NF: ${_number(expected)} ${item.unit}')),
                if (item.packageConversionFactor != null)
                  Chip(
                    label: Text(
                      '${_number(item.invoiceQuantity ?? expected)} ${item.invoiceUnit ?? item.unit} × ${_number(item.packageConversionFactor!)} = ${_number(expected)} ${item.unit}',
                    ),
                    backgroundColor: const Color(0xffe0f2fe),
                  ),
                if (!hasCount)
                  const Chip(label: Text('Aguardando contagem'))
                else if (difference != 0)
                  Chip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: Text(
                      difference > 0
                          ? '${_number(difference)} a mais'
                          : '${_number(-difference)} a menos',
                    ),
                    backgroundColor: const Color(0xfffff3e6),
                  ),
                if (pending) ...[
                  const Chip(
                    avatar: Icon(Icons.error_outline, size: 18),
                    label: Text('Produto não cadastrado'),
                    backgroundColor: Color(0xfffff3e6),
                  ),
                  OutlinedButton.icon(
                    onPressed: _saving ? null : () => _matchProduct(item),
                    icon: const Icon(Icons.link),
                    label: const Text('Associar produto'),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _saving
                        ? null
                        : () => _createAndMatchProduct(item),
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Cadastrar a partir do XML'),
                  ),
                ] else
                  const Chip(
                    avatar: Icon(Icons.check_circle_outline, size: 18),
                    label: Text('Produto associado'),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (widget.session.can('stock:entries:return'))
                  SizedBox(
                    width: 245,
                    child: DropdownButtonFormField<String>(
                      initialValue: _statuses[itemId] ?? 'accepted',
                      decoration: const InputDecoration(
                        labelText: 'Destino do item',
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'accepted',
                          child: Text('Receber no estoque'),
                        ),
                        DropdownMenuItem(
                          value: 'return',
                          child: Text('Devolver ao fornecedor'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setState(() => _statuses[itemId] = value);
                        }
                      },
                    ),
                  ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _quantities[itemId],
                    onChanged: (_) => setState(() {}),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Quantidade conferida',
                      isDense: true,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _saving ? null : () => _addLot(item),
                  icon: const Icon(Icons.layers_outlined),
                  label: const Text('Adicionar lote'),
                ),
                SizedBox(
                  width: 180,
                  child: TextField(
                    controller: _batches[itemId],
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(
                      labelText: 'Lote',
                      hintText: 'Informe o lote',
                      isDense: true,
                    ),
                  ),
                ),
                SizedBox(
                  width: 175,
                  child: TextField(
                    controller: _expirationDates[itemId],
                    readOnly: true,
                    onTap: () => _pickExpirationDate(itemId),
                    decoration: InputDecoration(
                      labelText: 'Validade',
                      hintText: 'DD/MM/AAAA',
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: 'Selecionar validade',
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: () => _pickExpirationDate(itemId),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 175,
                  child: TextField(
                    controller: _manufacturingDates[itemId],
                    readOnly: true,
                    onTap: () => _pickManufacturingDate(itemId),
                    decoration: InputDecoration(
                      labelText: 'Fabricação',
                      hintText: 'DD/MM/AAAA',
                      isDense: true,
                      suffixIcon: IconButton(
                        tooltip: 'Selecionar fabricação',
                        icon: const Icon(Icons.calendar_month_outlined),
                        onPressed: () => _pickManufacturingDate(itemId),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: 130,
                  child: TextField(
                    controller: _temperatures[itemId],
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Temperatura °C',
                      isDense: true,
                    ),
                  ),
                ),
                if (needsJustification)
                  SizedBox(
                    width: 360,
                    child: TextField(
                      controller: _notes[itemId],
                      maxLines: 1,
                      decoration: const InputDecoration(
                        labelText: 'Justificativa da divergência',
                        hintText: 'Informe o motivo da diferença',
                        isDense: true,
                      ),
                    ),
                  ),
                FilledButton.icon(
                  onPressed: _saving ? null : () => _saveQuantity(item),
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar item'),
                ),
              ],
            ),
            if (item.lots.isNotEmpty) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: item.lots
                    .map(
                      (lot) => Chip(
                        avatar: const Icon(
                          Icons.inventory_2_outlined,
                          size: 16,
                        ),
                        label: Text(
                          '${lot.lotNumber ?? 'Sem lote'} • ${_number(lot.quantity)} ${item.unit}',
                        ),
                      ),
                    )
                    .toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
