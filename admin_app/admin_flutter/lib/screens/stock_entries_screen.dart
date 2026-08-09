import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xml/xml.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../models/stock_entry.dart';
import '../models/supplier.dart';
import '../services/api_client.dart';
import '../services/file_download.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _stockEntryUnitOptions = {
  'un': 'Unidade',
  'pc': 'Peça',
  'eb': 'Embalagem',
  'cx': 'Caixa',
  'pct': 'Pacote',
  'fd': 'Fardo',
  'kg': 'Quilo',
  'g': 'Grama',
  'l': 'Litro',
  'ml': 'Mililitro',
};

class StockEntriesScreen extends StatefulWidget {
  const StockEntriesScreen({super.key, required this.session});

  final Session session;

  @override
  State<StockEntriesScreen> createState() => _StockEntriesScreenState();
}

class _StockEntriesScreenState extends State<StockEntriesScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<Product> _products = [];
  List<Supplier> _suppliers = [];
  List<StockEntry> _entries = [];
  List<XmlInboxMessage> _xmlInboxMessages = [];
  XmlInboxSettings? _xmlInboxSettings;
  List<StockEntryItem> _items = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _message;
  int? _supplierId;
  int? _productId;
  final _supplierName = TextEditingController();
  final _supplierDocument = TextEditingController();
  final _invoiceKey = TextEditingController();
  final _invoiceNumber = TextEditingController();
  final _invoiceSeries = TextEditingController();
  final _quantity = TextEditingController(text: '1');
  final _unitCost = TextEditingController(text: '0,00');
  final _notes = TextEditingController();
  final _xml = TextEditingController();
  final _accessKey = TextEditingController();
  final _entrySearch = TextEditingController();
  String? _xmlSupplierDocument;
  String _entrySource = 'manual';
  String _entrySourceFilter = 'todos';
  String _entryStatusFilter = 'abertas';
  String _entryMode = 'xml';
  int? _editingEntryId;
  int? _generatingXmlReceiptId;
  bool _showWorkspace = false;

  Product? get _selectedProduct {
    for (final product in _products) {
      if (product.id == _productId) return product;
    }
    return null;
  }

  Product? _productById(int? productId) {
    if (productId == null) return null;
    for (final product in _products) {
      if (product.id == productId) return product;
    }
    return null;
  }

  bool _hasPurchaseConversion(Product? product) {
    return product != null &&
        product.purchaseConversionEnabled &&
        (product.purchasePackageFactor ?? 0) > 0;
  }

  StockEntryItem _withProductPurchaseDefault(
    StockEntryItem item,
    Product? product,
  ) {
    if (!_hasPurchaseConversion(product)) return item;
    final factor = product!.purchasePackageFactor!;
    final invoiceQuantity = item.invoiceQuantity ?? item.quantity;
    final stockQuantity = invoiceQuantity * factor;
    if (stockQuantity <= 0) return item;
    final unitCost = item.totalCost > 0
        ? item.totalCost / stockQuantity
        : item.unitCost;
    return StockEntryItem(
      productId: product.id,
      description: item.description,
      barcode: item.barcode,
      invoiceQuantity: invoiceQuantity,
      invoiceUnit: product.purchaseInvoiceUnit ?? item.invoiceUnit ?? item.unit,
      packageConversionFactor: factor,
      quantity: stockQuantity,
      receivedQuantity: stockQuantity,
      unit: product.unit,
      unitCost: unitCost,
      totalCost: item.totalCost,
      ncm: item.ncm,
      cfop: item.cfop,
      ibsCbsCst: item.ibsCbsCst,
      ibsCbsClassification: item.ibsCbsClassification,
      cbsRate: item.cbsRate,
      ibsStateRate: item.ibsStateRate,
      ibsCityRate: item.ibsCityRate,
      selectiveTaxCst: item.selectiveTaxCst,
      selectiveTaxClassification: item.selectiveTaxClassification,
      selectiveTaxRate: item.selectiveTaxRate,
      batchNumber: item.batchNumber,
      expirationDate: item.expirationDate,
      checkStatus: item.checkStatus,
      checkNotes: item.checkNotes,
    );
  }

  bool get _canCreateEntry => widget.session.can('stock:entries:create');
  bool get _canConfirmEntry => widget.session.can('stock:entries:confirm');
  bool get _canReturnEntry => widget.session.can('stock:entries:return');
  bool get _canCreateSupplier =>
      widget.session.can('suppliers:create') ||
      widget.session.can('stock:entries:create');
  bool get _canCreateProductFromXml =>
      widget.session.can('stock:entries:create_product_from_xml') &&
      widget.session.can('products:create');

  String? _digitsOnly(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    return digits.isEmpty ? null : digits;
  }

  void _clearWorkspace({bool hide = true}) {
    setState(() {
      _editingEntryId = null;
      _showWorkspace = !hide;
      _supplierId = null;
      _xmlSupplierDocument = null;
      _supplierName.clear();
      _supplierDocument.clear();
      _invoiceKey.clear();
      _invoiceNumber.clear();
      _invoiceSeries.clear();
      _notes.clear();
      _xml.clear();
      _accessKey.clear();
      _items = [];
      _entrySource = 'manual';
      _entryMode = 'xml';
    });
  }

  void _startNewEntry() {
    _clearWorkspace(hide: false);
    setState(() {
      _message = null;
      _error = null;
    });
  }

  Future<void> _openEntryOnComputer(StockEntry entry) async {
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final current = await _api.getStockEntry(widget.session.token, entry.id);
      if (!mounted) return;
      setState(() {
        _editingEntryId = current.id;
        _showWorkspace = true;
        _supplierId = current.supplierId;
        _supplierName.text = current.supplierName ?? '';
        _supplierDocument.text = current.supplierDocument ?? '';
        _xmlSupplierDocument = current.source == 'manual'
            ? null
            : _digitsOnly(current.supplierDocument);
        _invoiceKey.text = current.invoiceKey ?? '';
        _invoiceNumber.text = current.invoiceNumber ?? '';
        _invoiceSeries.text = current.invoiceSeries ?? '';
        _notes.text = current.notes ?? '';
        _items = List<StockEntryItem>.from(current.items);
        _entrySource = current.source;
        _entryMode = switch (current.source) {
          'spreadsheet' => 'spreadsheet',
          'nfe_key' => 'key',
          'manual' => 'manual',
          _ => 'xml',
        };
        _message =
            'Entrada #${current.id} aberta no computador. Confira os itens e salve ou finalize.';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _generateReceiptFromXml(XmlInboxMessage message) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gerar recebimento?'),
        content: Text(
          'O XML da NF ${message.invoiceNumber ?? message.invoiceKey ?? message.id} vai virar uma entrada em conferência. Depois disso você poderá conferir itens, lotes, validade e finalizar o recebimento.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Agora não'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.playlist_add_check_outlined),
            label: const Text('Gerar recebimento'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() {
      _generatingXmlReceiptId = message.id;
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final entry = await _api.createReceiptFromXmlInbox(
        widget.session.token,
        message.id,
      );
      await _load();
      if (!mounted) return;
      await _openEntryOnComputer(entry);
      if (!mounted) return;
      setState(
        () => _message =
            'Recebimento #${entry.id} gerado a partir do XML. Confira antes de finalizar.',
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) {
        setState(() {
          _generatingXmlReceiptId = null;
          _saving = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    for (final controller in [
      _supplierName,
      _supplierDocument,
      _invoiceKey,
      _invoiceNumber,
      _invoiceSeries,
      _quantity,
      _unitCost,
      _notes,
      _xml,
      _accessKey,
      _entrySearch,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listProducts(widget.session.token, active: true),
        _api.listSuppliers(widget.session.token),
        _api.listStockEntries(widget.session.token),
        _api.getXmlInboxSettings(widget.session.token),
        _api.listXmlInboxMessages(widget.session.token),
      ]);
      setState(() {
        _products = results[0] as List<Product>;
        _suppliers = results[1] as List<Supplier>;
        _entries = results[2] as List<StockEntry>;
        _xmlInboxSettings = results[3] as XmlInboxSettings;
        _xmlInboxMessages = results[4] as List<XmlInboxMessage>;
        _productId ??= _products.isNotEmpty ? _products.first.id : null;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar entradas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _addManualItem() {
    final product = _selectedProduct;
    if (product == null) return;
    final quantity = parseBrazilianNumber(_quantity.text);
    final unitCost = parseBrazilianNumber(_unitCost.text);
    if (quantity <= 0) return;
    setState(() {
      _entrySource = 'manual';
      _items.add(
        StockEntryItem(
          productId: product.id,
          description: product.name,
          barcode: product.barcode ?? product.internalCode,
          quantity: quantity,
          receivedQuantity: quantity,
          unit: product.unit,
          unitCost: unitCost,
          totalCost: quantity * unitCost,
          ncm: product.ncm,
          cfop: product.cfopSale,
          ibsCbsCst: product.ibsCbsCst,
          ibsCbsClassification: product.ibsCbsClassification,
          cbsRate: product.cbsRate,
          ibsStateRate: product.ibsStateRate,
          ibsCityRate: product.ibsCityRate,
          selectiveTaxCst: product.selectiveTaxCst,
          selectiveTaxClassification: product.selectiveTaxClassification,
          selectiveTaxRate: product.selectiveTaxRate,
          checkStatus: 'accepted',
        ),
      );
    });
  }

  Future<void> _previewXml() async {
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final preview = await _api.previewNfeXml(widget.session.token, _xml.text);
      final items = <StockEntryItem>[];
      for (final item in preview.items) {
        final entryItem = StockEntryItem(
          productId: item.productId,
          description: item.description,
          barcode: item.barcode,
          quantity: item.quantity,
          receivedQuantity: item.quantity,
          unit: item.unit,
          unitCost: item.unitCost,
          totalCost: item.totalCost,
          ncm: item.ncm,
          cfop: item.cfop,
          ibsCbsCst: item.ibsCbsCst,
          ibsCbsClassification: item.ibsCbsClassification,
          cbsRate: item.cbsRate,
          ibsStateRate: item.ibsStateRate,
          ibsCityRate: item.ibsCityRate,
          selectiveTaxCst: item.selectiveTaxCst,
          selectiveTaxClassification: item.selectiveTaxClassification,
          selectiveTaxRate: item.selectiveTaxRate,
          batchNumber: item.batchNumber,
          expirationDate: item.expirationDate,
          checkStatus: item.productId == null ? 'pending_product' : 'accepted',
        );
        items.add(
          _withProductPurchaseDefault(entryItem, _productById(item.productId)),
        );
      }
      setState(() {
        _supplierId = preview.supplierId;
        _supplierName.text = preview.supplierName ?? '';
        _supplierDocument.text = preview.supplierDocument ?? '';
        _xmlSupplierDocument = _digitsOnly(preview.supplierDocument);
        _invoiceKey.text = preview.invoiceKey ?? '';
        _invoiceNumber.text = preview.invoiceNumber ?? '';
        _invoiceSeries.text = preview.invoiceSeries ?? '';
        _items = items;
        _entrySource = 'xml';
        final missing = items.where((item) => item.productId == null).length;
        final supplierMessage =
            preview.supplierId == null &&
                (preview.supplierDocument ?? '').isNotEmpty
            ? ' Fornecedor não cadastrado; cadastre ou confira antes de confirmar.'
            : ' Fornecedor vinculado automaticamente pelo CNPJ.';
        _message = missing > 0
            ? 'XML lido. $missing item(ns) precisam de decisao na conferência.$supplierMessage'
            : 'XML lido. Todos os itens foram vinculados automaticamente; confira quantidades, lote e validade.$supplierMessage';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickXmlFile() async {
    setState(() {
      _error = null;
      _message = null;
    });
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['xml'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final bytes = result.files.single.bytes;
    if (bytes == null) {
      setState(
        () => _error = 'Não foi possível ler o arquivo XML selecionado.',
      );
      return;
    }
    _xml.text = String.fromCharCodes(bytes);
    await _previewXml();
  }

  void _downloadImportTemplate() {
    const headers = [
      'fornecedor_nome',
      'fornecedor_documento',
      'número_nf',
      'serie_nf',
      'chave_nfe',
      'código_interno',
      'código_barras',
      'nome_produto',
      'unidade',
      'quantidade',
      'custo_unitario',
      'preço_venda',
      'estoque_minimo',
      'categoria',
      'marca',
      'ncm',
      'cfop',
      'lote',
      'validade',
      'observacao',
    ];
    const examples = [
      [
        'Fornecedor Exemplo LTDA',
        '12345678000190',
        '1001',
        '1',
        '35260612345678000190550010000010011000010011',
        'PROD001',
        '7891234567895',
        'Acucar Refinado 1kg',
        'UN',
        '10',
        '4,50',
        '6,99',
        '3',
        'Mercearia',
        'Marca Exemplo',
        '17019900',
        '1102',
        'LOTE-001',
        '31/12/2026',
        'Primeira carga',
      ],
      [
        'Fornecedor Exemplo LTDA',
        '12345678000190',
        '1001',
        '1',
        '35260612345678000190550010000010011000010011',
        'PROD002',
        '7891234567802',
        'Leite Integral 1L',
        'UN',
        '24',
        '3,20',
        '5,49',
        '6',
        'Laticinios',
        'Marca Exemplo',
        '04012010',
        '1102',
        'LOTE-002',
        '20/08/2026',
        '',
      ],
    ];
    downloadBytesFile(
      filename: 'modelo_entrada_mercadorias.xlsx',
      mimeType:
          'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      bytes: _buildXlsxTemplate(headers: headers, rows: examples),
    );
  }

  Future<void> _pickSpreadsheetFile() async {
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['xlsx', 'csv', 'txt'],
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final bytes = result.files.single.bytes;
      if (bytes == null) {
        setState(() => _error = 'Não foi possível ler o arquivo selecionado.');
        return;
      }
      final extension = result.files.single.extension?.toLowerCase();
      final content = extension == 'xlsx'
          ? _readXlsxFirstSheet(bytes)
          : _decodeSpreadsheetBytes(bytes);
      await _importSpreadsheetContent(content);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Não foi possível importar a planilha: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _importSpreadsheetContent(String content) async {
    final rows = _parseDelimitedRows(content);
    if (rows.length < 2) {
      throw const FormatException('a planilha precisa ter cabecalho e itens.');
    }
    final headers = rows.first.map(_normalizeHeader).toList();
    final importedItems = <StockEntryItem>[];
    var pendingProducts = 0;

    for (final row in rows.skip(1)) {
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final data = <String, String>{};
      for (var i = 0; i < headers.length && i < row.length; i++) {
        data[headers[i]] = _cleanSpreadsheetCell(row[i]);
      }
      final description = _cell(data, 'nome_produto', aliases: ['produto']);
      if (description == null || description.length < 2) continue;
      _applySpreadsheetHeader(data);

      final barcode = _cell(data, 'código_barras');
      final internalCode = _cell(data, 'código_interno');
      final quantity = _numberCell(data, 'quantidade', fallback: 0);
      final unitCost = _numberCell(data, 'custo_unitario', fallback: 0);
      if (quantity <= 0) {
        throw FormatException('quantidade invalida para "$description".');
      }

      final product = _findProductByCodes(barcode: barcode, code: internalCode);
      if (product == null) pendingProducts++;
      final entryItem = StockEntryItem(
        productId: product?.id,
        description: description,
        barcode: barcode ?? internalCode,
        quantity: quantity,
        receivedQuantity: quantity,
        unit: _cell(data, 'unidade') ?? product?.unit ?? 'un',
        unitCost: unitCost,
        totalCost: quantity * unitCost,
        ncm: _cell(data, 'ncm') ?? product?.ncm,
        cfop: _cell(data, 'cfop') ?? product?.cfopSale,
        batchNumber: _cell(data, 'lote'),
        expirationDate: _parseDateCell(_cell(data, 'validade')),
        checkStatus: product == null ? 'pending_product' : 'accepted',
        checkNotes: _cell(data, 'observacao'),
      );
      importedItems.add(_withProductPurchaseDefault(entryItem, product));
    }
    if (importedItems.isEmpty) {
      throw const FormatException('nenhum item valido encontrado.');
    }
    setState(() {
      _items = importedItems;
      _entrySource = 'spreadsheet';
      _message =
          'Planilha importada com ${importedItems.length} item(ns). '
          '$pendingProducts item(ns) precisam ser vinculados antes da confirmacao.';
    });
  }

  Future<void> _downloadByKey() async {
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final data = await _api.downloadNfeByKey(
        widget.session.token,
        _accessKey.text,
      );
      setState(() => _message = data['message']?.toString());
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editItem(int index) async {
    final item = _items[index];
    int? productId = item.productId;
    var status = item.checkStatus;
    var convertPackage =
        item.invoiceQuantity != null ||
        item.invoiceUnit != null ||
        (item.packageConversionFactor != null &&
            item.packageConversionFactor != 1);
    final invoiceQuantity = TextEditingController(
      text: formatBrazilianDecimal(item.invoiceQuantity ?? item.quantity),
    );
    String invoiceUnit = item.invoiceUnit ?? item.unit;
    final conversionFactor = TextEditingController(
      text: formatBrazilianDecimal(item.packageConversionFactor ?? 1),
    );
    final received = TextEditingController(
      text: formatBrazilianDecimal(item.receivedQuantity ?? item.quantity),
    );
    final initialProduct = _productById(productId);
    if (!convertPackage && _hasPurchaseConversion(initialProduct)) {
      final factor = initialProduct!.purchasePackageFactor!;
      convertPackage = true;
      invoiceQuantity.text = formatBrazilianDecimal(
        item.invoiceQuantity ?? item.quantity,
      );
      invoiceUnit =
          initialProduct.purchaseInvoiceUnit ?? item.invoiceUnit ?? item.unit;
      conversionFactor.text = formatBrazilianDecimal(factor);
      received.text = formatBrazilianDecimal(
        parseBrazilianNumber(invoiceQuantity.text) * factor,
      );
    }
    final batch = TextEditingController(text: item.batchNumber ?? '');
    final notes = TextEditingController(text: item.checkNotes ?? '');
    DateTime? expirationDate = item.expirationDate == null
        ? null
        : DateTime.tryParse(item.expirationDate!);

    final updated = await showDialog<StockEntryItem>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Conferir ${item.description}'),
              content: SizedBox(
                width: 720,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Nota: ${formatBrazilianDecimal(item.quantity)} ${item.unit} | Custo ${formatBrazilianMoney(item.unitCost)}',
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      initialValue: productId,
                      decoration: const InputDecoration(
                        labelText: 'Produto vinculado',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('Sem cadastro / decidir depois'),
                        ),
                        for (final product in _products)
                          DropdownMenuItem(
                            value: product.id,
                            child: Text('${product.name} | ${product.unit}'),
                          ),
                      ],
                      onChanged: (value) => setDialogState(() {
                        productId = value;
                        final product = _productById(value);
                        if (_hasPurchaseConversion(product)) {
                          final factor = product!.purchasePackageFactor!;
                          convertPackage = true;
                          invoiceQuantity.text = formatBrazilianDecimal(
                            item.invoiceQuantity ?? item.quantity,
                          );
                          invoiceUnit =
                              product.purchaseInvoiceUnit ??
                              item.invoiceUnit ??
                              item.unit;
                          conversionFactor.text = formatBrazilianDecimal(
                            factor,
                          );
                          received.text = formatBrazilianDecimal(
                            parseBrazilianNumber(invoiceQuantity.text) * factor,
                          );
                        } else if (product != null &&
                            product.unit != item.unit) {
                          convertPackage = true;
                          invoiceQuantity.text = formatBrazilianDecimal(
                            item.invoiceQuantity ?? item.quantity,
                          );
                          invoiceUnit = item.invoiceUnit ?? item.unit;
                        }
                      }),
                    ),
                    if (productId == null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Text(
                          'Produto ainda não cadastrado/vinculado. Selecione um produto existente acima ou clique em "Cadastrar produto". No cadastro o sistema pergunta se a nota veio por unidade, pacote, caixa ou fardo e quantas unidades entram no estoque.',
                          style: TextStyle(
                            color: Color(0xFF9A3412),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                    if (productId != null) ...[
                      const SizedBox(height: 12),
                      _ConversionBox(
                        enabled: convertPackage,
                        invoiceQuantity: invoiceQuantity,
                        invoiceUnit: invoiceUnit,
                        stockUnit: _productById(productId)?.unit ?? item.unit,
                        conversionFactor: conversionFactor,
                        originalUnit: item.unit,
                        onEnabledChanged: (value) => setDialogState(() {
                          convertPackage = value;
                          if (value) {
                            final factor = parseBrazilianNumber(
                              conversionFactor.text,
                            );
                            final invoiceQty = parseBrazilianNumber(
                              invoiceQuantity.text,
                            );
                            if (factor > 0 && invoiceQty > 0) {
                              received.text = formatBrazilianDecimal(
                                invoiceQty * factor,
                              );
                            }
                          }
                        }),
                        onInvoiceUnitChanged: (value) => setDialogState(
                          () => invoiceUnit = value ?? invoiceUnit,
                        ),
                        onRecalculate: () {
                          final factor = parseBrazilianNumber(
                            conversionFactor.text,
                          );
                          final invoiceQty = parseBrazilianNumber(
                            invoiceQuantity.text,
                          );
                          if (factor > 0 && invoiceQty > 0) {
                            setDialogState(() {
                              received.text = formatBrazilianDecimal(
                                invoiceQty * factor,
                              );
                            });
                          }
                        },
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: received,
                            decoration: const InputDecoration(
                              labelText: 'Quantidade recebida',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: batch,
                            decoration: const InputDecoration(
                              labelText: 'Lote',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked = await showDatePicker(
                                context: context,
                                initialDate: expirationDate ?? DateTime.now(),
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2100),
                              );
                              if (picked != null) {
                                setDialogState(() => expirationDate = picked);
                              }
                            },
                            icon: const Icon(Icons.calendar_month_outlined),
                            label: Text(
                              expirationDate == null
                                  ? 'Validade'
                                  : _dateOnly(expirationDate!),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: status,
                            decoration: const InputDecoration(
                              labelText: 'Decisao',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'accepted',
                                child: Text('Aceitar / entrar no estoque'),
                              ),
                              const DropdownMenuItem(
                                value: 'pending_product',
                                child: Text('Cadastrar ou vincular produto'),
                              ),
                              const DropdownMenuItem(
                                value: 'pending',
                                child: Text('Pendencia / divergencia'),
                              ),
                              if (_canReturnEntry || status == 'return')
                                DropdownMenuItem(
                                  value: 'return',
                                  child: Text('Devolver ao fornecedor'),
                                ),
                            ],
                            onChanged: (value) => setDialogState(
                              () => status = value ?? 'accepted',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: notes,
                      decoration: const InputDecoration(
                        labelText: 'Observação da conferência',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (_canCreateProductFromXml)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final conversion = await showDialog<_PackageConfig>(
                        context: dialogContext,
                        builder: (context) => _PackageConfigDialog(
                          item: item,
                          initialStockUnit: _defaultStockUnitForReceiptItem(
                            item,
                          ),
                        ),
                      );
                      if (conversion == null) return;
                      final stockQuantity =
                          conversion.invoiceQuantity * conversion.factor;
                      if (stockQuantity <= 0) {
                        setState(
                          () => _error = 'Informe uma conversão válida.',
                        );
                        return;
                      }
                      try {
                        final created = await _api.createProduct(
                          widget.session.token,
                          ProductPayload(
                            name: item.description,
                            productType: 'produto',
                            internalCode: item.barcode,
                            barcode: conversion.unitBarcode ?? item.barcode,
                            salePrice: 0,
                            purchaseTotalCost: item.totalCost,
                            purchaseQuantity: stockQuantity,
                            purchaseConversionEnabled:
                                conversion.factor != 1 ||
                                conversion.invoiceUnit != conversion.stockUnit,
                            purchaseInvoiceUnit: conversion.invoiceUnit,
                            purchasePackageFactor: conversion.factor,
                            purchasePackageBarcode: conversion.packageBarcode,
                            stockQuantity: 0,
                            minimumStock: 0,
                            unit: conversion.stockUnit,
                            tracksBatch:
                                item.batchNumber != null ||
                                item.expirationDate != null,
                            initialBatchNumber: item.batchNumber,
                            initialExpirationDate: item.expirationDate,
                            ncm: item.ncm,
                            cfopSale: item.cfop,
                            ibsCbsCst: item.ibsCbsCst,
                            ibsCbsClassification: item.ibsCbsClassification,
                            cbsRate: item.cbsRate,
                            ibsStateRate: item.ibsStateRate,
                            ibsCityRate: item.ibsCityRate,
                            selectiveTaxCst: item.selectiveTaxCst,
                            selectiveTaxClassification:
                                item.selectiveTaxClassification,
                            selectiveTaxRate: item.selectiveTaxRate,
                            newTaxSystem:
                                item.ibsCbsCst != null ||
                                item.ibsCbsClassification != null ||
                                item.selectiveTaxCst != null ||
                                item.selectiveTaxClassification != null,
                            active: true,
                          ),
                        );
                        setState(() => _products.add(created));
                        setDialogState(() {
                          productId = created.id;
                          status = 'accepted';
                          convertPackage =
                              conversion.factor != 1 ||
                              conversion.invoiceUnit != conversion.stockUnit;
                          invoiceQuantity.text = formatBrazilianDecimal(
                            conversion.invoiceQuantity,
                          );
                          invoiceUnit = conversion.invoiceUnit;
                          conversionFactor.text = formatBrazilianDecimal(
                            conversion.factor,
                          );
                          received.text = formatBrazilianDecimal(stockQuantity);
                          _error = null;
                        });
                      } on ApiException catch (error) {
                        setState(() => _error = error.message);
                      }
                    },
                    icon: const Icon(Icons.add_box_outlined),
                    label: const Text('Cadastrar produto'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: () {
                    final product = _productById(productId);
                    final stockUnit = product?.unit ?? item.unit;
                    final invoiceQty = parseBrazilianNumber(
                      invoiceQuantity.text,
                    );
                    final factor = parseBrazilianNumber(conversionFactor.text);
                    final convertedQuantity = convertPackage
                        ? invoiceQty * factor
                        : item.quantity;
                    final convertedReceived = convertPackage
                        ? parseBrazilianNumber(received.text)
                        : parseBrazilianNumber(received.text);
                    final unitCost = convertedQuantity > 0
                        ? item.totalCost / convertedQuantity
                        : item.unitCost;
                    Navigator.of(dialogContext).pop(
                      StockEntryItem(
                        productId: productId,
                        description: item.description,
                        barcode: item.barcode,
                        invoiceQuantity: convertPackage ? invoiceQty : null,
                        invoiceUnit: convertPackage ? invoiceUnit : null,
                        packageConversionFactor: convertPackage ? factor : null,
                        quantity: convertedQuantity,
                        receivedQuantity: convertedReceived,
                        unit: convertPackage ? stockUnit : item.unit,
                        unitCost: unitCost,
                        totalCost: item.totalCost,
                        ncm: item.ncm,
                        cfop: item.cfop,
                        ibsCbsCst: item.ibsCbsCst,
                        ibsCbsClassification: item.ibsCbsClassification,
                        cbsRate: item.cbsRate,
                        ibsStateRate: item.ibsStateRate,
                        ibsCityRate: item.ibsCityRate,
                        selectiveTaxCst: item.selectiveTaxCst,
                        selectiveTaxClassification:
                            item.selectiveTaxClassification,
                        selectiveTaxRate: item.selectiveTaxRate,
                        batchNumber: _emptyToNull(batch.text),
                        expirationDate: expirationDate == null
                            ? null
                            : _dateOnly(expirationDate!),
                        checkStatus: status,
                        checkNotes: _emptyToNull(notes.text),
                      ),
                    );
                  },
                  child: const Text('Salvar conferência'),
                ),
              ],
            );
          },
        );
      },
    );
    if (updated != null) {
      setState(() => _items[index] = updated);
    }
  }

  Future<void> _createAndLinkItemProduct(int index) async {
    if (!_canCreateProductFromXml) {
      setState(
        () => _error =
            'Seu usuario nao tem permissao para cadastrar produto pelo XML.',
      );
      return;
    }
    final item = _items[index];
    final conversion = await showDialog<_PackageConfig>(
      context: context,
      builder: (context) => _PackageConfigDialog(
        item: item,
        initialStockUnit: _defaultStockUnitForReceiptItem(item),
      ),
    );
    if (conversion == null) return;
    final stockQuantity = conversion.invoiceQuantity * conversion.factor;
    if (stockQuantity <= 0) {
      setState(() => _error = 'Informe uma conversao valida.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final created = await _api.createProduct(
        widget.session.token,
        ProductPayload(
          name: item.description,
          productType: 'produto',
          internalCode: item.barcode,
          barcode: conversion.unitBarcode ?? item.barcode,
          salePrice: 0,
          purchaseTotalCost: item.totalCost,
          purchaseQuantity: stockQuantity,
          purchaseConversionEnabled:
              conversion.factor != 1 ||
              conversion.invoiceUnit != conversion.stockUnit,
          purchaseInvoiceUnit: conversion.invoiceUnit,
          purchasePackageFactor: conversion.factor,
          purchasePackageBarcode: conversion.packageBarcode,
          stockQuantity: 0,
          minimumStock: 0,
          unit: conversion.stockUnit,
          tracksBatch: item.batchNumber != null || item.expirationDate != null,
          initialBatchNumber: item.batchNumber,
          initialExpirationDate: item.expirationDate,
          ncm: item.ncm,
          cfopSale: item.cfop,
          ibsCbsCst: item.ibsCbsCst,
          ibsCbsClassification: item.ibsCbsClassification,
          cbsRate: item.cbsRate,
          ibsStateRate: item.ibsStateRate,
          ibsCityRate: item.ibsCityRate,
          selectiveTaxCst: item.selectiveTaxCst,
          selectiveTaxClassification: item.selectiveTaxClassification,
          selectiveTaxRate: item.selectiveTaxRate,
          newTaxSystem:
              item.ibsCbsCst != null ||
              item.ibsCbsClassification != null ||
              item.selectiveTaxCst != null ||
              item.selectiveTaxClassification != null,
          active: true,
        ),
      );
      final unitCost = stockQuantity > 0
          ? item.totalCost / stockQuantity
          : item.unitCost;
      setState(() {
        _products.add(created);
        _items[index] = StockEntryItem(
          productId: created.id,
          description: item.description,
          barcode: item.barcode,
          invoiceQuantity: conversion.invoiceQuantity,
          invoiceUnit: conversion.invoiceUnit,
          packageConversionFactor: conversion.factor,
          quantity: stockQuantity,
          receivedQuantity: stockQuantity,
          unit: conversion.stockUnit,
          unitCost: unitCost,
          totalCost: item.totalCost,
          ncm: item.ncm,
          cfop: item.cfop,
          ibsCbsCst: item.ibsCbsCst,
          ibsCbsClassification: item.ibsCbsClassification,
          cbsRate: item.cbsRate,
          ibsStateRate: item.ibsStateRate,
          ibsCityRate: item.ibsCityRate,
          selectiveTaxCst: item.selectiveTaxCst,
          selectiveTaxClassification: item.selectiveTaxClassification,
          selectiveTaxRate: item.selectiveTaxRate,
          batchNumber: item.batchNumber,
          expirationDate: item.expirationDate,
          checkStatus: 'accepted',
          checkNotes: item.checkNotes,
        );
        _message =
            'Produto cadastrado e vinculado. Entrara ${formatBrazilianDecimal(stockQuantity)} ${conversion.stockUnit} no estoque.';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmEntry(String source) async {
    if (_items.isEmpty) {
      setState(() => _error = 'Adicione pelo menos um item para dar entrada.');
      return;
    }
    final blocked = _items.where((item) {
      final accepted = item.checkStatus == 'accepted';
      return accepted &&
          (item.productId == null || (item.receivedQuantity ?? 0) <= 0);
    }).length;
    if (blocked > 0) {
      setState(
        () => _error =
            '$blocked item(ns) aceitos precisam ter produto vinculado e quantidade recebida.',
      );
      return;
    }
    final effectiveItems = _items.where((item) {
      return item.checkStatus == 'accepted' ||
          item.checkStatus == 'return' ||
          item.checkStatus == 'pending' ||
          item.checkStatus == 'pending_product';
    }).toList();
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final payload = StockEntryPayload(
        supplierId: _supplierId,
        supplierName: _emptyToNull(_supplierName.text),
        supplierDocument: _emptyToNull(_supplierDocument.text),
        source: source,
        invoiceKey: _emptyToNull(_invoiceKey.text),
        invoiceNumber: _emptyToNull(_invoiceNumber.text),
        invoiceSeries: _emptyToNull(_invoiceSeries.text),
        notes: _emptyToNull(_notes.text),
        items: effectiveItems,
      );
      if (_editingEntryId == null) {
        await _api.createStockEntry(widget.session.token, payload);
      } else {
        await _api.updateOpenStockEntry(
          widget.session.token,
          _editingEntryId!,
          payload,
        );
        await _api.confirmOpenStockEntry(
          widget.session.token,
          _editingEntryId!,
        );
      }
      setState(() {
        _items = [];
        _editingEntryId = null;
        _showWorkspace = false;
        _entrySource = 'manual';
        _message =
            'Conferência confirmada. Itens aceitos entraram no estoque e custo medio foi atualizado.';
      });
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _sendEntryToMobile(String source) async {
    if (_items.isEmpty) {
      setState(
        () => _error = 'Adicione pelo menos um item para enviar ao celular.',
      );
      return;
    }
    final effectiveItems = _items.where((item) {
      return item.checkStatus == 'accepted' ||
          item.checkStatus == 'return' ||
          item.checkStatus == 'pending' ||
          item.checkStatus == 'pending_product';
    }).toList();
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final payload = StockEntryPayload(
        supplierId: _supplierId,
        supplierName: _emptyToNull(_supplierName.text),
        supplierDocument: _emptyToNull(_supplierDocument.text),
        source: source,
        invoiceKey: _emptyToNull(_invoiceKey.text),
        invoiceNumber: _emptyToNull(_invoiceNumber.text),
        invoiceSeries: _emptyToNull(_invoiceSeries.text),
        notes: _emptyToNull(_notes.text),
        items: effectiveItems,
      );
      final entry = _editingEntryId == null
          ? await _api.createOpenStockEntry(widget.session.token, payload)
          : await _api.updateOpenStockEntry(
              widget.session.token,
              _editingEntryId!,
              payload,
            );
      setState(() {
        _items = [];
        _editingEntryId = null;
        _showWorkspace = false;
        _entrySource = 'manual';
        _message =
            'Entrada #${entry.id} enviada para recebimento mobile. O estoque ainda não foi movimentado.';
      });
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _confirmExistingEntry(StockEntry entry) async {
    final proceed = await _showExistingEntryConference(entry);
    if (proceed != true) return;
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      await _api.confirmOpenStockEntry(widget.session.token, entry.id);
      setState(() {
        _message =
            'Entrada #${entry.id} finalizada. Estoque e custo medio atualizados.';
      });
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool?> _showExistingEntryConference(StockEntry entry) {
    final divergences = entry.items.where(_hasEntryItemDivergence).toList();
    return showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Conferência do recebimento'),
          content: SizedBox(
            width: 760,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _entryDisplayTitle(entry),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 12),
                  if (divergences.isEmpty)
                    const _ImportHint(
                      title: 'Sem divergencias',
                      text:
                          'As quantidades recebidas batem com a nota. Ao finalizar, o estoque será movimentado.',
                    )
                  else ...[
                    const Text(
                      'Divergencias encontradas',
                      style: TextStyle(fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 8),
                    for (final item in divergences) _DivergenceLine(item: item),
                    const SizedBox(height: 10),
                    const _ImportHint(
                      title: 'Decisao operacional',
                      text:
                          'Finalize para lançar somente o recebido no estoque. Itens faltantes ficam como divergencia da entrada; sobras entram como mercadoria recebida.',
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Voltar para reconferir'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(true),
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Finalizar conferência'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _createSupplierFromFields() async {
    final supplierName = _supplierName.text.trim();
    if (supplierName.length < 2) {
      setState(
        () => _error = 'Informe o nome do fornecedor antes de cadastrar.',
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _message = null;
    });
    try {
      final supplier = await _api.createSupplier(
        widget.session.token,
        SupplierPayload(
          name: supplierName,
          documentNumber: _supplierDocument.text,
        ),
      );
      setState(() {
        _suppliers = [..._suppliers, supplier]
          ..sort((a, b) => a.name.compareTo(b.name));
        _supplierId = supplier.id;
        _supplierName.text = supplier.name;
        _supplierDocument.text = supplier.documentNumber ?? '';
        _message = 'Fornecedor cadastrado e vinculado a entrada.';
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                        'Entradas',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Compra, XML NF-e e custo medio do estoque',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  onPressed: _load,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_error != null) ErrorPanel(message: _error!, onRetry: _load),
            if (_message != null)
              AppCard(
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: Color(0xFF0F766E),
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: Text(_message!)),
                  ],
                ),
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              )
            else
              _content(),
          ],
        ),
      ),
    );
  }

  Widget _content() {
    final receivingEntries = _entries
        .where((entry) => entry.status == 'receiving')
        .toList(growable: false);
    final pendingConference = receivingEntries.length;
    final recentTotal = _entries.fold<double>(
      0,
      (sum, entry) => sum + entry.totalAmount,
    );
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            final cards = [
              _MetricCard(
                label: 'Recebimentos',
                value: _entries.length.toString(),
                icon: Icons.inventory_2_outlined,
              ),
              _MetricCard(
                label: 'Aguardando conferência',
                value: receivingEntries.length.toString(),
                icon: Icons.fact_check_outlined,
              ),
              _MetricCard(
                label: 'Pendências',
                value: pendingConference.toString(),
                icon: Icons.report_problem_outlined,
              ),
              _MetricCard(
                label: 'Valor recente',
                value: formatBrazilianMoney(recentTotal),
                icon: Icons.payments_outlined,
              ),
            ];
            if (compact) {
              return Column(
                children: [
                  for (final card in cards) ...[
                    card,
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (final card in cards) ...[
                  Expanded(child: card),
                  if (card != cards.last) const SizedBox(width: 12),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _historyPanel(),
        const SizedBox(height: 16),
        _xmlInboxPanel(),
        if (_showWorkspace) ...[
          const SizedBox(height: 16),
          _entryWorkspace(),
          if (_items.isNotEmpty) ...[const SizedBox(height: 16), _itemsPanel()],
        ],
      ],
    );
  }

  Widget _entryWorkspace() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _editingEntryId == null
                      ? 'Nova entrada'
                      : 'Recebendo entrada #$_editingEntryId no computador',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton.outlined(
                tooltip: 'Fechar área de recebimento',
                onPressed: _saving ? null : () => _clearWorkspace(),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _editingEntryId == null
                ? 'Importe ou cadastre a nota. Depois receba no computador ou envie ao coletor.'
                : 'Ajuste a conferência desta mesma nota. O estoque só muda quando você finalizar.',
            style: const TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _ModeButton(
                selected: _entryMode == 'xml',
                icon: Icons.description_outlined,
                label: 'NF-e XML',
                onTap: () => setState(() => _entryMode = 'xml'),
              ),
              _ModeButton(
                selected: _entryMode == 'spreadsheet',
                icon: Icons.table_chart_outlined,
                label: 'Planilha',
                onTap: () => setState(() => _entryMode = 'spreadsheet'),
              ),
              _ModeButton(
                selected: _entryMode == 'key',
                icon: Icons.key_outlined,
                label: 'Chave NF-e',
                onTap: () => setState(() => _entryMode = 'key'),
              ),
              _ModeButton(
                selected: _entryMode == 'manual',
                icon: Icons.edit_note,
                label: 'Manual',
                onTap: () => setState(() => _entryMode = 'manual'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(
              key: ValueKey(_entryMode),
              child: switch (_entryMode) {
                'manual' => _manualTab(),
                'spreadsheet' => _spreadsheetTab(),
                'key' => _keyTab(),
                _ => _xmlTab(),
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _manualTab() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Use para compras pequenas, ajustes de recebimento e entrada sem documento eletrônico.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          _supplierFields(),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  initialValue: _productId,
                  decoration: const InputDecoration(
                    labelText: 'Produto',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    for (final product in _products)
                      DropdownMenuItem(
                        value: product.id,
                        child: Text('${product.name} | ${product.unit}'),
                      ),
                  ],
                  onChanged: (value) => setState(() => _productId = value),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: _field(_quantity, 'Quantidade')),
              const SizedBox(width: 12),
              Expanded(child: _field(_unitCost, 'Custo unitario')),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: _canCreateEntry ? _addManualItem : null,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _xmlTab() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Importe o XML da NF-e do fornecedor para preencher fornecedor, nota, itens, custos e dados fiscais.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 220,
            child: TextField(
              controller: _xml,
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
              decoration: const InputDecoration(
                labelText: 'Cole aqui o XML da NF-e enviado pelo fornecedor',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: _saving || !_canCreateEntry ? null : _pickXmlFile,
                icon: const Icon(Icons.upload_file),
                label: const Text('Selecionar XML'),
              ),
              const SizedBox(width: 10),
              FilledButton.icon(
                onPressed: _saving || !_canCreateEntry ? null : _previewXml,
                icon: const Icon(Icons.manage_search),
                label: const Text('Ler texto colado'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _spreadsheetTab() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Para primeira carga ou compra grande, baixe o modelo Excel, preencha e importe o .xlsx.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              OutlinedButton.icon(
                onPressed: _downloadImportTemplate,
                icon: const Icon(Icons.download_outlined),
                label: const Text('Baixar modelo de planilha'),
              ),
              FilledButton.icon(
                onPressed: _saving || !_canCreateEntry
                    ? null
                    : _pickSpreadsheetFile,
                icon: const Icon(Icons.upload_file_outlined),
                label: const Text('Importar planilha preenchida'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const _ImportHint(
            title: 'Colunas principais',
            text:
                'Produto, código interno ou barras, unidade, quantidade, custo, preço de venda, NCM, CFOP, lote e validade.',
          ),
          const SizedBox(height: 10),
          const _ImportHint(
            title: 'Cadastro em massa',
            text:
                'Se o produto não existir e o usuário tiver permissão, ele e cadastrado antes da conferência.',
          ),
          const SizedBox(height: 10),
          const _ImportHint(
            title: 'Conferência',
            text:
                'Depois da importacao, revise os itens abaixo e confirme para movimentar o estoque.',
          ),
        ],
      ),
    );
  }

  Widget _keyTab() {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _field(_accessKey, 'Chave de acesso da NF-e'),
          const SizedBox(height: 12),
          const Text(
            'Consulta preparada para distribuição de DF-e pela SEFAZ quando o certificado digital A1 estiver configurado no Fiscal.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.icon(
              onPressed: _saving || !_canCreateEntry ? null : _downloadByKey,
              icon: const Icon(Icons.cloud_download_outlined),
              label: const Text('Baixar pela chave'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _supplierFields() {
    final canRegisterCurrentSupplier =
        _canCreateSupplier &&
        _supplierId == null &&
        _supplierName.text.trim().isNotEmpty;
    final xmlSupplierDocument = _digitsOnly(_xmlSupplierDocument);
    final currentSupplierDocument = _digitsOnly(_supplierDocument.text);
    String? supplierWarning;
    if (xmlSupplierDocument != null && _supplierId == null) {
      supplierWarning =
          'Fornecedor do XML nao foi identificado pelo CNPJ $xmlSupplierDocument. Voce pode cadastrar o fornecedor ou seguir sem bloquear a entrada.';
    } else if (xmlSupplierDocument != null &&
        currentSupplierDocument != null &&
        xmlSupplierDocument != currentSupplierDocument) {
      supplierWarning =
          'Atencao: o CNPJ do fornecedor selecionado ($currentSupplierDocument) e diferente do CNPJ do XML ($xmlSupplierDocument). A entrada nao sera bloqueada, mas confira antes de finalizar.';
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 900;
        final fields = [
          DropdownButtonFormField<int?>(
            initialValue: _supplierId,
            decoration: const InputDecoration(
              labelText: 'Fornecedor cadastrado',
              border: OutlineInputBorder(),
            ),
            items: [
              const DropdownMenuItem(
                value: null,
                child: Text('Informar manualmente'),
              ),
              for (final supplier in _suppliers)
                DropdownMenuItem(
                  value: supplier.id,
                  child: Text(supplier.name),
                ),
            ],
            onChanged: (value) {
              setState(() {
                _supplierId = value;
                Supplier? supplier;
                for (final item in _suppliers) {
                  if (item.id == value) {
                    supplier = item;
                    break;
                  }
                }
                if (supplier != null) {
                  _supplierName.text = supplier.name;
                  _supplierDocument.text = supplier.documentNumber ?? '';
                }
              });
            },
          ),
          _field(
            _supplierName,
            'Fornecedor',
            onChanged: (_) => setState(() {}),
          ),
          _field(
            _supplierDocument,
            'CNPJ/CPF',
            onChanged: (_) => setState(() {}),
          ),
        ];
        final registerButton = OutlinedButton.icon(
          onPressed: canRegisterCurrentSupplier && !_saving
              ? _createSupplierFromFields
              : null,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Cadastrar fornecedor'),
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final field in fields) ...[
                field,
                const SizedBox(height: 10),
              ],
              registerButton,
              if (supplierWarning != null) ...[
                const SizedBox(height: 10),
                _SupplierWarningBox(message: supplierWarning),
              ],
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                for (final field in fields) ...[
                  Expanded(child: field),
                  const SizedBox(width: 12),
                ],
                registerButton,
              ],
            ),
            if (supplierWarning != null) ...[
              const SizedBox(height: 10),
              _SupplierWarningBox(message: supplierWarning),
            ],
          ],
        );
      },
    );
  }

  Widget _itemsPanel() {
    final total = _items.fold<double>(0, (sum, item) {
      if (item.checkStatus != 'accepted') return sum;
      return sum + ((item.receivedQuantity ?? 0) * item.unitCost);
    });
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Itens da entrada',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                'Total ${formatBrazilianMoney(total)}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Nenhum item adicionado.')),
            )
          else
            for (var i = 0; i < _items.length; i++) _receiptItemTile(i),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _field(_invoiceNumber, 'Número NF')),
              const SizedBox(width: 12),
              Expanded(child: _field(_invoiceSeries, 'Série')),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: _field(_invoiceKey, 'Chave NF-e')),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            decoration: const InputDecoration(
              labelText: 'Observações',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.end,
            spacing: 10,
            runSpacing: 10,
            children: [
              OutlinedButton.icon(
                onPressed: _saving || !_canConfirmEntry
                    ? null
                    : () => _sendEntryToMobile(_entrySource),
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('Enviar para celular'),
              ),
              FilledButton.icon(
                onPressed: _saving || !_canConfirmEntry
                    ? null
                    : () => _confirmEntry(_entrySource),
                icon: const Icon(Icons.check),
                label: const Text('Confirmar recebimento'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _receiptItemTile(int index) {
    final item = _items[index];
    final received = item.receivedQuantity ?? item.quantity;
    final divergence = received - item.quantity;
    final invoiceQuantity = item.invoiceQuantity;
    final invoiceUnit = item.invoiceUnit;
    final productName = _productName(item.productId);
    final statusColor = switch (item.checkStatus) {
      'accepted' => const Color(0xFF0F766E),
      'return' => const Color(0xFFB91C1C),
      'pending' => const Color(0xFFB45309),
      _ => const Color(0xFF2563EB),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (item.barcode != null) 'Cod. ${item.barcode}',
                    if (item.ncm != null) 'NCM ${item.ncm}',
                    if (item.cfop != null) 'CFOP ${item.cfop}',
                  ].join(' | '),
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 4),
                Text(
                  productName == null
                      ? 'Produto não cadastrado/vinculado'
                      : 'Vinculado: $productName',
                  style: TextStyle(
                    color: productName == null
                        ? const Color(0xFFB45309)
                        : const Color(0xFF0F766E),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Text(
              invoiceQuantity != null && invoiceUnit != null
                  ? 'Nota\n${formatBrazilianDecimal(invoiceQuantity)} $invoiceUnit'
                  : 'Nota\n${formatBrazilianDecimal(item.quantity)} ${item.unit}',
            ),
          ),
          if (invoiceQuantity != null && invoiceUnit != null)
            Expanded(
              child: Text(
                'Estoque\n${formatBrazilianDecimal(item.quantity)} ${item.unit}',
              ),
            ),
          Expanded(
            child: Text(
              'Recebido\n${formatBrazilianDecimal(received)} ${item.unit}',
            ),
          ),
          Expanded(
            child: Text(
              divergence == 0
                  ? 'Divergencia\n-'
                  : 'Divergencia\n${formatBrazilianDecimal(divergence)}',
            ),
          ),
          Expanded(child: Text('Validade\n${item.expirationDate ?? '-'}')),
          Expanded(
            child: item.checkStatus == 'pending_product'
                ? TextButton(
                    onPressed: () => _createAndLinkItemProduct(index),
                    style: TextButton.styleFrom(
                      foregroundColor: statusColor,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerLeft,
                      textStyle: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    child: const Text('Cadastrar produto'),
                  )
                : Text(
                    _statusLabel(item.checkStatus),
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
          ),
          IconButton(
            tooltip: 'Conferir item',
            onPressed: () => _editItem(index),
            icon: const Icon(Icons.fact_check_outlined),
          ),
          IconButton(
            tooltip: 'Remover item',
            onPressed: () => setState(() => _items.removeAt(index)),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  Widget _xmlInboxPanel() {
    final settings = _xmlInboxSettings;
    final filteredMessages = _filteredXmlInboxMessages();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.mark_email_read_outlined, color: Color(0xFF0A66D8)),
              SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Caixa de XML',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      'Endereço exclusivo desta empresa para receber NF-e.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              border: Border.all(color: const Color(0xFFD8E2EF)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Expanded(
                  child: SelectableText(
                    settings?.emailAddress ?? 'Endereço ainda não configurado',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Copiar endereço',
                  onPressed: settings == null || settings.emailAddress.isEmpty
                      ? null
                      : () async {
                          await Clipboard.setData(
                            ClipboardData(text: settings.emailAddress),
                          );
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Endereço da Caixa de XML copiado.',
                              ),
                            ),
                          );
                        },
                  icon: const Icon(Icons.copy_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          const _ImportHint(
            title: 'Validação obrigatória',
            text:
                'Só é importado XML cujo CNPJ destinatário seja igual ao CNPJ fiscal desta empresa. XML de outra empresa é rejeitado.',
          ),
          if (filteredMessages.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'XMLs recebidos',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            for (final message in filteredMessages.take(12))
              _XmlInboxMessageTile(
                message: message,
                onGenerateReceipt:
                    !_canCreateEntry ||
                        _saving ||
                        !message.pendingReceipt ||
                        _generatingXmlReceiptId != null
                    ? null
                    : () => _generateReceiptFromXml(message),
                generating: _generatingXmlReceiptId == message.id,
              ),
          ] else if (_xmlInboxMessages.isNotEmpty) ...[
            const SizedBox(height: 14),
            const Text(
              'Nenhum XML encontrado para a busca atual.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
          ],
        ],
      ),
    );
  }

  Widget _historyPanel() {
    final filteredEntries = _filteredEntries();
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Central de recebimentos',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 3),
                    Text(
                      'Consulte por número, chave ou fornecedor e escolha onde conferir.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              if (_canCreateEntry)
                FilledButton.icon(
                  onPressed: _saving ? null : _startNewEntry,
                  icon: const Icon(Icons.add),
                  label: const Text('Nova entrada'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _entrySearch,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Número da nota, chave ou fornecedor',
                    hintText: 'Digite para consultar...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 160,
                child: DropdownButtonFormField<String>(
                  initialValue: _entryStatusFilter,
                  decoration: const InputDecoration(
                    labelText: 'Situação',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'abertas',
                      child: Text('Em aberto'),
                    ),
                    DropdownMenuItem(value: 'todas', child: Text('Todas')),
                    DropdownMenuItem(
                      value: 'confirmed',
                      child: Text('Finalizadas'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _entryStatusFilter = value ?? 'abertas'),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<String>(
                  initialValue: _entrySourceFilter,
                  decoration: const InputDecoration(
                    labelText: 'Origem',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todas')),
                    DropdownMenuItem(value: 'manual', child: Text('Manual')),
                    DropdownMenuItem(value: 'xml', child: Text('XML')),
                    DropdownMenuItem(
                      value: 'spreadsheet',
                      child: Text('Planilha'),
                    ),
                    DropdownMenuItem(
                      value: 'nfe_key',
                      child: Text('Chave NF-e'),
                    ),
                  ],
                  onChanged: (value) =>
                      setState(() => _entrySourceFilter = value ?? 'todos'),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Limpar busca',
                onPressed: () => setState(() {
                  _entrySearch.clear();
                  _entrySourceFilter = 'todos';
                  _entryStatusFilter = 'abertas';
                }),
                icon: const Icon(Icons.clear),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (filteredEntries.isEmpty)
            const _ImportHint(
              title: 'Nenhuma nota encontrada',
              text:
                  'Altere os filtros ou use Nova entrada para importar XML, consultar chave, planilha ou cadastrar manualmente.',
            )
          else
            for (final entry in filteredEntries.take(20))
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _StockEntryCentralTile(
                  entry: entry,
                  onComputer:
                      entry.status == 'confirmed' || !_canCreateEntry || _saving
                      ? null
                      : () => _openEntryOnComputer(entry),
                  onCollector:
                      entry.status == 'confirmed' || !_canCreateEntry || _saving
                      ? null
                      : () async {
                          await _openEntryOnComputer(entry);
                          if (!mounted || _editingEntryId != entry.id) return;
                          await _sendEntryToMobile(entry.source);
                        },
                  onFinalize:
                      entry.status == 'confirmed' ||
                          !_canConfirmEntry ||
                          _saving
                      ? null
                      : () => _confirmExistingEntry(entry),
                ),
              ),
        ],
      ),
    );
  }

  List<StockEntry> _filteredEntries() {
    final term = _normalize(_entrySearch.text);
    return _entries.where((entry) {
      if (_entryStatusFilter == 'abertas' && entry.status == 'confirmed') {
        return false;
      }
      if (_entryStatusFilter == 'confirmed' && entry.status != 'confirmed') {
        return false;
      }
      if (_entrySourceFilter != 'todos' && entry.source != _entrySourceFilter) {
        return false;
      }
      if (term.isEmpty) return true;
      final haystack = _normalize(
        [
          entry.supplierName,
          entry.supplierDocument,
          entry.invoiceNumber,
          entry.invoiceSeries,
          entry.invoiceKey,
          entry.source,
          entry.notes,
          for (final item in entry.items) item.description,
          for (final item in entry.items) item.barcode,
          for (final item in entry.items) item.ncm,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }

  List<XmlInboxMessage> _filteredXmlInboxMessages() {
    final term = _normalize(_entrySearch.text);
    if (term.isEmpty) return _xmlInboxMessages;
    return _xmlInboxMessages.where((message) {
      final haystack = _normalize(
        [
          message.supplierName,
          message.supplierDocument,
          message.recipientDocument,
          message.invoiceNumber,
          message.invoiceKey,
          message.subject,
          message.attachmentName,
          message.senderEmail,
          message.status,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }

  String _decodeSpreadsheetBytes(List<int> bytes) {
    try {
      return utf8.decode(bytes);
    } catch (_) {
      return latin1.decode(bytes);
    }
  }

  List<int> _buildXlsxTemplate({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final archive = Archive();
    void add(String path, String content) {
      archive.addFile(ArchiveFile.string(path, content));
    }

    add('[Content_Types].xml', _xlsxContentTypes);
    add('_rels/.rels', _xlsxRootRels);
    add('xl/_rels/workbook.xml.rels', _xlsxWorkbookRels);
    add('xl/workbook.xml', _xlsxWorkbook);
    add('xl/styles.xml', _xlsxStyles);
    add('xl/worksheets/sheet1.xml', _xlsxSheet(headers, rows));
    return ZipEncoder().encode(archive);
  }

  String _readXlsxFirstSheet(List<int> bytes) {
    final archive = ZipDecoder().decodeBytes(bytes);
    final sheet = archive.findFile('xl/worksheets/sheet1.xml');
    if (sheet == null) {
      throw const FormatException('arquivo XLSX sem primeira aba.');
    }
    final sharedStrings = _readXlsxSharedStrings(archive);
    final xml = XmlDocument.parse(utf8.decode(sheet.content as List<int>));
    final rows = <List<String>>[];
    for (final row in xml.findAllElements('row')) {
      final valuesByColumn = <int, String>{};
      var maxColumn = 0;
      for (final cell in row.findElements('c')) {
        final reference = cell.getAttribute('r') ?? '';
        final column = _xlsxColumnIndex(reference);
        if (column <= 0) continue;
        maxColumn = column > maxColumn ? column : maxColumn;
        valuesByColumn[column] = _xlsxCellValue(cell, sharedStrings);
      }
      if (maxColumn > 0) {
        rows.add([
          for (var column = 1; column <= maxColumn; column++)
            valuesByColumn[column] ?? '',
        ]);
      }
    }
    return rows.map((row) => row.join(';')).join('\n');
  }

  List<String> _readXlsxSharedStrings(Archive archive) {
    final file = archive.findFile('xl/sharedStrings.xml');
    if (file == null) return const [];
    final xml = XmlDocument.parse(utf8.decode(file.content as List<int>));
    return [
      for (final item in xml.findAllElements('si'))
        item.findAllElements('t').map((text) => text.innerText).join(),
    ];
  }

  String _xlsxCellValue(XmlElement cell, List<String> sharedStrings) {
    final type = cell.getAttribute('t');
    if (type == 'inlineStr') {
      return cell.findAllElements('t').map((text) => text.innerText).join();
    }
    final raw = cell.findElements('v').firstOrNull?.innerText ?? '';
    if (type == 's') {
      final index = int.tryParse(raw);
      if (index == null || index < 0 || index >= sharedStrings.length) {
        return '';
      }
      return sharedStrings[index];
    }
    return raw;
  }

  List<List<String>> _parseDelimitedRows(String content) {
    final delimiter = _detectDelimiter(content);
    final rows = <List<String>>[];
    final currentRow = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < content.length; i++) {
      final char = content[i];
      if (char == '"') {
        final nextIsQuote = i + 1 < content.length && content[i + 1] == '"';
        if (inQuotes && nextIsQuote) {
          current.write('"');
          i++;
        } else {
          inQuotes = !inQuotes;
        }
      } else if (char == delimiter && !inQuotes) {
        currentRow.add(current.toString());
        current.clear();
      } else if ((char == '\n' || char == '\r') && !inQuotes) {
        if (char == '\r' && i + 1 < content.length && content[i + 1] == '\n') {
          i++;
        }
        currentRow.add(current.toString());
        current.clear();
        if (currentRow.any((cell) => cell.trim().isNotEmpty)) {
          rows.add(List<String>.from(currentRow));
        }
        currentRow.clear();
      } else {
        current.write(char);
      }
    }
    currentRow.add(current.toString());
    if (currentRow.any((cell) => cell.trim().isNotEmpty)) {
      rows.add(currentRow);
    }
    return rows;
  }

  String _detectDelimiter(String content) {
    final lines = content.split(RegExp(r'\r?\n'));
    final firstLine = lines.isEmpty ? '' : lines.first;
    final semicolons = ';'.allMatches(firstLine).length;
    final commas = ','.allMatches(firstLine).length;
    return semicolons >= commas ? ';' : ',';
  }

  void _applySpreadsheetHeader(Map<String, String> data) {
    final supplierName = _cell(data, 'fornecedor_nome');
    final supplierDocument = _cell(data, 'fornecedor_documento');
    if (_supplierName.text.trim().isEmpty && supplierName != null) {
      _supplierName.text = supplierName;
    }
    if (_supplierDocument.text.trim().isEmpty && supplierDocument != null) {
      _supplierDocument.text = supplierDocument;
      _xmlSupplierDocument = _digitsOnly(supplierDocument);
      final digits = _xmlSupplierDocument;
      for (final supplier in _suppliers) {
        if (_digitsOnly(supplier.documentNumber) == digits) {
          _supplierId = supplier.id;
          _supplierName.text = supplier.name;
          break;
        }
      }
    }
    _setIfEmpty(_invoiceNumber, _cell(data, 'número_nf'));
    _setIfEmpty(_invoiceSeries, _cell(data, 'serie_nf'));
    _setIfEmpty(_invoiceKey, _cell(data, 'chave_nfe'));
    _setIfEmpty(_notes, _cell(data, 'observacao'));
  }

  void _setIfEmpty(TextEditingController controller, String? value) {
    if (controller.text.trim().isEmpty && value != null) {
      controller.text = value;
    }
  }

  Product? _findProductByCodes({String? barcode, String? code}) {
    final normalizedBarcode = _normalizeCode(barcode);
    final normalizedCode = _normalizeCode(code);
    for (final product in _products) {
      if (normalizedBarcode != null &&
          (_normalizeCode(product.barcode) == normalizedBarcode ||
              _normalizeCode(product.internalCode) == normalizedBarcode ||
              _normalizeCode(product.purchasePackageBarcode) ==
                  normalizedBarcode)) {
        return product;
      }
      if (normalizedCode != null &&
          (_normalizeCode(product.internalCode) == normalizedCode ||
              _normalizeCode(product.barcode) == normalizedCode ||
              _normalizeCode(product.purchasePackageBarcode) ==
                  normalizedCode)) {
        return product;
      }
    }
    return null;
  }

  String? _cell(
    Map<String, String> data,
    String key, {
    List<String> aliases = const [],
  }) {
    for (final candidate in [key, ...aliases]) {
      final value = data[_normalizeHeader(candidate)]?.trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  double _numberCell(
    Map<String, String> data,
    String key, {
    required double fallback,
  }) {
    final value = _cell(data, key);
    if (value == null) return fallback;
    return parseBrazilianNumber(value);
  }

  String? _parseDateCell(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    final excelSerial = double.tryParse(trimmed.replaceAll(',', '.'));
    if (excelSerial != null && excelSerial > 1) {
      final date = DateTime.utc(
        1899,
        12,
        30,
      ).add(Duration(days: excelSerial.floor()));
      return _dateOnly(date);
    }
    final brazilian = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(trimmed);
    if (brazilian != null) {
      return '${brazilian.group(3)}-${brazilian.group(2)}-${brazilian.group(1)}';
    }
    final brazilianWithTime = RegExp(
      r'^(\d{2})/(\d{2})/(\d{4})\s+\d{1,2}:\d{2}(?::\d{2})?',
    ).firstMatch(trimmed);
    if (brazilianWithTime != null) {
      return '${brazilianWithTime.group(3)}-${brazilianWithTime.group(2)}-${brazilianWithTime.group(1)}';
    }
    final isoDateTime = RegExp(
      r'^(\d{4})-(\d{2})-(\d{2})[T\s]',
    ).firstMatch(trimmed);
    if (isoDateTime != null) {
      return '${isoDateTime.group(1)}-${isoDateTime.group(2)}-${isoDateTime.group(3)}';
    }
    final iso = DateTime.tryParse(trimmed);
    return iso == null ? trimmed : _dateOnly(iso);
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }

  String? _productName(int? productId) {
    if (productId == null) return null;
    for (final product in _products) {
      if (product.id == productId) return product.name;
    }
    return null;
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF1D4ED8)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                const SizedBox(height: 2),
                Text(
                  value,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(
        icon,
        size: 18,
        color: selected ? const Color(0xFF0F4C5C) : const Color(0xFF475569),
      ),
      label: Text(label),
      labelStyle: const TextStyle(fontWeight: FontWeight.w800),
      selectedColor: const Color(0xFFDDF7F9),
      backgroundColor: const Color(0xFFF8FAFC),
      side: BorderSide(
        color: selected ? const Color(0xFF67C7D1) : const Color(0xFFCBD6E4),
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    );
  }
}

class _DivergenceLine extends StatelessWidget {
  const _DivergenceLine({required this.item});

  final StockEntryItem item;

  @override
  Widget build(BuildContext context) {
    final received = item.receivedQuantity ?? 0;
    final diff = received - item.quantity;
    final label = _divergenceLabel(item);
    final color = diff < 0 ? const Color(0xFFB45309) : const Color(0xFF0F766E);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD8E2EF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            diff < 0 ? Icons.trending_down : Icons.trending_up,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.description,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                Text(
                  'Nota ${formatBrazilianDecimal(item.quantity)} ${item.unit} | Recebido ${formatBrazilianDecimal(received)} ${item.unit}',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
        ],
      ),
    );
  }
}

class _SupplierWarningBox extends StatelessWidget {
  const _SupplierWarningBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7ED),
        border: Border.all(color: const Color(0xFFFED7AA)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Color(0xFFB45309), size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _XmlInboxMessageTile extends StatelessWidget {
  const _XmlInboxMessageTile({
    required this.message,
    required this.onGenerateReceipt,
    required this.generating,
  });

  final XmlInboxMessage message;
  final VoidCallback? onGenerateReceipt;
  final bool generating;

  @override
  Widget build(BuildContext context) {
    final color = message.imported
        ? const Color(0xFF0F766E)
        : message.pendingReceipt
        ? const Color(0xFF2563EB)
        : const Color(0xFFB45309);
    final label = switch (message.status) {
      'pending_receipt' => 'XML recebido',
      'imported' => 'Recebimento gerado',
      'cnpj_mismatch' => 'CNPJ diferente',
      'duplicate' => 'Duplicado',
      'invalid_xml' => 'XML inválido',
      'company_cnpj_missing' => 'CNPJ não configurado',
      _ => message.status,
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD8E2EF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            message.imported
                ? Icons.check_circle_outline
                : message.pendingReceipt
                ? Icons.mark_email_read_outlined
                : Icons.report_problem_outlined,
            color: color,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.invoiceNumber == null
                      ? (message.attachmentName ?? 'Anexo XML')
                      : 'NF ${message.invoiceNumber} · ${message.supplierName ?? 'Fornecedor'}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                if (message.rejectionReason != null)
                  Text(
                    message.rejectionReason!,
                    style: const TextStyle(color: Color(0xFF64748B)),
                  ),
                if (message.pendingReceipt)
                  const Text(
                    'Aguardando decisão para gerar recebimento.',
                    style: TextStyle(color: Color(0xFF64748B)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (message.pendingReceipt)
            FilledButton.icon(
              onPressed: onGenerateReceipt,
              icon: generating
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.playlist_add_check_outlined),
              label: Text(generating ? 'Gerando...' : 'Gerar recebimento'),
            )
          else
            Text(
              label,
              style: TextStyle(color: color, fontWeight: FontWeight.w900),
            ),
        ],
      ),
    );
  }
}

class _StockEntryCentralTile extends StatelessWidget {
  const _StockEntryCentralTile({
    required this.entry,
    required this.onComputer,
    required this.onCollector,
    required this.onFinalize,
  });

  final StockEntry entry;
  final VoidCallback? onComputer;
  final VoidCallback? onCollector;
  final VoidCallback? onFinalize;

  @override
  Widget build(BuildContext context) {
    final open = entry.status != 'confirmed';
    final statusColor = open
        ? const Color(0xFFB45309)
        : const Color(0xFF0F766E);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        border: Border.all(color: const Color(0xFFD8E2EF)),
        borderRadius: BorderRadius.circular(10),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _entryDisplayTitle(entry),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      open ? 'Em recebimento' : 'Finalizada',
                      style: TextStyle(
                        color: statusColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 14,
                runSpacing: 5,
                children: [
                  Text(_sourceLabel(entry.source)),
                  Text('${entry.items.length} itens'),
                  Text(formatBrazilianMoney(entry.totalAmount)),
                  if ((entry.invoiceKey ?? '').isNotEmpty)
                    Text('Chave ${entry.invoiceKey}'),
                ],
              ),
            ],
          );
          final actions = Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: onComputer,
                icon: const Icon(Icons.computer_outlined),
                label: const Text('Receber no computador'),
              ),
              OutlinedButton.icon(
                onPressed: onCollector,
                icon: const Icon(Icons.phone_android_outlined),
                label: const Text('Enviar ao coletor'),
              ),
              FilledButton.icon(
                onPressed: onFinalize,
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Finalizar'),
              ),
            ],
          );
          if (constraints.maxWidth < 860) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [details, const SizedBox(height: 12), actions],
            );
          }
          return Row(
            children: [
              Expanded(child: details),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _ImportHint extends StatelessWidget {
  const _ImportHint({required this.title, required this.text});

  final String title;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.check_circle_outline, color: Color(0xFF0F766E)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Text(text, style: const TextStyle(color: Color(0xFF64748B))),
            ],
          ),
        ),
      ],
    );
  }
}

class _ConversionBox extends StatelessWidget {
  const _ConversionBox({
    required this.enabled,
    required this.invoiceQuantity,
    required this.invoiceUnit,
    required this.stockUnit,
    required this.conversionFactor,
    required this.originalUnit,
    required this.onEnabledChanged,
    required this.onInvoiceUnitChanged,
    required this.onRecalculate,
  });

  final bool enabled;
  final TextEditingController invoiceQuantity;
  final String invoiceUnit;
  final String stockUnit;
  final TextEditingController conversionFactor;
  final String originalUnit;
  final ValueChanged<bool> onEnabledChanged;
  final ValueChanged<String?> onInvoiceUnitChanged;
  final VoidCallback onRecalculate;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        border: Border.all(color: const Color(0xFFD8E2EF)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text(
              'Converter pacote/caixa da nota para unidade de estoque',
            ),
            subtitle: Text(
              'Use quando a NF-e vem em $originalUnit, mas o produto é vendido/controlado em $stockUnit.',
            ),
            value: enabled,
            onChanged: onEnabledChanged,
          ),
          if (enabled) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: invoiceQuantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianDecimalInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Qtd. na nota',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => onRecalculate(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        _stockEntryUnitOptions.containsKey(invoiceUnit)
                        ? invoiceUnit
                        : 'pc',
                    decoration: const InputDecoration(
                      labelText: 'Unidade na nota',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in _stockEntryUnitOptions.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text('${entry.value} (${entry.key})'),
                        ),
                    ],
                    onChanged: onInvoiceUnitChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: conversionFactor,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianDecimalInputFormatter()],
                    decoration: InputDecoration(
                      labelText: '$stockUnit por pacote',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => onRecalculate(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Exemplo: nota 1 pct, produto em un, fator 12 = entra 12 un no estoque.',
              style: TextStyle(
                color: Colors.blueGrey.shade700,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PackageConfig {
  const _PackageConfig({
    required this.invoiceQuantity,
    required this.invoiceUnit,
    required this.stockUnit,
    required this.factor,
    this.unitBarcode,
    this.packageBarcode,
  });

  final double invoiceQuantity;
  final String invoiceUnit;
  final String stockUnit;
  final double factor;
  final String? unitBarcode;
  final String? packageBarcode;
}

class _PackageConfigDialog extends StatefulWidget {
  const _PackageConfigDialog({
    required this.item,
    required this.initialStockUnit,
  });

  final StockEntryItem item;
  final String initialStockUnit;

  @override
  State<_PackageConfigDialog> createState() => _PackageConfigDialogState();
}

class _PackageConfigDialogState extends State<_PackageConfigDialog> {
  late final _invoiceQuantity = TextEditingController(
    text: formatBrazilianDecimal(
      widget.item.invoiceQuantity ?? widget.item.quantity,
    ),
  );
  late final _factor = TextEditingController(
    text: formatBrazilianDecimal(widget.item.packageConversionFactor ?? 1),
  );
  late String _invoiceUnit = widget.item.invoiceUnit ?? widget.item.unit;
  late String _stockUnit = widget.initialStockUnit;
  final _unitBarcode = TextEditingController();
  bool _sameUnitBarcode = false;
  late bool _comesAsPackage = !_isKgUnit(widget.item.unit);
  String? _error;

  @override
  void dispose() {
    _invoiceQuantity.dispose();
    _factor.dispose();
    _unitBarcode.dispose();
    super.dispose();
  }

  void _submit() {
    final invoiceQty = parseBrazilianNumber(_invoiceQuantity.text);
    final factor = _comesAsPackage ? parseBrazilianNumber(_factor.text) : 1.0;
    final packageBarcode = _comesAsPackage
        ? _emptyToNull(widget.item.barcode ?? '')
        : null;
    final unitBarcode = _sameUnitBarcode || !_comesAsPackage
        ? _emptyToNull(widget.item.barcode ?? '')
        : _emptyToNull(_unitBarcode.text);
    if (invoiceQty <= 0 || factor <= 0) {
      setState(() => _error = 'Informe quantidade e conversão válidas.');
      return;
    }
    if (_comesAsPackage && !_sameUnitBarcode && unitBarcode == null) {
      setState(() => _error = 'Informe o codigo de barras da unidade.');
      return;
    }
    Navigator.of(context).pop(
      _PackageConfig(
        invoiceQuantity: invoiceQty,
        invoiceUnit: _comesAsPackage ? _invoiceUnit : _stockUnit,
        stockUnit: _stockUnit,
        factor: factor,
        unitBarcode: unitBarcode,
        packageBarcode: packageBarcode,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final stockQuantity =
        parseBrazilianNumber(_invoiceQuantity.text) *
        (_comesAsPackage ? parseBrazilianNumber(_factor.text) : 1);
    final stockUnitCost = stockQuantity > 0
        ? widget.item.totalCost / stockQuantity
        : widget.item.unitCost;
    return AlertDialog(
      title: const Text('Como este produto entra no estoque?'),
      content: SizedBox(
        width: 560,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.item.description,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(
                  value: false,
                  label: Text('Por unidade'),
                  icon: Icon(Icons.inventory_2_outlined),
                ),
                ButtonSegment(
                  value: true,
                  label: Text('Por pacote/caixa'),
                  icon: Icon(Icons.all_inbox_outlined),
                ),
              ],
              selected: {_comesAsPackage},
              onSelectionChanged: (values) {
                setState(() => _comesAsPackage = values.first);
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _invoiceQuantity,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianDecimalInputFormatter()],
                    decoration: const InputDecoration(
                      labelText: 'Quantidade na nota',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue:
                        _stockEntryUnitOptions.containsKey(_invoiceUnit)
                        ? _invoiceUnit
                        : 'pc',
                    decoration: const InputDecoration(
                      labelText: 'Unidade da nota',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in _stockEntryUnitOptions.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text('${entry.value} (${entry.key})'),
                        ),
                    ],
                    onChanged: _comesAsPackage
                        ? (value) => setState(
                            () => _invoiceUnit = value ?? _invoiceUnit,
                          )
                        : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _stockUnit,
                    decoration: const InputDecoration(
                      labelText: 'Unidade de venda/estoque',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in _stockEntryUnitOptions.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text('${entry.value} (${entry.key})'),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _stockUnit = value ?? _stockUnit),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _factor,
                    enabled: _comesAsPackage,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianDecimalInputFormatter()],
                    decoration: InputDecoration(
                      labelText: '$_stockUnit por pacote',
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (_comesAsPackage) ...[
              TextFormField(
                initialValue: widget.item.barcode ?? '',
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Código do pacote/embalagem vindo da nota',
                  helperText:
                      'Este código será vinculado à embalagem usada pelo fornecedor.',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  'O código da unidade é o mesmo da embalagem?',
                ),
                subtitle: Text(
                  widget.item.barcode == null
                      ? 'A nota não trouxe código da embalagem. Informe abaixo o código usado na unidade.'
                      : 'Marque somente quando o mesmo código também estiver impresso em cada unidade.',
                ),
                value: _sameUnitBarcode,
                onChanged: widget.item.barcode == null
                    ? null
                    : (value) => setState(() => _sameUnitBarcode = value),
              ),
              if (!_sameUnitBarcode || widget.item.barcode == null) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _unitBarcode,
                  decoration: const InputDecoration(
                    labelText: 'Código de barras da unidade / EAN de venda',
                    helperText:
                        'Este será o código principal do produto no estoque e no PDV.',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
              ],
            ],
            Text(
              'Vai entrar no estoque: ${formatBrazilianDecimal(stockQuantity)} $_stockUnit',
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Nota/XML: ${formatBrazilianMoney(widget.item.unitCost)} por ${widget.item.unit} • '
              'Total do item: ${formatBrazilianMoney(widget.item.totalCost)}',
              style: const TextStyle(color: Color(0xFF475569)),
            ),
            Text(
              'Custo calculado no estoque: ${formatBrazilianMoney(stockUnitCost)} por $_stockUnit',
              style: const TextStyle(
                color: Color(0xFF0F766E),
                fontWeight: FontWeight.w800,
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Continuar cadastro'),
        ),
      ],
    );
  }
}

String? _emptyToNull(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) return null;
  return trimmed;
}

String _defaultStockUnitForReceiptItem(StockEntryItem item) {
  return _isKgUnit(item.unit) || _isKgUnit(item.invoiceUnit) ? 'kg' : 'un';
}

bool _isKgUnit(String? unit) {
  final normalized = (unit ?? '').trim().toLowerCase();
  return normalized == 'kg' ||
      normalized == 'kgs' ||
      normalized == 'quilo' ||
      normalized == 'quilos' ||
      normalized == 'kilograma' ||
      normalized == 'kilogramas';
}

String _cleanSpreadsheetCell(String value) {
  var cleaned = value.trim();
  if (cleaned.startsWith('=')) {
    cleaned = cleaned.substring(1).trim();
  }
  if (cleaned.length >= 2 && cleaned.startsWith('"') && cleaned.endsWith('"')) {
    cleaned = cleaned.substring(1, cleaned.length - 1).replaceAll('""', '"');
  }
  return cleaned;
}

String _statusLabel(String status) {
  return switch (status) {
    'accepted' => 'Aceito',
    'return' => 'Devolver',
    'pending' => 'Pendencia',
    'pending_product' => 'Cadastrar/vincular',
    _ => status,
  };
}

String _sourceLabel(String source) {
  return switch (source) {
    'manual' => 'Manual',
    'xml' => 'NF-e XML',
    'spreadsheet' => 'Planilha',
    'nfe_key' => 'Chave NF-e',
    'email_xml' => 'Caixa de XML',
    _ => source,
  };
}

String _entryDisplayTitle(StockEntry entry) {
  final number = entry.invoiceNumber ?? 'Entrada #${entry.id}';
  final supplier = entry.supplierName ?? 'Fornecedor não informado';
  return '$number - $supplier';
}

bool _hasEntryItemDivergence(StockEntryItem item) {
  return (item.receivedQuantity ?? 0) != item.quantity ||
      item.productId == null;
}

String _divergenceLabel(StockEntryItem item) {
  final received = item.receivedQuantity ?? 0;
  final diff = received - item.quantity;
  if (item.productId == null && received > 0) return 'Vincular produto';
  if (diff < 0) return 'Falta ${formatBrazilianDecimal(diff.abs())}';
  if (diff > 0) return 'Sobra ${formatBrazilianDecimal(diff)}';
  return 'Pendente';
}

String _dateOnly(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _normalizeHeader(String value) {
  return _normalize(value)
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
}

String? _normalizeCode(String? value) {
  final normalized = value?.trim();
  if (normalized == null || normalized.isEmpty) return null;
  return normalized.toLowerCase();
}

int _xlsxColumnIndex(String reference) {
  var result = 0;
  for (final codeUnit in reference.codeUnits) {
    final char = String.fromCharCode(codeUnit).toUpperCase();
    final value = char.codeUnitAt(0) - 64;
    if (value < 1 || value > 26) break;
    result = (result * 26) + value;
  }
  return result;
}

String _xlsxColumnName(int index) {
  var value = index;
  final chars = <String>[];
  while (value > 0) {
    value--;
    chars.insert(0, String.fromCharCode(65 + (value % 26)));
    value ~/= 26;
  }
  return chars.join();
}

String _xmlEscape(String value) {
  return value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&apos;');
}

String _xlsxSheet(List<String> headers, List<List<String>> rows) {
  const textColumns = {2, 5, 6, 7, 16, 17, 18, 19};
  const moneyColumns = {11, 12};
  const numberColumns = {10, 13};
  final buffer = StringBuffer()
    ..write('<?xml version="1.0" encoding="UTF-8" standalone="yes"?>')
    ..write(
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
      'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">',
    )
    ..write('<sheetViews><sheetView workbookViewId="0">')
    ..write(
      '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>',
    )
    ..write('</sheetView></sheetViews>')
    ..write('<cols>');
  for (var column = 1; column <= headers.length; column++) {
    final width = switch (column) {
      1 => 28,
      2 => 20,
      5 => 48,
      7 => 18,
      8 => 28,
      20 => 28,
      _ => 14,
    };
    final style = textColumns.contains(column) ? ' style="1"' : '';
    buffer.write(
      '<col min="$column" max="$column" width="$width" customWidth="1"$style/>',
    );
  }
  buffer.write('</cols><sheetData>');
  void writeRow(int rowNumber, List<String> values, {bool header = false}) {
    buffer.write('<row r="$rowNumber">');
    for (var i = 0; i < values.length; i++) {
      final column = i + 1;
      final ref = '${_xlsxColumnName(column)}$rowNumber';
      final style = header
          ? 2
          : textColumns.contains(column)
          ? 1
          : moneyColumns.contains(column)
          ? 3
          : numberColumns.contains(column)
          ? 4
          : 0;
      buffer.write(
        '<c r="$ref" s="$style" t="inlineStr"><is><t>${_xmlEscape(values[i])}</t></is></c>',
      );
    }
    buffer.write('</row>');
  }

  writeRow(1, headers, header: true);
  for (var i = 0; i < rows.length; i++) {
    writeRow(i + 2, rows[i]);
  }
  buffer
    ..write('</sheetData>')
    ..write('<autoFilter ref="A1:${_xlsxColumnName(headers.length)}1"/>')
    ..write('</worksheet>');
  return buffer.toString();
}

const _xlsxContentTypes =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>';

const _xlsxRootRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>';

const _xlsxWorkbookRels =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
    '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
    '</Relationships>';

const _xlsxWorkbook =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
    'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
    '<sheets><sheet name="Entrada de mercadorias" sheetId="1" r:id="rId1"/></sheets>'
    '</workbook>';

const _xlsxStyles =
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
    '<fonts count="2">'
    '<font><sz val="11"/><name val="Calibri"/></font>'
    '<font><b/><sz val="11"/><name val="Calibri"/></font>'
    '</fonts>'
    '<fills count="2">'
    '<fill><patternFill patternType="none"/></fill>'
    '<fill><patternFill patternType="gray125"/></fill>'
    '</fills>'
    '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
    '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
    '<cellXfs count="5">'
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
    '<xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
    '<xf numFmtId="4" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '<xf numFmtId="2" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
    '</cellXfs>'
    '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
    '</styleSheet>';

String formatBrazilianMoney(double value) =>
    'R\$ ${formatBrazilianMoneyInput(value)}';

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
