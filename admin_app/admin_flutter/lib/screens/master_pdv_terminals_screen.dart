import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../models/company.dart';
import '../models/pdv_terminal.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/error_panel.dart';

const _pdvWindowsNotAllowedMessage =
    'Cliente nao possui PDV Windows liberado no plano/cadastro. '
    'Libere o modulo PDV Windows no plano ou como excecao no cadastro da empresa.';

class MasterPdvTerminalsScreen extends StatefulWidget {
  const MasterPdvTerminalsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterPdvTerminalsScreen> createState() =>
      _MasterPdvTerminalsScreenState();
}

class _MasterPdvTerminalsScreenState extends State<MasterPdvTerminalsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  final _cashNumber = TextEditingController();
  final _label = TextEditingController(text: 'PDV Windows');

  List<Company> _companies = [];
  List<PdvTerminal> _terminals = [];
  Company? _selectedCompany;
  bool _loading = true;
  bool _loadingTerminals = false;
  bool _saving = false;
  int _cutoffMinutes = 180;
  String? _error;
  PdvTerminalActivationCode? _lastCode;
  final Map<int, String> _terminalCommandStatus = {};

  @override
  void initState() {
    super.initState();
    _loadCompanies();
  }

  @override
  void dispose() {
    _search.dispose();
    _cashNumber.dispose();
    _label.dispose();
    super.dispose();
  }

  List<Company> get _filteredCompanies {
    final query = _search.text.trim().toLowerCase();
    final active = _companies.where((company) => company.active).toList();
    if (query.isEmpty) return active;
    return active.where((company) {
      final values = [
        company.name,
        company.tradeName,
        company.code,
        company.documentNumber,
        company.email,
        company.city,
        company.state,
      ].whereType<String>().join(' ').toLowerCase();
      return values.contains(query);
    }).toList();
  }

  Future<void> _loadCompanies() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final companies = await _api.listCompanies(widget.session.token);
      companies.sort((a, b) => a.name.compareTo(b.name));
      if (!mounted) return;
      setState(() {
        _companies = companies;
        final filtered = _filteredCompanies;
        _selectedCompany = filtered.isEmpty ? null : filtered.first;
      });
      if (_selectedCompany != null) {
        await _loadTerminals(_selectedCompany!);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Nao foi possivel carregar as empresas.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _selectCompany(Company company) {
    setState(() {
      _selectedCompany = company;
      _lastCode = null;
      _terminals = [];
      if (_label.text.trim().isEmpty || _label.text.trim() == 'PDV Windows') {
        _label.text = 'PDV Windows';
      }
    });
    _loadTerminals(company);
  }

  Future<void> _loadTerminals(Company company) async {
    setState(() {
      _loadingTerminals = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listMasterPdvTerminals(widget.session.token, company.code),
        _api.getMasterPdvBusinessDaySettings(
          widget.session.token,
          company.code,
        ),
      ]);
      final terminals = results[0] as List<PdvTerminal>;
      final settings = results[1] as PdvBusinessDaySettings;
      if (!mounted || _selectedCompany?.code != company.code) return;
      setState(() {
        _terminals = terminals;
        _cutoffMinutes = settings.cutoffMinutes;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Nao foi possivel carregar os PDVs do cliente.',
        );
      }
    } finally {
      if (mounted) setState(() => _loadingTerminals = false);
    }
  }

  Future<void> _editBusinessDayCutoff() async {
    final company = _selectedCompany;
    if (company == null) return;
    final selected = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(
        hour: _cutoffMinutes ~/ 60,
        minute: _cutoffMinutes % 60,
      ),
      helpText: 'Encerramento do dia comercial',
      confirmText: 'Salvar',
      cancelText: 'Cancelar',
    );
    if (selected == null) return;
    try {
      final settings = await _api.updateMasterPdvBusinessDaySettings(
        widget.session.token,
        company.code,
        selected.hour * 60 + selected.minute,
      );
      if (mounted && _selectedCompany?.code == company.code) {
        setState(() => _cutoffMinutes = settings.cutoffMinutes);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _generateCode() async {
    final company = _selectedCompany;
    final cash = _normalizeCashRegisterNumber(_cashNumber.text);
    if (company == null) {
      setState(() => _error = 'Escolha a empresa cliente.');
      return;
    }
    if (!company.enabledModules.contains('pdv_windows')) {
      setState(() => _error = _pdvWindowsNotAllowedMessage);
      return;
    }
    if (cash == null) {
      setState(() => _error = 'Informe o numero do caixa.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
      _lastCode = null;
    });
    try {
      final result = await _api.createMasterPdvTerminalActivationCode(
        widget.session.token,
        MasterPdvTerminalActivationCreatePayload(
          companyCode: company.code,
          cashRegisterNumber: cash,
          deviceLabel: _label.text.trim().isEmpty ? null : _label.text.trim(),
        ),
      );
      if (!mounted) return;
      setState(() => _lastCode = result);
      await _loadTerminals(company);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Nao foi possivel gerar o codigo.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String? _normalizeCashRegisterNumber(String? value) {
    final digits = (value ?? '').replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) return null;
    return digits.padLeft(2, '0');
  }

  Future<void> _changeTerminalNumber(PdvTerminal terminal) async {
    final company = _selectedCompany;
    if (company == null) return;
    final controller = TextEditingController(text: terminal.cashRegisterNumber);
    try {
      final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Trocar numero do Caixa ${terminal.cashRegisterNumber}'),
          content: TextField(
            controller: controller,
            autofocus: true,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Novo numero do caixa',
              border: OutlineInputBorder(),
            ),
            onSubmitted: (_) => Navigator.of(context).pop(controller.text),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text),
              child: const Text('Salvar'),
            ),
          ],
        ),
      );
      final normalized = _normalizeCashRegisterNumber(value);
      if (normalized == null || normalized == terminal.cashRegisterNumber) {
        return;
      }
      await _api.updateMasterPdvTerminalNumber(
        widget.session.token,
        company.code,
        terminal.id,
        normalized,
      );
      await _loadTerminals(company);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _deleteTerminal(PdvTerminal terminal) async {
    final company = _selectedCompany;
    if (company == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Excluir Caixa ${terminal.cashRegisterNumber}?'),
        content: Text(
          'Esta acao remove o vinculo do PDV em ${company.name}. '
          'Use apenas quando for reconfigurar ou remover uma maquina.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await _api.deleteMasterPdvTerminal(
        widget.session.token,
        company.code,
        terminal.id,
      );
      await _loadTerminals(company);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _sendCommand(PdvTerminal terminal, String action) async {
    final company = _selectedCompany;
    if (company == null) return;
    final label = _terminalCommandLabel(action);
    try {
      final command = await _api.createMasterPdvTerminalCommand(
        widget.session.token,
        company.code,
        terminal.id,
        action,
        message: label,
      );
      if (!mounted) return;
      setState(() {
        _terminalCommandStatus[terminal.id] =
            '$label enviado. Aguardando confirmação do PDV...';
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '$label enviado para o Caixa ${terminal.cashRegisterNumber}.',
          ),
        ),
      );
      await _waitCommandConfirmation(company, terminal.id, command.id, label);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _showCommandHistory(PdvTerminal terminal) async {
    final company = _selectedCompany;
    if (company == null) return;
    try {
      final commands = await _api.listMasterPdvTerminalCommands(
        widget.session.token,
        company.code,
        terminal.id,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text('Histórico do Caixa ${terminal.cashRegisterNumber}'),
          content: SizedBox(
            width: 680,
            child: commands.isEmpty
                ? const Text('Nenhum comando enviado para este PDV.')
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: commands.length,
                    separatorBuilder: (_, _) => const Divider(height: 18),
                    itemBuilder: (context, index) {
                      final command = commands[index];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _InfoChip(
                                icon: Icons.bolt_outlined,
                                label: _terminalCommandLabel(command.action),
                              ),
                              _InfoChip(
                                icon: _commandStatusIcon(command.status),
                                label: _commandStatusLabel(command.status),
                              ),
                              _InfoChip(
                                icon: Icons.schedule_outlined,
                                label: _dateTimeOrDash(command.createdAt),
                              ),
                            ],
                          ),
                          if (command.deliveredAt != null) ...[
                            const Gap(6),
                            Text(
                              'Entregue ao PDV em ${_dateTimeOrDash(command.deliveredAt)}',
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                          if (command.completedAt != null) ...[
                            const Gap(4),
                            Text(
                              'Concluído em ${_dateTimeOrDash(command.completedAt)}',
                              style: const TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                          if ((command.resultMessage ?? '').isNotEmpty) ...[
                            const Gap(8),
                            SelectableText(command.resultMessage!),
                          ],
                        ],
                      );
                    },
                  ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _waitCommandConfirmation(
    Company company,
    int terminalId,
    int commandId,
    String label,
  ) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      await Future<void>.delayed(const Duration(seconds: 1));
      if (!mounted || _selectedCompany?.code != company.code) return;
      final commands = await _api.listMasterPdvTerminalCommands(
        widget.session.token,
        company.code,
        terminalId,
      );
      PdvTerminalCommand? current;
      for (final command in commands) {
        if (command.id == commandId) {
          current = command;
          break;
        }
      }
      if (current == null) continue;
      if (current.status == 'done') {
        setState(() {
          _terminalCommandStatus[terminalId] =
              '$label confirmado pelo PDV agora.';
        });
        return;
      }
      if (current.status == 'failed') {
        setState(() {
          _terminalCommandStatus[terminalId] =
              current?.resultMessage ?? '$label falhou no PDV.';
        });
        return;
      }
    }
    if (!mounted || _selectedCompany?.code != company.code) return;
    setState(() {
      _terminalCommandStatus[terminalId] =
          '$label enviado. O PDV ainda não confirmou.';
    });
  }

  @override
  Widget build(BuildContext context) {
    final companies = _filteredCompanies;
    final selected = _selectedCompany;
    return SafeArea(
      child: Padding(
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
                        'Terminais PDV',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Gap(4),
                      Text(
                        'Ative PDV Windows escolhendo o cliente e o numero do caixa.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  onPressed: _loading ? null : _loadCompanies,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Atualizar',
                ),
              ],
            ),
            const Gap(18),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: ErrorPanel(message: _error!, onRetry: _loadCompanies),
              ),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final stacked = constraints.maxWidth < 980;
                    final left = _ClientSelector(
                      search: _search,
                      companies: companies,
                      selected: selected,
                      onSearchChanged: (_) => setState(() {
                        final filtered = _filteredCompanies;
                        if (!filtered.contains(_selectedCompany)) {
                          _selectedCompany = filtered.isEmpty
                              ? null
                              : filtered.first;
                          _lastCode = null;
                        }
                      }),
                      onSelect: _selectCompany,
                    );
                    final right = _ActivationPanel(
                      company: selected,
                      cashNumber: _cashNumber,
                      label: _label,
                      saving: _saving,
                      lastCode: _lastCode,
                      terminals: _terminals,
                      loadingTerminals: _loadingTerminals,
                      onGenerate: _generateCode,
                      onRefreshTerminals: selected == null
                          ? null
                          : () => _loadTerminals(selected),
                      onChangeNumber: _changeTerminalNumber,
                      onDelete: _deleteTerminal,
                      onSendCommand: _sendCommand,
                      onShowHistory: _showCommandHistory,
                      commandStatusByTerminal: _terminalCommandStatus,
                      cutoffMinutes: _cutoffMinutes,
                      onEditCutoff: selected == null
                          ? null
                          : _editBusinessDayCutoff,
                    );
                    if (stacked) {
                      return ListView(
                        children: [
                          SizedBox(height: 420, child: left),
                          const Gap(14),
                          right,
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 430, child: left),
                        const Gap(16),
                        Expanded(child: SingleChildScrollView(child: right)),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ClientSelector extends StatelessWidget {
  const _ClientSelector({
    required this.search,
    required this.companies,
    required this.selected,
    required this.onSearchChanged,
    required this.onSelect,
  });

  final TextEditingController search;
  final List<Company> companies;
  final Company? selected;
  final ValueChanged<String> onSearchChanged;
  final ValueChanged<Company> onSelect;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: _panelDecoration,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: search,
              onChanged: onSearchChanged,
              decoration: const InputDecoration(
                labelText: 'Pesquisar cliente',
                hintText: 'Nome, codigo, CNPJ, cidade...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
            const Gap(12),
            Text(
              '${companies.length} cliente(s) encontrado(s)',
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const Gap(10),
            Expanded(
              child: companies.isEmpty
                  ? const Center(child: Text('Nenhum cliente encontrado.'))
                  : ListView.separated(
                      itemCount: companies.length,
                      separatorBuilder: (_, _) => const Gap(8),
                      itemBuilder: (context, index) {
                        final company = companies[index];
                        return _CompanyTile(
                          company: company,
                          selected: selected?.id == company.id,
                          onTap: () => onSelect(company),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompanyTile extends StatelessWidget {
  const _CompanyTile({
    required this.company,
    required this.selected,
    required this.onTap,
  });

  final Company company;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEFF6FF) : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? const Color(0xFF60A5FA) : const Color(0xFFE2E8F0),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: selected
                    ? const Color(0xFF2563EB)
                    : const Color(0xFFE2E8F0),
                foregroundColor: selected
                    ? Colors.white
                    : const Color(0xFF334155),
                child: Text(_initials(company.name)),
              ),
              const Gap(10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      company.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const Gap(3),
                    Text(
                      [
                        company.code,
                        if ((company.documentNumber ?? '').isNotEmpty)
                          company.documentNumber!,
                        if ((company.city ?? '').isNotEmpty) company.city!,
                      ].join('  |  '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                const Icon(Icons.check_circle, color: Color(0xFF2563EB)),
            ],
          ),
        ),
      ),
    );
  }
}

class _PlanBlockedNotice extends StatelessWidget {
  const _PlanBlockedNotice();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFF59E0B)),
      ),
      child: const Padding(
        padding: EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline, color: Color(0xFFB45309)),
            Gap(10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'PDV Windows nao liberado para este cliente',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF78350F),
                    ),
                  ),
                  Gap(4),
                  Text(
                    'O plano/cadastro atual nao permite gerar codigo de ativacao. '
                    'Libere o modulo PDV Windows no plano ou como excecao no cadastro da empresa.',
                    style: TextStyle(color: Color(0xFF92400E)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivationPanel extends StatelessWidget {
  const _ActivationPanel({
    required this.company,
    required this.cashNumber,
    required this.label,
    required this.saving,
    required this.lastCode,
    required this.terminals,
    required this.loadingTerminals,
    required this.onGenerate,
    required this.onRefreshTerminals,
    required this.onChangeNumber,
    required this.onDelete,
    required this.onSendCommand,
    required this.onShowHistory,
    required this.commandStatusByTerminal,
    required this.cutoffMinutes,
    required this.onEditCutoff,
  });

  final Company? company;
  final TextEditingController cashNumber;
  final TextEditingController label;
  final bool saving;
  final PdvTerminalActivationCode? lastCode;
  final List<PdvTerminal> terminals;
  final bool loadingTerminals;
  final VoidCallback onGenerate;
  final VoidCallback? onRefreshTerminals;
  final ValueChanged<PdvTerminal> onChangeNumber;
  final ValueChanged<PdvTerminal> onDelete;
  final void Function(PdvTerminal terminal, String action) onSendCommand;
  final ValueChanged<PdvTerminal> onShowHistory;
  final Map<int, String> commandStatusByTerminal;
  final int cutoffMinutes;
  final VoidCallback? onEditCutoff;

  @override
  Widget build(BuildContext context) {
    final selected = company;
    final hasPdvWindows =
        selected?.enabledModules.contains('pdv_windows') ?? false;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DecoratedBox(
          decoration: _panelDecoration,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Cliente selecionado',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Gap(14),
                if (selected == null)
                  const Text('Selecione um cliente na lista.')
                else
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _InfoChip(
                        icon: Icons.apartment_outlined,
                        label: selected.name,
                      ),
                      _InfoChip(icon: Icons.tag_outlined, label: selected.code),
                      if ((selected.documentNumber ?? '').isNotEmpty)
                        _InfoChip(
                          icon: Icons.badge_outlined,
                          label: selected.documentNumber!,
                        ),
                      if ((selected.city ?? '').isNotEmpty ||
                          (selected.state ?? '').isNotEmpty)
                        _InfoChip(
                          icon: Icons.location_on_outlined,
                          label: [
                            selected.city,
                            selected.state,
                          ].whereType<String>().join(' / '),
                        ),
                    ],
                  ),
                if (selected != null && !hasPdvWindows) ...[
                  const Gap(14),
                  const _PlanBlockedNotice(),
                ],
              ],
            ),
          ),
        ),
        const Gap(14),
        DecoratedBox(
          decoration: _panelDecoration,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gerar ativacao',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const Gap(14),
                TextField(
                  controller: cashNumber,
                  enabled: !saving && hasPdvWindows,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Numero do caixa',
                    hintText: '1, 2, 3...',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.point_of_sale_outlined),
                  ),
                  onSubmitted: (_) =>
                      saving || !hasPdvWindows ? null : onGenerate(),
                ),
                const Gap(12),
                TextField(
                  controller: label,
                  enabled: !saving && hasPdvWindows,
                  decoration: const InputDecoration(
                    labelText: 'Identificacao',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.computer_outlined),
                  ),
                  onSubmitted: (_) =>
                      saving || !hasPdvWindows ? null : onGenerate(),
                ),
                const Gap(16),
                Align(
                  alignment: Alignment.centerRight,
                  child: FilledButton.icon(
                    onPressed: saving || !hasPdvWindows ? null : onGenerate,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.vpn_key_outlined),
                    label: const Text('Gerar codigo'),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (lastCode != null) ...[
          const Gap(14),
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF93C5FD)),
            ),
            child: Padding(
              padding: const EdgeInsets.all(22),
              child: Column(
                children: [
                  Text(
                    'Codigo para Caixa ${lastCode!.terminal.cashRegisterNumber}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Gap(10),
                  SelectableText(
                    lastCode!.activationCode,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 40,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F4C81),
                    ),
                  ),
                  const Gap(8),
                  const Text('Digite este codigo no PDV Windows do cliente.'),
                ],
              ),
            ),
          ),
        ],
        const Gap(14),
        DecoratedBox(
          decoration: _panelDecoration,
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'PDVs do cliente',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton.outlined(
                      onPressed: onRefreshTerminals,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Atualizar PDVs',
                    ),
                    const Gap(8),
                    OutlinedButton.icon(
                      onPressed: onEditCutoff,
                      icon: const Icon(Icons.schedule_outlined),
                      label: Text('Dia comercial: ${_time(cutoffMinutes)}'),
                    ),
                  ],
                ),
                const Gap(10),
                if (loadingTerminals)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(22),
                      child: CircularProgressIndicator(),
                    ),
                  )
                else if (terminals.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 16),
                    child: Text('Nenhum PDV cadastrado para este cliente.'),
                  )
                else
                  ...terminals.map(
                    (terminal) => Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MasterTerminalCard(
                        terminal: terminal,
                        onChangeNumber: () => onChangeNumber(terminal),
                        onDelete: () => onDelete(terminal),
                        onSendCommand: (action) =>
                            onSendCommand(terminal, action),
                        onShowHistory: () => onShowHistory(terminal),
                        commandStatus: commandStatusByTerminal[terminal.id],
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
}

class _MasterTerminalCard extends StatelessWidget {
  const _MasterTerminalCard({
    required this.terminal,
    required this.onChangeNumber,
    required this.onDelete,
    required this.onSendCommand,
    required this.onShowHistory,
    this.commandStatus,
  });

  final PdvTerminal terminal;
  final VoidCallback onChangeNumber;
  final VoidCallback onDelete;
  final ValueChanged<String> onSendCommand;
  final VoidCallback onShowHistory;
  final String? commandStatus;

  @override
  Widget build(BuildContext context) {
    final online = _isRecentlyOnline(terminal.lastSeenAt);
    final status = online ? _statusLabel(terminal.currentStatus) : 'Offline';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: online
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFE2E8F0),
                  foregroundColor: online
                      ? const Color(0xFF166534)
                      : const Color(0xFF475569),
                  child: Text(terminal.cashRegisterNumber),
                ),
                const Gap(10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Caixa ${terminal.cashRegisterNumber} - $status',
                        style: const TextStyle(fontWeight: FontWeight.w900),
                      ),
                      const Gap(3),
                      Text(
                        [
                          terminal.deviceLabel ?? 'PDV Windows',
                          if (terminal.machineName != null)
                            terminal.machineName!,
                          if (terminal.appVersion != null)
                            'v${terminal.appVersion}',
                        ].join('  |  '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton.outlined(
                  tooltip: 'Trocar número',
                  onPressed: onChangeNumber,
                  icon: const Icon(Icons.edit_outlined),
                ),
                const Gap(6),
                IconButton.outlined(
                  tooltip: 'Excluir PDV',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline),
                ),
                const Gap(6),
                IconButton.outlined(
                  tooltip: 'Histórico do terminal',
                  onPressed: onShowHistory,
                  icon: const Icon(Icons.history_outlined),
                ),
                const Gap(6),
                PopupMenuButton<String>(
                  tooltip: 'Ações remotas',
                  onSelected: onSendCommand,
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'force_reconnect',
                      child: Text('Forçar reconexão'),
                    ),
                    PopupMenuItem(
                      value: 'sync_offline_sales',
                      child: Text('Sincronizar pendências'),
                    ),
                    PopupMenuItem(
                      value: 'reload_catalog',
                      child: Text('Forçar carga completa'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'clear_local_queue',
                      child: Text('Limpar fila local'),
                    ),
                    PopupMenuDivider(),
                    PopupMenuItem(
                      value: 'block_terminal',
                      child: Text('Bloquear terminal'),
                    ),
                    PopupMenuItem(
                      value: 'unblock_terminal',
                      child: Text('Desbloquear terminal'),
                    ),
                    PopupMenuItem(
                      value: 'reset_terminal_link',
                      child: Text('Resetar vínculo'),
                    ),
                    PopupMenuItem(
                      value: 'request_update',
                      child: Text('Solicitar atualização'),
                    ),
                  ],
                  child: const Padding(
                    padding: EdgeInsets.all(8),
                    child: Icon(Icons.more_vert),
                  ),
                ),
              ],
            ),
            const Gap(10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _InfoChip(
                  icon: Icons.person_outline,
                  label: terminal.currentOperatorName ?? 'Sem operador',
                ),
                _InfoChip(
                  icon: Icons.schedule_outlined,
                  label: 'Contato: ${_dateTimeOrDash(terminal.lastSeenAt)}',
                ),
                if (terminal.crossedBusinessDay)
                  const _InfoChip(
                    icon: Icons.warning_amber_outlined,
                    label: 'Atravessou o dia comercial',
                  ),
              ],
            ),
            if (commandStatus != null) ...[
              const Gap(10),
              _InfoChip(icon: Icons.task_alt_outlined, label: commandStatus!),
            ],
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: const Color(0xFF475569)),
            const Gap(7),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

BoxDecoration get _panelDecoration => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(14),
  border: Border.all(color: const Color(0xFFD7E2F0)),
  boxShadow: const [
    BoxShadow(color: Color(0x0A0F172A), blurRadius: 20, offset: Offset(0, 10)),
  ],
);

String _initials(String value) {
  final parts = value
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  if (parts.isEmpty) return 'L';
  return parts.map((part) => part[0].toUpperCase()).join();
}

bool _isRecentlyOnline(DateTime? value) {
  if (value == null) return false;
  return DateTime.now().difference(value).inMinutes <= 2;
}

String _statusLabel(String? status) {
  return switch (status) {
    'open' => 'Aberto',
    'paused' => 'Pausado',
    'closed' => 'Fechado',
    'pending' => 'Pendente',
    _ => 'Online',
  };
}

String _dateTimeOrDash(DateTime? value) {
  if (value == null) return '-';
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString().padLeft(4, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$day/$month/$year $hour:$minute';
}

String _time(int minutes) {
  final hour = (minutes ~/ 60).toString().padLeft(2, '0');
  final minute = (minutes % 60).toString().padLeft(2, '0');
  return '$hour:$minute';
}

String _terminalCommandLabel(String action) {
  return switch (action) {
    'force_reconnect' => 'Forçar reconexão',
    'sync_offline_sales' => 'Sincronizar pendências',
    'reload_catalog' => 'Forçar carga completa',
    'clear_local_queue' => 'Limpar fila local',
    'block_terminal' => 'Bloquear terminal',
    'unblock_terminal' => 'Desbloquear terminal',
    'reset_terminal_link' => 'Resetar vínculo',
    'request_update' => 'Solicitar atualização',
    _ => 'Comando remoto',
  };
}

String _commandStatusLabel(String status) {
  return switch (status) {
    'pending' => 'Pendente',
    'done' => 'Concluído',
    'failed' => 'Falhou',
    _ => status,
  };
}

IconData _commandStatusIcon(String status) {
  return switch (status) {
    'done' => Icons.check_circle_outline,
    'failed' => Icons.error_outline,
    _ => Icons.pending_actions_outlined,
  };
}
