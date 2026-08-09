import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/session.dart';
import '../models/website_contact_request.dart';
import '../services/api_client.dart';
import '../widgets/error_panel.dart';

class MasterWebsiteContactsScreen extends StatefulWidget {
  const MasterWebsiteContactsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterWebsiteContactsScreen> createState() =>
      _MasterWebsiteContactsScreenState();
}

class _MasterWebsiteContactsScreenState
    extends State<MasterWebsiteContactsScreen> {
  static const _statuses = <String, String>{
    '': 'Todos',
    'new': 'Novos',
    'in_progress': 'Em atendimento',
    'contacted': 'Contatados',
    'closed': 'Encerrados',
  };

  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _searchController = TextEditingController();
  Timer? _searchTimer;
  List<WebsiteContactRequest> _requests = [];
  String _filter = '';
  String? _error;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchTimer?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final requests = await _api.listMasterContactRequests(
        widget.session.token,
        status: _filter,
        search: _searchController.text,
      );
      if (mounted) setState(() => _requests = requests);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _changeStatus(
    WebsiteContactRequest request,
    String status,
  ) async {
    try {
      await _api.updateMasterContactRequestStatus(
        widget.session.token,
        request.id,
        status,
      );
      await _load();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  String _digits(String value) => value.replaceAll(RegExp(r'\D'), '');

  Future<void> _openWhatsApp(WebsiteContactRequest request) async {
    final phone = _digits(request.phone);
    final number = phone.startsWith('55') ? phone : '55$phone';
    final text = Uri.encodeComponent(
      'Olá, ${request.name}. Recebemos seu contato pelo site da Lyncar.',
    );
    await launchUrl(
      Uri.parse('https://wa.me/$number?text=$text'),
      mode: LaunchMode.externalApplication,
    );
  }

  String _date(DateTime value) {
    final local = value.toLocal();
    String two(int number) => number.toString().padLeft(2, '0');
    return '${two(local.day)}/${two(local.month)}/${local.year} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final newCount = _requests.where((item) => item.status == 'new').length;
    final progressCount = _requests
        .where((item) => item.status == 'in_progress')
        .length;
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
                      'Contatos do site',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Solicitações comerciais recebidas pelo site institucional.',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                onPressed: _loading ? null : _load,
                tooltip: 'Atualizar',
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _Summary(
                label: 'Novos',
                value: newCount,
                icon: Icons.mark_email_unread_outlined,
              ),
              _Summary(
                label: 'Em atendimento',
                value: progressCount,
                icon: Icons.support_agent_outlined,
              ),
              _Summary(
                label: 'Na lista',
                value: _requests.length,
                icon: Icons.contacts_outlined,
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _searchController,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              labelText: 'Buscar por nome, empresa, telefone ou e-mail',
            ),
            onChanged: (_) {
              _searchTimer?.cancel();
              _searchTimer = Timer(const Duration(milliseconds: 350), _load);
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _statuses.entries.map((entry) {
              return ChoiceChip(
                label: Text(entry.value),
                selected: _filter == entry.key,
                onSelected: (_) {
                  setState(() => _filter = entry.key);
                  _load();
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 14),
          Expanded(child: _body()),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return ErrorPanel(message: _error!, onRetry: _load);
    if (_requests.isEmpty) {
      return const Center(child: Text('Nenhum contato encontrado.'));
    }
    return ListView.separated(
      itemCount: _requests.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final request = _requests[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final details = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if ((request.companyName ?? '').isNotEmpty)
                      Text(
                        request.companyName!,
                        style: const TextStyle(color: Color(0xFF64748B)),
                      ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 14,
                      runSpacing: 6,
                      children: [
                        Text(request.phone),
                        if ((request.email ?? '').isNotEmpty)
                          Text(request.email!),
                        Text(_date(request.createdAt)),
                      ],
                    ),
                    if ((request.message ?? '').isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(request.message!),
                    ],
                  ],
                );
                final actions = Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    IconButton.outlined(
                      onPressed: () => _openWhatsApp(request),
                      tooltip: 'Abrir WhatsApp',
                      icon: const Icon(Icons.chat_outlined),
                    ),
                    DropdownButton<String>(
                      value: request.status,
                      items: _statuses.entries
                          .where((entry) => entry.key.isNotEmpty)
                          .map(
                            (entry) => DropdownMenuItem(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) _changeStatus(request, value);
                      },
                    ),
                  ],
                );
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [details, const SizedBox(height: 12), actions],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: details),
                    const SizedBox(width: 16),
                    actions,
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final int value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF0E7490)),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: const TextStyle(color: Color(0xFF64748B))),
                  Text(
                    '$value',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
