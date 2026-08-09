import 'dart:async';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/master_support.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/support_file_actions.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

const _supportModules = {
  'pdv': 'PDV',
  'fiscal': 'Fiscal',
  'produtos': 'Produtos',
  'financeiro': 'Financeiro',
  'relatorios': 'Relatórios',
  'login': 'Login',
  'impressora': 'Impressora',
  'terminal': 'Terminal',
  'outro': 'Outro',
};

const _supportPriorities = {
  'baixa': 'Baixa',
  'normal': 'Normal',
  'alta': 'Alta',
  'urgente': 'Urgente',
};

const _supportStatuses = {
  'aberto': 'Aberto',
  'em_analise': 'Em andamento',
  'aguardando_cliente': 'Aguardando cliente',
  'resolvido': 'Resolvido',
  'fechado': 'Fechado',
};

String _ticketCode(MasterSupportTicket ticket) {
  final date = ticket.createdAt;
  final y = date.year.toString().padLeft(4, '0');
  final m = date.month.toString().padLeft(2, '0');
  final d = date.day.toString().padLeft(2, '0');
  return 'SUP-$y$m$d-${ticket.id.toString().padLeft(5, '0')}';
}

bool _isImageAttachment(String? name, String? url) {
  final value = '${name ?? ''} ${url ?? ''}'.toLowerCase();
  return value.endsWith('.jpg') ||
      value.endsWith('.jpeg') ||
      value.endsWith('.png') ||
      value.endsWith('.webp') ||
      value.endsWith('.gif') ||
      value.contains('.jpg?') ||
      value.contains('.jpeg?') ||
      value.contains('.png?') ||
      value.contains('.webp?') ||
      value.contains('.gif?');
}

class SupportScreen extends StatefulWidget {
  const SupportScreen({super.key, required this.session});

  final Session session;

  @override
  State<SupportScreen> createState() => _SupportScreenState();
}

class _SupportScreenState extends State<SupportScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<MasterSupportTicket> _tickets = [];
  MasterSupportTicket? _selected;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _wsSubscription;
  Timer? _reconnectTimer;
  Timer? _typingStopTimer;
  Timer? _typingHideTimer;
  bool _loading = true;
  String? _error;
  String? _typingLabel;

  bool get _isMaster => widget.session.isMasterCompany;

  String get _authorName => _isMaster ? 'Lyncar' : widget.session.companyName;

  @override
  void initState() {
    super.initState();
    _load();
    _connectRealtime();
  }

  @override
  void dispose() {
    _reconnectTimer?.cancel();
    _typingStopTimer?.cancel();
    _typingHideTimer?.cancel();
    _wsSubscription?.cancel();
    _channel?.sink.close();
    super.dispose();
  }

  Uri _wsUri() {
    final base = Uri.parse(_api.baseUrl);
    final scheme = base.scheme == 'https' ? 'wss' : 'ws';
    final path = _isMaster ? '/master/support/ws' : '/support/ws';
    return base.replace(
      scheme: scheme,
      path: path,
      queryParameters: {'token': widget.session.token},
    );
  }

  void _connectRealtime() {
    _reconnectTimer?.cancel();
    try {
      _channel = WebSocketChannel.connect(_wsUri());
      _wsSubscription = _channel!.stream.listen(
        _handleRealtimeEvent,
        onDone: _scheduleReconnect,
        onError: (_) => _scheduleReconnect(),
      );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _wsSubscription?.cancel();
    _channel = null;
    if (!mounted) return;
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(seconds: 3), _connectRealtime);
  }

  void _handleRealtimeEvent(dynamic raw) {
    if (!mounted) return;
    final data = jsonDecode(raw.toString()) as Map<String, dynamic>;
    final type = data['type']?.toString();
    if (type == 'typing') {
      final ticketId = data['ticket_id'] as int?;
      if (ticketId != _selected?.id) return;
      final payload = (data['payload'] as Map<String, dynamic>?) ?? {};
      final fromMaster = payload['is_master'] as bool? ?? false;
      if (fromMaster == _isMaster) return;
      final typing = payload['typing'] as bool? ?? false;
      setState(() {
        _typingLabel = typing
            ? '${payload['author_name']?.toString() ?? 'A pessoa'} está digitando...'
            : null;
      });
      _typingHideTimer?.cancel();
      if (typing) {
        _typingHideTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _typingLabel = null);
        });
      }
      return;
    }

    if (!{
      'ticket.created',
      'ticket.updated',
      'message.created',
    }.contains(type)) {
      return;
    }
    final payload = data['payload'] as Map<String, dynamic>?;
    if (payload == null) return;
    final ticket = MasterSupportTicket.fromJson(payload);
    setState(() {
      final index = _tickets.indexWhere((item) => item.id == ticket.id);
      if (index >= 0) {
        _tickets[index] = ticket;
      } else {
        _tickets.insert(0, ticket);
      }
      _tickets.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      if (_selected?.id == ticket.id) {
        _selected = ticket;
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tickets = _isMaster
          ? await _api.listMasterSupportTickets(widget.session.token)
          : await _api.listSupportTickets(widget.session.token);
      setState(() {
        _tickets = tickets;
        if (_selected != null) {
          _selected = tickets
              .where((item) => item.id == _selected!.id)
              .firstOrNull;
        }
      });
    } catch (error) {
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openNewTicket() async {
    final input = await showDialog<MasterSupportTicketInput>(
      context: context,
      builder: (context) => const _TicketDialog(),
    );
    if (input == null) return;
    try {
      final created = await _api.createSupportTicket(
        widget.session.token,
        input,
      );
      await _load();
      setState(() => _selected = created);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _reply(MasterSupportTicket ticket, String body) async {
    try {
      final updated = _isMaster
          ? await _api.addMasterSupportMessage(
              widget.session.token,
              ticket.id,
              body,
              status: ticket.status == 'aberto' ? 'em_analise' : null,
            )
          : await _api.addSupportMessage(widget.session.token, ticket.id, body);
      _upsertTicket(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _changeStatus(MasterSupportTicket ticket, String status) async {
    try {
      final updated = await _api.updateMasterSupportTicket(
        widget.session.token,
        ticket.id,
        status: status,
      );
      _upsertTicket(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _toggleCustomerAttachments(MasterSupportTicket ticket) async {
    try {
      final updated = await _api.updateMasterSupportTicket(
        widget.session.token,
        ticket.id,
        customerAttachmentsEnabled: !ticket.customerAttachmentsEnabled,
      );
      _upsertTicket(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _uploadAttachment(
    MasterSupportTicket ticket, {
    required String filename,
    required Uint8List bytes,
    String body = '',
  }) async {
    final canUpload = _isMaster || ticket.customerAttachmentsEnabled;
    if (!canUpload) return;
    try {
      final updated = await _api.uploadSupportAttachment(
        widget.session.token,
        ticket.id,
        filename: filename,
        bytes: bytes,
        body: body,
        master: _isMaster,
      );
      _upsertTicket(updated);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  void _sendTyping(MasterSupportTicket ticket) {
    _channel?.sink.add(
      jsonEncode({
        'type': 'typing',
        'ticket_id': ticket.id,
        'company_code': ticket.companyCode,
        'author_name': _authorName,
        'typing': true,
      }),
    );
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(milliseconds: 1200), () {
      _channel?.sink.add(
        jsonEncode({
          'type': 'typing',
          'ticket_id': ticket.id,
          'company_code': ticket.companyCode,
          'author_name': _authorName,
          'typing': false,
        }),
      );
    });
  }

  void _upsertTicket(MasterSupportTicket ticket) {
    setState(() {
      final index = _tickets.indexWhere((item) => item.id == ticket.id);
      if (index >= 0) {
        _tickets[index] = ticket;
      } else {
        _tickets.insert(0, ticket);
      }
      _tickets.sort((a, b) => b.lastMessageAt.compareTo(a.lastMessageAt));
      _selected = ticket;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(28),
      child: _selected == null
          ? _buildQueue(context)
          : _buildConversation(context),
    );
  }

  Widget _buildQueue(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SupportHeader(
          title: _isMaster ? 'Suporte Lyncar' : 'Suporte',
          subtitle: _isMaster
              ? 'Fila de chamados, atendimento e histórico dos clientes.'
              : 'Abra chamados e acompanhe as respostas da equipe Lyncar.',
          onRefresh: _load,
          onNewTicket: _isMaster ? null : _openNewTicket,
        ),
        const Gap(22),
        if (!_isMaster)
          const _SupportNotice()
        else
          _SupportMetrics(tickets: _tickets),
        const Gap(18),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? ErrorPanel(message: _error!, onRetry: _load)
              : _TicketQueue(
                  tickets: _tickets,
                  onSelect: (ticket) => setState(() => _selected = ticket),
                ),
        ),
      ],
    );
  }

  Widget _buildConversation(BuildContext context) {
    final ticket = _selected!;
    return _TicketConversation(
      ticket: ticket,
      isMaster: _isMaster,
      apiBaseUrl: _api.baseUrl,
      typingLabel: _typingLabel,
      onBack: () => setState(() => _selected = null),
      onReply: _reply,
      onTyping: _sendTyping,
      onUpload: _uploadAttachment,
      onChangeStatus: _changeStatus,
      onToggleCustomerAttachments: _isMaster
          ? _toggleCustomerAttachments
          : null,
    );
  }
}

class _SupportHeader extends StatelessWidget {
  const _SupportHeader({
    required this.title,
    required this.subtitle,
    required this.onRefresh,
    this.onNewTicket,
  });

  final String title;
  final String subtitle;
  final VoidCallback onRefresh;
  final VoidCallback? onNewTicket;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF142033),
                ),
              ),
              const Gap(6),
              Text(
                subtitle,
                style: const TextStyle(color: Color(0xFF60708A), fontSize: 16),
              ),
            ],
          ),
        ),
        IconButton.outlined(
          tooltip: 'Atualizar',
          onPressed: onRefresh,
          icon: const Icon(Icons.refresh),
        ),
        if (onNewTicket != null) ...[
          const Gap(12),
          FilledButton.icon(
            onPressed: onNewTicket,
            icon: const Icon(Icons.add),
            label: const Text('Abrir chamado'),
          ),
        ],
      ],
    );
  }
}

class _SupportNotice extends StatelessWidget {
  const _SupportNotice();

  @override
  Widget build(BuildContext context) {
    return const AppCard(
      child: Row(
        children: [
          Icon(Icons.schedule_outlined, color: Color(0xFF146B83)),
          Gap(12),
          Expanded(
            child: Text(
              'Atendimento em horário comercial. Chamados urgentes são priorizados.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _SupportMetrics extends StatelessWidget {
  const _SupportMetrics({required this.tickets});

  final List<MasterSupportTicket> tickets;

  @override
  Widget build(BuildContext context) {
    final open = tickets.where((item) => item.status != 'fechado').length;
    final urgent = tickets.where((item) => item.priority == 'urgente').length;
    final waiting = tickets
        .where((item) => item.status == 'aguardando_cliente')
        .length;
    return Row(
      children: [
        Expanded(
          child: _MetricCard(label: 'Abertos', value: '$open'),
        ),
        const Gap(12),
        Expanded(
          child: _MetricCard(label: 'Urgentes', value: '$urgent'),
        ),
        const Gap(12),
        Expanded(
          child: _MetricCard(label: 'Aguardando cliente', value: '$waiting'),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          const Icon(Icons.support_agent_outlined, color: Color(0xFF146B83)),
          const Gap(12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Color(0xFF60708A))),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TicketQueue extends StatefulWidget {
  const _TicketQueue({required this.tickets, required this.onSelect});

  final List<MasterSupportTicket> tickets;
  final ValueChanged<MasterSupportTicket> onSelect;

  @override
  State<_TicketQueue> createState() => _TicketQueueState();
}

class _TicketQueueState extends State<_TicketQueue> {
  String _filter = 'ativos';

  List<MasterSupportTicket> get _filteredTickets {
    return widget.tickets.where((ticket) {
      return switch (_filter) {
        'novos' => ticket.status == 'aberto',
        'andamento' => ticket.status == 'em_analise',
        'aguardando' => ticket.status == 'aguardando_cliente',
        'concluidos' =>
          ticket.status == 'resolvido' || ticket.status == 'fechado',
        'todos' => true,
        _ => ticket.status != 'resolvido' && ticket.status != 'fechado',
      };
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.tickets.isEmpty) {
      return const AppCard(
        child: Center(child: Text('Nenhum chamado aberto.')),
      );
    }
    final tickets = _filteredTickets;
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'ativos', label: Text('Ativos')),
              ButtonSegment(
                value: 'novos',
                label: Text('Aguardando atendimento'),
              ),
              ButtonSegment(value: 'andamento', label: Text('Em andamento')),
              ButtonSegment(
                value: 'aguardando',
                label: Text('Aguardando cliente'),
              ),
              ButtonSegment(value: 'concluidos', label: Text('Concluídos')),
              ButtonSegment(value: 'todos', label: Text('Todos')),
            ],
            selected: {_filter},
            onSelectionChanged: (values) {
              setState(() => _filter = values.single);
            },
          ),
        ),
        const Gap(12),
        Expanded(
          child: AppCard(
            padding: EdgeInsets.zero,
            child: tickets.isEmpty
                ? const Center(child: Text('Nenhum chamado nesta aba.'))
                : ListView.separated(
                    itemCount: tickets.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final ticket = tickets[index];
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        leading: CircleAvatar(
                          child: Text(ticket.id.toString().padLeft(2, '0')),
                        ),
                        title: Row(
                          children: [
                            Text(
                              _ticketCode(ticket),
                              style: const TextStyle(
                                color: Color(0xFF146B83),
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const Gap(10),
                            Expanded(
                              child: Text(
                                ticket.subject,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        subtitle: Text(
                          '${ticket.companyName} - ${ticket.messages.length} mensagem(ns)',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Wrap(
                          spacing: 8,
                          children: [
                            _StatusChip(status: ticket.status),
                            _PriorityChip(priority: ticket.priority),
                            const Icon(Icons.chevron_right),
                          ],
                        ),
                        onTap: () => widget.onSelect(ticket),
                      );
                    },
                  ),
          ),
        ),
      ],
    );
  }
}

class _SendMessageIntent extends Intent {
  const _SendMessageIntent();
}

class _TicketConversation extends StatefulWidget {
  const _TicketConversation({
    required this.ticket,
    required this.isMaster,
    required this.apiBaseUrl,
    required this.typingLabel,
    required this.onBack,
    required this.onReply,
    required this.onTyping,
    required this.onUpload,
    required this.onChangeStatus,
    this.onToggleCustomerAttachments,
  });

  final MasterSupportTicket ticket;
  final bool isMaster;
  final String apiBaseUrl;
  final String? typingLabel;
  final VoidCallback onBack;
  final Future<void> Function(MasterSupportTicket ticket, String body) onReply;
  final void Function(MasterSupportTicket ticket) onTyping;
  final Future<void> Function(
    MasterSupportTicket ticket, {
    required String filename,
    required Uint8List bytes,
    String body,
  })
  onUpload;
  final Future<void> Function(MasterSupportTicket ticket, String status)
  onChangeStatus;
  final Future<void> Function(MasterSupportTicket ticket)?
  onToggleCustomerAttachments;

  @override
  State<_TicketConversation> createState() => _TicketConversationState();
}

class _TicketConversationState extends State<_TicketConversation> {
  final _reply = TextEditingController();
  final _scroll = ScrollController();
  PlatformFile? _pendingFile;
  bool _sending = false;

  bool get _canUpload =>
      widget.isMaster || widget.ticket.customerAttachmentsEnabled;

  List<MasterSupportMessage> get _attachments => widget.ticket.messages
      .where((message) => message.attachmentUrl?.isNotEmpty == true)
      .toList();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _ensureBottom(jump: true),
    );
  }

  @override
  void didUpdateWidget(covariant _TicketConversation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ticket.id != widget.ticket.id ||
        oldWidget.ticket.messages.length != widget.ticket.messages.length) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _ensureBottom(jump: oldWidget.ticket.id != widget.ticket.id),
      );
    }
  }

  @override
  void dispose() {
    _reply.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _pickAttachment() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.any,
      withData: true,
    );
    final file = picked?.files.single;
    if (file == null) return;
    if (file.bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Não foi possível ler o arquivo selecionado.'),
        ),
      );
      return;
    }
    setState(() => _pendingFile = file);
  }

  Future<void> _sendCurrent() async {
    if (_sending) return;
    final text = _reply.text.trim();
    final file = _pendingFile;
    if (text.isEmpty && file == null) return;
    setState(() => _sending = true);
    try {
      if (file != null) {
        final bytes = file.bytes;
        if (bytes == null) return;
        await widget.onUpload(
          widget.ticket,
          filename: file.name,
          bytes: bytes,
          body: text,
        );
      } else {
        await widget.onReply(widget.ticket, text);
      }
      _reply.clear();
      if (mounted) setState(() => _pendingFile = null);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _ensureBottom({bool jump = false}) {
    _scrollToBottom(jump: jump);
    for (final delay in const [
      Duration(milliseconds: 80),
      Duration(milliseconds: 220),
      Duration(milliseconds: 520),
    ]) {
      Future.delayed(delay, () {
        if (!mounted) return;
        _scrollToBottom(jump: true);
      });
    }
  }

  void _scrollToBottom({bool jump = false}) {
    if (!_scroll.hasClients) return;
    final target = _scroll.position.maxScrollExtent;
    if (jump) {
      _scroll.jumpTo(target);
      return;
    }
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  Future<void> _openAttachment(String url) async {
    final uri = _attachmentUri(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não foi possível abrir o arquivo.')),
      );
    }
  }

  Future<void> _previewImage(MasterSupportMessage message) async {
    final url = message.attachmentUrl;
    if (url == null || url.isEmpty) return;
    await showDialog<void>(
      context: context,
      builder: (context) {
        final uri = _attachmentUri(url);
        return Dialog.fullscreen(
          backgroundColor: const Color(0xF0142033),
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.6,
                  maxScale: 4,
                  child: Image.network(
                    uri.toString(),
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Text(
                      'Não foi possível carregar a imagem.',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 24,
                right: 24,
                child: Row(
                  children: [
                    FilledButton.tonalIcon(
                      onPressed: () => _downloadAttachment(message),
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Baixar'),
                    ),
                    const Gap(10),
                    IconButton.filledTonal(
                      tooltip: 'Fechar',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _downloadAttachment(MasterSupportMessage message) async {
    final url = message.attachmentUrl;
    if (url == null || url.isEmpty) return;
    try {
      await downloadSupportFile(
        _attachmentUri(url),
        message.attachmentName ?? 'arquivo',
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível baixar o arquivo: $error')),
      );
    }
  }

  Uri _attachmentUri(String url) {
    final parsed = Uri.parse(url);
    if (parsed.hasScheme) return parsed;
    final base = Uri.parse(widget.apiBaseUrl);
    return base.resolve(url.startsWith('/') ? url.substring(1) : url);
  }

  @override
  Widget build(BuildContext context) {
    final ticket = widget.ticket;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            IconButton.outlined(
              tooltip: 'Voltar',
              onPressed: widget.onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_ticketCode(ticket)} ${ticket.subject}',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const Gap(4),
                  Text(
                    '${ticket.companyName} • Atendente: ${ticket.assignedMasterUserName ?? 'Não iniciado'}',
                    style: const TextStyle(color: Color(0xFF60708A)),
                  ),
                ],
              ),
            ),
            if (widget.isMaster)
              DropdownButton<String>(
                value: ticket.status,
                items: _supportStatuses.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) widget.onChangeStatus(ticket, value);
                },
              )
            else
              _StatusChip(status: ticket.status),
          ],
        ),
        const Gap(14),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            Chip(label: Text(_supportModules[ticket.module] ?? ticket.module)),
            _PriorityChip(priority: ticket.priority),
            if (ticket.customerAttachmentsEnabled)
              const Chip(
                avatar: Icon(Icons.attach_file, size: 18),
                label: Text('Cliente pode anexar'),
              ),
            if (widget.isMaster)
              ActionChip(
                avatar: Icon(
                  ticket.customerAttachmentsEnabled
                      ? Icons.lock_open_outlined
                      : Icons.lock_outline,
                ),
                label: Text(
                  ticket.customerAttachmentsEnabled
                      ? 'Bloquear anexos do cliente'
                      : 'Liberar anexos do cliente',
                ),
                onPressed: () =>
                    widget.onToggleCustomerAttachments?.call(ticket),
              ),
          ],
        ),
        const Gap(14),
        Expanded(
          child: Row(
            children: [
              Expanded(
                flex: 3,
                child: AppCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      Expanded(
                        child: ListView.separated(
                          controller: _scroll,
                          padding: const EdgeInsets.all(18),
                          itemCount: ticket.messages.length,
                          separatorBuilder: (_, _) => const Gap(10),
                          itemBuilder: (context, index) {
                            return _MessageBubble(
                              message: ticket.messages[index],
                              attachmentUri: _attachmentUri,
                              onOpenAttachment: _openAttachment,
                              onPreviewImage: _previewImage,
                              onDownloadAttachment: _downloadAttachment,
                              onImageLoaded: () => _ensureBottom(jump: true),
                            );
                          },
                        ),
                      ),
                      if (widget.typingLabel != null)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              widget.typingLabel!,
                              style: const TextStyle(
                                color: Color(0xFF60708A),
                                fontStyle: FontStyle.italic,
                              ),
                            ),
                          ),
                        ),
                      const Divider(height: 1),
                      Padding(
                        padding: const EdgeInsets.all(14),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            IconButton.outlined(
                              tooltip: _canUpload
                                  ? 'Anexar arquivo'
                                  : 'Anexo liberado pelo suporte',
                              onPressed: _canUpload ? _pickAttachment : null,
                              icon: const Icon(Icons.attach_file),
                            ),
                            const Gap(10),
                            Expanded(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (_pendingFile != null) ...[
                                    InputChip(
                                      avatar: const Icon(Icons.attach_file),
                                      label: Text(_pendingFile!.name),
                                      onDeleted: () {
                                        setState(() => _pendingFile = null);
                                      },
                                    ),
                                    const Gap(8),
                                  ],
                                  Shortcuts(
                                    shortcuts: const {
                                      SingleActivator(LogicalKeyboardKey.enter):
                                          _SendMessageIntent(),
                                    },
                                    child: Actions(
                                      actions: {
                                        _SendMessageIntent:
                                            CallbackAction<_SendMessageIntent>(
                                              onInvoke: (_) {
                                                _sendCurrent();
                                                return null;
                                              },
                                            ),
                                      },
                                      child: TextField(
                                        controller: _reply,
                                        minLines: 1,
                                        maxLines: 4,
                                        textInputAction: TextInputAction.send,
                                        onChanged: (_) =>
                                            widget.onTyping(ticket),
                                        onSubmitted: (_) => _sendCurrent(),
                                        decoration: const InputDecoration(
                                          hintText: 'Escreva uma resposta',
                                          border: OutlineInputBorder(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Gap(10),
                            FilledButton.icon(
                              onPressed: _sending ? null : _sendCurrent,
                              icon: _sending
                                  ? const SizedBox.square(
                                      dimension: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.send_outlined),
                              label: const Text('Enviar'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const Gap(16),
              SizedBox(
                width: 330,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Arquivos do chamado',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Gap(10),
                      Expanded(
                        child: _attachments.isEmpty
                            ? const Center(
                                child: Text('Nenhum arquivo enviado.'),
                              )
                            : ListView.separated(
                                itemCount: _attachments.length,
                                separatorBuilder: (_, _) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final file = _attachments[index];
                                  return ListTile(
                                    contentPadding: EdgeInsets.zero,
                                    leading: const Icon(
                                      Icons.insert_drive_file_outlined,
                                    ),
                                    title: Text(
                                      file.attachmentName ?? 'Arquivo',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(file.authorName ?? ''),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          tooltip: 'Abrir',
                                          onPressed: () {
                                            final url = file.attachmentUrl;
                                            if (url != null && url.isNotEmpty) {
                                              _openAttachment(url);
                                            }
                                          },
                                          icon: const Icon(
                                            Icons.open_in_new,
                                            size: 18,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Baixar',
                                          onPressed: () =>
                                              _downloadAttachment(file),
                                          icon: const Icon(
                                            Icons.download_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ],
                                    ),
                                    onTap: () {
                                      final url = file.attachmentUrl;
                                      if (url != null && url.isNotEmpty) {
                                        _openAttachment(url);
                                      }
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.attachmentUri,
    required this.onOpenAttachment,
    required this.onPreviewImage,
    required this.onDownloadAttachment,
    required this.onImageLoaded,
  });

  final MasterSupportMessage message;
  final Uri Function(String url) attachmentUri;
  final ValueChanged<String> onOpenAttachment;
  final ValueChanged<MasterSupportMessage> onPreviewImage;
  final Future<void> Function(MasterSupportMessage message)
  onDownloadAttachment;
  final VoidCallback onImageLoaded;

  @override
  Widget build(BuildContext context) {
    final master = message.authorType == 'master';
    final system = message.authorType == 'sistema';
    final hasImage = _isImageAttachment(
      message.attachmentName,
      message.attachmentUrl,
    );
    return Align(
      alignment: system
          ? Alignment.center
          : master
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: system
                ? const Color(0xFFEFF4FA)
                : master
                ? const Color(0xFFE8F7FB)
                : const Color(0xFFF3F6FA),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFFD8E3F0)),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.authorName ?? (master ? 'Lyncar' : 'Cliente'),
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                const Gap(6),
                Text(message.body),
                if (message.attachmentUrl?.isNotEmpty == true) ...[
                  const Gap(10),
                  if (hasImage)
                    InkWell(
                      onTap: () => onPreviewImage(message),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.network(
                          attachmentUri(message.attachmentUrl!).toString(),
                          width: 360,
                          height: 220,
                          fit: BoxFit.cover,
                          frameBuilder:
                              (context, child, frame, wasSynchronouslyLoaded) {
                                if (frame != null || wasSynchronouslyLoaded) {
                                  WidgetsBinding.instance.addPostFrameCallback((
                                    _,
                                  ) {
                                    onImageLoaded();
                                  });
                                }
                                return child;
                              },
                          errorBuilder: (_, _, _) => const SizedBox(
                            width: 360,
                            height: 120,
                            child: Center(
                              child: Text(
                                'Não foi possível carregar a imagem.',
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  const Gap(8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          if (hasImage) {
                            onPreviewImage(message);
                          } else {
                            onOpenAttachment(message.attachmentUrl!);
                          }
                        },
                        icon: const Icon(Icons.open_in_new),
                        label: Text(
                          hasImage
                              ? 'Abrir imagem'
                              : (message.attachmentName ?? 'Abrir arquivo'),
                        ),
                      ),
                      PopupMenuButton<String>(
                        tooltip: 'Opcoes do arquivo',
                        icon: const Icon(Icons.more_vert),
                        onSelected: (value) {
                          if (value == 'download') {
                            onDownloadAttachment(message);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: 'download',
                            child: ListTile(
                              leading: Icon(Icons.download_outlined),
                              title: Text('Baixar arquivo'),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PriorityChip extends StatelessWidget {
  const _PriorityChip({required this.priority});

  final String priority;

  @override
  Widget build(BuildContext context) {
    final color = switch (priority) {
      'urgente' => const Color(0xFFB42318),
      'alta' => const Color(0xFFC2410C),
      'baixa' => const Color(0xFF475467),
      _ => const Color(0xFF146B83),
    };
    return Chip(
      label: Text(_supportPriorities[priority] ?? priority),
      labelStyle: TextStyle(color: color, fontWeight: FontWeight.w800),
      backgroundColor: color.withValues(alpha: 0.08),
      side: BorderSide(color: color.withValues(alpha: 0.18)),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});

  final String status;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text(_supportStatuses[status] ?? status));
  }
}

class _TicketDialog extends StatefulWidget {
  const _TicketDialog();

  @override
  State<_TicketDialog> createState() => _TicketDialogState();
}

class _TicketDialogState extends State<_TicketDialog> {
  final _formKey = GlobalKey<FormState>();
  final _subject = TextEditingController();
  final _description = TextEditingController();
  String _module = 'pdv';
  String _priority = 'normal';

  @override
  void dispose() {
    _subject.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Abrir chamado'),
      content: SizedBox(
        width: 560,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _module,
                decoration: const InputDecoration(labelText: 'Módulo'),
                items: _supportModules.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _module = value ?? 'outro'),
              ),
              const Gap(12),
              DropdownButtonFormField<String>(
                initialValue: _priority,
                decoration: const InputDecoration(labelText: 'Prioridade'),
                items: _supportPriorities.entries
                    .map(
                      (entry) => DropdownMenuItem(
                        value: entry.key,
                        child: Text(entry.value),
                      ),
                    )
                    .toList(),
                onChanged: (value) =>
                    setState(() => _priority = value ?? 'normal'),
              ),
              const Gap(12),
              TextFormField(
                controller: _subject,
                decoration: const InputDecoration(labelText: 'Assunto'),
                validator: (value) => (value ?? '').trim().length < 3
                    ? 'Informe o assunto.'
                    : null,
              ),
              const Gap(12),
              TextFormField(
                controller: _description,
                minLines: 4,
                maxLines: 6,
                decoration: const InputDecoration(labelText: 'Descrição'),
                validator: (value) => (value ?? '').trim().length < 5
                    ? 'Descreva o problema.'
                    : null,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            if (!_formKey.currentState!.validate()) return;
            Navigator.pop(
              context,
              MasterSupportTicketInput(
                module: _module,
                priority: _priority,
                subject: _subject.text.trim(),
                description: _description.text.trim(),
              ),
            );
          },
          icon: const Icon(Icons.add),
          label: const Text('Abrir chamado'),
        ),
      ],
    );
  }
}
