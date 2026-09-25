import 'package:flutter/material.dart';

import '../models/session.dart';
import '../services/api_client.dart';

class SupplierProductLinksScreen extends StatefulWidget {
  const SupplierProductLinksScreen({super.key, required this.session});

  final Session session;

  @override
  State<SupplierProductLinksScreen> createState() =>
      _SupplierProductLinksScreenState();
}

class _SupplierProductLinksScreenState
    extends State<SupplierProductLinksScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  List<Map<String, dynamic>> _links = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final links = await _api.listSupplierProductLinks(
        widget.session.token,
        query: _search.text,
        active: true,
      );
      if (!mounted) return;
      setState(() {
        _links = links;
        _loading = false;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Não foi possível carregar os vínculos: $error';
      });
    }
  }

  Future<void> _edit(Map<String, dynamic> link) async {
    final code = TextEditingController(
      text: link['supplier_product_code']?.toString() ?? '',
    );
    final description = TextEditingController(
      text: link['supplier_description']?.toString() ?? '',
    );
    final commercial = TextEditingController(
      text: link['commercial_gtin']?.toString() ?? '',
    );
    final tax = TextEditingController(text: link['tax_gtin']?.toString() ?? '');
    final factor = TextEditingController(
      text: link['conversion_factor']?.toString() ?? '',
    );
    try {
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Editar vínculo do fornecedor'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _field(code, 'Código do fornecedor'),
                  _field(description, 'Descrição enviada pelo fornecedor'),
                  _field(commercial, 'GTIN comercial'),
                  _field(tax, 'GTIN tributável'),
                  _field(factor, 'Fator de conversão', number: true),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'O código interno e os GTINs principais do produto não são alterados aqui.',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () async {
                try {
                  await _api.updateSupplierProductLink(
                    widget.session.token,
                    link['id'] as int,
                    {
                      'supplier_product_code': code.text.trim(),
                      'supplier_description': description.text.trim(),
                      'commercial_gtin': commercial.text.trim(),
                      'tax_gtin': tax.text.trim(),
                      'conversion_factor': double.tryParse(
                        factor.text.replaceAll(',', '.'),
                      ),
                    },
                  );
                  if (dialogContext.mounted) {
                    Navigator.pop(dialogContext, true);
                  }
                } on ApiException catch (error) {
                  if (dialogContext.mounted) {
                    ScaffoldMessenger.of(
                      dialogContext,
                    ).showSnackBar(SnackBar(content: Text(error.message)));
                  }
                }
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      );
      if (saved == true) await _load();
    } finally {
      code.dispose();
      description.dispose();
      commercial.dispose();
      tax.dispose();
      factor.dispose();
    }
  }

  Future<void> _deactivate(Map<String, dynamic> link) async {
    await _api.deactivateSupplierProductLink(
      widget.session.token,
      link['id'] as int,
    );
    await _load();
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: TextField(
      controller: controller,
      keyboardType: number
          ? const TextInputType.numberWithOptions(decimal: true)
          : null,
      decoration: InputDecoration(labelText: label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Vínculos de fornecedores'),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Referências usadas para reconhecer automaticamente os produtos nas próximas notas.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: 'Pesquisar fornecedor, produto, código ou GTIN',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  onPressed: () {
                    _search.clear();
                    _load();
                  },
                  icon: const Icon(Icons.clear),
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Expanded(child: Center(child: Text(_error!)))
            else if (_links.isEmpty)
              const Expanded(
                child: Center(child: Text('Nenhum vínculo encontrado.')),
              )
            else
              Expanded(
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  child: SingleChildScrollView(
                    child: DataTable(
                      columns: const [
                        DataColumn(label: Text('Fornecedor')),
                        DataColumn(label: Text('Produto')),
                        DataColumn(label: Text('Código do fornecedor')),
                        DataColumn(label: Text('GTIN unidade')),
                        DataColumn(label: Text('GTIN caixa')),
                        DataColumn(label: Text('Ações')),
                      ],
                      rows: _links
                          .map(
                            (link) => DataRow(
                              cells: [
                                DataCell(
                                  Text(
                                    link['supplier_name']?.toString() ?? '—',
                                  ),
                                ),
                                DataCell(
                                  Text(link['product_name']?.toString() ?? '—'),
                                ),
                                DataCell(
                                  Text(
                                    link['supplier_product_code']?.toString() ??
                                        '—',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    link['commercial_gtin']?.toString() ?? '—',
                                  ),
                                ),
                                DataCell(
                                  Text(link['tax_gtin']?.toString() ?? '—'),
                                ),
                                DataCell(
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        tooltip: 'Editar vínculo',
                                        onPressed: () => _edit(link),
                                        icon: const Icon(Icons.edit_outlined),
                                      ),
                                      IconButton(
                                        tooltip: 'Desativar vínculo',
                                        onPressed: () => _deactivate(link),
                                        icon: const Icon(
                                          Icons.link_off_outlined,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          )
                          .toList(),
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
