import 'package:flutter/material.dart';

import '../models/session.dart';
import '../models/supplier.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

class SuppliersScreen extends StatefulWidget {
  const SuppliersScreen({super.key, required this.session});

  final Session session;

  @override
  State<SuppliersScreen> createState() => _SuppliersScreenState();
}

class _SuppliersScreenState extends State<SuppliersScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  List<Supplier> _suppliers = [];
  bool _loading = true;
  String? _error;
  String _statusFilter = 'ativos';

  bool get _canCreate => widget.session.can('suppliers:create');
  bool get _canUpdate => widget.session.can('suppliers:update');
  bool get _canDelete => widget.session.can('suppliers:delete');

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
      final suppliers = await _api.listSuppliers(widget.session.token);
      setState(() => _suppliers = suppliers);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar fornecedores.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Supplier? supplier]) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _SupplierDialog(
        api: _api,
        token: widget.session.token,
        supplier: supplier,
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _deleteSupplier(Supplier supplier) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir fornecedor?'),
        content: Text(
          'Deseja realmente excluir o fornecedor "${supplier.name}"? Esta ação não pode ser desfeita.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.deleteSupplier(widget.session.token, supplier.id);
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  List<Supplier> _filteredSuppliers() {
    final term = _normalize(_search.text);
    return _suppliers.where((supplier) {
      if (_statusFilter == 'ativos' && !supplier.active) return false;
      if (_statusFilter == 'inativos' && supplier.active) return false;
      if (term.isEmpty) return true;
      final haystack = _normalize(
        [
          supplier.name,
          supplier.tradeName,
          supplier.documentNumber,
          supplier.stateRegistration,
          supplier.phone,
          supplier.email,
          supplier.city,
          supplier.state,
          supplier.addressLine,
          supplier.notes,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final suppliers = _filteredSuppliers();
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
                        'Fornecedores',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Cadastro usado em compras, XML NF-e e entradas de mercadoria',
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
                const SizedBox(width: 8),
                if (_canCreate)
                  FilledButton.icon(
                    onPressed: () => _openForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('Novo fornecedor'),
                  ),
              ],
            ),
            const SizedBox(height: 18),
            AppCard(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact = constraints.maxWidth < 720;
                  final search = TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      labelText: 'Buscar fornecedores',
                      hintText: 'Nome, CNPJ/CPF, e-mail, telefone, cidade...',
                      prefixIcon: Icon(Icons.search),
                      border: OutlineInputBorder(),
                    ),
                  );
                  final status = DropdownButtonFormField<String>(
                    initialValue: _statusFilter,
                    decoration: const InputDecoration(
                      labelText: 'Status',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'todos', child: Text('Todos')),
                      DropdownMenuItem(value: 'ativos', child: Text('Ativos')),
                      DropdownMenuItem(
                        value: 'inativos',
                        child: Text('Inativos'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _statusFilter = value ?? 'ativos'),
                  );
                  if (compact) {
                    return Column(
                      children: [search, const SizedBox(height: 12), status],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: search),
                      const SizedBox(width: 12),
                      SizedBox(width: 190, child: status),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: suppliers.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhum fornecedor encontrado.'),
                      )
                    : _SuppliersTable(
                        suppliers: suppliers,
                        canEdit: _canUpdate,
                        canDelete: _canDelete,
                        onEdit: _openForm,
                        onDelete: _deleteSupplier,
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SuppliersTable extends StatelessWidget {
  const _SuppliersTable({
    required this.suppliers,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Supplier> suppliers;
  final bool canEdit;
  final bool canDelete;
  final ValueChanged<Supplier> onEdit;
  final ValueChanged<Supplier> onDelete;

  @override
  Widget build(BuildContext context) {
    return ResponsiveDataTable(
      child: DataTable(
        columnSpacing: 32,
        horizontalMargin: 24,
        columns: const [
          DataColumn(label: Text('Fornecedor')),
          DataColumn(label: Text('Documento')),
          DataColumn(label: Text('Contato')),
          DataColumn(label: Text('Cidade')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('Ações')),
        ],
        rows: [
          for (final supplier in suppliers)
            DataRow(
              cells: [
                DataCell(
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        supplier.name,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      if ((supplier.tradeName ?? '').isNotEmpty)
                        Text(
                          supplier.tradeName!,
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
                DataCell(Text(supplier.documentNumber ?? '-')),
                DataCell(
                  Text(
                    [supplier.phone, supplier.email]
                        .whereType<String>()
                        .where((value) => value.isNotEmpty)
                        .join('\n'),
                  ),
                ),
                DataCell(
                  Text(
                    [
                      supplier.city,
                      supplier.state,
                    ].whereType<String>().join(' / '),
                  ),
                ),
                DataCell(
                  Chip(
                    label: Text(supplier.active ? 'Ativo' : 'Inativo'),
                    backgroundColor: supplier.active
                        ? const Color(0xFFE0F2FE)
                        : const Color(0xFFF1F5F9),
                  ),
                ),
                DataCell(
                  SizedBox(
                    width: 104,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Editar fornecedor',
                          onPressed: canEdit ? () => onEdit(supplier) : null,
                          icon: const Icon(Icons.edit_outlined),
                        ),
                        IconButton(
                          tooltip: 'Excluir fornecedor',
                          onPressed: canDelete
                              ? () => onDelete(supplier)
                              : null,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _SupplierDialog extends StatefulWidget {
  const _SupplierDialog({
    required this.api,
    required this.token,
    this.supplier,
  });

  final ApiClient api;
  final String token;
  final Supplier? supplier;

  @override
  State<_SupplierDialog> createState() => _SupplierDialogState();
}

class _SupplierDialogState extends State<_SupplierDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.supplier?.name ?? '');
  late final _tradeName = TextEditingController(
    text: widget.supplier?.tradeName ?? '',
  );
  late final _document = TextEditingController(
    text: widget.supplier?.documentNumber ?? '',
  );
  late final _stateRegistration = TextEditingController(
    text: widget.supplier?.stateRegistration ?? '',
  );
  late final _phone = TextEditingController(text: widget.supplier?.phone ?? '');
  late final _email = TextEditingController(text: widget.supplier?.email ?? '');
  late final _address = TextEditingController(
    text: widget.supplier?.addressLine ?? '',
  );
  late final _city = TextEditingController(text: widget.supplier?.city ?? '');
  late final _state = TextEditingController(text: widget.supplier?.state ?? '');
  late final _notes = TextEditingController(text: widget.supplier?.notes ?? '');
  late bool _active = widget.supplier?.active ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final controller in [
      _name,
      _tradeName,
      _document,
      _stateRegistration,
      _phone,
      _email,
      _address,
      _city,
      _state,
      _notes,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    final payload = SupplierPayload(
      name: _name.text,
      tradeName: _tradeName.text,
      documentNumber: _document.text,
      stateRegistration: _stateRegistration.text,
      phone: _phone.text,
      email: _email.text,
      addressLine: _address.text,
      city: _city.text,
      state: _state.text,
      notes: _notes.text,
      active: _active,
    );
    try {
      if (widget.supplier == null) {
        await widget.api.createSupplier(widget.token, payload);
      } else {
        await widget.api.updateSupplier(
          widget.token,
          widget.supplier!.id,
          payload,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.supplier == null ? 'Novo fornecedor' : 'Editar fornecedor',
      ),
      content: SizedBox(
        width: 820,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_error != null) ...[
                  ErrorPanel(message: _error!, onRetry: _save),
                  const SizedBox(height: 12),
                ],
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _name,
                      decoration: const InputDecoration(
                        labelText: 'Razao social / nome',
                        border: OutlineInputBorder(),
                      ),
                      validator: (value) =>
                          value == null || value.trim().length < 2
                          ? 'Informe o fornecedor.'
                          : null,
                    ),
                    TextFormField(
                      controller: _tradeName,
                      decoration: const InputDecoration(
                        labelText: 'Nome fantasia',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _document,
                      decoration: const InputDecoration(
                        labelText: 'CNPJ/CPF',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _stateRegistration,
                      decoration: const InputDecoration(
                        labelText: 'Inscrição estadual',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _phone,
                      decoration: const InputDecoration(
                        labelText: 'Telefone',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _email,
                      decoration: const InputDecoration(
                        labelText: 'E-mail',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _ResponsiveFields(
                  children: [
                    TextFormField(
                      controller: _address,
                      decoration: const InputDecoration(
                        labelText: 'Endereço',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _city,
                      decoration: const InputDecoration(
                        labelText: 'Cidade',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    TextFormField(
                      controller: _state,
                      decoration: const InputDecoration(
                        labelText: 'UF',
                        border: OutlineInputBorder(),
                      ),
                      maxLength: 2,
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Observações',
                    border: OutlineInputBorder(),
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _active,
                  onChanged: (value) => setState(() => _active = value),
                  title: const Text('Fornecedor ativo'),
                  contentPadding: EdgeInsets.zero,
                ),
              ],
            ),
          ),
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
          label: Text(_saving ? 'Salvando...' : 'Salvar'),
        ),
      ],
    );
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            children: [
              for (final child in children) ...[
                child,
                if (child != children.last) const SizedBox(height: 12),
              ],
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final child in children) ...[
              Expanded(child: child),
              if (child != children.last) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
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
