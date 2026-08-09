import 'package:flutter/material.dart';

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
  'suppliers': 'Fornecedores',
  'production': 'Producao',
  'service_contracts': 'Contratos',
  'sales': 'Vendas',
  'pdv': 'PDV Web',
  'pdv_windows': 'PDV Windows',
  'service_orders': 'Ordens de servico',
  'equipments': 'Equipamentos',
  'tickets': 'Chamados',
  'monitoring': 'Monitoramento',
  'reports': 'Relatorios',
  'finance': 'Financeiro',
  'fiscal': 'Fiscal',
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
      final plans = await _api.listMasterPlans(widget.session.token);
      setState(() => _plans = plans);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit(SubscriptionPlan plan) async {
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

  @override
  Widget build(BuildContext context) {
    return Padding(
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
                      'Planos',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Preços e limites padrão usados para novos contratos.',
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
            ],
          ),
          const SizedBox(height: 18),
          if (_error != null) ...[
            ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: AppCard(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : ResponsiveDataTable(
                      child: DataTable(
                        columns: const [
                          DataColumn(label: Text('Plano')),
                          DataColumn(label: Text('Mensal')),
                          DataColumn(label: Text('Anual')),
                          DataColumn(label: Text('Usuários')),
                          DataColumn(label: Text('Dados')),
                          DataColumn(label: Text('Arquivos')),
                          DataColumn(label: Text('API')),
                          DataColumn(label: Text('Suporte')),
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
                                    plan.annualPrice == null
                                        ? 'Personalizado'
                                        : 'R\$ ${plan.annualPrice}',
                                  ),
                                ),
                                DataCell(
                                  Text(
                                    plan.maxUsers == null
                                        ? 'Ilimitados'
                                        : '${plan.maxUsers}',
                                  ),
                                ),
                                DataCell(
                                  Text(_storageLabel(plan.databaseLimitMb)),
                                ),
                                DataCell(Text(_storageLabel(plan.fileLimitMb))),
                                DataCell(Text(plan.apiEnabled ? 'Sim' : 'Não')),
                                DataCell(
                                  Text(
                                    plan.prioritySupport
                                        ? 'Prioritário'
                                        : 'Padrão',
                                  ),
                                ),
                                DataCell(
                                  IconButton(
                                    tooltip: 'Editar plano',
                                    onPressed: () => _edit(plan),
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlanDialog extends StatefulWidget {
  const _PlanDialog({required this.plan});

  final SubscriptionPlan plan;

  @override
  State<_PlanDialog> createState() => _PlanDialogState();
}

class _PlanDialogState extends State<_PlanDialog> {
  late final _name = TextEditingController(text: widget.plan.name);
  late final _monthly = TextEditingController(
    text: widget.plan.monthlyPrice ?? '',
  );
  late final _annual = TextEditingController(
    text: widget.plan.annualPrice ?? '',
  );
  late final _users = TextEditingController(
    text: widget.plan.maxUsers?.toString() ?? '',
  );
  late final _database = TextEditingController(
    text: widget.plan.databaseLimitMb.toString(),
  );
  late final _files = TextEditingController(
    text: widget.plan.fileLimitMb.toString(),
  );
  late final _multiCompany = TextEditingController(
    text: widget.plan.multiCompanyLimit?.toString() ?? '',
  );
  late bool _api = widget.plan.apiEnabled;
  late bool _support = widget.plan.prioritySupport;
  late bool _active = widget.plan.active;
  late final Set<String> _modules = widget.plan.defaultModules.toSet();

  @override
  void dispose() {
    _name.dispose();
    _monthly.dispose();
    _annual.dispose();
    _users.dispose();
    _database.dispose();
    _files.dispose();
    _multiCompany.dispose();
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

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Editar ${widget.plan.name}'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                        labelText: 'Preço mensal',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _annual,
                      decoration: const InputDecoration(
                        labelText: 'Preço anual',
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
                      decoration: const InputDecoration(labelText: 'Usuários'),
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
              const SizedBox(height: 8),
              SwitchListTile(
                value: _api,
                onChanged: (value) => setState(() => _api = value),
                title: const Text('API liberada'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _support,
                onChanged: (value) => setState(() => _support = value),
                title: const Text('Suporte prioritário'),
                contentPadding: EdgeInsets.zero,
              ),
              SwitchListTile(
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Plano ativo'),
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(height: 28),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEFF6FF),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFBFDBFE)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Color(0xFF2563EB)),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Ao salvar, os modulos marcados aqui serao aplicados a todos os clientes deste plano.',
                        style: TextStyle(
                          color: Color(0xFF1E3A8A),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
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
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in _planModuleLabels.entries)
                    FilterChip(
                      label: Text(entry.value),
                      selected: _modules.contains(entry.key),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _modules.add(entry.key);
                            if (entry.key == 'stock') _modules.add('suppliers');
                          } else {
                            _modules.remove(entry.key);
                          }
                        });
                      },
                    ),
                ],
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
            Navigator.of(context).pop(
              SubscriptionPlan(
                id: widget.plan.id,
                code: widget.plan.code,
                name: _name.text.trim().isEmpty
                    ? widget.plan.name
                    : _name.text.trim(),
                monthlyPrice: _emptyToNull(_monthly),
                annualPrice: _emptyToNull(_annual),
                maxUsers: _intOrNull(_users),
                databaseLimitMb: _requiredInt(
                  _database,
                  widget.plan.databaseLimitMb,
                ),
                fileLimitMb: _requiredInt(_files, widget.plan.fileLimitMb),
                multiCompanyLimit: _intOrNull(_multiCompany),
                apiEnabled: _api,
                prioritySupport: _support,
                defaultModules: _modules.toList()..sort(),
                active: _active,
                sortOrder: widget.plan.sortOrder,
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
