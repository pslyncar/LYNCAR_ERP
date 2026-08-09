import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../models/client.dart';
import '../models/product.dart';
import '../models/service_contract.dart';
import '../models/session.dart';
import '../services/api_client.dart';

class ServiceContractsScreen extends StatefulWidget {
  const ServiceContractsScreen({super.key, required this.session});

  final Session session;

  @override
  State<ServiceContractsScreen> createState() => _ServiceContractsScreenState();
}

class _ServiceContractsScreenState extends State<ServiceContractsScreen> {
  late final ApiClient _api;
  List<ServiceContract> _contracts = [];
  List<ServiceAppointment> _appointments = [];
  List<ServiceBilling> _billings = [];
  List<Client> _clients = [];
  List<Product> _products = [];
  ServiceContract? _selected;
  bool _loading = true;
  bool _busy = false;
  int _selectedTab = 0;
  String? _error;
  late final TextEditingController _startController;
  late final TextEditingController _endController;
  late final TextEditingController _searchController;
  int _contractListTab = 0;

  bool get _canManage => widget.session.can('service_contracts:manage');
  bool get _canPoint => widget.session.can('service_contracts:appointments');
  bool get _canBill => widget.session.can('service_contracts:billing');

  @override
  void initState() {
    super.initState();
    _api = ApiClient(widget.session.apiBaseUrl);
    final now = DateTime.now();
    _startController = TextEditingController(
      text: _formatBrazilDateFromDate(
        DateTime(now.year, now.month, now.day <= 15 ? 1 : 16),
      ),
    );
    _endController = TextEditingController(
      text: _formatBrazilDateFromDate(
        DateTime(
          now.year,
          now.month,
          now.day <= 15 ? 15 : DateTime(now.year, now.month + 1, 0).day,
        ),
      ),
    );
    _searchController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _startController.dispose();
    _endController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  bool _contractIsActive(ServiceContract contract) {
    final status = contract.status.trim().toLowerCase();
    return contract.active && status != 'closed' && status != 'encerrado';
  }

  List<ServiceContract> get _filteredContracts {
    final query = _searchController.text.trim().toLowerCase();
    return _contracts.where((contract) {
      final active = _contractIsActive(contract);
      if (_contractListTab == 0 && !active) return false;
      if (_contractListTab == 1 && active) return false;
      if (query.isEmpty) return true;
      final haystack = [
        contract.clientName,
        contract.description,
        contract.number,
        _formatMoney(contract.valuePerPerson),
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList();
  }

  void _selectFirstVisibleContract() {
    final visible = _filteredContracts;
    if (visible.isEmpty) {
      _selected = null;
      _appointments = [];
      _billings = [];
      return;
    }
    if (_selected == null ||
        !visible.any((contract) => contract.id == _selected!.id)) {
      _selected = visible.first;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listServiceContracts(widget.session.token),
        _api.listClients(widget.session.token),
        _api.listProducts(widget.session.token, active: true),
      ]);
      _contracts = results[0] as List<ServiceContract>;
      _clients = results[1] as List<Client>;
      _products = results[2] as List<Product>;
      _selectFirstVisibleContract();
      await _loadContractDetails(skipClosedPeriods: true);
    } catch (error) {
      _error = error.toString();
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadContractDetails({bool skipClosedPeriods = false}) async {
    await _loadBillings();
    if (skipClosedPeriods) {
      _moveToNextOpenPeriod();
    }
    await _loadAppointments();
  }

  void _moveToNextOpenPeriod() {
    var guard = 0;
    while (_periodHasBillingHistory(_periodStartIso, _periodEndIso) &&
        guard < 24) {
      final start = _parseDateInput(_startController.text);
      final end = _parseDateInput(_endController.text);
      if (start == null || end == null) return;
      final nextPeriod = _nextQuinzena(start, end);
      _startController.text = _formatBrazilDateFromDate(nextPeriod.$1);
      _endController.text = _formatBrazilDateFromDate(nextPeriod.$2);
      guard++;
    }
  }

  bool _periodHasActiveBilling(String periodStart, String periodEnd) {
    return _billings.any(
      (billing) =>
          billing.periodStart == periodStart &&
          billing.periodEnd == periodEnd &&
          billing.status != 'cancelado',
    );
  }

  bool _periodHasBillingHistory(String periodStart, String periodEnd) {
    return _billings.any(
      (billing) =>
          billing.periodStart == periodStart && billing.periodEnd == periodEnd,
    );
  }

  bool get _hasConfirmedDaysWithoutBilling {
    return !_periodHasActiveBilling(_periodStartIso, _periodEndIso) &&
        _appointments.any(
          (appointment) =>
              appointment.status == 'confirmado' || appointment.stockPosted,
        );
  }

  String get _periodStartIso => _dateInputToIso(_startController.text);
  String get _periodEndIso => _dateInputToIso(_endController.text);

  Future<void> _loadAppointments() async {
    final selected = _selected;
    if (selected == null) {
      _appointments = [];
      return;
    }
    _appointments = await _api.listServiceAppointments(
      widget.session.token,
      selected.id,
      periodStart: _periodStartIso,
      periodEnd: _periodEndIso,
    );
  }

  Future<void> _loadBillings() async {
    final selected = _selected;
    if (selected == null) {
      _billings = [];
      return;
    }
    _billings = await _api.listServiceBillings(
      widget.session.token,
      selected.id,
    );
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } catch (error) {
      _error = error is ApiException ? error.message : error.toString();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _generateAppointments() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      _appointments = await _api.generateServiceAppointments(
        widget.session.token,
        selected.id,
        periodStart: _periodStartIso,
        periodEnd: _periodEndIso,
      );
    } catch (error) {
      final message = error is ApiException ? error.message : error.toString();
      if (message.contains('ja foi gerado')) {
        await _loadAppointments();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Per\u00EDodo j\u00E1 existia. Dias carregados para edi\u00E7\u00E3o.',
              ),
            ),
          );
        }
      } else {
        _error = message;
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _createBilling() async {
    final selected = _selected;
    if (selected == null) return;
    await _runBusy(() async {
      final billing = await _api.createServiceBilling(
        widget.session.token,
        selected.id,
        periodStart: _periodStartIso,
        periodEnd: _periodEndIso,
        dueDate: _periodEndIso,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Fechamento ${billing.number ?? billing.id} confirmado, estoque baixado e Contas a Receber gerado.',
          ),
        ),
      );
      final nextPeriod = _nextQuinzena(
        _parseDateInput(_startController.text) ?? DateTime.now(),
        _parseDateInput(_endController.text) ?? DateTime.now(),
      );
      _startController.text = _formatBrazilDateFromDate(nextPeriod.$1);
      _endController.text = _formatBrazilDateFromDate(nextPeriod.$2);
      _selectedTab = 0;
      await _loadContractDetails(skipClosedPeriods: true);
    });
  }

  Future<void> _cancelBilling(ServiceBilling billing) async {
    final selected = _selected;
    if (selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cancelar fechamento?'),
        content: Text(
          'Isso reabre o periodo ${billing.periodStart} a ${billing.periodEnd}, '
          'estorna a baixa de estoque e remove o Contas a Receber se ainda nao foi pago.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Cancelar fechamento'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBusy(() async {
      await _api.cancelServiceBilling(
        widget.session.token,
        selected.id,
        billing.id,
      );
      _startController.text = _formatBrazilDate(billing.periodStart);
      _endController.text = _formatBrazilDate(billing.periodEnd);
      _selectedTab = 0;
      await _loadContractDetails();
    });
  }

  Future<void> _openBillingPeriodForEdit(ServiceBilling billing) async {
    _startController.text = _formatBrazilDate(billing.periodStart);
    _endController.text = _formatBrazilDate(billing.periodEnd);
    setState(() => _selectedTab = 0);
    await _loadContractDetails();
  }

  Future<void> _reopenCanceledBilling(ServiceBilling billing) async {
    final selected = _selected;
    if (selected == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reabrir período?'),
        content: Text(
          'Isso remove o fechamento cancelado de ${_formatBrazilDate(billing.periodStart)} a ${_formatBrazilDate(billing.periodEnd)} '
          'e libera a quinzena para editar e fechar novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reabrir período'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBusy(() async {
      await _api.reopenCanceledServiceBilling(
        widget.session.token,
        selected.id,
        billing.id,
      );
      _startController.text = _formatBrazilDate(billing.periodStart);
      _endController.text = _formatBrazilDate(billing.periodEnd);
      _selectedTab = 0;
      await _loadContractDetails();
    });
  }

  Future<void> _openContractDialog([ServiceContract? contract]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _ContractDialog(
        session: widget.session,
        api: _api,
        clients: _clients,
        products: _products,
        contract: contract,
      ),
    );
    if (saved == true) {
      await _load();
    }
  }

  ServiceContractPayload _payloadFromContract(
    ServiceContract contract, {
    required bool active,
    required String status,
  }) {
    return ServiceContractPayload(
      clientId: contract.clientId,
      description: contract.description,
      valuePerPerson: contract.valuePerPerson,
      defaultPeopleQuantity: contract.defaultPeopleQuantity,
      startDate: contract.startDate,
      active: active,
      status: status,
      notes: contract.notes,
      rules: contract.rules,
      consumptionItems: contract.consumptionItems,
    );
  }

  Future<void> _setContractClosed(ServiceContract contract) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar contrato?'),
        content: Text(
          'O contrato de ${contract.clientName ?? contract.description} vai sair dos ativos e ficar no historico. '
          'Os fechamentos e Contas a Receber continuam preservados.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Voltar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runBusy(() async {
      await _api.updateServiceContract(
        widget.session.token,
        contract.id,
        _payloadFromContract(contract, active: false, status: 'closed'),
      );
      _contractListTab = 1;
      await _load();
    });
  }

  Future<void> _reactivateContract(ServiceContract contract) async {
    await _runBusy(() async {
      await _api.updateServiceContract(
        widget.session.token,
        contract.id,
        _payloadFromContract(contract, active: true, status: 'active'),
      );
      _contractListTab = 0;
      await _load();
    });
  }

  Future<void> _openAppointmentDialog(ServiceAppointment appointment) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => _AppointmentDialog(
        session: widget.session,
        api: _api,
        products: _products,
        appointment: appointment,
      ),
    );
    if (saved == true) {
      await _runBusy(_loadAppointments);
    }
  }

  Future<void> _pickPeriodDate(TextEditingController controller) async {
    final initialDate = _parseDateInput(controller.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      controller.text = _formatBrazilDateFromDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return Padding(
      padding: const EdgeInsets.all(24),
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
                      'Contratos vari\u00E1veis',
                      style: TextStyle(
                        fontSize: 30,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Gap(4),
                    Text(
                      'Recorr\u00EAncia por apontamento, baixa de produtos e fechamento quinzenal.',
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Atualizar',
                onPressed: _busy ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
              const Gap(8),
              if (_canManage)
                FilledButton.icon(
                  onPressed: _busy ? null : () => _openContractDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Novo contrato'),
                ),
            ],
          ),
          const Gap(16),
          if (_error != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF1F2),
                border: Border.all(color: const Color(0xFFFCA5A5)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _error!,
                style: const TextStyle(color: Color(0xFF991B1B)),
              ),
            ),
          const Gap(12),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 360, child: _buildContractsList()),
                const Gap(16),
                Expanded(child: _buildAppointmentsPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContractsList() {
    final contracts = _filteredContracts;
    return Column(
      children: [
        TextField(
          controller: _searchController,
          decoration: InputDecoration(
            labelText: 'Pesquisar cliente',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _searchController.text.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Limpar pesquisa',
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      setState(() => _searchController.clear());
                      await _runBusy(_loadContractDetails);
                    },
                  ),
          ),
          onChanged: (_) async {
            setState(_selectFirstVisibleContract);
            await _runBusy(_loadContractDetails);
          },
        ),
        const Gap(10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<int>(
            segments: const [
              ButtonSegment(
                value: 0,
                icon: Icon(Icons.people_alt_outlined),
                label: Text('Ativos'),
              ),
              ButtonSegment(
                value: 1,
                icon: Icon(Icons.history),
                label: Text('Historico'),
              ),
            ],
            selected: {_contractListTab},
            onSelectionChanged: (values) async {
              setState(() {
                _contractListTab = values.first;
                _selectFirstVisibleContract();
              });
              await _runBusy(
                () => _loadContractDetails(skipClosedPeriods: true),
              );
            },
          ),
        ),
        const Gap(10),
        Expanded(
          child: _contracts.isEmpty
              ? const _EmptyState(text: 'Nenhum contrato cadastrado.')
              : contracts.isEmpty
              ? const _EmptyState(text: 'Nenhum cliente encontrado.')
              : ListView.separated(
                  itemCount: contracts.length,
                  separatorBuilder: (_, _) => const Gap(8),
                  itemBuilder: (context, index) {
                    final contract = contracts[index];
                    final selected = contract.id == _selected?.id;
                    final active = _contractIsActive(contract);
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: selected
                              ? const Color(0xFF2563EB)
                              : const Color(0xFFD8E2F0),
                        ),
                      ),
                      child: ListTile(
                        selected: selected,
                        title: Text(
                          contract.clientName ?? contract.description,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          '${contract.number ?? 'CT'} - ${_formatMoney(contract.valuePerPerson)} por pessoa'
                          '${active ? '' : ' - ${_contractStatusLabel(contract.status)}'}',
                        ),
                        trailing: _canManage
                            ? PopupMenuButton<String>(
                                tooltip: 'Opcoes do contrato',
                                enabled: !_busy,
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _openContractDialog(contract);
                                      break;
                                    case 'close':
                                      _setContractClosed(contract);
                                      break;
                                    case 'reactivate':
                                      _reactivateContract(contract);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => [
                                  const PopupMenuItem(
                                    value: 'edit',
                                    child: Row(
                                      children: [
                                        Icon(Icons.edit_outlined),
                                        Gap(8),
                                        Text('Editar contrato'),
                                      ],
                                    ),
                                  ),
                                  if (active)
                                    const PopupMenuItem(
                                      value: 'close',
                                      child: Row(
                                        children: [
                                          Icon(Icons.archive_outlined),
                                          Gap(8),
                                          Text('Encerrar cliente'),
                                        ],
                                      ),
                                    )
                                  else
                                    const PopupMenuItem(
                                      value: 'reactivate',
                                      child: Row(
                                        children: [
                                          Icon(Icons.restore_outlined),
                                          Gap(8),
                                          Text('Reativar contrato'),
                                        ],
                                      ),
                                    ),
                                ],
                              )
                            : null,
                        onTap: () async {
                          setState(() {
                            _selected = contract;
                            _selectedTab = 0;
                          });
                          await _runBusy(
                            () => _loadContractDetails(skipClosedPeriods: true),
                          );
                        },
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAppointmentsPanel() {
    final selected = _selected;
    if (selected == null) {
      return const _EmptyState(text: 'Selecione ou crie um contrato.');
    }
    return Column(
      children: [
        _buildContractTabs(),
        const Gap(12),
        if (_selectedTab == 0) ...[
          Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: Color(0xFFD8E2F0)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 170,
                    child: TextField(
                      controller: _startController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'In\u00EDcio',
                        suffixIcon: IconButton(
                          tooltip: 'Abrir calend\u00E1rio',
                          onPressed: () => _pickPeriodDate(_startController),
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                      onTap: () => _pickPeriodDate(_startController),
                    ),
                  ),
                  SizedBox(
                    width: 170,
                    child: TextField(
                      controller: _endController,
                      readOnly: true,
                      decoration: InputDecoration(
                        labelText: 'Fim',
                        suffixIcon: IconButton(
                          tooltip: 'Abrir calend\u00E1rio',
                          onPressed: () => _pickPeriodDate(_endController),
                          icon: const Icon(Icons.calendar_month_outlined),
                        ),
                      ),
                      onTap: () => _pickPeriodDate(_endController),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _runBusy(_loadAppointments),
                    icon: const Icon(Icons.search),
                    label: const Text('Buscar'),
                  ),
                  if (_canPoint)
                    FilledButton.icon(
                      onPressed: _busy ? null : _generateAppointments,
                      icon: const Icon(Icons.calendar_month),
                      label: const Text('Gerar per\u00EDodo'),
                    ),
                  if (_canBill)
                    FilledButton.tonalIcon(
                      onPressed: _busy ? null : _createBilling,
                      icon: const Icon(Icons.request_quote_outlined),
                      label: const Text('Fechar e gerar cobran\u00E7a'),
                    ),
                  const SizedBox(
                    width: 560,
                    child: Text(
                      'C\u00E1lculo: pessoas x valor por pessoa x multiplicador. Fechar confirma os dias cobrados, baixa estoque dos produtos do apontamento e gera o Contas a Receber.',
                      style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Gap(12),
          if (_hasConfirmedDaysWithoutBilling) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                border: Border.all(color: const Color(0xFFF59E0B)),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Este periodo ainda nao foi fechado, mas possui dias confirmados individualmente. Eles continuam aqui ate fechar a quinzena ou cancelar o dia.',
                style: TextStyle(
                  color: Color(0xFF92400E),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const Gap(12),
          ],
          Expanded(
            child: _appointments.isEmpty
                ? const _EmptyState(text: 'Nenhum apontamento no per\u00EDodo.')
                : SingleChildScrollView(
                    child: DataTable(
                      columnSpacing: 22,
                      columns: const [
                        DataColumn(label: Text('Data')),
                        DataColumn(label: Text('Tipo')),
                        DataColumn(label: Text('Pessoas')),
                        DataColumn(label: Text('Valor')),
                        DataColumn(label: Text('Status')),
                        DataColumn(label: Text('Estoque')),
                        DataColumn(label: Text('A\u00E7\u00F5es')),
                      ],
                      rows: _appointments.map((appointment) {
                        return DataRow(
                          cells: [
                            DataCell(
                              Text(
                                _formatBrazilDate(appointment.appointmentDate),
                              ),
                            ),
                            DataCell(Text(_dayTypeLabel(appointment.dayType))),
                            DataCell(Text(_number(appointment.peopleQuantity))),
                            DataCell(
                              Text(_formatMoney(appointment.totalAmount)),
                            ),
                            DataCell(Text(_statusLabel(appointment.status))),
                            DataCell(
                              Icon(
                                appointment.stockPosted
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                size: 18,
                              ),
                            ),
                            DataCell(
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Editar',
                                    onPressed: _canPoint
                                        ? () => _openAppointmentDialog(
                                            appointment,
                                          )
                                        : null,
                                    icon: const Icon(Icons.edit_outlined),
                                  ),
                                  IconButton(
                                    tooltip: 'Confirmar e baixar estoque',
                                    onPressed:
                                        _canPoint &&
                                            appointment.status != 'confirmado'
                                        ? () => _runBusy(() async {
                                            await _api
                                                .confirmServiceAppointment(
                                                  widget.session.token,
                                                  appointment.id,
                                                );
                                            await _loadContractDetails();
                                          })
                                        : null,
                                    icon: const Icon(Icons.done_all),
                                  ),
                                  IconButton(
                                    tooltip: 'Cancelar e estornar',
                                    onPressed:
                                        _canPoint &&
                                            appointment.status != 'cancelado'
                                        ? () => _runBusy(() async {
                                            await _api.cancelServiceAppointment(
                                              widget.session.token,
                                              appointment.id,
                                            );
                                            await _loadContractDetails();
                                          })
                                        : null,
                                    icon: const Icon(Icons.cancel_outlined),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
          ),
        ] else
          Expanded(child: _buildBillingHistory()),
      ],
    );
  }

  Widget _buildContractTabs() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(
            value: 0,
            icon: Icon(Icons.calendar_month_outlined),
            label: Text('Quinzena atual'),
          ),
          ButtonSegment(
            value: 1,
            icon: Icon(Icons.history),
            label: Text('Hist\u00F3rico'),
          ),
        ],
        selected: {_selectedTab},
        onSelectionChanged: (values) {
          setState(() => _selectedTab = values.first);
        },
      ),
    );
  }

  Widget _buildBillingHistory() {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFD8E2F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.history, size: 18, color: Color(0xFF2563EB)),
                const Gap(8),
                Expanded(
                  child: Text(
                    'Hist\u00F3rico de fechamentos',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_billings.length} fechamento(s)',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const Gap(4),
            const Text(
              'Cada quinzena fechada fica registrada aqui. O valor j\u00E1 foi enviado para o Contas a Receber.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const Gap(16),
            if (_billings.isEmpty)
              const Expanded(
                child: Center(
                  child: _EmptyState(
                    text: 'Nenhuma quinzena fechada para este contrato.',
                  ),
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: _billings.length,
                  separatorBuilder: (_, _) => const Gap(10),
                  itemBuilder: (context, index) {
                    final billing = _billings[index];
                    final cr = billing.receivableId == null
                        ? 'Sem CR'
                        : 'CR ${billing.receivableId}';
                    final isCanceled = billing.status == 'cancelado';
                    return Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF8FBFF),
                        border: Border.all(color: const Color(0xFFD8E2F0)),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: ExpansionTile(
                        tilePadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          14,
                          0,
                          14,
                          14,
                        ),
                        leading: Icon(
                          isCanceled
                              ? Icons.edit_calendar_outlined
                              : Icons.receipt_long_outlined,
                          color: isCanceled
                              ? const Color(0xFF64748B)
                              : const Color(0xFF2563EB),
                        ),
                        title: Text(
                          '${_formatBrazilDate(billing.periodStart)} a ${_formatBrazilDate(billing.periodEnd)}',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '$cr - ${_billingStatusLabel(billing.status)}',
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12,
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _formatMoney(billing.totalAmount),
                              style: const TextStyle(
                                color: Color(0xFF0F5F7A),
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Gap(8),
                            if (_canBill) ...[
                              PopupMenuButton<String>(
                                tooltip: 'Op\u00E7\u00F5es do fechamento',
                                enabled: !_busy,
                                onSelected: (value) {
                                  switch (value) {
                                    case 'edit':
                                      _openBillingPeriodForEdit(billing);
                                      break;
                                    case 'cancel':
                                      _cancelBilling(billing);
                                      break;
                                    case 'reopen':
                                      _reopenCanceledBilling(billing);
                                      break;
                                  }
                                },
                                itemBuilder: (_) => isCanceled
                                    ? [
                                        const PopupMenuItem(
                                          value: 'reopen',
                                          child: Row(
                                            children: [
                                              Icon(Icons.lock_open_outlined),
                                              Gap(8),
                                              Text('Reabrir período'),
                                            ],
                                          ),
                                        ),
                                      ]
                                    : [
                                        const PopupMenuItem(
                                          value: 'edit',
                                          child: Row(
                                            children: [
                                              Icon(Icons.edit_outlined),
                                              Gap(8),
                                              Text('Editar período'),
                                            ],
                                          ),
                                        ),
                                        const PopupMenuItem(
                                          value: 'cancel',
                                          child: Row(
                                            children: [
                                              Icon(Icons.cancel_outlined),
                                              Gap(8),
                                              Text('Cancelar fechamento'),
                                            ],
                                          ),
                                        ),
                                      ],
                                child: const Icon(Icons.more_vert),
                              ),
                              const Gap(4),
                            ],
                            const Icon(Icons.expand_more),
                          ],
                        ),
                        children: [
                          if (billing.items.isEmpty)
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: Text(
                                  'Este fechamento n\u00E3o possui dias cobrados.',
                                  style: TextStyle(color: Color(0xFF64748B)),
                                ),
                              ),
                            )
                          else
                            _buildBillingItemsTable(billing.items),
                        ],
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBillingItemsTable(List<ServiceBillingItem> items) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD8E2F0)),
          borderRadius: BorderRadius.circular(8),
          color: Colors.white,
        ),
        child: DataTable(
          headingRowColor: WidgetStateProperty.all(const Color(0xFFEFF6FF)),
          columnSpacing: 18,
          columns: const [
            DataColumn(label: Text('Data')),
            DataColumn(label: Text('Descri\u00E7\u00E3o')),
            DataColumn(label: Text('Pessoas')),
            DataColumn(label: Text('Unit\u00E1rio')),
            DataColumn(label: Text('Mult.')),
            DataColumn(label: Text('Total')),
          ],
          rows: items.map((item) {
            return DataRow(
              cells: [
                DataCell(Text(_formatBrazilDate(item.itemDate))),
                DataCell(Text(item.description)),
                DataCell(Text(_number(item.peopleQuantity))),
                DataCell(Text(_formatMoney(item.unitPrice))),
                DataCell(Text(_number(item.multiplier))),
                DataCell(
                  Text(
                    _formatMoney(item.totalAmount),
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            );
          }).toList(),
        ),
      ),
    );
  }

  DateTime _lastDayOfMonth(int year, int month) {
    return DateTime(year, month + 1, 0);
  }

  (DateTime, DateTime) _nextQuinzena(DateTime periodStart, DateTime periodEnd) {
    if (periodStart.day <= 15 && periodEnd.day <= 15) {
      final start = DateTime(periodStart.year, periodStart.month, 16);
      return (start, _lastDayOfMonth(start.year, start.month));
    }
    final start = periodStart.month == 12
        ? DateTime(periodStart.year + 1, 1, 1)
        : DateTime(periodStart.year, periodStart.month + 1, 1);
    return (start, DateTime(start.year, start.month, 15));
  }

  String _number(double value) {
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(3);
  }
}

class _ContractDialog extends StatefulWidget {
  const _ContractDialog({
    required this.session,
    required this.api,
    required this.clients,
    required this.products,
    this.contract,
  });

  final Session session;
  final ApiClient api;
  final List<Client> clients;
  final List<Product> products;
  final ServiceContract? contract;

  @override
  State<_ContractDialog> createState() => _ContractDialogState();
}

class _ContractDialogState extends State<_ContractDialog> {
  final _formKey = GlobalKey<FormState>();
  late int _clientId;
  late bool _active;
  late final TextEditingController _description;
  late final TextEditingController _value;
  late final TextEditingController _people;
  late final TextEditingController _start;
  late final TextEditingController _notes;
  late List<ServiceContractRule> _rules;
  late List<ServiceContractConsumptionItem> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final contract = widget.contract;
    _clientId =
        contract?.clientId ??
        (widget.clients.isNotEmpty ? widget.clients.first.id : 0);
    _active = contract?.active ?? true;
    _description = TextEditingController(text: contract?.description ?? '');
    _value = TextEditingController(
      text: contract == null ? '' : contract.valuePerPerson.toStringAsFixed(2),
    );
    _people = TextEditingController(
      text: contract == null
          ? ''
          : contract.defaultPeopleQuantity.toStringAsFixed(0),
    );
    _start = TextEditingController(
      text: contract == null ? '' : _formatBrazilDate(contract.startDate),
    );
    _notes = TextEditingController(text: contract?.notes ?? '');
    _rules =
        contract?.rules.toList() ??
        const [
          ServiceContractRule(
            dayType: 'weekday',
            attends: true,
            charges: true,
            multiplier: 1,
          ),
          ServiceContractRule(
            dayType: 'saturday',
            attends: false,
            charges: false,
            multiplier: 0,
          ),
          ServiceContractRule(
            dayType: 'sunday',
            attends: false,
            charges: false,
            multiplier: 0,
          ),
          ServiceContractRule(
            dayType: 'holiday',
            attends: false,
            charges: false,
            multiplier: 0,
          ),
        ].toList();
    _items = contract?.consumptionItems.toList() ?? [];
  }

  @override
  void dispose() {
    _description.dispose();
    _value.dispose();
    _people.dispose();
    _start.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final payload = ServiceContractPayload(
      clientId: _clientId,
      description: _description.text,
      valuePerPerson: _parse(_value.text),
      defaultPeopleQuantity: _parse(_people.text),
      startDate: _dateInputToIso(_start.text),
      active: _active,
      notes: _notes.text,
      rules: _rules,
      consumptionItems: _items,
    );
    try {
      final contract = widget.contract;
      if (contract == null) {
        await widget.api.createServiceContract(widget.session.token, payload);
      } else {
        await widget.api.updateServiceContract(
          widget.session.token,
          contract.id,
          payload,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickStartDate() async {
    final initialDate = _parseDateInput(_start.text) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      _start.text = _formatBrazilDateFromDate(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.contract == null ? 'Novo contrato' : 'Editar contrato',
      ),
      content: SizedBox(
        width: 760,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<int>(
                  initialValue: _clientId == 0 ? null : _clientId,
                  decoration: const InputDecoration(labelText: 'Cliente'),
                  items: widget.clients
                      .map(
                        (client) => DropdownMenuItem(
                          value: client.id,
                          child: Text(client.name),
                        ),
                      )
                      .toList(),
                  validator: (value) =>
                      value == null ? 'Selecione o cliente.' : null,
                  onChanged: (value) => setState(() => _clientId = value ?? 0),
                ),
                const Gap(10),
                TextFormField(
                  controller: _description,
                  decoration: const InputDecoration(
                    labelText: 'Descri\u00E7\u00E3o',
                  ),
                  validator: _required,
                ),
                const Gap(10),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Valor total do dia = quantidade de pessoas x valor por pessoa x multiplicador do tipo de dia.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
                const Gap(10),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _value,
                        decoration: const InputDecoration(
                          labelText: 'Valor por pessoa',
                          hintText: 'Ex: 20,00',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _positive,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: TextFormField(
                        controller: _people,
                        decoration: const InputDecoration(
                          labelText: 'Qtd. padr\u00E3o de pessoas',
                          hintText: 'Ex: 50',
                        ),
                        keyboardType: TextInputType.number,
                        validator: _positive,
                      ),
                    ),
                    const Gap(10),
                    Expanded(
                      child: TextFormField(
                        controller: _start,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Data inicial',
                          suffixIcon: IconButton(
                            tooltip: 'Abrir calend\u00E1rio',
                            onPressed: _pickStartDate,
                            icon: const Icon(Icons.calendar_month_outlined),
                          ),
                        ),
                        validator: _required,
                        onTap: _pickStartDate,
                      ),
                    ),
                  ],
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: _active,
                  title: const Text('Contrato ativo'),
                  onChanged: (value) => setState(() => _active = value),
                ),
                const Divider(),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Regras por tipo de dia',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                const Gap(4),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Define se o sistema gera atendimento e cobran\u00E7a para dia \u00FAtil, s\u00E1bado, domingo e feriado.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
                const Gap(8),
                ..._rules.map(_ruleTile),
                const Divider(),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Produtos padr\u00E3o por atendimento',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: _addItem,
                      icon: const Icon(Icons.add),
                      label: const Text('Adicionar'),
                    ),
                  ],
                ),
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Esses produtos viram sugest\u00E3o nos dias gerados. A baixa de estoque s\u00F3 acontece ao confirmar o apontamento ou ao fechar a quinzena.',
                    style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                  ),
                ),
                const Gap(8),
                ..._items.asMap().entries.map(
                  (entry) => _itemTile(entry.key, entry.value),
                ),
                const Gap(8),
                TextFormField(
                  controller: _notes,
                  decoration: const InputDecoration(
                    labelText: 'Observa\u00E7\u00F5es',
                  ),
                  maxLines: 2,
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
          icon: const Icon(Icons.save),
          label: const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _ruleTile(ServiceContractRule rule) {
    final index = _rules.indexOf(rule);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(width: 110, child: Text(_dayTypeLabel(rule.dayType))),
          Checkbox(
            value: rule.attends,
            onChanged: (value) => _updateRule(index, attends: value),
          ),
          const Text('Atende'),
          const Gap(8),
          Checkbox(
            value: rule.charges,
            onChanged: (value) => _updateRule(index, charges: value),
          ),
          const Text('Cobra'),
          const Gap(12),
          SizedBox(
            width: 120,
            child: TextFormField(
              initialValue: rule.multiplier.toString(),
              decoration: const InputDecoration(labelText: 'Multiplicador'),
              onChanged: (value) =>
                  _updateRule(index, multiplier: _parse(value)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _itemTile(int index, ServiceContractConsumptionItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: item.productId == 0 ? null : item.productId,
              decoration: const InputDecoration(labelText: 'Produto'),
              items: widget.products
                  .map(
                    (product) => DropdownMenuItem(
                      value: product.id,
                      child: Text(product.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => _updateItem(index, productId: value),
            ),
          ),
          const Gap(8),
          Expanded(
            child: TextFormField(
              initialValue: item.quantityPerPerson.toString(),
              decoration: const InputDecoration(labelText: 'Qtd/pessoa'),
              onChanged: (value) => _updateItem(index, quantity: _parse(value)),
            ),
          ),
          const Gap(8),
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: item.unit,
              decoration: const InputDecoration(labelText: 'Un.'),
              onChanged: (value) => _updateItem(index, unit: value),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _items.removeAt(index)),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  void _updateRule(
    int index, {
    bool? attends,
    bool? charges,
    double? multiplier,
  }) {
    final rule = _rules[index];
    setState(() {
      _rules[index] = ServiceContractRule(
        id: rule.id,
        dayType: rule.dayType,
        attends: attends ?? rule.attends,
        charges: charges ?? rule.charges,
        multiplier: multiplier ?? rule.multiplier,
        notes: rule.notes,
      );
    });
  }

  void _addItem() {
    final product = widget.products.isNotEmpty ? widget.products.first : null;
    if (product == null) return;
    setState(() {
      _items.add(
        ServiceContractConsumptionItem(
          productId: product.id,
          productName: product.name,
          quantityPerPerson: 1,
          unit: product.unit,
          wastePercent: 0,
          active: true,
        ),
      );
    });
  }

  void _updateItem(
    int index, {
    int? productId,
    double? quantity,
    String? unit,
  }) {
    final item = _items[index];
    final product = productId == null
        ? null
        : widget.products.where((p) => p.id == productId).firstOrNull;
    setState(() {
      _items[index] = ServiceContractConsumptionItem(
        id: item.id,
        productId: productId ?? item.productId,
        productName: product?.name ?? item.productName,
        quantityPerPerson: quantity ?? item.quantityPerPerson,
        unit: unit ?? product?.unit ?? item.unit,
        wastePercent: item.wastePercent,
        active: item.active,
        notes: item.notes,
      );
    });
  }
}

class _AppointmentDialog extends StatefulWidget {
  const _AppointmentDialog({
    required this.session,
    required this.api,
    required this.products,
    required this.appointment,
  });

  final Session session;
  final ApiClient api;
  final List<Product> products;
  final ServiceAppointment appointment;

  @override
  State<_AppointmentDialog> createState() => _AppointmentDialogState();
}

class _AppointmentDialogState extends State<_AppointmentDialog> {
  late final TextEditingController _people;
  late final TextEditingController _value;
  late final TextEditingController _multiplier;
  late final TextEditingController _notes;
  late String _status;
  late List<ServiceAppointmentConsumptionItem> _items;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final appointment = widget.appointment;
    _people = TextEditingController(
      text: appointment.peopleQuantity.toString(),
    );
    _value = TextEditingController(
      text: appointment.valuePerPerson.toStringAsFixed(2),
    );
    _multiplier = TextEditingController(
      text: appointment.multiplier.toString(),
    );
    _notes = TextEditingController(text: appointment.notes ?? '');
    _status = appointment.status;
    _items = appointment.items.toList();
  }

  @override
  void dispose() {
    _people.dispose();
    _value.dispose();
    _multiplier.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.api.updateServiceAppointment(
        widget.session.token,
        widget.appointment.id,
        {
          'people_quantity': _parse(_people.text),
          'value_per_person': _parse(_value.text),
          'multiplier': _parse(_multiplier.text),
          'status': _status,
          'notes': _notes.text,
          'items': _items.map((item) => item.toJson()).toList(),
        },
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        'Apontamento ${_formatBrazilDate(widget.appointment.appointmentDate)}',
      ),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _people,
                      decoration: const InputDecoration(labelText: 'Pessoas'),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: TextField(
                      controller: _value,
                      decoration: const InputDecoration(
                        labelText: 'Valor por pessoa',
                      ),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: TextField(
                      controller: _multiplier,
                      decoration: const InputDecoration(
                        labelText: 'Multiplicador',
                      ),
                    ),
                  ),
                  const Gap(8),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _status,
                      decoration: const InputDecoration(labelText: 'Status'),
                      items: const [
                        DropdownMenuItem(
                          value: 'previsto',
                          child: Text('Previsto'),
                        ),
                        DropdownMenuItem(
                          value: 'confirmado',
                          child: Text('Confirmado'),
                        ),
                        DropdownMenuItem(
                          value: 'cancelado',
                          child: Text('Cancelado'),
                        ),
                        DropdownMenuItem(
                          value: 'sem_atendimento',
                          child: Text('Sem atendimento'),
                        ),
                      ],
                      onChanged: (value) =>
                          setState(() => _status = value ?? _status),
                    ),
                  ),
                ],
              ),
              const Gap(8),
              const Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Esse valor entra no fechamento: pessoas x valor por pessoa x multiplicador. Status sem atendimento ou cancelado n\u00E3o cobra.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
              ),
              const Gap(12),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Produtos levados/consumidos',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              const Gap(8),
              ..._items.asMap().entries.map(
                (entry) => _itemTile(entry.key, entry.value),
              ),
              TextButton.icon(
                onPressed: _addItem,
                icon: const Icon(Icons.add),
                label: const Text('Adicionar produto'),
              ),
              TextField(
                controller: _notes,
                decoration: const InputDecoration(
                  labelText: 'Observa\u00E7\u00F5es',
                ),
                maxLines: 2,
              ),
            ],
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
          icon: const Icon(Icons.save),
          label: const Text('Salvar'),
        ),
      ],
    );
  }

  Widget _itemTile(int index, ServiceAppointmentConsumptionItem item) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: item.productId,
              decoration: const InputDecoration(labelText: 'Produto'),
              items: widget.products
                  .map(
                    (product) => DropdownMenuItem(
                      value: product.id,
                      child: Text(product.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) => _updateItem(index, productId: value),
            ),
          ),
          const Gap(8),
          Expanded(
            child: TextFormField(
              initialValue: item.quantityPlanned.toString(),
              decoration: const InputDecoration(labelText: 'Planejado'),
              onChanged: (value) => _updateItem(index, planned: _parse(value)),
            ),
          ),
          const Gap(8),
          Expanded(
            child: TextFormField(
              initialValue: item.quantityConfirmed.toString(),
              decoration: const InputDecoration(labelText: 'Confirmado'),
              onChanged: (value) =>
                  _updateItem(index, confirmed: _parse(value)),
            ),
          ),
          const Gap(8),
          SizedBox(
            width: 80,
            child: TextFormField(
              initialValue: item.unit,
              decoration: const InputDecoration(labelText: 'Un.'),
              onChanged: (value) => _updateItem(index, unit: value),
            ),
          ),
          IconButton(
            onPressed: () => setState(() => _items.removeAt(index)),
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
    );
  }

  void _addItem() {
    final product = widget.products.isNotEmpty ? widget.products.first : null;
    if (product == null) return;
    setState(() {
      _items.add(
        ServiceAppointmentConsumptionItem(
          productId: product.id,
          productName: product.name,
          quantityPlanned: 1,
          quantityConfirmed: 1,
          unit: product.unit,
        ),
      );
    });
  }

  void _updateItem(
    int index, {
    int? productId,
    double? planned,
    double? confirmed,
    String? unit,
  }) {
    final item = _items[index];
    final product = productId == null
        ? null
        : widget.products.where((p) => p.id == productId).firstOrNull;
    setState(() {
      _items[index] = ServiceAppointmentConsumptionItem(
        id: item.id,
        productId: productId ?? item.productId,
        productName: product?.name ?? item.productName,
        quantityPlanned: planned ?? item.quantityPlanned,
        quantityConfirmed: confirmed ?? item.quantityConfirmed,
        unit: unit ?? product?.unit ?? item.unit,
        notes: item.notes,
      );
    });
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(text, style: const TextStyle(color: Color(0xFF64748B))),
    );
  }
}

String _dayTypeLabel(String value) {
  return switch (value) {
    'weekday' => 'Dia \u00FAtil',
    'saturday' => 'S\u00E1bado',
    'sunday' => 'Domingo',
    'holiday' => 'Feriado',
    _ => value,
  };
}

String _statusLabel(String value) {
  return switch (value) {
    'previsto' => 'Previsto',
    'confirmado' => 'Confirmado',
    'cancelado' => 'Cancelado',
    'sem_atendimento' => 'Sem atendimento',
    _ => value,
  };
}

String _contractStatusLabel(String value) {
  return switch (value) {
    'active' => 'Ativo',
    'closed' => 'Encerrado',
    'encerrado' => 'Encerrado',
    _ => value,
  };
}

String _billingStatusLabel(String value) {
  return switch (value) {
    'generated' => 'Fechado',
    'cancelado' => 'Cancelado',
    _ => value,
  };
}

String _formatIsoDate(DateTime value) {
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '${value.year}-$month-$day';
}

String _formatBrazilDate(String value) {
  final date = _parseDateInput(value);
  if (date == null) return value;
  return _formatBrazilDateFromDate(date);
}

String _formatBrazilDateFromDate(DateTime value) {
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  return '$day/$month/${value.year}';
}

String _dateInputToIso(String value) {
  final date = _parseDateInput(value);
  return date == null ? value : _formatIsoDate(date);
}

DateTime? _parseDateInput(String value) {
  return _parseIsoDate(value) ?? _parseBrazilDate(value);
}

DateTime? _parseIsoDate(String value) {
  final parts = value.split('-');
  if (parts.length != 3) return null;
  final year = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final day = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

DateTime? _parseBrazilDate(String value) {
  final parts = value.split('/');
  if (parts.length != 3) return null;
  final day = int.tryParse(parts[0]);
  final month = int.tryParse(parts[1]);
  final year = int.tryParse(parts[2]);
  if (year == null || month == null || day == null) return null;
  return DateTime(year, month, day);
}

String _formatMoney(double value) {
  final fixed = value.toStringAsFixed(2).replaceAll('.', ',');
  final parts = fixed.split(',');
  final buffer = StringBuffer();
  for (var i = 0; i < parts.first.length; i++) {
    final remaining = parts.first.length - i;
    buffer.write(parts.first[i]);
    if (remaining > 1 && remaining % 3 == 1) {
      buffer.write('.');
    }
  }
  return 'R\$ ${buffer.toString()},${parts.last}';
}

String? _required(String? value) {
  return value == null || value.trim().isEmpty ? 'Obrigat\u00F3rio.' : null;
}

String? _positive(String? value) {
  return _parse(value ?? '') <= 0 ? 'Informe um valor maior que zero.' : null;
}

double _parse(String value) {
  final trimmed = value.trim();
  if (trimmed.contains(',')) {
    return double.tryParse(trimmed.replaceAll('.', '').replaceAll(',', '.')) ??
        0;
  }
  return double.tryParse(trimmed) ?? 0;
}
