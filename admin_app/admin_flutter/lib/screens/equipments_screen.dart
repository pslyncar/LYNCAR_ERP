import 'dart:async';

import 'package:flutter/material.dart';

import '../models/client.dart';
import '../models/equipment.dart';
import '../models/equipment_current_status.dart';
import '../models/monitoring_snapshot.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class EquipmentsScreen extends StatefulWidget {
  const EquipmentsScreen({super.key, required this.session});

  final Session session;

  @override
  State<EquipmentsScreen> createState() => _EquipmentsScreenState();
}

class _EquipmentsScreenState extends State<EquipmentsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<Equipment> _equipments = [];
  List<Client> _clients = [];
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
      final equipments = await _api.listEquipments(widget.session.token);
      var clients = <Client>[];
      try {
        clients = await _api.listClients(widget.session.token);
      } catch (_) {
        clients = [];
      }
      setState(() {
        _equipments = equipments;
        _clients = clients;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (error) {
      setState(() => _error = 'Não foi possível carregar equipamentos: $error');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openCreateDialog() async {
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => _EquipmentFormDialog(
        api: _api,
        token: widget.session.token,
        clients: _clients,
      ),
    );
    if (created == true) {
      await _load();
    }
  }

  Future<void> _openDetails(Equipment equipment) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _EquipmentDetailsDialog(
        api: _api,
        token: widget.session.token,
        equipment: equipment,
        clientName: _clientName(equipment.clientId),
        canGenerateToken: widget.session.can('equipments:update'),
      ),
    );
    await _load();
  }

  String _clientName(int clientId) {
    return _clients
        .firstWhere(
          (client) => client.id == clientId,
          orElse: () => Client(
            id: clientId,
            name: 'Cliente $clientId',
            personType: 'PF',
            contractType: 'avulso',
            allowCredit: false,
            creditLimit: 0,
            creditStatus: 'liberado',
            monthlyFee: 0,
            active: true,
            createdAt: DateTime.now(),
          ),
        )
        .name;
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
          children: [
            _Header(
              canCreate: widget.session.can('equipments:create'),
              onCreate: _openCreateDialog,
              onRefresh: _load,
            ),
            const SizedBox(height: 24),
            if (_loading)
              const LinearProgressIndicator()
            else if (_error != null)
              ErrorPanel(message: _error!, onRetry: _load)
            else
              AppCard(
                padding: EdgeInsets.zero,
                child: _equipments.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nenhuma máquina cadastrada.'),
                      )
                    : Column(
                        children: [
                          for (final equipment in _equipments)
                            _EquipmentRow(
                              equipment: equipment,
                              clientName: _clientName(equipment.clientId),
                              onTap: () => _openDetails(equipment),
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

class _Header extends StatelessWidget {
  const _Header({
    required this.canCreate,
    required this.onCreate,
    required this.onRefresh,
  });

  final bool canCreate;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Equipamentos',
                style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
              ),
              SizedBox(height: 4),
              Text(
                'Máquinas cadastradas e monitoradas pelo agente',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            ],
          ),
        ),
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
            label: const Text('Nova máquina'),
          ),
      ],
    );
  }
}

class _EquipmentRow extends StatelessWidget {
  const _EquipmentRow({
    required this.equipment,
    required this.clientName,
    required this.onTap,
  });

  final Equipment equipment;
  final String clientName;
  final VoidCallback onTap;

  bool get online {
    final lastSeenAt = equipment.lastSeenAt;
    if (lastSeenAt == null) {
      return false;
    }
    return DateTime.now().difference(lastSeenAt.toLocal()).inMinutes < 5;
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 82),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
        ),
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: online
                    ? const Color(0xFFDCFCE7)
                    : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                online ? Icons.computer : Icons.computer_outlined,
                color: online
                    ? const Color(0xFF15803D)
                    : const Color(0xFF475569),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              flex: 3,
              child: _TwoLine(
                primary: equipment.hostname,
                secondary: [
                  clientName,
                  equipment.assetTag == null
                      ? null
                      : 'Patr. ${equipment.assetTag}',
                ].whereType<String>().join(' • '),
                bold: true,
              ),
            ),
            Expanded(
              flex: 2,
              child: _TwoLine(
                primary: equipment.location ?? '-',
                secondary: equipment.responsibleUser,
              ),
            ),
            Expanded(
              flex: 2,
              child: _TwoLine(
                primary: equipment.lastIpAddress ?? '-',
                secondary: equipment.agentVersion == null
                    ? null
                    : 'Agente ${equipment.agentVersion}',
              ),
            ),
            Expanded(
              flex: 2,
              child: _TwoLine(
                primary: 'RAM ${equipment.ramTotalGb ?? '-'} GB',
                secondary: 'Armaz. ${equipment.storageTotalGb ?? '-'} GB',
              ),
            ),
            Expanded(
              flex: 2,
              child: _TwoLine(
                primary: online ? 'Online' : 'Offline',
                secondary: equipment.lastSeenAt == null
                    ? 'sem comunicação'
                    : _formatDate(equipment.lastSeenAt!),
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}';
  }
}

class _TwoLine extends StatelessWidget {
  const _TwoLine({required this.primary, this.secondary, this.bold = false});

  final String primary;
  final String? secondary;
  final bool bold;

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
            fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
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

class _EquipmentFormDialog extends StatefulWidget {
  const _EquipmentFormDialog({
    required this.api,
    required this.token,
    required this.clients,
  });

  final ApiClient api;
  final String token;
  final List<Client> clients;

  @override
  State<_EquipmentFormDialog> createState() => _EquipmentFormDialogState();
}

class _EquipmentFormDialogState extends State<_EquipmentFormDialog> {
  final _formKey = GlobalKey<FormState>();
  final _hostname = TextEditingController();
  final _assetTag = TextEditingController();
  final _location = TextEditingController();
  final _responsibleUser = TextEditingController();
  final _os = TextEditingController();
  final _processor = TextEditingController();
  final _ram = TextEditingController();
  final _storage = TextEditingController();
  final _notes = TextEditingController();

  int? _clientId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (widget.clients.isNotEmpty) {
      _clientId = widget.clients.first.id;
    }
  }

  @override
  void dispose() {
    _hostname.dispose();
    _assetTag.dispose();
    _location.dispose();
    _responsibleUser.dispose();
    _os.dispose();
    _processor.dispose();
    _ram.dispose();
    _storage.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _clientId == null) {
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.api.createEquipment(
        widget.token,
        EquipmentCreate(
          clientId: _clientId!,
          hostname: _hostname.text,
          assetTag: _assetTag.text,
          location: _location.text,
          responsibleUser: _responsibleUser.text,
          operatingSystem: _os.text,
          processor: _processor.text,
          ramTotalGb: _ram.text,
          storageTotalGb: _storage.text,
          technicalNotes: _notes.text,
        ),
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível salvar a máquina.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Nova máquina',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 18),
                  DropdownButtonFormField<int>(
                    initialValue: _clientId,
                    decoration: const InputDecoration(
                      labelText: 'Cliente',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final client in widget.clients)
                        DropdownMenuItem(
                          value: client.id,
                          child: Text(client.name),
                        ),
                    ],
                    onChanged: (value) => setState(() => _clientId = value),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _hostname,
                    decoration: const InputDecoration(
                      labelText: 'Nome da máquina',
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Informe o nome da máquina.';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  _ResponsiveFields(
                    children: [
                      _field(_assetTag, 'Patrimonio / etiqueta'),
                      _field(_location, 'Setor / local'),
                      _field(_responsibleUser, 'Usuário responsavel'),
                      _field(_os, 'Sistema operacional'),
                      _field(_processor, 'Processador'),
                      _field(_ram, 'RAM total GB', number: true),
                      _field(_storage, 'Armazenamento total GB', number: true),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _notes,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Observações técnicas',
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
                        icon: const Icon(Icons.save_outlined),
                        label: Text(_saving ? 'Salvando...' : 'Salvar máquina'),
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
    bool number = false,
  }) {
    return TextField(
      controller: controller,
      keyboardType: number ? TextInputType.text : null,
      inputFormatters: number ? const [BrazilianDecimalInputFormatter()] : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}

class _EquipmentDetailsDialog extends StatefulWidget {
  const _EquipmentDetailsDialog({
    required this.api,
    required this.token,
    required this.equipment,
    required this.clientName,
    required this.canGenerateToken,
  });

  final ApiClient api;
  final String token;
  final Equipment equipment;
  final String clientName;
  final bool canGenerateToken;

  @override
  State<_EquipmentDetailsDialog> createState() =>
      _EquipmentDetailsDialogState();
}

class _EquipmentDetailsDialogState extends State<_EquipmentDetailsDialog> {
  List<MonitoringSnapshot> _snapshots = [];
  List<EquipmentAlert> _alerts = [];
  EquipmentCurrentStatus? _currentStatus;
  late Equipment _equipment = widget.equipment;
  Timer? _refreshTimer;
  DateTime? _lastRefreshAt;
  bool _refreshing = false;
  String? _agentToken;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadRealtimeData();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _loadRealtimeData(silent: true),
    );
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadRealtimeData({bool silent = false}) async {
    if (!silent) {
      setState(() => _refreshing = true);
    }
    try {
      final results = await Future.wait([
        widget.api.listMonitoringSnapshots(widget.token, widget.equipment.id),
        widget.api.listEquipmentAlerts(widget.token, widget.equipment.id),
        widget.api.getEquipmentCurrentStatus(widget.token, widget.equipment.id),
        widget.api.listEquipments(widget.token),
      ]);
      if (!mounted) {
        return;
      }
      final equipments = results[3] as List<Equipment>;
      setState(() {
        _snapshots = results[0] as List<MonitoringSnapshot>;
        _alerts = results[1] as List<EquipmentAlert>;
        _currentStatus = results[2] as EquipmentCurrentStatus?;
        _equipment = equipments.firstWhere(
          (equipment) => equipment.id == widget.equipment.id,
          orElse: () => _equipment,
        );
        _lastRefreshAt = DateTime.now();
      });
    } catch (_) {
      // Histórico vazio não deve impedir abrir os detalhes da máquina.
    } finally {
      if (mounted && !silent) {
        setState(() => _refreshing = false);
      }
    }
  }

  Future<void> _generateToken() async {
    setState(() {
      _error = null;
      _agentToken = null;
    });

    try {
      final result = await widget.api.generateEquipmentAgentToken(
        widget.token,
        widget.equipment.id,
      );
      setState(() => _agentToken = result.token);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final equipment = _equipment;

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 820),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.computer, size: 34),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            equipment.hostname,
                            style: const TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          Text(
                            widget.clientName,
                            style: const TextStyle(color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                    ),
                    IconButton.outlined(
                      tooltip: 'Atualizar agora',
                      onPressed: _refreshing ? null : _loadRealtimeData,
                      icon: _refreshing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _InfoChip('SO', equipment.operatingSystem ?? '-'),
                    _InfoChip('CPU', equipment.processor ?? '-'),
                    _InfoChip('Patrimonio', equipment.assetTag ?? '-'),
                    _InfoChip('Setor/local', equipment.location ?? '-'),
                    _InfoChip('Responsavel', equipment.responsibleUser ?? '-'),
                    _InfoChip('IP local', equipment.lastIpAddress ?? '-'),
                    _InfoChip('Agente', equipment.agentVersion ?? '-'),
                    _InfoChip(
                      'Usuário logado',
                      equipment.lastLoggedUser ?? '-',
                    ),
                    _InfoChip('RAM', '${equipment.ramTotalGb ?? '-'} GB'),
                    _InfoChip(
                      'Armazenamento',
                      '${equipment.storageTotalGb ?? '-'} GB',
                    ),
                    _InfoChip(
                      'Ultima comunicação',
                      equipment.lastSeenAt == null
                          ? 'sem comunicação'
                          : equipment.lastSeenAt!.toLocal().toString(),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _CurrentStatusPanel(
                  status: _currentStatus,
                  lastRefreshAt: _lastRefreshAt,
                ),
                const SizedBox(height: 18),
                if (widget.canGenerateToken)
                  FilledButton.icon(
                    onPressed: _generateToken,
                    icon: const Icon(Icons.vpn_key_outlined),
                    label: const Text('Gerar token para instalar agente'),
                  ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _error!,
                    style: const TextStyle(color: Color(0xFFB91C1C)),
                  ),
                ],
                if (_agentToken != null) ...[
                  const SizedBox(height: 12),
                  SelectableText(
                    _agentToken!,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ],
                const SizedBox(height: 20),
                const Text(
                  'Alertas ativos',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (_alerts.isEmpty)
                  const Text('Nenhum alerta ativo.')
                else
                  for (final alert in _alerts)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(
                        alert.severity == 'critical'
                            ? Icons.error_outline
                            : Icons.warning_amber_outlined,
                        color: alert.severity == 'critical'
                            ? const Color(0xFFB91C1C)
                            : const Color(0xFFA16207),
                      ),
                      title: Text(alert.message),
                      subtitle: Text(alert.createdAt.toLocal().toString()),
                    ),
                const SizedBox(height: 20),
                const Text(
                  'Histórico crítico',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                const Text(
                  'Mantem somente os 3 ultimos registros críticos.',
                  style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
                ),
                const SizedBox(height: 8),
                if (_snapshots.isEmpty)
                  const Text('Nenhum histórico crítico registrado.')
                else
                  for (final snapshot in _snapshots)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        'CPU ${snapshot.cpuUsagePercent}%  RAM ${snapshot.memoryUsagePercent}%  Armazenamento ${snapshot.diskUsagePercent}%',
                      ),
                      subtitle: Text(snapshot.collectedAt.toLocal().toString()),
                    ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CurrentStatusPanel extends StatelessWidget {
  const _CurrentStatusPanel({
    required this.status,
    required this.lastRefreshAt,
  });

  final EquipmentCurrentStatus? status;
  final DateTime? lastRefreshAt;

  @override
  Widget build(BuildContext context) {
    final value = status;
    if (value == null) {
      return const Text('Sem status atual recebido do agente.');
    }

    final statusColor = switch (value.healthStatus) {
      'critical' => const Color(0xFFB91C1C),
      'warning' => const Color(0xFFA16207),
      _ => const Color(0xFF15803D),
    };

    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.sensors, color: statusColor),
                const SizedBox(width: 8),
                Text(
                  'Monitoramento em tempo real',
                  style: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Text(
                  lastRefreshAt == null
                      ? 'sincronizando...'
                      : 'atualizado ${_formatClock(lastRefreshAt!)}',
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _InfoChip('Saude', value.healthStatus),
                _InfoChip('CPU', '${value.cpuUsagePercent}%'),
                _InfoChip('RAM', '${value.memoryUsagePercent}%'),
                _InfoChip('Armazenamento', '${value.diskUsagePercent}%'),
                _InfoChip(
                  'Temp.',
                  value.temperatureCelsius == null
                      ? '-'
                      : '${value.temperatureCelsius} C',
                ),
                _InfoChip('Coleta', _formatDateTime(value.collectedAt)),
              ],
            ),
            if (value.storageVolumes.isNotEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'Unidades de armazenamento',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              for (final volume in value.storageVolumes)
                _StorageVolumeRow(volume: volume),
            ],
          ],
        ),
      ),
    );
  }

  String _formatClock(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  String _formatDateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.day.toString().padLeft(2, '0')}/'
        '${local.month.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }
}

class _StorageVolumeRow extends StatelessWidget {
  const _StorageVolumeRow({required this.volume});

  final StorageVolume volume;

  @override
  Widget build(BuildContext context) {
    final percent = double.tryParse(volume.usagePercent) ?? 0;
    final color = percent >= 90
        ? const Color(0xFFB91C1C)
        : percent >= 80
        ? const Color(0xFFA16207)
        : const Color(0xFF15803D);

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '${volume.mountpoint} ${volume.filesystem ?? ''}'.trim(),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                '${volume.usagePercent}% usado',
                style: TextStyle(color: color, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 4),
          LinearProgressIndicator(
            value: (percent / 100).clamp(0, 1),
            minHeight: 6,
            color: color,
            backgroundColor: const Color(0xFFE2E8F0),
          ),
          const SizedBox(height: 3),
          Text(
            '${volume.usedGb} GB usados de ${volume.totalGb} GB | Livre ${volume.freeGb} GB',
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      side: const BorderSide(color: Color(0xFFCBD5E1)),
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
        final itemWidth = constraints.maxWidth >= 680
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
