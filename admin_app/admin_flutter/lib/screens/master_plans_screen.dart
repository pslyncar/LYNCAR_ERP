import 'package:flutter/material.dart';

import '../models/business_segment.dart';
import '../models/session.dart';
import '../models/subscription_plan.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';
import '../widgets/responsive_data_table.dart';

const _planModuleLabels = {
  'dashboard': 'Dashboard',
  'clients': 'Clientes',
  'products': 'Produtos',
  'stock': 'Estoque',
  'stock_entries': 'Entradas',
  'stock_withdrawals': 'Baixas',
  'suppliers': 'Fornecedores',
  'production': 'Producao',
  'service_contracts': 'Contratos',
  'sales': 'Vendas',
  'cash_closings': 'Caixa e tesouraria',
  'pdv': 'PDV Web',
  'pdv_windows': 'PDV Windows',
  'service_orders': 'Ordens de servico',
  'equipments': 'Equipamentos',
  'tickets': 'Chamados',
  'monitoring': 'Monitoramento',
  'reports': 'Relatorios',
  'finance': 'Financeiro',
  'fiscal': 'Fiscal',
  'marketplaces': 'Marketplaces',
  'support': 'Suporte',
  'settings': 'Configuracoes',
  'users': 'Usuarios',
  'permissions': 'Permissoes',
};

class MasterPlansScreen extends StatefulWidget {
  const MasterPlansScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterPlansScreen> createState() => _MasterPlansScreenState();
}

class _MasterPlansScreenState extends State<MasterPlansScreen> {
  late final _api = ApiClient(widget.session.apiBaseUrl);
  List<SubscriptionPlan> _plans = [];
  List<BusinessSegment> _segments = [];
  int _tabIndex = 0;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listMasterPlans(widget.session.token),
        _api.listMasterSegments(widget.session.token),
      ]);
      setState(() {
        _plans = results[0] as List<SubscriptionPlan>;
        _segments = results[1] as List<BusinessSegment>;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createPlan() async {
    final plan = await showDialog<SubscriptionPlan>(
      context: context,
      builder: (context) => const _PlanDialog(),
    );
    if (plan == null) return;
    try {
      await _api.createMasterPlan(widget.session.token, plan);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _editPlan(SubscriptionPlan plan) async {
    final updated = await showDialog<SubscriptionPlan>(
      context: context,
      builder: (context) => _PlanDialog(plan: plan),
    );
    if (updated == null) return;
    try {
      await _api.updateMasterPlan(widget.session.token, plan.code, updated);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _deletePlan(SubscriptionPlan plan) async {
    final destination = await _confirmDeleteWithMigration(
      title: 'Excluir ${plan.name}?',
      message:
          'Se existir cliente usando este plano, escolha outro plano para migrar antes de excluir.',
      destinationLabel: 'Migrar clientes para',
      options: [
        for (final item in _plans)
          if (item.code != plan.code) _DeleteDestination(item.code, item.name),
      ],
    );
    if (destination == _DeleteCancelled.value) return;
    try {
      await _api.deleteMasterPlan(
        widget.session.token,
        plan.code,
        migrateToPlan: destination,
      );
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _createSegment() async {
    final segment = await showDialog<BusinessSegment>(
      context: context,
      builder: (context) => const _SegmentDialog(),
    );
    if (segment == null) return;
    try {
      await _api.createMasterSegment(widget.session.token, segment);
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _editSegment(BusinessSegment segment) async {
    final updated = await showDialog<BusinessSegment>(
      context: context,
      builder: (context) => _SegmentDialog(segment: segment),
    );
    if (updated == null) return;
    try {
      await _api.updateMasterSegment(
        widget.session.token,
        segment.code,
        updated,
      );
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<void> _deleteSegment(BusinessSegment segment) async {
    final destination = await _confirmDeleteWithMigration(
      title: 'Excluir ${segment.name}?',
      message:
          'Se existir cliente usando este segmento, escolha outro segmento para migrar antes de excluir.',
      destinationLabel: 'Migrar clientes para',
      options: [
        for (final item in _segments)
          if (item.code != segment.code)
            _DeleteDestination(item.code, item.name),
      ],
    );
    if (destination == _DeleteCancelled.value) return;
    try {
      await _api.deleteMasterSegment(
        widget.session.token,
        segment.code,
        migrateToSegment: destination,
      );
      await _load();
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  Future<String?> _confirmDeleteWithMigration({
    required String title,
    required String message,
    required String destinationLabel,
    required List<_DeleteDestination> options,
  }) async {
    String? destination;
    return showDialog<String?>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(title),
          content: SizedBox(
            width: 460,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message),
                if (options.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: destination,
                    decoration: InputDecoration(labelText: destinationLabel),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Excluir apenas se nao estiver em uso'),
                      ),
                      for (final option in options)
                        DropdownMenuItem(
                          value: option.code,
                          child: Text(option.name),
                        ),
                    ],
                    onChanged: (value) =>
                        setDialogState(() => destination = value),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_DeleteCancelled.value),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(destination),
              icon: const Icon(Icons.delete_outline),
              label: Text(destination == null ? 'Excluir' : 'Migrar e excluir'),
            ),
          ],
        ),
      ),
    );
  }

  String _storageLabel(int mb) {
    if (mb >= 1024) {
      final gb = mb / 1024;
      final text = gb == gb.roundToDouble()
          ? gb.toStringAsFixed(0)
          : gb.toStringAsFixed(1).replaceAll('.', ',');
      return '$text GB';
    }
    return '$mb MB';
  }

  String _modulesLabel(List<String> modules) {
    final labels = modules
        .map((module) => _planModuleLabels[module] ?? module)
        .take(5)
        .join(', ');
    final extra = modules.length - 5;
    return extra > 0 ? '$labels +$extra' : labels;
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Padding(
        padding: const EdgeInsets.all(18),
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
                        'Planos e segmentos',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Controle os pacotes comerciais e as sugestoes por tipo de negocio.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Atualizar',
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _loading
                      ? null
                      : _tabIndex == 0
                      ? _createPlan
                      : _createSegment,
                  icon: const Icon(Icons.add),
                  label: Text(_tabIndex == 0 ? 'Novo plano' : 'Novo segmento'),
                ),
              ],
            ),
            const SizedBox(height: 14),
            TabBar(
              onTap: (index) => setState(() => _tabIndex = index),
              tabs: const [
                Tab(text: 'Planos'),
                Tab(text: 'Segmentos'),
              ],
            ),
            const SizedBox(height: 14),
            if (_error != null) ...[
              ErrorPanel(message: _error!, onRetry: _load),
              const SizedBox(height: 12),
            ],
            Expanded(
              child: _loading
                  ? const AppCard(
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : TabBarView(
                      children: [
                        AppCard(child: _plansTable()),
                        AppCard(child: _segmentsTable()),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _plansTable() {
    return ResponsiveDataTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Plano')),
          DataColumn(label: Text('Mensal')),
          DataColumn(label: Text('Usuarios')),
          DataColumn(label: Text('Dados')),
          DataColumn(label: Text('Arquivos')),
          DataColumn(label: Text('Modulos')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final plan in _plans)
            DataRow(
              cells: [
                DataCell(Text(plan.name)),
                DataCell(
                  Text(
                    plan.monthlyPrice == null
                        ? 'Personalizado'
                        : 'R\$ ${plan.monthlyPrice}',
                  ),
                ),
                DataCell(
                  Text(
                    plan.maxUsers == null ? 'Ilimitados' : '${plan.maxUsers}',
                  ),
                ),
                DataCell(Text(_storageLabel(plan.databaseLimitMb))),
                DataCell(Text(_storageLabel(plan.fileLimitMb))),
                DataCell(Text(_modulesLabel(plan.defaultModules))),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar plano',
                        onPressed: () => _editPlan(plan),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Excluir plano',
                        onPressed: () => _deletePlan(plan),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _segmentsTable() {
    return ResponsiveDataTable(
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Segmento')),
          DataColumn(label: Text('Codigo')),
          DataColumn(label: Text('Modulos sugeridos')),
          DataColumn(label: Text('Status')),
          DataColumn(label: Text('')),
        ],
        rows: [
          for (final segment in _segments)
            DataRow(
              cells: [
                DataCell(Text(segment.name)),
                DataCell(Text(segment.code)),
                DataCell(Text(_modulesLabel(segment.defaultModules))),
                DataCell(Text(segment.active ? 'Ativo' : 'Inativo')),
                DataCell(
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Editar segmento',
                        onPressed: () => _editSegment(segment),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Excluir segmento',
                        onPressed: segment.code == 'custom'
                            ? null
                            : () => _deleteSegment(segment),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _DeleteDestination {
  const _DeleteDestination(this.code, this.name);

  final String code;
  final String name;
}

class _DeleteCancelled {
  static const value = '__cancelled__';
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({this.plan});

  final SubscriptionPlan? plan;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final _code = TextEditingController(text: widget.plan?.code ?? '');
  late final _name = TextEditingController(text: widget.plan?.name ?? '');
  late final _monthly = TextEditingController(
    text: widget.plan?.monthlyPrice ?? '',
  );
  late final _annual = TextEditingController(
    text: widget.plan?.annualPrice ?? '',
  );
  late final _users = TextEditingController(
    text: widget.plan?.maxUsers?.toString() ?? '',
  );
  late final _database = TextEditingController(
    text: widget.plan?.databaseLimitMb.toString() ?? '80',
  );
  late final _files = TextEditingController(
    text: widget.plan?.fileLimitMb.toString() ?? '1536',
  );
  late final _multiCompany = TextEditingController(
    text: widget.plan?.multiCompanyLimit?.toString() ?? '1',
  );
  late final _sortOrder = TextEditingController(
    text: widget.plan?.sortOrder.toString() ?? '0',
  );
  late bool _api = widget.plan?.apiEnabled ?? false;
  late bool _support = widget.plan?.prioritySupport ?? false;
  late bool _active = widget.plan?.active ?? true;
  late final Set<String> _modules =
      widget.plan?.defaultModules.toSet() ?? <String>{};

  bool get _isEditing => widget.plan != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _monthly.dispose();
    _annual.dispose();
    _users.dispose();
    _database.dispose();
    _files.dispose();
    _multiCompany.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  int? _intOrNull(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  int _requiredInt(TextEditingController controller, int fallback) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value <= 0 ? fallback : value;
  }

  String? _emptyToNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  String _normalizeCode(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar ${widget.plan!.name}' : 'Novo plano'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _code,
                enabled: !_isEditing,
                decoration: const InputDecoration(labelText: 'Codigo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _monthly,
                      decoration: const InputDecoration(
                        labelText: 'Preco mensal',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _annual,
                      decoration: const InputDecoration(
                        labelText: 'Preco anual',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _users,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Usuarios'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _database,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Dados em MB',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _files,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Arquivos em MB',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _multiCompany,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Multiempresa',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sortOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ordem'),
              ),
              SwitchListTile(
                value: _api,
                onChanged: (value) => setState(() => _api = value),
                title: const Text('API liberada'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _support,
                onChanged: (value) => setState(() => _support = value),
                title: const Text('Suporte prioritario'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Plano ativo'),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Modulos padrao do plano',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ModuleChips(modules: _modules),
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
            final code = _normalizeCode(
              _isEditing ? widget.plan!.code : _code.text,
            );
            final name = _name.text.trim();
            if (code.isEmpty || name.isEmpty) return;
            Navigator.of(context).pop(
              SubscriptionPlan(
                id: widget.plan?.id ?? 0,
                code: code,
                name: name,
                monthlyPrice: _emptyToNull(_monthly),
                annualPrice: _emptyToNull(_annual),
                maxUsers: _intOrNull(_users),
                databaseLimitMb: _requiredInt(
                  _database,
                  widget.plan?.databaseLimitMb ?? 80,
                ),
                fileLimitMb: _requiredInt(
                  _files,
                  widget.plan?.fileLimitMb ?? 1536,
                ),
                multiCompanyLimit: _intOrNull(_multiCompany),
                apiEnabled: _api,
                prioritySupport: _support,
                defaultModules: _modules.toList()..sort(),
                active: _active,
                sortOrder:
                    int.tryParse(_sortOrder.text.trim()) ??
                    widget.plan?.sortOrder ??
                    0,
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _SegmentDialog extends StatefulWidget {
  const _SegmentDialog({this.segment});

  final BusinessSegment? segment;

  @override
  State<_SegmentDialog> createState() => _SegmentDialogState();
}

class _SegmentDialogState extends State<_SegmentDialog> {
  late final _code = TextEditingController(text: widget.segment?.code ?? '');
  late final _name = TextEditingController(text: widget.segment?.name ?? '');
  late final _description = TextEditingController(
    text: widget.segment?.description ?? '',
  );
  late final _sortOrder = TextEditingController(
    text: widget.segment?.sortOrder.toString() ?? '0',
  );
  late bool _active = widget.segment?.active ?? true;
  late bool _sellerRoleEnabled = widget.segment?.sellerRoleEnabled ?? false;
  late bool _technicianRoleEnabled =
      widget.segment?.technicianRoleEnabled ?? false;
  late final Set<String> _modules =
      widget.segment?.defaultModules.toSet() ?? <String>{};

  bool get _isEditing => widget.segment != null;

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _description.dispose();
    _sortOrder.dispose();
    super.dispose();
  }

  String _normalizeCode(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_');
  }

  String? _emptyToNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Editar segmento' : 'Novo segmento'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _code,
                enabled: !_isEditing,
                decoration: const InputDecoration(labelText: 'Codigo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Nome'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Descricao'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _sortOrder,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Ordem'),
              ),
              SwitchListTile(
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Segmento ativo'),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Modulos sugeridos pelo segmento',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _ModuleChips(modules: _modules),
              const Divider(height: 28),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Funcoes operacionais',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              SwitchListTile(
                value: _sellerRoleEnabled,
                onChanged: (value) =>
                    setState(() => _sellerRoleEnabled = value),
                title: const Text('Permitir perfis de vendedor'),
                subtitle: const Text(
                  'Usuarios com esse perfil terao codigo de vendedor obrigatorio.',
                ),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _technicianRoleEnabled,
                onChanged: (value) =>
                    setState(() => _technicianRoleEnabled = value),
                title: const Text('Permitir perfis de tecnico'),
                subtitle: const Text(
                  'Usuarios com esse perfil terao codigo de tecnico obrigatorio.',
                ),
                contentPadding: EdgeInsets.zero,
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
            final code = _normalizeCode(
              _isEditing ? widget.segment!.code : _code.text,
            );
            final name = _name.text.trim();
            if (code.isEmpty || name.isEmpty) return;
            Navigator.of(context).pop(
              BusinessSegment(
                id: widget.segment?.id ?? 0,
                code: code,
                name: name,
                description: _emptyToNull(_description),
                defaultModules: _modules.toList()..sort(),
                sellerRoleEnabled: _sellerRoleEnabled,
                technicianRoleEnabled: _technicianRoleEnabled,
                active: _active,
                sortOrder:
                    int.tryParse(_sortOrder.text.trim()) ??
                    widget.segment?.sortOrder ??
                    0,
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _ModuleChips extends StatefulWidget {
  const _ModuleChips({required this.modules});

  final Set<String> modules;

  @override
  State<_ModuleChips> createState() => _ModuleChipsState();
}

class _ModuleChipsState extends State<_ModuleChips> {
  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final entry in _planModuleLabels.entries)
          FilterChip(
            label: Text(entry.value),
            selected: widget.modules.contains(entry.key),
            onSelected: (selected) {
              setState(() {
                if (selected) {
                  widget.modules.add(entry.key);
                  if (entry.key == 'stock') widget.modules.add('suppliers');
                } else {
                  widget.modules.remove(entry.key);
                }
              });
            },
          ),
      ],
    );
  }
}
