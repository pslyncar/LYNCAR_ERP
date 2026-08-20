import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../models/pdv_terminal.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/error_panel.dart';

class PdvTerminalsScreen extends StatefulWidget {
  const PdvTerminalsScreen({super.key, required this.session});

  final Session session;

  @override
  State<PdvTerminalsScreen> createState() => _PdvTerminalsScreenState();
}

class _PdvTerminalsScreenState extends State<PdvTerminalsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  List<PdvTerminal> _terminals = [];
  bool _loading = true;
  bool _forcingSync = false;
  int _cutoffMinutes = 180;
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
        _api.listPdvTerminals(widget.session.token),
        _api.getPdvBusinessDaySettings(widget.session.token),
      ]);
      final terminals = results[0] as List<PdvTerminal>;
      final settings = results[1] as PdvBusinessDaySettings;
      if (!mounted) return;
      setState(() {
        _terminals = terminals;
        _cutoffMinutes = settings.cutoffMinutes;
      });
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível carregar os terminais PDV.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editBusinessDayCutoff() async {
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
      final settings = await _api.updatePdvBusinessDaySettings(
        widget.session.token,
        selected.hour * 60 + selected.minute,
      );
      if (mounted) {
        setState(() => _cutoffMinutes = settings.cutoffMinutes);
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  Future<void> _forceCatalogReload([PdvTerminal? terminal]) async {
    final targets = terminal == null ? _terminals : [terminal];
    if (targets.isEmpty || _forcingSync) return;
    setState(() => _forcingSync = true);
    try {
      for (final target in targets) {
        await _api.createPdvTerminalCommand(
          widget.session.token,
          target.id,
          'reload_catalog',
          message: 'Forçar carga completa de produtos, clientes e ofertas',
        );
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            terminal == null
                ? 'Carga completa enviada para ${targets.length} PDV(s).'
                : 'Carga completa enviada para o Caixa ${terminal.cashRegisterNumber}.',
          ),
        ),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _forcingSync = false);
    }
  }

  List<PdvTerminal> get _filteredTerminals {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _terminals;
    return _terminals.where((terminal) {
      return terminal.cashRegisterNumber.toLowerCase().contains(query) ||
          (terminal.deviceLabel ?? '').toLowerCase().contains(query) ||
          (terminal.currentOperatorName ?? '').toLowerCase().contains(query) ||
          (terminal.appVersion ?? '').toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final terminals = _filteredTerminals;
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
                      SizedBox(height: 4),
                      Text(
                        'Controle os caixas, computadores e movimentação atual do PDV',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                const Gap(10),
                OutlinedButton.icon(
                  onPressed: widget.session.can('pdv_operators:manage')
                      ? _editBusinessDayCutoff
                      : null,
                  icon: const Icon(Icons.schedule_outlined),
                  label: Text('Dia comercial: ${_time(_cutoffMinutes)}'),
                ),
                const Gap(10),
                OutlinedButton.icon(
                  onPressed:
                      widget.session.can('pdv_operators:manage') &&
                          !_forcingSync
                      ? () => _forceCatalogReload()
                      : null,
                  icon: const Icon(Icons.sync_outlined),
                  label: const Text('Forçar carga completa'),
                ),
                const Gap(10),
                IconButton.outlined(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh),
                  tooltip: 'Atualizar',
                ),
              ],
            ),
            const Gap(18),
            _SummaryCards(terminals: _terminals),
            const Gap(14),
            TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                labelText: 'Buscar por caixa, operador, versão ou terminal',
                border: OutlineInputBorder(),
              ),
            ),
            const Gap(14),
            if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : terminals.isEmpty
                    ? const Center(
                        child: Text('Nenhum terminal PDV cadastrado.'),
                      )
                    : ListView.separated(
                        itemCount: terminals.length,
                        separatorBuilder: (_, _) => const Gap(10),
                        itemBuilder: (context, index) {
                          final terminal = terminals[index];
                          return _TerminalCard(
                            terminal: terminal,
                            onReload: widget.session.can('pdv_operators:manage')
                                ? () => _forceCatalogReload(terminal)
                                : null,
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

class _SummaryCards extends StatelessWidget {
  const _SummaryCards({required this.terminals});

  final List<PdvTerminal> terminals;

  @override
  Widget build(BuildContext context) {
    final online = terminals
        .where((terminal) => _isRecentlyOnline(terminal.lastSeenAt))
        .length;
    final open = terminals
        .where((terminal) => terminal.currentStatus == 'open')
        .length;
    final paused = terminals
        .where((terminal) => terminal.currentStatus == 'paused')
        .length;
    final totalToday = terminals.fold<double>(
      0,
      (sum, terminal) => sum + terminal.todaySalesAmount,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final itemWidth = width < 900 ? (width - 12) / 2 : (width - 36) / 4;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _SummaryCard(
              width: itemWidth,
              icon: Icons.point_of_sale_outlined,
              label: 'Terminais',
              value: '${terminals.length}',
            ),
            _SummaryCard(
              width: itemWidth,
              icon: Icons.wifi_tethering_outlined,
              label: 'Online agora',
              value: '$online',
            ),
            _SummaryCard(
              width: itemWidth,
              icon: Icons.lock_open_outlined,
              label: 'Abertos / pausados',
              value: '$open / $paused',
            ),
            _SummaryCard(
              width: itemWidth,
              icon: Icons.payments_outlined,
              label: 'Vendas hoje',
              value: _money(totalToday),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.width,
    required this.icon,
    required this.label,
    required this.value,
  });

  final double width;
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFD7E2F0)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF166A85)),
              const Gap(12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: Color(0xFF64748B)),
                    ),
                    const Gap(4),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalCard extends StatelessWidget {
  const _TerminalCard({required this.terminal, this.onReload});

  final PdvTerminal terminal;
  final VoidCallback? onReload;

  @override
  Widget build(BuildContext context) {
    final online = _isRecentlyOnline(terminal.lastSeenAt);
    final status = _statusLabel(terminal.currentStatus, online);
    final color = _statusColor(terminal.currentStatus, online);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFD7E2F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 25,
                  backgroundColor: color.withValues(alpha: 0.12),
                  child: Text(
                    terminal.cashRegisterNumber,
                    style: TextStyle(color: color, fontWeight: FontWeight.w900),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Caixa ${terminal.cashRegisterNumber}',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Gap(3),
                      Text(
                        [
                          terminal.deviceLabel ?? 'Terminal sem identificação',
                          if (terminal.machineName != null)
                            terminal.machineName!,
                          if (terminal.appVersion != null)
                            'v${terminal.appVersion}',
                          'Último contato: ${_dateTimeOrDash(terminal.lastSeenAt)}',
                        ].join(' • '),
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                _StatusChip(label: status, color: color),
                const Gap(8),
                IconButton.outlined(
                  tooltip: 'Forçar carga completa neste PDV',
                  onPressed: onReload,
                  icon: const Icon(Icons.sync_outlined),
                ),
                if (terminal.crossedBusinessDay) ...[
                  const Gap(8),
                  const _StatusChip(
                    label: 'Atravessou o dia comercial',
                    color: Color(0xFFB45309),
                  ),
                ],
              ],
            ),
            const Divider(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 10,
              children: [
                _InfoLine(
                  icon: Icons.computer_outlined,
                  label: 'Maquina',
                  value: _machineLabel(terminal),
                ),
                _InfoLine(
                  icon: Icons.vpn_key_outlined,
                  label: 'Ativacao',
                  value: terminal.activationStatus == 'pending'
                      ? 'Pendente ate ${_dateTimeOrDash(terminal.activationCodeExpiresAt)}'
                      : 'Ativado em ${_dateTimeOrDash(terminal.activatedAt)}',
                ),
                _InfoLine(
                  icon: Icons.person_outline,
                  label: 'Operador',
                  value: terminal.currentOperatorName ?? '-',
                ),
                _InfoLine(
                  icon: Icons.lock_open_outlined,
                  label: 'Abertura',
                  value: _dateTimeOrDash(terminal.cashOpenedAt),
                ),
                _InfoLine(
                  icon: Icons.receipt_long_outlined,
                  label: 'Vendas hoje',
                  value:
                      '${terminal.todaySalesCount} venda(s) • ${_money(terminal.todaySalesAmount)}',
                ),
                _InfoLine(
                  icon: Icons.point_of_sale_outlined,
                  label: 'Sessão atual',
                  value: _money(terminal.currentSessionTotalAmount ?? 0),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w800),
        ),
      ),
    );
  }
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Row(
        children: [
          Icon(icon, size: 18, color: const Color(0xFF64748B)),
          const Gap(8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

bool _isRecentlyOnline(DateTime? value) {
  if (value == null) return false;
  return DateTime.now().difference(value).inMinutes <= 2;
}

String _statusLabel(String? status, bool online) {
  if (!online) return 'Offline';
  return switch (status) {
    'open' => 'Aberto',
    'paused' => 'Pausado',
    'closed' => 'Fechado',
    _ => 'Online',
  };
}

Color _statusColor(String? status, bool online) {
  if (!online) return const Color(0xFF64748B);
  return switch (status) {
    'open' => const Color(0xFF00876C),
    'paused' => const Color(0xFFC46A00),
    'closed' => const Color(0xFF2563EB),
    _ => const Color(0xFF166A85),
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

String _machineLabel(PdvTerminal terminal) {
  final parts = [
    terminal.machineName,
    terminal.windowsUser,
  ].whereType<String>().where((part) => part.trim().isNotEmpty).toList();
  return parts.isEmpty ? '-' : parts.join(' / ');
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';
