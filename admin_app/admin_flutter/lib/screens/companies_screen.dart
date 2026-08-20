import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/company.dart';
import '../models/business_segment.dart';
import '../models/session.dart';
import '../models/subscription_plan.dart';
import '../services/api_client.dart';
import '../services/cep_service.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _businessTypeLabels = {
  'assistencia_papezzo': 'Assistência Papezzo com monitoramento',
  'assistencia_técnica': 'Assistência técnica',
  'mercado': 'Mercado',
  'padaria': 'Padaria',
  'loja': 'Loja',
  'custom': 'Personalizado',
};

const _moduleLabels = {
  'dashboard': 'Dashboard',
  'clients': 'Clientes',
  'products': 'Produtos',
  'product_promotions': 'Preços e promoções',
  'stock': 'Estoque',
  'stock_entries': 'Entradas',
  'stock_withdrawals': 'Baixas',
  'suppliers': 'Fornecedores',
  'production': 'Produção',
  'service_contracts': 'Contratos variáveis',
  'sales': 'Histórico de vendas',
  'cash_closings': 'Caixa e tesouraria',
  'pdv': 'PDV Web',
  'pdv_windows': 'PDV Windows',
  'service_orders': 'OS',
  'equipments': 'Máquinas',
  'tickets': 'Chamados',
  'monitoring': 'Monitoramento',
  'reports': 'Relatórios',
  'finance': 'Financeiro',
  'fiscal': 'Fiscal',
  'marketplaces': 'Marketplaces',
  'support': 'Suporte',
  'settings': 'Configurações',
  'users': 'Usuários',
  'permissions': 'Permissões',
};

const _taxRegimeLabels = {
  '': 'Nao informado',
  'mei': 'MEI',
  'simples_nacional': 'Simples Nacional',
  'lucro_presumido': 'Lucro Presumido',
  'lucro_real': 'Lucro Real',
  'outro': 'Outro',
};

const _crtLabels = {
  '': 'Nao informado',
  '1': '1 - Simples Nacional',
  '2': '2 - Simples excesso sublimite',
  '3': '3 - Regime Normal',
  '4': '4 - MEI',
};

const _businessTypeModules = {
  'assistencia_papezzo': [
    'dashboard',
    'clients',
    'products',
    'stock',
    'stock_entries',
    'stock_withdrawals',
    'suppliers',
    'production',
    'service_contracts',
    'sales',
    'cash_closings',
    'pdv',
    'service_orders',
    'equipments',
    'tickets',
    'monitoring',
    'reports',
    'finance',
    'fiscal',
    'marketplaces',
    'support',
    'settings',
    'users',
    'permissions',
  ],
  'assistencia_técnica': [
    'dashboard',
    'clients',
    'products',
    'stock',
    'stock_entries',
    'stock_withdrawals',
    'suppliers',
    'service_contracts',
    'sales',
    'cash_closings',
    'pdv',
    'service_orders',
    'tickets',
    'reports',
    'finance',
    'fiscal',
    'marketplaces',
    'support',
    'settings',
    'users',
    'permissions',
  ],
  'mercado': [
    'dashboard',
    'clients',
    'products',
    'stock',
    'stock_entries',
    'stock_withdrawals',
    'suppliers',
    'service_contracts',
    'sales',
    'cash_closings',
    'pdv',
    'reports',
    'finance',
    'fiscal',
    'marketplaces',
    'support',
    'settings',
    'users',
    'permissions',
  ],
  'padaria': [
    'dashboard',
    'clients',
    'products',
    'stock',
    'stock_entries',
    'stock_withdrawals',
    'suppliers',
    'production',
    'service_contracts',
    'sales',
    'cash_closings',
    'pdv',
    'reports',
    'finance',
    'fiscal',
    'marketplaces',
    'support',
    'settings',
    'users',
    'permissions',
  ],
  'loja': [
    'dashboard',
    'clients',
    'products',
    'stock',
    'suppliers',
    'service_contracts',
    'sales',
    'pdv',
    'reports',
    'finance',
    'fiscal',
    'marketplaces',
    'users',
    'permissions',
  ],
  'custom': [
    'dashboard',
    'clients',
    'products',
    'stock',
    'production',
    'service_contracts',
    'sales',
    'pdv',
    'service_orders',
    'equipments',
    'tickets',
    'monitoring',
    'reports',
    'finance',
    'fiscal',
    'users',
    'permissions',
  ],
};

bool _moduleAllowedByPlanInfo(String module, _PlanInfo? plan) {
  return true;
}

class _PlanInfo {
  const _PlanInfo({
    required this.name,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.maxUsers,
    required this.databaseLimitMb,
    required this.fileLimitMb,
    required this.multiCompany,
    required this.api,
    required this.prioritySupport,
    required this.defaultModules,
  });

  final String name;
  final String? monthlyPrice;
  final String? annualPrice;
  final int? maxUsers;
  final int databaseLimitMb;
  final int fileLimitMb;
  final String multiCompany;
  final bool api;
  final bool prioritySupport;
  final List<String> defaultModules;
}

class _SegmentInfo {
  const _SegmentInfo({
    required this.name,
    required this.defaultModules,
    required this.active,
  });

  final String name;
  final List<String> defaultModules;
  final bool active;
}

const _plans = {
  'start': _PlanInfo(
    name: 'Start',
    monthlyPrice: '59,90',
    annualPrice: '599,00',
    maxUsers: 5,
    databaseLimitMb: 80,
    fileLimitMb: 1536,
    multiCompany: 'Não',
    api: false,
    prioritySupport: false,
    defaultModules: [
      'dashboard',
      'clients',
      'products',
      'stock',
      'suppliers',
      'sales',
      'pdv',
      'reports',
      'finance',
      'users',
      'permissions',
    ],
  ),
  'pro': _PlanInfo(
    name: 'Pro',
    monthlyPrice: '119,90',
    annualPrice: '1.199,00',
    maxUsers: 25,
    databaseLimitMb: 250,
    fileLimitMb: 4096,
    multiCompany: 'Até 3',
    api: true,
    prioritySupport: false,
    defaultModules: [
      'dashboard',
      'clients',
      'products',
      'stock',
      'suppliers',
      'production',
      'service_contracts',
      'sales',
      'pdv',
      'pdv_windows',
      'service_orders',
      'tickets',
      'reports',
      'finance',
      'fiscal',
      'users',
      'permissions',
    ],
  ),
  'business': _PlanInfo(
    name: 'Business',
    monthlyPrice: '279,90',
    annualPrice: '2.799,00',
    maxUsers: 100,
    databaseLimitMb: 2048,
    fileLimitMb: 8192,
    multiCompany: 'Até 5',
    api: true,
    prioritySupport: true,
    defaultModules: [
      'dashboard',
      'clients',
      'products',
      'stock',
      'suppliers',
      'production',
      'service_contracts',
      'sales',
      'pdv',
      'pdv_windows',
      'service_orders',
      'equipments',
      'tickets',
      'monitoring',
      'reports',
      'finance',
      'fiscal',
      'users',
      'permissions',
    ],
  ),
  'enterprise': _PlanInfo(
    name: 'Enterprise',
    monthlyPrice: null,
    annualPrice: null,
    maxUsers: null,
    databaseLimitMb: 5120,
    fileLimitMb: 51200,
    multiCompany: 'Avançado',
    api: true,
    prioritySupport: true,
    defaultModules: [
      'dashboard',
      'clients',
      'products',
      'stock',
      'suppliers',
      'production',
      'service_contracts',
      'sales',
      'pdv',
      'pdv_windows',
      'service_orders',
      'equipments',
      'tickets',
      'monitoring',
      'reports',
      'finance',
      'fiscal',
      'users',
      'permissions',
    ],
  ),
};

const _paymentOptions = {
  'pix': 'Pix',
  'boleto': 'Boleto',
  'cartao_credito': 'Cartão de crédito',
  'cartao_debito': 'Cartão de débito',
  'dinheiro': 'Dinheiro',
  'transferencia': 'Transferência',
  'outro': 'Outro',
};

String _paymentValue(String? value) {
  final normalized = (value ?? '').trim().toLowerCase();
  if (normalized.isEmpty) return '';
  if (_paymentOptions.containsKey(normalized)) return normalized;
  for (final entry in _paymentOptions.entries) {
    if (entry.value.toLowerCase() == normalized) return entry.key;
  }
  return 'outro';
}

String _companyAccessUrl(String code) {
  final cleaned = code.trim().toLowerCase();
  if (cleaned.isEmpty) {
    return 'https://cliente.lyncar.com.br';
  }
  return 'https://$cleaned.lyncar.com.br';
}

class CompaniesScreen extends StatefulWidget {
  const CompaniesScreen({super.key, required this.session});

  final Session session;

  @override
  State<CompaniesScreen> createState() => _CompaniesScreenState();
}

class _CompaniesScreenState extends State<CompaniesScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  List<Company> _companies = [];
  Map<String, _PlanInfo> _availablePlans = _plans;
  Map<String, _SegmentInfo> _availableSegments = {
    for (final entry in _businessTypeLabels.entries)
      entry.key: _SegmentInfo(
        name: entry.value,
        defaultModules: _businessTypeModules[entry.key] ?? const [],
        active: true,
      ),
  };
  String _planFilter = 'all';
  String _statusFilter = 'all';
  bool _onlyUsageAlert = false;
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
      final results = await Future.wait([
        _api.listCompanies(widget.session.token),
        _api.listMasterPlans(widget.session.token),
        _api.listMasterSegments(widget.session.token),
      ]);
      final companies = results[0] as List<Company>;
      final plans = results[1] as List<SubscriptionPlan>;
      final segments = results[2] as List<BusinessSegment>;
      setState(() {
        _companies = companies;
        _availablePlans = {
          for (final plan in plans)
            plan.code: _PlanInfo(
              name: plan.name,
              monthlyPrice: plan.monthlyPrice,
              annualPrice: plan.annualPrice,
              maxUsers: plan.maxUsers,
              databaseLimitMb: plan.databaseLimitMb,
              fileLimitMb: plan.fileLimitMb,
              multiCompany: plan.multiCompanyLimit == null
                  ? 'Avançado'
                  : plan.multiCompanyLimit == 1
                  ? 'Não'
                  : 'Até ${plan.multiCompanyLimit}',
              api: plan.apiEnabled,
              prioritySupport: plan.prioritySupport,
              defaultModules: plan.defaultModules,
            ),
        };
        _availableSegments = {
          for (final segment in segments)
            segment.code: _SegmentInfo(
              name: segment.name,
              defaultModules: segment.defaultModules,
              active: segment.active,
            ),
        };
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar empresas.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openForm([Company? company]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _CompanyFormDialog(
        api: _api,
        token: widget.session.token,
        plans: _availablePlans,
        segments: _availableSegments,
        company: company,
        onSave: (input) async {
          if (company == null) {
            await _api.createCompany(widget.session.token, input);
          } else {
            await _api.updateCompany(widget.session.token, company.id, input);
          }
        },
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  String _storageLabel(int? mb) {
    if (mb == null) return '-';
    if (mb >= 1024) {
      final gb = mb / 1024;
      final text = gb == gb.roundToDouble()
          ? gb.toStringAsFixed(0)
          : gb.toStringAsFixed(1).replaceAll('.', ',');
      return '$text GB';
    }
    return '$mb MB';
  }

  double _usagePercent(int? usedMb, int? limitMb) {
    final used = usedMb ?? 0;
    final limit = limitMb ?? 0;
    if (limit <= 0) return 0;
    return used / limit;
  }

  bool _hasUsageAlert(Company company) {
    return _usagePercent(company.databaseUsageMb, company.databaseLimitMb) >=
            0.8 ||
        _usagePercent(company.fileUsageMb, company.fileLimitMb) >= 0.8;
  }

  List<Company> get _filteredCompanies {
    final query = _search.text.trim().toLowerCase();
    return _companies.where((company) {
      final matchesSearch =
          query.isEmpty ||
          company.name.toLowerCase().contains(query) ||
          company.code.toLowerCase().contains(query) ||
          (company.email ?? '').toLowerCase().contains(query) ||
          (company.documentNumber ?? '').toLowerCase().contains(query);
      final matchesPlan = _planFilter == 'all' || company.plan == _planFilter;
      final matchesStatus = switch (_statusFilter) {
        'active' => company.active,
        'inactive' => !company.active,
        _ => true,
      };
      final matchesUsage = !_onlyUsageAlert || _hasUsageAlert(company);
      return matchesSearch && matchesPlan && matchesStatus && matchesUsage;
    }).toList();
  }

  Future<void> _openUsageDetails(Company company) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(company.name),
        content: SizedBox(
          width: 620,
          child: _CompanyUsageRow(
            company: company,
            storageLabel: _storageLabel,
            expanded: true,
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
              _openForm(company);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar cliente'),
          ),
        ],
      ),
    );
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
                        'Empresas',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 4),
                      Text(
                        'Clientes que usam o PapezzoSync e seus bancos separados',
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
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _openForm(),
                  icon: const Icon(Icons.add),
                  label: const Text('Nova empresa'),
                ),
              ],
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else ...[
              AppCard(
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          flex: 2,
                          child: TextField(
                            controller: _search,
                            decoration: const InputDecoration(
                              labelText: 'Buscar cliente',
                              prefixIcon: Icon(Icons.search),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _planFilter,
                            decoration: const InputDecoration(
                              labelText: 'Plano',
                            ),
                            items: [
                              const DropdownMenuItem(
                                value: 'all',
                                child: Text('Todos'),
                              ),
                              for (final entry in _availablePlans.entries)
                                DropdownMenuItem(
                                  value: entry.key,
                                  child: Text(entry.value.name),
                                ),
                            ],
                            onChanged: (value) =>
                                setState(() => _planFilter = value ?? 'all'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            initialValue: _statusFilter,
                            decoration: const InputDecoration(
                              labelText: 'Status',
                            ),
                            items: const [
                              DropdownMenuItem(
                                value: 'all',
                                child: Text('Todos'),
                              ),
                              DropdownMenuItem(
                                value: 'active',
                                child: Text('Ativos'),
                              ),
                              DropdownMenuItem(
                                value: 'inactive',
                                child: Text('Inativos'),
                              ),
                            ],
                            onChanged: (value) =>
                                setState(() => _statusFilter = value ?? 'all'),
                          ),
                        ),
                      ],
                    ),
                    SwitchListTile(
                      value: _onlyUsageAlert,
                      onChanged: (value) =>
                          setState(() => _onlyUsageAlert = value),
                      title: const Text(
                        'Mostrar apenas clientes com uso acima de 80%',
                      ),
                      contentPadding: EdgeInsets.zero,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (_filteredCompanies.isEmpty)
                const AppCard(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('Nenhuma empresa encontrada.'),
                    ),
                  ),
                )
              else
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 1120;
                    return Wrap(
                      spacing: 14,
                      runSpacing: 14,
                      children: [
                        for (final company in _filteredCompanies)
                          SizedBox(
                            width: twoColumns
                                ? (constraints.maxWidth - 14) / 2
                                : constraints.maxWidth,
                            child: _CompanyMasterCard(
                              company: company,
                              storageLabel: _storageLabel,
                              onUsage: () => _openUsageDetails(company),
                              onEdit: () => _openForm(company),
                            ),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CompanyMasterCard extends StatelessWidget {
  const _CompanyMasterCard({
    required this.company,
    required this.storageLabel,
    required this.onUsage,
    required this.onEdit,
  });

  final Company company;
  final String Function(int? mb) storageLabel;
  final VoidCallback onUsage;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final statusColor = company.active
        ? const Color(0xFFE0F2FE)
        : const Color(0xFFFEE2E2);
    final statusTextColor = company.active
        ? const Color(0xFF075985)
        : const Color(0xFF991B1B);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _InfoPill(
                          icon: Icons.link_outlined,
                          text: company.code,
                        ),
                        _InfoPill(
                          icon: Icons.workspace_premium_outlined,
                          text: company.plan.toUpperCase(),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            company.active ? company.status : 'bloqueada',
                            style: TextStyle(
                              color: statusTextColor,
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Ver consumo',
                onPressed: onUsage,
                icon: const Icon(Icons.query_stats_outlined),
              ),
              const SizedBox(width: 4),
              IconButton.filledTonal(
                tooltip: 'Editar',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _CompanyUsageRow(company: company, storageLabel: storageLabel),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Row(
              children: [
                const Icon(
                  Icons.storage_outlined,
                  size: 18,
                  color: Color(0xFF64748B),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    company.databaseUrl,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF475569),
                      fontSize: 12,
                    ),
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

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF64748B)),
          const SizedBox(width: 5),
          Text(
            text,
            style: const TextStyle(
              color: Color(0xFF334155),
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _CompanyFormDialog extends StatefulWidget {
  const _CompanyFormDialog({
    required this.api,
    required this.token,
    required this.onSave,
    required this.plans,
    required this.segments,
    this.company,
  });

  final ApiClient api;
  final String token;
  final Company? company;
  final Map<String, _PlanInfo> plans;
  final Map<String, _SegmentInfo> segments;
  final Future<void> Function(CompanyInput input) onSave;

  @override
  State<_CompanyFormDialog> createState() => _CompanyFormDialogState();
}

class _CompanyUsageRow extends StatelessWidget {
  const _CompanyUsageRow({
    required this.company,
    required this.storageLabel,
    this.expanded = false,
  });

  final Company company;
  final String Function(int? mb) storageLabel;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 780;
        final bars = [
          _UsageBar(
            label: 'Dados',
            usedMb: company.databaseUsageMb,
            limitMb: company.databaseLimitMb,
            storageLabel: storageLabel,
            color: const Color(0xFF2563EB),
            expanded: expanded,
          ),
          _UsageBar(
            label: 'Arquivos',
            usedMb: company.fileUsageMb,
            limitMb: company.fileLimitMb,
            storageLabel: storageLabel,
            color: const Color(0xFF0F766E),
            expanded: expanded,
          ),
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    company.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  company.plan.toUpperCase(),
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (compact)
              Column(
                children: [
                  for (final bar in bars) ...[
                    bar,
                    if (bar != bars.last) const SizedBox(height: 10),
                  ],
                ],
              )
            else
              Row(
                children: [
                  Expanded(child: bars[0]),
                  const SizedBox(width: 14),
                  Expanded(child: bars[1]),
                ],
              ),
          ],
        );
      },
    );
  }
}

class _UsageBar extends StatelessWidget {
  const _UsageBar({
    required this.label,
    required this.usedMb,
    required this.limitMb,
    required this.storageLabel,
    required this.color,
    this.expanded = false,
  });

  final String label;
  final int? usedMb;
  final int? limitMb;
  final String Function(int? mb) storageLabel;
  final Color color;
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final used = usedMb ?? 0;
    final limit = limitMb ?? 0;
    final percent = limit <= 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final percentText = limit <= 0 ? '-' : '${(percent * 100).round()}%';
    final danger = percent >= 0.9;
    final barColor = danger ? const Color(0xFFDC2626) : color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            Text(
              '${storageLabel(usedMb)} / ${storageLabel(limitMb)}',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 42,
              child: Text(
                percentText,
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: danger
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFF334155),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 7),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: percent,
            minHeight: expanded ? 16 : 10,
            backgroundColor: const Color(0xFFE2E8F0),
            valueColor: AlwaysStoppedAnimation<Color>(barColor),
          ),
        ),
      ],
    );
  }
}

class _CompanyFormDialogState extends State<_CompanyFormDialog> {
  late final _code = TextEditingController(text: widget.company?.code ?? '');
  late final _name = TextEditingController(text: widget.company?.name ?? '');
  late String _plan = _normalizePlanCode(widget.company?.plan);
  late String _businessType =
      widget.company?.businessType ?? 'assistencia_tecnica';
  late Set<String> _enabledModules;
  late final _document = TextEditingController(
    text: widget.company?.documentNumber ?? '',
  );
  late final _stateRegistration = TextEditingController(
    text: widget.company?.stateRegistration ?? '',
  );
  late final _municipalRegistration = TextEditingController(
    text: widget.company?.municipalRegistration ?? '',
  );
  late final _tradeName = TextEditingController(
    text: widget.company?.tradeName ?? '',
  );
  late final _contactName = TextEditingController(
    text: widget.company?.contactName ?? '',
  );
  late final _responsibleCpf = TextEditingController(
    text: widget.company?.responsibleCpf ?? '',
  );
  late final _responsibleBirthDate = TextEditingController(
    text: _dateToBrazilian(widget.company?.responsibleBirthDate),
  );
  late final _phone = TextEditingController(text: widget.company?.phone ?? '');
  late final _email = TextEditingController(text: widget.company?.email ?? '');
  late final _addressLine = TextEditingController(
    text: widget.company?.addressLine ?? '',
  );
  late final _addressNumber = TextEditingController(
    text: widget.company?.addressNumber ?? '',
  );
  late final _neighborhood = TextEditingController(
    text: widget.company?.neighborhood ?? '',
  );
  late final _city = TextEditingController(text: widget.company?.city ?? '');
  late final _cityCode = TextEditingController(
    text: widget.company?.cityCode ?? '',
  );
  late final _state = TextEditingController(text: widget.company?.state ?? '');
  late final _zipCode = TextEditingController(
    text: widget.company?.zipCode ?? '',
  );
  late String _taxRegime = widget.company?.taxRegime ?? '';
  late String _crt = widget.company?.crt ?? '';
  CompanyTaxProfileLookup? _taxLookup;
  late final _databaseUrl = TextEditingController(
    text: widget.company?.databaseUrl ?? '',
  );
  late final _monthlyPrice = TextEditingController(
    text:
        widget.company?.monthlyPrice ??
        widget.plans[_normalizePlanCode(widget.company?.plan)]?.monthlyPrice ??
        '',
  );
  late final _billingDay = TextEditingController(
    text: widget.company?.billingDay ?? '',
  );
  late final _paymentMethod = TextEditingController(
    text: _paymentValue(widget.company?.paymentMethod),
  );
  late final _maxUsersOverride = TextEditingController(
    text: _overrideText('max_users'),
  );
  late final _databaseLimitOverride = TextEditingController(
    text: _overrideText('database_limit_mb'),
  );
  late final _fileLimitOverride = TextEditingController(
    text: _overrideText('file_limit_mb'),
  );
  late final _multiCompanyLimitOverride = TextEditingController(
    text: _overrideText('multi_company_limit'),
  );
  late final _notes = TextEditingController(text: widget.company?.notes ?? '');
  late final _adminName = TextEditingController();
  late final _adminEmail = TextEditingController();
  late final _adminPassword = TextEditingController();
  late String _personType = widget.company?.personType ?? 'PF';
  late bool _active = widget.company?.active ?? true;
  bool _provisionDatabase = true;
  bool _lookingUpCep = false;
  bool _lookingUpTaxProfile = false;
  bool _saving = false;
  String? _error;
  Timer? _cnpjLookupDebounce;
  String? _lastAutoLookupCnpj;
  String? _lastAutoLookupCep;

  @override
  void initState() {
    super.initState();
    _enabledModules = {
      ...(widget.company?.enabledModules.isNotEmpty == true
          ? widget.company!.enabledModules
          : _suggestedModulesFor(_plan, widget.company?.businessType)),
    };
    _applyBrazilianMasks();
    _document.addListener(_scheduleCnpjLookup);
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _document.removeListener(_scheduleCnpjLookup);
    _cnpjLookupDebounce?.cancel();
    _document.dispose();
    _stateRegistration.dispose();
    _municipalRegistration.dispose();
    _tradeName.dispose();
    _contactName.dispose();
    _responsibleCpf.dispose();
    _responsibleBirthDate.dispose();
    _phone.dispose();
    _email.dispose();
    _addressLine.dispose();
    _addressNumber.dispose();
    _neighborhood.dispose();
    _city.dispose();
    _cityCode.dispose();
    _state.dispose();
    _zipCode.dispose();
    _databaseUrl.dispose();
    _monthlyPrice.dispose();
    _billingDay.dispose();
    _paymentMethod.dispose();
    _maxUsersOverride.dispose();
    _databaseLimitOverride.dispose();
    _fileLimitOverride.dispose();
    _multiCompanyLimitOverride.dispose();
    _notes.dispose();
    _adminName.dispose();
    _adminEmail.dispose();
    _adminPassword.dispose();
    super.dispose();
  }

  Future<void> _save({bool allowCrossCompanyDuplicate = false}) async {
    final documentDigits = _document.text.replaceAll(RegExp(r'\D'), '');
    if (_personType == 'PF' && documentDigits.length != 11) {
      setState(() => _error = 'Informe um CPF válido com 11 dígitos.');
      return;
    }
    if (_personType == 'PJ' && documentDigits.length != 14) {
      setState(() => _error = 'Informe um CNPJ válido com 14 dígitos.');
      return;
    }
    final responsibleCpfDigits = _responsibleCpf.text.replaceAll(
      RegExp(r'\D'),
      '',
    );
    if (_personType == 'PJ' && responsibleCpfDigits.length != 11) {
      setState(() => _error = 'Informe o CPF do responsável com 11 dígitos.');
      return;
    }
    if (_responsibleBirthDate.text.trim().isNotEmpty &&
        !_isValidBrazilianDate(_responsibleBirthDate.text)) {
      setState(
        () => _error = 'Informe uma data de nascimento válida em dd/mm/aaaa.',
      );
      return;
    }
    final day = int.tryParse(_billingDay.text.trim());
    if (day == null || day < 1 || day > 31) {
      setState(() => _error = 'Informe o dia de vencimento entre 1 e 31.');
      return;
    }
    if (_paymentMethod.text.trim().isEmpty) {
      setState(() => _error = 'Selecione a forma de pagamento.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(
        CompanyInput(
          code: _code.text.trim(),
          name: _name.text.trim(),
          businessType: _businessType,
          personType: _personType,
          documentNumber: _emptyToNull(_document.text),
          stateRegistration: _emptyToNull(_stateRegistration.text),
          municipalRegistration: _emptyToNull(_municipalRegistration.text),
          tradeName: _emptyToNull(_tradeName.text),
          contactName: _emptyToNull(_contactName.text),
          responsibleCpf: _personType == 'PJ'
              ? _emptyToNull(responsibleCpfDigits)
              : null,
          responsibleBirthDate: _brazilianDateToIso(_responsibleBirthDate.text),
          phone: _emptyToNull(_phone.text),
          email: _emptyToNull(_email.text),
          addressLine: _emptyToNull(_addressLine.text),
          addressNumber: _emptyToNull(_addressNumber.text),
          neighborhood: _emptyToNull(_neighborhood.text),
          city: _emptyToNull(_city.text),
          cityCode: _emptyToNull(_cityCode.text),
          state: _emptyToNull(_state.text),
          zipCode: _emptyToNull(_zipCode.text),
          taxRegime: _taxRegime.trim().isEmpty ? null : _taxRegime,
          crt: _crt.trim().isEmpty ? null : _crt,
          databaseUrl: _databaseUrl.text.trim(),
          plan: _plan,
          planOverrides: _planOverrides(),
          enabledModules: _enabledModules.toList()..sort(),
          monthlyPrice: _emptyToNull(_monthlyPrice.text),
          billingDay: _emptyToNull(_billingDay.text),
          paymentMethod: _emptyToNull(_paymentMethod.text),
          status: _active ? 'active' : 'inactive',
          active: _active,
          provisionDatabase: _provisionDatabase,
          adminName: _adminName.text.trim(),
          adminEmail: _adminEmail.text.trim(),
          adminPassword: _adminPassword.text,
          allowCrossCompanyDuplicate: allowCrossCompanyDuplicate,
          notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        ),
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (await _showDuplicateEmailBlock(error)) return;
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar a empresa.');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _showDuplicateEmailBlock(ApiException error) async {
    final detail = error.data?['detail'];
    if (detail is! Map<String, dynamic>) return false;
    if (detail['code'] != 'email_exists_other_companies') return false;
    final companies = detail['companies'];
    if (companies is! List) return false;
    final companyLines = companies
        .whereType<Map<String, dynamic>>()
        .map(
          (company) =>
              '${company['company_name'] ?? company['company_code']} - ${company['access_url'] ?? ''}',
        )
        .join('\n');
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('E-mail já usado em outro cliente'),
        content: Text(
          'Este e-mail já existe em outro sistema:\n\n$companyLines\n\nUse outro e-mail para evitar conflito no login.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Entendi'),
          ),
        ],
      ),
    );
    if (mounted) {
      setState(() => _error = 'Este e-mail já está em uso em outro cliente.');
    }
    return true;
  }

  String? _emptyToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  String _dateToBrazilian(String? value) {
    if (value == null || value.trim().isEmpty) return '';
    final date = DateTime.tryParse(value.trim());
    if (date == null) return value;
    return '${date.day.toString().padLeft(2, '0')}/'
        '${date.month.toString().padLeft(2, '0')}/'
        '${date.year.toString().padLeft(4, '0')}';
  }

  String? _brazilianDateToIso(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final parts = text.split('/');
    if (parts.length != 3) return text;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null) return text;
    return '${year.toString().padLeft(4, '0')}-'
        '${month.toString().padLeft(2, '0')}-'
        '${day.toString().padLeft(2, '0')}';
  }

  bool _isValidBrazilianDate(String value) {
    final parts = value.trim().split('/');
    if (parts.length != 3) return false;
    final day = int.tryParse(parts[0]);
    final month = int.tryParse(parts[1]);
    final year = int.tryParse(parts[2]);
    if (day == null || month == null || year == null || year < 1900) {
      return false;
    }
    final date = DateTime(year, month, day);
    return date.year == year &&
        date.month == month &&
        date.day == day &&
        !date.isAfter(DateTime.now());
  }

  Future<void> _lookupCep() async {
    await _lookupCepInternal();
  }

  Future<void> _lookupCepInternal({bool auto = false}) async {
    final cep = _zipCode.text.replaceAll(RegExp(r'\D'), '');
    if (auto && (cep.length != 8 || cep == _lastAutoLookupCep)) return;
    setState(() {
      _lookingUpCep = true;
      if (!auto) _error = null;
    });
    try {
      final address = await const CepService().lookup(_zipCode.text);
      if (auto) _lastAutoLookupCep = cep;
      setState(() {
        if (_addressLine.text.trim().isEmpty) {
          _addressLine.text = address.street;
        }
        if (_neighborhood.text.trim().isEmpty) {
          _neighborhood.text = address.neighborhood;
        }
        _city.text = address.city;
        _state.text = address.state;
        if ((address.cityCode ?? '').trim().isNotEmpty) {
          _cityCode.text = address.cityCode!.trim();
        }
      });
    } on CepLookupException catch (error) {
      if (!auto) setState(() => _error = error.message);
    } catch (_) {
      if (!auto) setState(() => _error = 'Nao foi possivel consultar o CEP.');
    } finally {
      if (mounted) setState(() => _lookingUpCep = false);
    }
  }

  Future<void> _lookupTaxProfile() async {
    await _lookupTaxProfileInternal(force: true);
  }

  void _scheduleCnpjLookup() {
    final cnpj = _document.text.replaceAll(RegExp(r'\D'), '');
    _cnpjLookupDebounce?.cancel();
    if (cnpj.length != 14 || cnpj == _lastAutoLookupCnpj) return;
    _cnpjLookupDebounce = Timer(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      if (_personType != 'PJ') {
        setState(() => _personType = 'PJ');
      }
      _lookupTaxProfileInternal(auto: true);
    });
  }

  Future<void> _lookupTaxProfileInternal({
    bool auto = false,
    bool force = false,
  }) async {
    final cnpj = _document.text.replaceAll(RegExp(r'\D'), '');
    if (cnpj.length != 14) {
      if (!auto) {
        setState(
          () => _error = 'Informe um CNPJ com 14 digitos para consultar.',
        );
      }
      return;
    }
    if (!force && cnpj == _lastAutoLookupCnpj) {
      return;
    }
    setState(() {
      _lookingUpTaxProfile = true;
      if (!auto) _error = null;
    });
    try {
      final result = await widget.api.lookupCompanyTaxProfile(
        widget.token,
        cnpj,
      );
      _lastAutoLookupCnpj = cnpj;
      setState(() {
        _taxLookup = result;
        if ((result.taxRegime ?? '').isNotEmpty && _taxRegime.trim().isEmpty) {
          _taxRegime = result.taxRegime!;
        }
        if ((result.crt ?? '').isNotEmpty && _crt.trim().isEmpty) {
          _crt = result.crt!;
        }
        _fillIfEmpty(_name, result.legalName);
        _fillIfEmpty(_tradeName, result.tradeName);
        _fillIfEmpty(_email, result.email);
        _fillIfEmpty(_phone, result.phone);
        _fillIfEmpty(_zipCode, result.zipCode);
        _fillIfEmpty(_addressLine, result.addressLine);
        _fillIfEmpty(_addressNumber, result.addressNumber);
        _fillIfEmpty(_neighborhood, result.neighborhood);
        _fillIfEmpty(_city, result.city);
        _fillIfEmpty(_cityCode, result.cityCode);
        _fillIfEmpty(_state, result.state);
      });
      await _lookupCepInternal(auto: true);
    } on ApiException catch (error) {
      if (!auto) setState(() => _error = error.message);
    } catch (_) {
      if (!auto) {
        setState(
          () => _error =
              'Nao foi possivel consultar o CNPJ gratis. Informe manualmente.',
        );
      }
    } finally {
      if (mounted) setState(() => _lookingUpTaxProfile = false);
    }
  }

  void _fillIfEmpty(TextEditingController controller, String? value) {
    final text = value?.trim();
    if (text == null || text.isEmpty || controller.text.trim().isNotEmpty) {
      return;
    }
    controller.text = text;
    _formatControllerIfNeeded(controller);
  }

  void _applyBrazilianMasks() {
    _formatController(_document, const BrazilianCpfCnpjInputFormatter());
    _formatController(_responsibleCpf, const BrazilianCpfCnpjInputFormatter());
    _formatController(
      _responsibleBirthDate,
      const BrazilianDateInputFormatter(),
    );
    _formatController(_phone, const BrazilianPhoneInputFormatter());
    _formatController(_zipCode, const BrazilianCepInputFormatter());
    _formatController(_monthlyPrice, const BrazilianMoneyInputFormatter());
    _state.text = _state.text.toUpperCase();
  }

  void _formatControllerIfNeeded(TextEditingController controller) {
    if (controller == _document || controller == _responsibleCpf) {
      _formatController(controller, const BrazilianCpfCnpjInputFormatter());
    } else if (controller == _responsibleBirthDate) {
      _formatController(controller, const BrazilianDateInputFormatter());
    } else if (controller == _phone) {
      _formatController(controller, const BrazilianPhoneInputFormatter());
    } else if (controller == _zipCode) {
      _formatController(controller, const BrazilianCepInputFormatter());
    } else if (controller == _monthlyPrice) {
      _formatController(controller, const BrazilianMoneyInputFormatter());
    } else if (controller == _state) {
      controller.text = controller.text.toUpperCase();
    }
  }

  void _formatController(
    TextEditingController controller,
    TextInputFormatter formatter,
  ) {
    final value = TextEditingValue(
      text: controller.text,
      selection: TextSelection.collapsed(offset: controller.text.length),
    );
    final formatted = formatter.formatEditUpdate(value, value);
    controller.value = formatted;
  }

  String _normalizePlanCode(String? value) {
    final code = (value ?? 'start').trim().toLowerCase();
    return switch (code) {
      'starter' => 'start',
      'erp' => 'start',
      'premium' => 'business',
      'pro' || 'business' || 'enterprise' || 'start' => code,
      _ => 'start',
    };
  }

  String _overrideText(String key) {
    final value = widget.company?.planOverrides?[key];
    return value == null ? '' : value.toString();
  }

  int? _intOverride(TextEditingController controller) {
    final value = int.tryParse(controller.text.trim());
    return value == null || value <= 0 ? null : value;
  }

  Map<String, dynamic>? _planOverrides() {
    final data = <String, dynamic>{};
    final maxUsers = _intOverride(_maxUsersOverride);
    final databaseLimit = _intOverride(_databaseLimitOverride);
    final fileLimit = _intOverride(_fileLimitOverride);
    final multiCompanyLimit = _intOverride(_multiCompanyLimitOverride);
    if (maxUsers != null) data['max_users'] = maxUsers;
    if (databaseLimit != null) data['database_limit_mb'] = databaseLimit;
    if (fileLimit != null) data['file_limit_mb'] = fileLimit;
    if (multiCompanyLimit != null) {
      data['multi_company_limit'] = multiCompanyLimit;
    }
    return data.isEmpty ? null : data;
  }

  Set<String> _suggestedModulesFor(String plan, String? businessType) {
    final planModules =
        widget.plans[plan]?.defaultModules.toSet() ?? <String>{};
    final segmentModules =
        widget.segments[businessType ?? _businessType]?.defaultModules
            .toSet() ??
        _businessTypeModules[businessType ?? _businessType]?.toSet() ??
        <String>{};
    final suggested = {...segmentModules, ...planModules};
    if (suggested.contains('stock')) {
      suggested.add('suppliers');
    }
    return suggested;
  }

  List<DropdownMenuItem<String>> _segmentMenuItems() {
    final entries =
        widget.segments.entries
            .where((entry) => entry.value.active || entry.key == _businessType)
            .toList()
          ..sort((a, b) => a.value.name.compareTo(b.value.name));
    final hasCurrent = entries.any((entry) => entry.key == _businessType);
    return [
      if (!hasCurrent)
        DropdownMenuItem(
          value: _businessType,
          child: Text(_businessTypeLabels[_businessType] ?? _businessType),
        ),
      for (final entry in entries)
        DropdownMenuItem(value: entry.key, child: Text(entry.value.name)),
    ];
  }

  void _applyPlan(String plan) {
    final oldInfo = widget.plans[_plan];
    final info = widget.plans[plan]!;
    final currentMonthly = _monthlyPrice.text.trim();
    final shouldUsePlanPrice =
        currentMonthly.isEmpty ||
        currentMonthly == (oldInfo?.monthlyPrice ?? '');
    setState(() {
      _plan = plan;
      _enabledModules = _suggestedModulesFor(plan, _businessType);
      if (shouldUsePlanPrice) {
        _monthlyPrice.text = info.monthlyPrice ?? '';
      }
    });
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

  List<int> _optionsWithCurrent(
    List<int> options,
    TextEditingController controller,
  ) {
    final current = int.tryParse(controller.text.trim());
    final values = {...options};
    if (current != null && current > 0) values.add(current);
    return values.toList()..sort();
  }

  Widget _limitDropdown({
    required TextEditingController controller,
    required String label,
    required List<int> options,
    required String Function(int value) valueLabel,
  }) {
    final selected = controller.text.trim();
    final values = _optionsWithCurrent(options, controller);
    return DropdownButtonFormField<String>(
      initialValue: selected.isEmpty ? '' : selected,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: '', child: Text('Usar plano')),
        for (final value in values)
          DropdownMenuItem(
            value: value.toString(),
            child: Text(valueLabel(value)),
          ),
      ],
      onChanged: (value) => setState(() => controller.text = value ?? ''),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.company == null ? 'Nova empresa' : 'Editar empresa'),
      content: SizedBox(
        width: 860,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_error != null) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFECACA)),
                  ),
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              TextField(
                controller: _code,
                enabled: widget.company == null,
                decoration: const InputDecoration(
                  labelText: 'Subdomínio/link do cliente',
                  hintText: 'ex: padariadrika',
                ),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: ListenableBuilder(
                  listenable: _code,
                  builder: (context, _) => Text(
                    _companyAccessUrl(_code.text),
                    style: const TextStyle(
                      color: Color(0xFF2563EB),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _name,
                decoration: const InputDecoration(
                  labelText: 'Razao social / nome',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _businessType,
                decoration: const InputDecoration(labelText: 'Segmento'),
                items: _segmentMenuItems(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _businessType = value;
                    _enabledModules = _suggestedModulesFor(_plan, value);
                  });
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Dados fiscais para emissao',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Preencha CNPJ/IE e endereco se a empresa for usar certificado A1, NF-e ou NFC-e.',
                  style: TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'PF', label: Text('PF')),
                      ButtonSegment(value: 'PJ', label: Text('PJ')),
                    ],
                    selected: {_personType},
                    onSelectionChanged: (value) =>
                        setState(() => _personType = value.first),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _document,
                      decoration: const InputDecoration(labelText: 'CPF/CNPJ'),
                      keyboardType: TextInputType.number,
                      inputFormatters: const [BrazilianCpfCnpjInputFormatter()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _taxRegimeLabels.containsKey(_taxRegime)
                          ? _taxRegime
                          : '',
                      decoration: const InputDecoration(
                        labelText: 'Regime tributario sugerido',
                      ),
                      items: [
                        for (final entry in _taxRegimeLabels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _taxRegime = value ?? '';
                          if (_taxRegime == 'mei') {
                            _crt = '4';
                          } else if (_taxRegime == 'simples_nacional') {
                            _crt = '1';
                          } else if (_taxRegime == 'lucro_presumido' ||
                              _taxRegime == 'lucro_real') {
                            _crt = '3';
                          }
                        });
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _crtLabels.containsKey(_crt) ? _crt : '',
                      decoration: const InputDecoration(labelText: 'CRT'),
                      items: [
                        for (final entry in _crtLabels.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) => setState(() => _crt = value ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _lookingUpTaxProfile
                              ? null
                              : _lookupTaxProfile,
                          icon: _lookingUpTaxProfile
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.manage_search),
                          label: Text(
                            _lookingUpTaxProfile
                                ? 'Consultando CNPJ'
                                : 'Reconsultar CNPJ',
                          ),
                        ),
                        if (widget.company?.taxRegimeCheckedAt != null)
                          Text(
                            'Ultima consulta: ${widget.company!.taxRegimeCheckedAt}',
                            style: const TextStyle(
                              color: Color(0xFF64748B),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Ao digitar um CNPJ valido, o sistema consulta automaticamente dados publicos gratuitos e preenche o que estiver vazio. Confira sempre com o contador antes de emitir nota.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                    if (_taxLookup != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        _taxLookup!.message ??
                            'Consulta concluida. Confira os dados.',
                        style: TextStyle(
                          color: _taxLookup!.found
                              ? const Color(0xFF047857)
                              : const Color(0xFFB45309),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      if ((_taxLookup!.source ?? '').isNotEmpty)
                        Text(
                          'Fonte: ${_taxLookup!.source}',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                    ] else if ((widget.company?.cnpjLookupMessage ?? '')
                        .isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        widget.company!.cnpjLookupMessage!,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _stateRegistration,
                decoration: const InputDecoration(
                  labelText: 'Inscrição Estadual (IE)',
                  hintText:
                      'Deixe vazio se a empresa for isenta/não contribuinte',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _tradeName,
                decoration: const InputDecoration(labelText: 'Nome fantasia'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _municipalRegistration,
                decoration: const InputDecoration(
                  labelText: 'Inscricao municipal',
                ),
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Dados do responsável',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  _personType == 'PJ'
                      ? 'Informe o nome, o CPF e a data de nascimento do responsável pela empresa.'
                      : 'Informe o nome e a data de nascimento do titular.',
                  style: const TextStyle(color: Color(0xFF64748B)),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _contactName,
                      decoration: InputDecoration(
                        labelText: _personType == 'PJ'
                            ? 'Nome do responsável'
                            : 'Nome completo',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _personType == 'PJ'
                        ? TextField(
                            controller: _responsibleCpf,
                            keyboardType: TextInputType.number,
                            inputFormatters: const [
                              BrazilianCpfCnpjInputFormatter(),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'CPF do responsável',
                            ),
                          )
                        : TextField(
                            controller: _responsibleBirthDate,
                            keyboardType: TextInputType.datetime,
                            inputFormatters: const [
                              BrazilianDateInputFormatter(),
                            ],
                            decoration: const InputDecoration(
                              labelText: 'Data de nascimento',
                              hintText: 'dd/mm/aaaa',
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_personType == 'PJ')
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _responsibleBirthDate,
                        keyboardType: TextInputType.datetime,
                        inputFormatters: const [BrazilianDateInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Data de nascimento do responsável',
                          hintText: 'dd/mm/aaaa',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _phone,
                        keyboardType: TextInputType.phone,
                        inputFormatters: const [BrazilianPhoneInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Telefone',
                        ),
                      ),
                    ),
                  ],
                )
              else
                TextField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: const [BrazilianPhoneInputFormatter()],
                  decoration: const InputDecoration(labelText: 'Telefone'),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                  labelText: 'E-mail comercial',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _addressLine,
                decoration: const InputDecoration(labelText: 'Endereço'),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _addressNumber,
                      decoration: const InputDecoration(labelText: 'Número'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _neighborhood,
                      decoration: const InputDecoration(labelText: 'Bairro'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _city,
                      decoration: const InputDecoration(labelText: 'Cidade'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _state,
                      textCapitalization: TextCapitalization.characters,
                      inputFormatters: [
                        const UpperCaseTextFormatter(),
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(labelText: 'UF'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _zipCode,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [BrazilianCepInputFormatter()],
                      decoration: InputDecoration(
                        labelText: 'CEP',
                        suffixIcon: _lookingUpCep
                            ? const Padding(
                                padding: EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              )
                            : IconButton(
                                tooltip: 'Buscar CEP',
                                onPressed: _lookupCep,
                                icon: const Icon(Icons.search),
                              ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _cityCode,
                keyboardType: TextInputType.number,
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(7),
                ],
                decoration: const InputDecoration(
                  labelText: 'Codigo IBGE da cidade',
                  hintText: 'Ex: Leme/SP = 3526704',
                ),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Módulos liberados',
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
                  for (final entry in _moduleLabels.entries)
                    Builder(
                      builder: (context) {
                        final allowed =
                            _moduleAllowedByPlanInfo(
                              entry.key,
                              widget.plans[_plan],
                            ) ||
                            widget.company != null;
                        return FilterChip(
                          tooltip: allowed
                              ? null
                              : 'Disponível somente a partir do plano Pro.',
                          label: Text(entry.value),
                          selected: _enabledModules.contains(entry.key),
                          onSelected: allowed
                              ? (selected) {
                                  setState(() {
                                    if (selected) {
                                      _enabledModules.add(entry.key);
                                    } else {
                                      _enabledModules.remove(entry.key);
                                    }
                                  });
                                }
                              : null,
                        );
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _databaseUrl,
                decoration: const InputDecoration(
                  labelText: 'URL do banco PostgreSQL',
                  hintText: 'Vazio gera um banco automaticamente',
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _plan,
                      decoration: const InputDecoration(labelText: 'Plano'),
                      items: [
                        for (final entry in widget.plans.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value.name),
                          ),
                      ],
                      onChanged: (value) {
                        if (value != null) _applyPlan(value);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _PlanSummary(
                info: widget.plans[_plan]!,
                storageLabel: _storageLabel,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _limitDropdown(
                      controller: _maxUsersOverride,
                      label: 'Usuários',
                      options: const [5, 10, 25, 50, 100, 250],
                      valueLabel: (value) => '$value usuários',
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _limitDropdown(
                      controller: _databaseLimitOverride,
                      label: 'Dados',
                      options: const [80, 250, 512, 1024, 2048, 5120, 10240],
                      valueLabel: _storageLabel,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _limitDropdown(
                      controller: _fileLimitOverride,
                      label: 'Arquivos',
                      options: const [1536, 4096, 8192, 51200, 102400],
                      valueLabel: _storageLabel,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _limitDropdown(
                      controller: _multiCompanyLimitOverride,
                      label: 'Multiempresa',
                      options: const [1, 3, 5, 10, 25],
                      valueLabel: (value) =>
                          value == 1 ? 'Não' : 'Até $value empresas',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _monthlyPrice,
                      keyboardType: TextInputType.number,
                      inputFormatters: const [BrazilianMoneyInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Mensalidade',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _billingDay,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(2),
                      ],
                      decoration: const InputDecoration(labelText: 'Dia venc.'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _paymentMethod.text,
                      decoration: const InputDecoration(labelText: 'Pagamento'),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Selecione'),
                        ),
                        for (final entry in _paymentOptions.entries)
                          DropdownMenuItem(
                            value: entry.key,
                            child: Text(entry.value),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _paymentMethod.text = value ?? ''),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                value: _active,
                onChanged: (value) => setState(() => _active = value),
                title: const Text('Empresa ativa'),
                contentPadding: EdgeInsets.zero,
              ),
              TextField(
                controller: _notes,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Observações'),
              ),
              if (widget.company == null) ...[
                const SizedBox(height: 18),
                const Divider(),
                const SizedBox(height: 8),
                SwitchListTile(
                  value: _provisionDatabase,
                  onChanged: (value) =>
                      setState(() => _provisionDatabase = value),
                  title: const Text('Criar/preparar banco automaticamente'),
                  subtitle: const Text(
                    'Cria o banco da empresa, tabelas e permissões iniciais.',
                  ),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _adminName,
                  decoration: const InputDecoration(
                    labelText: 'Nome do primeiro admin',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _adminEmail,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'E-mail do primeiro admin',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _adminPassword,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Senha inicial do admin',
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_error != null)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Color(0xFFB91C1C),
                  size: 18,
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    _error!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
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

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({required this.info, required this.storageLabel});

  final _PlanInfo info;
  final String Function(int mb) storageLabel;

  @override
  Widget build(BuildContext context) {
    final users = info.maxUsers == null ? 'Ilimitados' : '${info.maxUsers}';
    final price = info.monthlyPrice == null
        ? 'Preço personalizado'
        : 'R\$ ${info.monthlyPrice}/mês';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Wrap(
        spacing: 14,
        runSpacing: 8,
        children: [
          _PlanPill(label: 'Preço', value: price),
          _PlanPill(label: 'Usuários', value: users),
          _PlanPill(label: 'Dados', value: storageLabel(info.databaseLimitMb)),
          _PlanPill(label: 'Arquivos', value: storageLabel(info.fileLimitMb)),
          _PlanPill(label: 'Multiempresa', value: info.multiCompany),
          _PlanPill(label: 'API', value: info.api ? 'Sim' : 'Não'),
          _PlanPill(
            label: 'Suporte',
            value: info.prioritySupport ? 'Prioritário' : 'Padrão',
          ),
        ],
      ),
    );
  }
}

class _PlanPill extends StatelessWidget {
  const _PlanPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF64748B),
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              color: Color(0xFF0F172A),
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
