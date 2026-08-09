import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../models/master_access_status.dart';
import '../models/session.dart';
import '../services/api_client.dart';

class MasterAccessScreen extends StatefulWidget {
  const MasterAccessScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterAccessScreen> createState() => _MasterAccessScreenState();
}

class _MasterAccessScreenState extends State<MasterAccessScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  MasterAccessStatus? _status;
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
      final status = await _api.getMasterAccessStatus(widget.session.token);
      if (!mounted) return;
      setState(() => _status = status);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<MasterCompanyAccessStatus> get _filteredItems {
    final items = _status?.items ?? const <MasterCompanyAccessStatus>[];
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return items;
    return items.where((item) {
      return item.companyName.toLowerCase().contains(query) ||
          item.companyCode.toLowerCase().contains(query) ||
          item.plan.toLowerCase().contains(query);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final status = _status;
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(22),
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
                          'Acessos',
                          style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Gap(4),
                        Text(
                          'Clientes online e primeiro acesso das empresas',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton.outlined(
                    onPressed: _loading ? null : _load,
                    icon: const Icon(Icons.refresh),
                    tooltip: 'Atualizar',
                  ),
                ],
              ),
              const Gap(18),
              if (status != null) _SummaryGrid(status: status),
              const Gap(14),
              TextField(
                controller: _search,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'Buscar por cliente, subdominio ou plano',
                ),
              ),
              const Gap(14),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _error != null
                    ? _ErrorState(message: _error!, onRetry: _load)
                    : _AccessList(items: _filteredItems),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({required this.status});

  final MasterAccessStatus status;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 1000
            ? 4
            : width >= 680
            ? 2
            : 1;
        return GridView.count(
          crossAxisCount: columns,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          childAspectRatio: columns == 1 ? 5.2 : 3.6,
          physics: const NeverScrollableScrollPhysics(),
          children: [
            _SummaryCard(
              label: 'Empresas online',
              value: '${status.onlineCompanies}',
              icon: Icons.wifi_tethering,
              color: const Color(0xFF059669),
            ),
            _SummaryCard(
              label: 'Usuarios online',
              value: '${status.onlineUsers}',
              icon: Icons.people_alt_outlined,
              color: const Color(0xFF0A66D8),
            ),
            _SummaryCard(
              label: 'Primeiro acesso feito',
              value: '${status.firstAccessCompletedCompanies}',
              icon: Icons.verified_user_outlined,
              color: const Color(0xFF7C3AED),
            ),
            _SummaryCard(
              label: 'Pendentes',
              value: '${status.pendingFirstAccessCompanies}',
              icon: Icons.warning_amber_outlined,
              color: const Color(0xFFF97316),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String label;
  final String value;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDCE5F2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.12),
              foregroundColor: color,
              child: Icon(icon),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
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

class _AccessList extends StatelessWidget {
  const _AccessList({required this.items});

  final List<MasterCompanyAccessStatus> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return const Center(child: Text('Nenhuma empresa encontrada.'));
    }
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) => const Gap(10),
      itemBuilder: (context, index) => _CompanyAccessCard(item: items[index]),
    );
  }
}

class _CompanyAccessCard extends StatelessWidget {
  const _CompanyAccessCard({required this.item});

  final MasterCompanyAccessStatus item;

  @override
  Widget build(BuildContext context) {
    final onlineColor = item.online
        ? const Color(0xFF059669)
        : const Color(0xFF94A3B8);
    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Color(0xFFDCE5F2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.companyName,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                _StatusPill(
                  label: item.online ? 'Online' : 'Offline',
                  color: onlineColor,
                  icon: item.online ? Icons.circle : Icons.circle_outlined,
                ),
              ],
            ),
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                Chip(label: Text(item.companyCode)),
                Chip(label: Text(item.plan.toUpperCase())),
                Chip(label: Text('${item.activeUsers} usuario(s) ativo(s)')),
                _StatusPill(
                  label: item.firstAccessCompleted
                      ? 'Primeiro acesso feito'
                      : 'Primeiro acesso pendente',
                  color: item.firstAccessCompleted
                      ? const Color(0xFF059669)
                      : const Color(0xFFF97316),
                  icon: item.firstAccessCompleted
                      ? Icons.check_circle_outline
                      : Icons.schedule,
                ),
              ],
            ),
            const Gap(10),
            Text(
              'Senha provisoria pendente: ${item.pendingFirstAccessUsers} • Senha ja alterada: ${item.changedPasswordUsers}',
              style: const TextStyle(color: Color(0xFF475569)),
            ),
            if (item.lastSeenAt != null) ...[
              const Gap(4),
              Text(
                'Ultima atividade: ${_formatDateTime(item.lastSeenAt!)}',
                style: const TextStyle(color: Color(0xFF64748B)),
              ),
            ],
            if (item.usersOnlineDetails.isNotEmpty) ...[
              const Gap(10),
              const Divider(),
              const Gap(6),
              ...item.usersOnlineDetails.map(
                (user) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.person_outline,
                        size: 18,
                        color: Color(0xFF0A66D8),
                      ),
                      const Gap(8),
                      Expanded(
                        child: Text(
                          '${user.name} • ${user.email} • ${user.clientType}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (user.lastSeenAt != null)
                        Text(
                          _formatTime(user.lastSeenAt!),
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (item.accessError != null && item.accessError!.isNotEmpty) ...[
              const Gap(10),
              Text(
                'Nao foi possivel ler usuarios do banco: ${item.accessError}',
                style: const TextStyle(color: Color(0xFFB45309)),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.color,
    required this.icon,
  });

  final String label;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const Gap(6),
          Text(
            label,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, size: 42, color: Color(0xFFDC2626)),
          const Gap(10),
          const Text(
            'Nao foi possivel carregar os acessos.',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const Gap(6),
          Text(message, textAlign: TextAlign.center),
          const Gap(14),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Tentar novamente'),
          ),
        ],
      ),
    );
  }
}

String _formatDateTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.day)}/${_two(local.month)}/${local.year} ${_two(local.hour)}:${_two(local.minute)}';
}

String _formatTime(DateTime value) {
  final local = value.toLocal();
  return '${_two(local.hour)}:${_two(local.minute)}';
}

String _two(int value) => value.toString().padLeft(2, '0');
