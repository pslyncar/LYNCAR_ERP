import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/client.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/cep_service.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class ClientsScreen extends StatefulWidget {
  const ClientsScreen({super.key, required this.session});

  final Session session;

  @override
  State<ClientsScreen> createState() => _ClientsScreenState();
}

class _ClientsScreenState extends State<ClientsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<Client> _clients = [];
  final _search = TextEditingController();
  String _personTypeFilter = 'todos';
  String _contractFilter = 'todos';
  String _statusFilter = 'ativos';
  bool _advancedOpen = false;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadClients();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadClients() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final clients = await _api.listClients(widget.session.token);
      setState(() => _clients = clients);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar os clientes.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _ClientFormDialog(
        api: _api,
        token: widget.session.token,
        businessType: widget.session.businessType,
        enabledModules: widget.session.enabledModules,
        client: null,
      ),
    );

    if (created == true) {
      await _loadClients();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filteredClients = _filteredClients();
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _loadClients,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            _Header(
              canCreate: widget.session.can('clients:create'),
              businessType: widget.session.businessType,
              enabledModules: widget.session.enabledModules,
              onCreate: _openCreateDialog,
              onRefresh: _loadClients,
            ),
            const SizedBox(height: 18),
            _ClientSearchPanel(
              search: _search,
              personTypeFilter: _personTypeFilter,
              contractFilter: _contractFilter,
              statusFilter: _statusFilter,
              advancedOpen: _advancedOpen,
              onChanged: () => setState(() {}),
              onToggleAdvanced: () =>
                  setState(() => _advancedOpen = !_advancedOpen),
              onPersonTypeChanged: (value) =>
                  setState(() => _personTypeFilter = value ?? 'todos'),
              onContractChanged: (value) =>
                  setState(() => _contractFilter = value ?? 'todos'),
              onStatusChanged: (value) =>
                  setState(() => _statusFilter = value ?? 'ativos'),
              onClear: _clearFilters,
            ),
            const SizedBox(height: 18),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _loadClients)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: filteredClients.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhum cliente encontrado com esses filtros.',
                        ),
                      )
                    : _ClientsTable(
                        clients: filteredClients,
                        onOpenClient: _openDetailsDialog,
                        canEdit: widget.session.can('clients:update'),
                      ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openDetailsDialog(Client client) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ClientDetailsDialog(
        client: client,
        api: _api,
        token: widget.session.token,
        businessType: widget.session.businessType,
        enabledModules: widget.session.enabledModules,
        canDelete: widget.session.can('clients:delete'),
      ),
    );

    if (changed == true) {
      await _loadClients();
    }
  }

  void _clearFilters() {
    setState(() {
      _search.clear();
      _personTypeFilter = 'todos';
      _contractFilter = 'todos';
      _statusFilter = 'ativos';
    });
  }

  List<Client> _filteredClients() {
    final term = _normalize(_search.text);
    return _clients.where((client) {
      if (_statusFilter == 'ativos' && !client.active) return false;
      if (_statusFilter == 'inativos' && client.active) return false;
      if (_personTypeFilter != 'todos' &&
          client.personType != _personTypeFilter) {
        return false;
      }
      if (_contractFilter != 'todos' &&
          client.contractType != _contractFilter) {
        return false;
      }
      if (term.isEmpty) return true;
      final haystack = _normalize(
        [
          client.name,
          client.tradeName,
          client.documentNumber,
          client.email,
          client.phone,
          client.mobilePhone,
          client.contactPerson,
          client.city,
          client.state,
          client.address,
        ].whereType<String>().join(' '),
      );
      return haystack.contains(term);
    }).toList();
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.canCreate,
    required this.businessType,
    required this.enabledModules,
    required this.onCreate,
    required this.onRefresh,
  });

  final bool canCreate;
  final String businessType;
  final List<String> enabledModules;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final technical = _isTechnicalBusiness(businessType, enabledModules);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Clientes',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Text(
                technical
                    ? 'Cadastro completo para PF, PJ, contratos e atendimentos'
                    : 'Cadastro de consumidores, empresas e crediario',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        IconButton.outlined(
          tooltip: 'Atualizar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        const SizedBox(width: 8),
        if (canCreate)
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('Novo cliente'),
          ),
      ],
    );
  }
}

class _ClientSearchPanel extends StatelessWidget {
  const _ClientSearchPanel({
    required this.search,
    required this.personTypeFilter,
    required this.contractFilter,
    required this.statusFilter,
    required this.advancedOpen,
    required this.onChanged,
    required this.onToggleAdvanced,
    required this.onPersonTypeChanged,
    required this.onContractChanged,
    required this.onStatusChanged,
    required this.onClear,
  });

  final TextEditingController search;
  final String personTypeFilter;
  final String contractFilter;
  final String statusFilter;
  final bool advancedOpen;
  final VoidCallback onChanged;
  final VoidCallback onToggleAdvanced;
  final ValueChanged<String?> onPersonTypeChanged;
  final ValueChanged<String?> onContractChanged;
  final ValueChanged<String?> onStatusChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: search,
                  onChanged: (_) => onChanged(),
                  decoration: const InputDecoration(
                    labelText: 'Buscar clientes',
                    hintText: 'Nome, documento, e-mail, telefone, cidade...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                onPressed: onToggleAdvanced,
                icon: const Icon(Icons.manage_search_outlined),
                label: Text(
                  advancedOpen ? 'Ocultar filtros' : 'Busca avancada',
                ),
              ),
              const SizedBox(width: 8),
              IconButton.outlined(
                tooltip: 'Limpar busca',
                onPressed: onClear,
                icon: const Icon(Icons.clear),
              ),
            ],
          ),
          if (advancedOpen) ...[
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth >= 760
                    ? (constraints.maxWidth - 24) / 3
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        initialValue: personTypeFilter,
                        decoration: const InputDecoration(
                          labelText: 'Tipo de pessoa',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(value: 'PF', child: Text('PF')),
                          DropdownMenuItem(value: 'PJ', child: Text('PJ')),
                        ],
                        onChanged: onPersonTypeChanged,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        initialValue: contractFilter,
                        decoration: const InputDecoration(
                          labelText: 'Contrato',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(
                            value: 'avulso',
                            child: Text('Avulso'),
                          ),
                          DropdownMenuItem(
                            value: 'mensal',
                            child: Text('Mensal'),
                          ),
                        ],
                        onChanged: onContractChanged,
                      ),
                    ),
                    SizedBox(
                      width: width,
                      child: DropdownButtonFormField<String>(
                        initialValue: statusFilter,
                        decoration: const InputDecoration(
                          labelText: 'Status',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'todos',
                            child: Text('Todos'),
                          ),
                          DropdownMenuItem(
                            value: 'ativos',
                            child: Text('Ativos'),
                          ),
                          DropdownMenuItem(
                            value: 'inativos',
                            child: Text('Inativos'),
                          ),
                        ],
                        onChanged: onStatusChanged,
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _ClientsTable extends StatelessWidget {
  const _ClientsTable({
    required this.clients,
    required this.onOpenClient,
    required this.canEdit,
  });

  final List<Client> clients;
  final ValueChanged<Client> onOpenClient;
  final bool canEdit;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            color: Color(0xFFF8FAFC),
            borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
            border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
          ),
          child: const Row(
            children: [
              Expanded(flex: 4, child: _HeaderCell('Cliente')),
              Expanded(flex: 2, child: _HeaderCell('Tipo / documento')),
              Expanded(flex: 3, child: _HeaderCell('Contato')),
              Expanded(flex: 2, child: _HeaderCell('Contrato')),
              Expanded(flex: 2, child: _HeaderCell('Cidade')),
              SizedBox(width: 92, child: _HeaderCell('Status')),
            ],
          ),
        ),
        for (final client in clients)
          InkWell(
            onTap: canEdit ? () => onOpenClient(client) : null,
            child: Container(
              constraints: const BoxConstraints(minHeight: 72),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
              ),
              child: Row(
                children: [
                  Expanded(flex: 4, child: _MainClientCell(client: client)),
                  Expanded(
                    flex: 2,
                    child: _TwoLineCell(
                      primary: client.personType,
                      secondary: client.documentNumber ?? '-',
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: _TwoLineCell(
                      primary:
                          client.contactPerson ??
                          client.mobilePhone ??
                          client.phone ??
                          '-',
                      secondary: client.email,
                    ),
                  ),
                  Expanded(flex: 2, child: Text(client.contractType)),
                  Expanded(flex: 2, child: Text(_cityState(client))),
                  SizedBox(
                    width: 92,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Chip(
                        label: Text(client.active ? 'Ativo' : 'Inativo'),
                        visualDensity: VisualDensity.compact,
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  String _cityState(Client client) {
    final city = client.city;
    final state = client.state;
    if (city == null && state == null) {
      return '-';
    }
    return [city, state].whereType<String>().join(' / ');
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(
        color: Color(0xFF475569),
        fontSize: 12,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _MainClientCell extends StatelessWidget {
  const _MainClientCell({required this.client});

  final Client client;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFFEFF6FF),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(
            client.personType == 'PJ'
                ? Icons.business_outlined
                : Icons.person_outline,
            color: const Color(0xFF334155),
            size: 20,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _TwoLineCell(
            primary: client.name,
            secondary: client.tradeName,
            boldPrimary: true,
          ),
        ),
      ],
    );
  }
}

class _TwoLineCell extends StatelessWidget {
  const _TwoLineCell({
    required this.primary,
    this.secondary,
    this.boldPrimary = false,
  });

  final String primary;
  final String? secondary;
  final bool boldPrimary;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          primary,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontWeight: boldPrimary ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
        if (secondary != null && secondary!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            secondary!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ],
    );
  }
}

class _ClientDetailsDialog extends StatelessWidget {
  const _ClientDetailsDialog({
    required this.client,
    required this.api,
    required this.token,
    required this.businessType,
    required this.enabledModules,
    required this.canDelete,
  });

  final Client client;
  final ApiClient api;
  final String token;
  final String businessType;
  final List<String> enabledModules;
  final bool canDelete;

  Future<void> _edit(BuildContext context) async {
    final changed = await showDialog<bool>(
      context: context,
      builder: (context) => _ClientFormDialog(
        api: api,
        token: token,
        businessType: businessType,
        enabledModules: enabledModules,
        client: client,
      ),
    );

    if (context.mounted && changed == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _delete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir cliente?'),
        content: Text(
          'Deseja realmente excluir o cliente "${client.name}"? Esta ação não pode ser desfeita.',
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
      await api.deleteClient(token, client.id);
      if (context.mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height - 48;
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 760, maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      client.personType == 'PJ'
                          ? Icons.business_outlined
                          : Icons.person_outline,
                      color: const Color(0xFF334155),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          client.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          [
                            client.personType,
                            client.contractType,
                            client.active ? 'ativo' : 'inativo',
                          ].join(' • '),
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    tooltip: 'Fechar',
                    onPressed: () => Navigator.of(context).pop(false),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Flexible(
                child: SingleChildScrollView(
                  child: _DetailsGrid(
                    items: [
                      _DetailItem('Nome fantasia', client.tradeName),
                      _DetailItem('CPF/CNPJ', client.documentNumber),
                      _DetailItem('Responsável', client.contactPerson),
                      _DetailItem('Telefone', client.phone),
                      _DetailItem('Celular / WhatsApp', client.mobilePhone),
                      _DetailItem('E-mail', client.email),
                      _DetailItem('Endereço', client.address),
                      _DetailItem('Cidade/UF', _cityState(client)),
                      _DetailItem('CEP', client.zipCode),
                      _DetailItem(
                        'Mensalidade',
                        client.contractType == 'mensal'
                            ? 'R\$ ${formatBrazilianMoneyInput(client.monthlyFee)} - vence dia ${client.monthlyDueDay ?? '-'}'
                            : 'Avulso',
                      ),
                      _DetailItem(
                        'Crédito',
                        client.allowCredit
                            ? '${_creditStatusLabel(client.creditStatus)} - limite R\$ ${formatBrazilianMoneyInput(client.creditLimit)}'
                            : 'Não liberado',
                      ),
                      _DetailItem('Condição de pagamento', client.paymentTerms),
                      _DetailItem(
                        'Observações financeiras',
                        client.billingNotes,
                      ),
                      _DetailItem('Observações', client.notes),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: const Text('Fechar'),
                  ),
                  const SizedBox(width: 8),
                  if (canDelete)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: OutlinedButton.icon(
                        onPressed: () => _delete(context),
                        icon: const Icon(Icons.delete_outline),
                        label: const Text('Excluir'),
                      ),
                    ),
                  FilledButton.icon(
                    onPressed: () => _edit(context),
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Editar cliente'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _cityState(Client client) {
    final city = client.city;
    final state = client.state;
    if (city == null && state == null) {
      return '-';
    }
    return [city, state].whereType<String>().join(' / ');
  }
}

class _DetailsGrid extends StatelessWidget {
  const _DetailsGrid({required this.items});

  final List<_DetailItem> items;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 680
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final item in items)
              SizedBox(
                width: itemWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          item.value == null || item.value!.trim().isEmpty
                              ? '-'
                              : item.value!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _DetailItem {
  const _DetailItem(this.label, this.value);

  final String label;
  final String? value;
}

class _ClientFormDialog extends StatefulWidget {
  const _ClientFormDialog({
    required this.api,
    required this.token,
    required this.businessType,
    required this.enabledModules,
    required this.client,
  });

  final ApiClient api;
  final String token;
  final String businessType;
  final List<String> enabledModules;
  final Client? client;

  @override
  State<_ClientFormDialog> createState() => _ClientFormDialogState();
}

class _ClientFormDialogState extends State<_ClientFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _tradeName = TextEditingController();
  final _document = TextEditingController();
  final _stateRegistration = TextEditingController();
  final _municipalRegistration = TextEditingController();
  final _cityCode = TextEditingController();
  final _countryCode = TextEditingController();
  final _countryName = TextEditingController();
  final _suframa = TextEditingController();
  final _contact = TextEditingController();
  final _phone = TextEditingController();
  final _mobile = TextEditingController();
  final _email = TextEditingController();
  final _address = TextEditingController();
  final _addressNumber = TextEditingController();
  final _addressComplement = TextEditingController();
  final _neighborhood = TextEditingController();
  final _city = TextEditingController();
  final _state = TextEditingController();
  final _zipCode = TextEditingController();
  final _monthlyFee = TextEditingController();
  final _monthlyDueDay = TextEditingController();
  final _creditLimit = TextEditingController();
  final _paymentTerms = TextEditingController();
  final _billingNotes = TextEditingController();
  final _notes = TextEditingController();

  String _personType = 'PF';
  String _taxContributorType = 'auto';
  String _contractType = 'avulso';
  String _creditStatus = 'liberado';
  bool _allowCredit = false;
  bool _lookingUpCep = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    if (client != null) {
      _name.text = client.name;
      _tradeName.text = client.tradeName ?? '';
      _document.text = client.documentNumber ?? '';
      _stateRegistration.text = client.stateRegistration ?? '';
      _municipalRegistration.text = client.municipalRegistration ?? '';
      _cityCode.text = client.cityCode ?? '';
      _countryCode.text = client.countryCode ?? '';
      _countryName.text = client.countryName ?? '';
      _suframa.text = client.suframa ?? '';
      _contact.text = client.contactPerson ?? '';
      _phone.text = client.phone ?? '';
      _mobile.text = client.mobilePhone ?? '';
      _email.text = client.email ?? '';
      _address.text = client.address ?? '';
      _addressNumber.text = client.addressNumber ?? '';
      _addressComplement.text = client.addressComplement ?? '';
      _neighborhood.text = client.neighborhood ?? '';
      _city.text = client.city ?? '';
      _state.text = client.state ?? '';
      _zipCode.text = client.zipCode ?? '';
      _monthlyFee.text = formatBrazilianMoneyInput(client.monthlyFee);
      _monthlyDueDay.text = client.monthlyDueDay?.toString() ?? '';
      _creditLimit.text = formatBrazilianMoneyInput(client.creditLimit);
      _paymentTerms.text = client.paymentTerms ?? '';
      _billingNotes.text = client.billingNotes ?? '';
      _notes.text = client.notes ?? '';
      _personType = client.personType;
      _taxContributorType = client.taxContributorType ?? 'auto';
      _contractType = client.contractType;
      _creditStatus = client.creditStatus;
      _allowCredit = client.allowCredit;
    }
  }

  @override
  void dispose() {
    _name.dispose();
    _tradeName.dispose();
    _document.dispose();
    _stateRegistration.dispose();
    _municipalRegistration.dispose();
    _cityCode.dispose();
    _countryCode.dispose();
    _countryName.dispose();
    _suframa.dispose();
    _contact.dispose();
    _phone.dispose();
    _mobile.dispose();
    _email.dispose();
    _address.dispose();
    _addressNumber.dispose();
    _addressComplement.dispose();
    _neighborhood.dispose();
    _city.dispose();
    _state.dispose();
    _zipCode.dispose();
    _monthlyFee.dispose();
    _monthlyDueDay.dispose();
    _creditLimit.dispose();
    _paymentTerms.dispose();
    _billingNotes.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    if (_contractType == 'mensal') {
      if (parseBrazilianNumber(_monthlyFee.text) <= 0) {
        setState(() => _error = 'Informe o valor mensal do contrato.');
        return;
      }
      final dueDay = int.tryParse(_monthlyDueDay.text.trim());
      if (dueDay == null || dueDay < 1 || dueDay > 31) {
        setState(() => _error = 'Informe um dia de vencimento entre 1 e 31.');
        return;
      }
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final payload = ClientUpdate(
        name: _name.text,
        personType: _personType,
        contractType: _contractType,
        monthlyFee: parseBrazilianNumber(_monthlyFee.text),
        monthlyDueDay: int.tryParse(_monthlyDueDay.text.trim()),
        allowCredit: _allowCredit,
        creditLimit: parseBrazilianNumber(_creditLimit.text),
        creditStatus: _creditStatus,
        tradeName: _tradeName.text,
        documentNumber: _document.text,
        stateRegistration: _stateRegistration.text,
        municipalRegistration: _municipalRegistration.text,
        taxContributorType: _taxContributorType == 'auto'
            ? null
            : _taxContributorType,
        cityCode: _cityCode.text,
        countryCode: _countryCode.text,
        countryName: _countryName.text,
        suframa: _suframa.text,
        contactPerson: _contact.text,
        phone: _phone.text,
        mobilePhone: _mobile.text,
        email: _email.text,
        address: _address.text,
        addressNumber: _addressNumber.text,
        addressComplement: _addressComplement.text,
        neighborhood: _neighborhood.text,
        city: _city.text,
        state: _state.text,
        zipCode: _zipCode.text,
        paymentTerms: _paymentTerms.text,
        billingNotes: _billingNotes.text,
        notes: _notes.text,
      );
      final client = widget.client;
      if (client == null) {
        await widget.api.createClient(widget.token, payload);
      } else {
        await widget.api.updateClient(widget.token, client.id, payload);
      }
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar o cliente.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final technical = _isTechnicalBusiness(
      widget.businessType,
      widget.enabledModules,
    );
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.client == null ? 'Novo cliente' : 'Editar cliente',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'PF', label: Text('PF')),
                          ButtonSegment(value: 'PJ', label: Text('PJ')),
                        ],
                        selected: {_personType},
                        onSelectionChanged: (value) {
                          setState(() => _personType = value.first);
                        },
                      ),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'avulso', label: Text('Avulso')),
                          ButtonSegment(value: 'mensal', label: Text('Mensal')),
                        ],
                        selected: {_contractType},
                        onSelectionChanged: (value) {
                          setState(() => _contractType = value.first);
                        },
                      ),
                    ],
                  ),
                  if (!technical) ...[
                    const SizedBox(height: 8),
                    const Text(
                      'Use mensal apenas para contrato/recorrência. Crediário fica na área comercial.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ],
                  const SizedBox(height: 18),
                  _ResponsiveFields(
                    children: [
                      _field(
                        _name,
                        _personType == 'PJ' ? 'Razao social' : 'Nome completo',
                        required: true,
                      ),
                      _field(_tradeName, 'Nome fantasia / apelido'),
                      _field(
                        _document,
                        _personType == 'PJ' ? 'CNPJ' : 'CPF',
                        inputFormatters: const [
                          BrazilianCpfCnpjInputFormatter(),
                        ],
                      ),
                      _field(_contact, 'Responsável / contato'),
                      _field(
                        _phone,
                        'Telefone',
                        inputFormatters: const [BrazilianPhoneInputFormatter()],
                      ),
                      _field(
                        _mobile,
                        'Celular / WhatsApp',
                        inputFormatters: const [BrazilianPhoneInputFormatter()],
                      ),
                      _field(_email, 'E-mail'),
                      _field(
                        _zipCode,
                        'CEP',
                        inputFormatters: const [BrazilianCepInputFormatter()],
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
                      _field(_address, 'Endereço'),
                      _field(_addressNumber, 'Numero'),
                      _field(_addressComplement, 'Complemento'),
                      _field(_neighborhood, 'Bairro'),
                      _field(_city, 'Cidade'),
                      _field(_state, 'UF'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  const _SectionTitle(
                    title: 'Fiscal',
                    subtitle:
                        'Dados usados na emissao de NF-e para destinatario',
                  ),
                  const SizedBox(height: 12),
                  _ResponsiveFields(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _taxContributorType,
                        decoration: const InputDecoration(
                          labelText: 'Contribuinte ICMS',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'auto',
                            child: Text('Automatico'),
                          ),
                          DropdownMenuItem(
                            value: '1',
                            child: Text('Contribuinte'),
                          ),
                          DropdownMenuItem(value: '2', child: Text('Isento')),
                          DropdownMenuItem(
                            value: '9',
                            child: Text('Nao contribuinte'),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _taxContributorType = value ?? 'auto',
                        ),
                      ),
                      _field(_stateRegistration, 'Inscricao estadual'),
                      _field(_municipalRegistration, 'Inscricao municipal'),
                      _field(_cityCode, 'Codigo IBGE da cidade'),
                      _field(_suframa, 'SUFRAMA'),
                      _field(_countryCode, 'Codigo do pais'),
                      _field(_countryName, 'Pais'),
                    ],
                  ),
                  const SizedBox(height: 18),
                  if (_contractType == 'mensal') ...[
                    const _SectionTitle(
                      title: 'Mensalidade',
                      subtitle:
                          'Ao salvar, o sistema cria ou atualiza a conta a receber do mes atual',
                    ),
                    const SizedBox(height: 12),
                    _ResponsiveFields(
                      children: [
                        _field(
                          _monthlyFee,
                          'Valor mensal',
                          required: true,
                          inputFormatters: const [
                            BrazilianMoneyInputFormatter(),
                          ],
                        ),
                        _field(
                          _monthlyDueDay,
                          'Dia de vencimento',
                          required: true,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                  ],
                  const _SectionTitle(
                    title: 'Comercial',
                    subtitle: 'Controle de crediario e condicoes do cliente',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Permitir venda crediario'),
                    subtitle: const Text(
                      'Use para clientes que podem comprar e pagar depois.',
                    ),
                    value: _allowCredit,
                    onChanged: (value) => setState(() => _allowCredit = value),
                  ),
                  _ResponsiveFields(
                    children: [
                      _field(
                        _creditLimit,
                        'Limite de credito',
                        inputFormatters: const [BrazilianMoneyInputFormatter()],
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _creditStatus,
                        decoration: const InputDecoration(
                          labelText: 'Status de credito',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'liberado',
                            child: Text('Liberado'),
                          ),
                          DropdownMenuItem(
                            value: 'em_analise',
                            child: Text('Em analise'),
                          ),
                          DropdownMenuItem(
                            value: 'bloqueado',
                            child: Text('Bloqueado'),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _creditStatus = value ?? 'liberado'),
                      ),
                      _field(_paymentTerms, 'Condição de pagamento'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _billingNotes,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Observações financeiras',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Observações',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  const SizedBox(height: 18),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.end,
                    children: [
                      TextButton(
                        onPressed: _saving
                            ? null
                            : () => Navigator.of(context).pop(false),
                        child: const Text('Cancelar'),
                      ),
                      FilledButton.icon(
                        onPressed: _saving ? null : _save,
                        icon: _saving
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Salvando...' : 'Salvar cliente'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    bool required = false,
    List<TextInputFormatter>? inputFormatters,
    Widget? suffixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: inputFormatters == null ? null : TextInputType.text,
      inputFormatters: inputFormatters,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: suffixIcon,
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().length < 2) {
                return 'Informe ao menos 2 caracteres.';
              }
              return null;
            }
          : null,
    );
  }

  Future<void> _lookupCep() async {
    setState(() {
      _lookingUpCep = true;
      _error = null;
    });
    try {
      final address = await const CepService().lookup(_zipCode.text);
      setState(() {
        if (_address.text.trim().isEmpty) {
          _address.text = address.street;
        }
        if (_neighborhood.text.trim().isEmpty) {
          _neighborhood.text = address.neighborhood;
        }
        _city.text = address.city;
        _state.text = address.state;
      });
    } on CepLookupException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Nao foi possivel consultar o CEP.');
    } finally {
      if (mounted) setState(() => _lookingUpCep = false);
    }
  }
}

class _ResponsiveFields extends StatelessWidget {
  const _ResponsiveFields({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = constraints.maxWidth >= 720
            ? (constraints.maxWidth - 12) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(color: Color(0xFF64748B))),
      ],
    );
  }
}

bool _isTechnicalBusiness(String businessType, List<String> enabledModules) {
  return businessType == 'assistencia_papezzo' ||
      businessType == 'assistencia_técnica' ||
      enabledModules.contains('service_orders') ||
      enabledModules.contains('monitoring') ||
      enabledModules.contains('equipments');
}

String _creditStatusLabel(String status) {
  return switch (status) {
    'em_analise' => 'Em analise',
    'bloqueado' => 'Bloqueado',
    _ => 'Liberado',
  };
}

String _normalize(String value) {
  const replacements = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'ä': 'a',
    'é': 'e',
    'è': 'e',
    'ê': 'e',
    'ë': 'e',
    'í': 'i',
    'ì': 'i',
    'î': 'i',
    'ï': 'i',
    'ó': 'o',
    'ò': 'o',
    'õ': 'o',
    'ô': 'o',
    'ö': 'o',
    'ú': 'u',
    'ù': 'u',
    'û': 'u',
    'ü': 'u',
    'ç': 'c',
  };
  var normalized = value.toLowerCase().trim();
  for (final entry in replacements.entries) {
    normalized = normalized.replaceAll(entry.key, entry.value);
  }
  return normalized;
}
