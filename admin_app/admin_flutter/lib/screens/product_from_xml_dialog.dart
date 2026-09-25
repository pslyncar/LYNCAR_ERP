import 'package:flutter/material.dart';

import '../models/stock_entry.dart';

class NewProductFromXml {
  const NewProductFromXml({
    required this.name,
    required this.description,
    required this.barcode,
    required this.stockUnit,
    required this.minimumStock,
    required this.category,
    required this.stockLocation,
    required this.tracksBatch,
    required this.purchaseConversionEnabled,
    this.purchasePackageFactor,
    this.purchasePackageBarcode,
  });

  final String name;
  final String description;
  final String? barcode;
  final String stockUnit;
  final double minimumStock;
  final String? category;
  final String? stockLocation;
  final bool tracksBatch;
  final bool purchaseConversionEnabled;
  final double? purchasePackageFactor;
  final String? purchasePackageBarcode;
}

class ProductFromXmlDialog extends StatefulWidget {
  const ProductFromXmlDialog({super.key, required this.item});

  final StockEntryItem item;

  @override
  State<ProductFromXmlDialog> createState() => _ProductFromXmlDialogState();
}

class _ProductFromXmlDialogState extends State<ProductFromXmlDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _barcode;
  late final TextEditingController _unit;
  final _minimumStock = TextEditingController(text: '0');
  final _category = TextEditingController();
  final _location = TextEditingController();
  late final TextEditingController _packageFactor;
  late final TextEditingController _packageBarcode;
  bool _tracksBatch = false;
  bool _usePackageConversion = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(text: widget.item.description);
    _barcode = TextEditingController(text: widget.item.barcode ?? '');
    _unit = TextEditingController(text: widget.item.unit);
    _packageFactor = TextEditingController(
      text: widget.item.packageConversionFactor == null
          ? ''
          : widget.item.packageConversionFactor!.toString(),
    );
    _packageBarcode = TextEditingController();
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _barcode,
      _unit,
      _minimumStock,
      _category,
      _location,
      _packageFactor,
      _packageBarcode,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    final minimumStock = double.tryParse(
      _minimumStock.text.replaceAll(',', '.'),
    );
    final factor = double.tryParse(_packageFactor.text.replaceAll(',', '.'));
    if (minimumStock == null || minimumStock < 0) {
      _showError('Informe um estoque mínimo válido.');
      return;
    }
    if (_usePackageConversion && (factor == null || factor <= 0)) {
      _showError('Informe quantas unidades de estoque há na embalagem.');
      return;
    }
    Navigator.pop(
      context,
      NewProductFromXml(
        name: _name.text.trim(),
        description: widget.item.description,
        barcode: _optional(_barcode.text),
        stockUnit: _unit.text.trim(),
        minimumStock: minimumStock,
        category: _optional(_category.text),
        stockLocation: _optional(_location.text),
        tracksBatch: _tracksBatch,
        purchaseConversionEnabled: _usePackageConversion,
        purchasePackageFactor: _usePackageConversion ? factor : null,
        purchasePackageBarcode: _usePackageConversion
            ? _optional(_packageBarcode.text)
            : null,
      ),
    );
  }

  void _showError(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return AlertDialog(
      title: const Text('Cadastrar produto a partir do XML'),
      content: SizedBox(
        width: 680,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Os dados da nota são preservados no recebimento. Revise apenas o cadastro interno antes de criar o produto.',
                  style: const TextStyle(color: Color(0xff52657f)),
                ),
                const SizedBox(height: 16),
                _xmlData(item),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(
                    labelText: 'Nome do produto *',
                  ),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Informe o nome do produto.'
                      : null,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        controller: _unit,
                        decoration: const InputDecoration(
                          labelText: 'Unidade de estoque *',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Informe a unidade.'
                            : null,
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        controller: _minimumStock,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'Estoque mínimo',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        controller: _barcode,
                        decoration: const InputDecoration(
                          labelText: 'GTIN / código de barras',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        controller: _category,
                        decoration: const InputDecoration(
                          labelText: 'Categoria',
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: TextFormField(
                        controller: _location,
                        decoration: const InputDecoration(
                          labelText: 'Localização no estoque',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  value: _tracksBatch,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Rastrear lote e validade'),
                  subtitle: const Text(
                    'Organiza saldos por lote quando informado; não bloqueia o recebimento.',
                  ),
                  onChanged: (value) => setState(() => _tracksBatch = value),
                ),
                SwitchListTile(
                  value: _usePackageConversion,
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Usar conversão de embalagem de compra'),
                  subtitle: Text(
                    'A nota vem em ${item.invoiceUnit ?? item.unit}; o estoque usa a unidade informada acima.',
                  ),
                  onChanged: (value) =>
                      setState(() => _usePackageConversion = value),
                ),
                if (_usePackageConversion)
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: 280,
                        child: TextFormField(
                          controller: _packageFactor,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Unidades de estoque por embalagem *',
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 280,
                        child: TextFormField(
                          controller: _packageBarcode,
                          decoration: const InputDecoration(
                            labelText: 'Código da embalagem',
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: _save,
          icon: const Icon(Icons.save_outlined),
          label: const Text('Cadastrar e associar'),
        ),
      ],
    );
  }

  Widget _xmlData(StockEntryItem item) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xfff2f7ff),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Wrap(
      spacing: 18,
      runSpacing: 6,
      children: [
        Text('XML: ${item.description}'),
        Text('NCM: ${item.ncm ?? 'não informado'}'),
        Text(
          'Código fornecedor: ${item.supplierProductCode ?? 'não informado'}',
        ),
        Text('Unidade NF: ${item.invoiceUnit ?? item.unit}'),
      ],
    ),
  );
}
