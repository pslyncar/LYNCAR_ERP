import 'package:flutter/material.dart';

import '../models/session.dart';
import '../models/web_session_info.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class MasterSecuritySessionsScreen extends StatefulWidget {
  const MasterSecuritySessionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterSecuritySessionsScreen> createState() =>
      _MasterSecuritySessionsScreenState();
}

class _MasterSecuritySessionsScreenState
    extends State<MasterSecuritySessionsScreen> {
  late final _api = ApiClient(widget.session.apiBaseUrl);
  final _searchController = TextEditingController();
  List<WebSessionInfo> _sessions = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sessions = await _api.listMasterWebSessions(widget.session.token);
      if (mounted) setState(() => _sessions = sessions);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(WebSessionInfo session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar dispositivo?'),
        content: Text(
          'O acesso de ${session.companyName} neste dispositivo será encerrado. '
          'A pessoa precisará entrar novamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar acesso'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _api.revokeMasterWebSession(widget.session.token, session.id);
      if (!mounted) return;
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Acesso encerrado com segurança.')),
        );
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    }
  }

  List<WebSessionInfo> get _filteredSessions {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _sessions;
    return _sessions
        .where(
          (item) =>
              item.companyName.toLowerCase().contains(query) ||
              item.companyCode.toLowerCase().contains(query) ||
              _deviceLabel(item.userAgent).toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _filteredSessions;
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
                      'Sessões e dispositivos',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Veja e encerre acessos ativos das empresas com segurança.',
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
          const SizedBox(height: 16),
          AppCard(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.shield_outlined, color: Color(0xFF176B87)),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Esta área é exclusiva para segurança operacional. '
                    'Mostramos somente o necessário: empresa, dispositivo, '
                    'última atividade e um identificador de rede mascarado. '
                    'Nenhum token ou localização precisa é exibido.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: 'Buscar empresa, código ou dispositivo',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                ? ErrorPanel(message: _error!, onRetry: _load)
                : sessions.isEmpty
                ? const Center(child: Text('Nenhuma sessão ativa encontrada.'))
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 18),
                    itemCount: sessions.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _sessionCard(sessions[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _sessionCard(WebSessionInfo session) {
    final device = _deviceLabel(session.userAgent);
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 560;
          final details = Wrap(
            spacing: 18,
            runSpacing: 8,
            children: [
              _detail('Dispositivo', device),
              _detail('Última atividade', _formatDate(session.lastSeenAt)),
              _detail('Rede', session.ipHint ?? 'Não informado'),
            ],
          );
          final action = session.current
              ? const Chip(
                  avatar: Icon(Icons.check, size: 16),
                  label: Text('Este dispositivo'),
                )
              : OutlinedButton.icon(
                  onPressed: () => _revoke(session),
                  icon: const Icon(Icons.logout, size: 18),
                  label: const Text('Encerrar'),
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    device.toLowerCase().contains('celular')
                        ? Icons.smartphone_outlined
                        : Icons.laptop_mac_outlined,
                    color: const Color(0xFF176B87),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          session.companyName,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Text(
                          '${session.companyCode} • ${session.userHint}',
                          style: const TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  if (!compact) action,
                ],
              ),
              const SizedBox(height: 12),
              details,
              if (compact) ...[
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: action),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _detail(String label, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(label, style: const TextStyle(color: Color(0xFF64748B))),
      const SizedBox(height: 2),
      Text(value, style: const TextStyle(fontWeight: FontWeight.w600)),
    ],
  );

  String _deviceLabel(String? userAgent) {
    final value = userAgent ?? '';
    final browser = value.contains('Edg')
        ? 'Edge'
        : value.contains('Chrome')
        ? 'Chrome'
        : value.contains('Firefox')
        ? 'Firefox'
        : value.contains('Safari')
        ? 'Safari'
        : 'Navegador';
    final mobile = value.contains('Mobile') || value.contains('Android');
    return '$browser • ${mobile ? 'Celular' : 'Computador'}';
  }

  String _formatDate(DateTime? value) {
    if (value == null) return 'Não informado';
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} às '
        '${two(local.hour)}:${two(local.minute)}';
  }
}
