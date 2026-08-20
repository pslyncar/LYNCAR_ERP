import 'package:flutter/material.dart';

import '../models/marketplace.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class MasterIntegrationsScreen extends StatefulWidget {
  const MasterIntegrationsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterIntegrationsScreen> createState() =>
      _MasterIntegrationsScreenState();
}

class _MasterIntegrationsScreenState extends State<MasterIntegrationsScreen> {
  late final _api = ApiClient(widget.session.apiBaseUrl);
  MercadoLivreAppConfig? _mercadoLivreConfig;
  bool _loading = true;
  bool _saving = false;
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
      final config = await _api.getMasterMercadoLivreConfig(
        widget.session.token,
      );
      if (mounted) setState(() => _mercadoLivreConfig = config);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openMercadoLivreConfig() async {
    final input = await showDialog<MercadoLivreAppConfigInput>(
      context: context,
      builder: (context) =>
          _MercadoLivreConfigDialog(config: _mercadoLivreConfig),
    );
    if (input == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _api.updateMasterMercadoLivreConfig(
        widget.session.token,
        input,
      );
      if (!mounted) return;
      setState(() => _mercadoLivreConfig = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração Mercado Livre salva.')),
      );
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
                      'Configurações',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    SizedBox(height: 4),
                    Text(
                      'Integrações e credenciais administrativas da plataforma.',
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
          if (_error != null) ...[
            ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    children: [
                      Text(
                        'Marketplaces',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _mercadoLivrePanel(),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _mercadoLivrePanel() {
    final config = _mercadoLivreConfig;
    final configured = config?.configured == true;
    final theme = Theme.of(context);
    return AppCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 760;
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Mercado Livre',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                configured
                    ? 'Aplicação oficial configurada para os clientes autorizados.'
                    : 'Configure a aplicação oficial antes de liberar aos clientes.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (config?.clientId?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text('Client ID: ${config!.clientId}'),
              ],
            ],
          );
          final status = Chip(
            avatar: Icon(
              configured ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
            ),
            label: Text(configured ? 'Configurado' : 'Pendente'),
          );
          final action = FilledButton.icon(
            onPressed: _saving ? null : _openMercadoLivreConfig,
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.settings_outlined),
            label: const Text('Configurar Mercado Livre'),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _marketplaceIcon(theme),
                    const SizedBox(width: 12),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 14),
                Align(alignment: Alignment.centerLeft, child: status),
                const SizedBox(height: 8),
                action,
              ],
            );
          }

          return Row(
            children: [
              _marketplaceIcon(theme),
              const SizedBox(width: 16),
              Expanded(child: details),
              const SizedBox(width: 16),
              status,
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }

  Widget _marketplaceIcon(ThemeData theme) {
    return CircleAvatar(
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
      child: Icon(Icons.storefront, color: theme.colorScheme.primary),
    );
  }
}

class _MercadoLivreConfigDialog extends StatefulWidget {
  const _MercadoLivreConfigDialog({this.config});

  final MercadoLivreAppConfig? config;

  @override
  State<_MercadoLivreConfigDialog> createState() =>
      _MercadoLivreConfigDialogState();
}

class _MercadoLivreConfigDialogState extends State<_MercadoLivreConfigDialog> {
  late final _clientId = TextEditingController(
    text: widget.config?.clientId ?? '',
  );
  late final _clientSecret = TextEditingController();
  late final _redirectUri = TextEditingController(
    text:
        widget.config?.redirectUri ??
        'https://cliente.lyncar.com.br/marketplaces/mercado-livre/callback',
  );
  late final _webhookUrl = TextEditingController(
    text:
        widget.config?.webhookUrl ??
        'https://cliente.lyncar.com.br/marketplaces/mercado-livre/notifications',
  );
  bool _showSecret = false;

  @override
  void dispose() {
    _clientId.dispose();
    _clientSecret.dispose();
    _redirectUri.dispose();
    _webhookUrl.dispose();
    super.dispose();
  }

  String? _emptyToNull(TextEditingController controller) {
    final text = controller.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final hasSecret = widget.config?.clientSecretConfigured == true;
    return AlertDialog(
      title: const Text('Configurar Mercado Livre'),
      content: SizedBox(
        width: 640,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _clientId,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Client ID'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _clientSecret,
                obscureText: !_showSecret,
                decoration: InputDecoration(
                  labelText: 'Client Secret',
                  helperText: hasSecret
                      ? 'Deixe vazio para manter o secret atual.'
                      : null,
                  suffixIcon: IconButton(
                    tooltip: _showSecret ? 'Ocultar' : 'Mostrar',
                    onPressed: () => setState(() => _showSecret = !_showSecret),
                    icon: Icon(
                      _showSecret
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _redirectUri,
                decoration: const InputDecoration(labelText: 'URI de redirect'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _webhookUrl,
                decoration: const InputDecoration(
                  labelText: 'URL de notificações',
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          onPressed: () {
            final clientId = _clientId.text.trim();
            final redirectUri = _redirectUri.text.trim();
            if (clientId.isEmpty || redirectUri.isEmpty) return;
            Navigator.of(context).pop(
              MercadoLivreAppConfigInput(
                clientId: clientId,
                clientSecret: _emptyToNull(_clientSecret),
                redirectUri: redirectUri,
                webhookUrl: _emptyToNull(_webhookUrl),
              ),
            );
          },
          icon: const Icon(Icons.save_outlined),
          label: const Text('Salvar'),
        ),
      ],
    );
  }
}
