import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/session.dart';
import '../models/stock_entry.dart';
import '../services/api_client.dart';

class XmlInboxScreen extends StatefulWidget {
  const XmlInboxScreen({super.key, required this.session});

  final Session session;

  @override
  State<XmlInboxScreen> createState() => _XmlInboxScreenState();
}

class _XmlInboxScreenState extends State<XmlInboxScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<XmlInboxMessage> _messages = const [];
  XmlInboxSettings? _settings;
  bool _loading = true;
  String? _error;
  int? _working;

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
      final messages = await _api.listXmlInboxMessages(widget.session.token);
      XmlInboxSettings? settings;
      try {
        settings = await _api.getXmlInboxSettings(widget.session.token);
      } on ApiException {
        // A listagem continua disponível mesmo quando a empresa ainda não tem
        // um endereço de recebimento configurado.
      }
      if (mounted) {
        setState(() {
          _messages = messages;
          _settings = settings;
          _loading = false;
        });
      }
    } on ApiException catch (error) {
      if (mounted) {
        setState(() {
          _error = error.message;
          _loading = false;
        });
      }
    }
  }

  Future<void> _generate(XmlInboxMessage message) async {
    setState(() => _working = message.id);
    try {
      final entry = await _api.createReceiptFromXmlInbox(
        widget.session.token,
        message.id,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Entrada #${entry.id} criada.')));
        _load();
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.message)));
      }
    } finally {
      if (mounted) setState(() => _working = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xfff6f8fb),
      appBar: AppBar(
        title: const Text('Caixa de XML'),
        backgroundColor: const Color(0xfff6f8fb),
        foregroundColor: const Color(0xff172b4d),
        elevation: 0,
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Card(
              elevation: 0,
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'Notas recebidas por e-mail',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff172b4d),
                      ),
                    ),
                    const SizedBox(height: 6),
                    const Text(
                      'Visualize os XMLs que chegaram à caixa configurada e gere o recebimento somente depois de conferir o documento.',
                      style: TextStyle(color: Color(0xff64748b)),
                    ),
                    if (_settings != null) ...[
                      const SizedBox(height: 18),
                      _emailAddressCard(_settings!),
                    ],
                    const Divider(height: 28),
                    Expanded(child: _body()),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emailAddressCard(XmlInboxSettings settings) {
    final color = settings.enabled
        ? const Color(0xff087f5b)
        : const Color(0xffb42318);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xfff0f7ff),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xffc7dcf4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.alternate_email_outlined, color: Color(0xff176b80)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Envie os XMLs para este e-mail',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                SelectableText(
                  settings.emailAddress,
                  style: const TextStyle(
                    color: Color(0xff0f4c5c),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  settings.enabled
                      ? 'Os XMLs recebidos aparecerão nesta caixa para conferência.'
                      : 'O recebimento por e-mail está desativado para esta empresa.',
                  style: TextStyle(color: color, fontSize: 12),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Copiar e-mail',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(text: settings.emailAddress),
              );
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('E-mail da Caixa de XML copiado.'),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Text(_error!, style: const TextStyle(color: Color(0xffb42318))),
      );
    }
    if (_messages.isEmpty) {
      return const Center(child: Text('Nenhum XML recebido pendente.'));
    }
    return ListView.separated(
      itemCount: _messages.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, index) {
        final message = _messages[index];
        final imported = message.imported;
        return ListTile(
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          leading: Icon(
            imported ? Icons.check_circle_outline : Icons.receipt_long_outlined,
            color: imported ? const Color(0xff087f5b) : const Color(0xff176b80),
          ),
          title: Text(
            message.invoiceNumber == null
                ? 'Nota recebida'
                : 'NF ${message.invoiceNumber}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          subtitle: Text(
            '${message.supplierName ?? 'Fornecedor não identificado'} • ${message.subject ?? 'XML recebido'}',
          ),
          trailing: imported
              ? const Chip(label: Text('Gerado'))
              : FilledButton(
                  onPressed: _working == message.id
                      ? null
                      : () => _generate(message),
                  child: _working == message.id
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Gerar recebimento'),
                ),
        );
      },
    );
  }
}
