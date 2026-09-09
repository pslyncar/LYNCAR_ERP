import 'package:flutter/material.dart';

import '../models/marketplace.dart';
import '../models/master_email_setting.dart';
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
  MasterEmailSetting? _emailConfig;
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
      final emailConfig = await _api.getMasterEmailSetting(
        widget.session.token,
      );
      if (mounted) {
        setState(() {
          _mercadoLivreConfig = config;
          _emailConfig = emailConfig;
        });
      }
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

  Future<void> _openEmailConfig() async {
    final input = await showDialog<MasterEmailSettingInput>(
      context: context,
      builder: (context) => _MasterEmailConfigDialog(config: _emailConfig),
    );
    if (input == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await _api.updateMasterEmailSetting(
        widget.session.token,
        input,
      );
      if (!mounted) return;
      setState(() => _emailConfig = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Configuração de e-mail salva.')),
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
                      const SizedBox(height: 24),
                      Text(
                        'Comunicação e segurança',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 10),
                      _emailPanel(),
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

  Widget _emailPanel() {
    final config = _emailConfig;
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
                'E-mail para recuperação de senha',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                configured
                    ? 'Canal configurado para enviar códigos de recuperação.'
                    : 'Configure o canal que será usado no esqueci minha senha.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (config?.fromEmail?.isNotEmpty == true) ...[
                const SizedBox(height: 6),
                Text('Remetente: ${config!.fromEmail}'),
              ],
              const SizedBox(height: 8),
              Text(
                'As credenciais ficam protegidas e nunca são exibidas novamente.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final status = Chip(
            avatar: Icon(
              configured ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
            ),
            label: Text(configured ? 'Pronto' : 'Pendente'),
          );
          final action = FilledButton.icon(
            onPressed: _saving ? null : _openEmailConfig,
            icon: const Icon(Icons.mail_outline),
            label: const Text('Configurar e-mail'),
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
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
              Icon(
                Icons.mark_email_read_outlined,
                color: theme.colorScheme.primary,
                size: 34,
              ),
              const SizedBox(width: 16),
              Expanded(child: details),
              status,
              const SizedBox(width: 16),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _MasterEmailConfigDialog extends StatefulWidget {
  const _MasterEmailConfigDialog({this.config});

  final MasterEmailSetting? config;

  @override
  State<_MasterEmailConfigDialog> createState() =>
      _MasterEmailConfigDialogState();
}

class _MasterEmailConfigDialogState extends State<_MasterEmailConfigDialog> {
  late final _host = TextEditingController(
    text: widget.config?.smtpHost ?? 'smtp.gmail.com',
  );
  late final _port = TextEditingController(
    text: '${widget.config?.smtpPort ?? 587}',
  );
  late final _username = TextEditingController(
    text: widget.config?.username ?? '',
  );
  late final _fromEmail = TextEditingController(
    text: widget.config?.fromEmail ?? '',
  );
  late final _fromName = TextEditingController(
    text: widget.config?.fromName ?? 'Lyncar',
  );
  late final _clientId = TextEditingController(
    text: widget.config?.clientId ?? '',
  );
  final _password = TextEditingController();
  final _clientSecret = TextEditingController();
  final _refreshToken = TextEditingController();
  late String _authMethod = widget.config?.authMethod ?? 'smtp';
  late bool _enabled = widget.config?.enabled ?? false;

  @override
  void dispose() {
    for (final controller in [
      _host,
      _port,
      _username,
      _fromEmail,
      _fromName,
      _clientId,
      _password,
      _clientSecret,
      _refreshToken,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  String? _optional(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  @override
  Widget build(BuildContext context) {
    final smtp = _authMethod == 'smtp';
    return AlertDialog(
      title: const Text('E-mail de recuperação de senha'),
      content: SizedBox(
        width: 680,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Deixe desativado até concluir a configuração. Use credenciais próprias do Lyncar.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _authMethod,
                decoration: const InputDecoration(labelText: 'Método de envio'),
                items: const [
                  DropdownMenuItem(
                    value: 'smtp',
                    child: Text('SMTP (Gmail ou outro provedor)'),
                  ),
                  DropdownMenuItem(
                    value: 'gmail_api',
                    child: Text('Gmail API (OAuth 2.0)'),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => _authMethod = value ?? 'smtp'),
              ),
              if (smtp) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _host,
                        decoration: const InputDecoration(
                          labelText: 'Servidor SMTP',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _port,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Porta'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _username,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(
                    labelText: 'Usuário/e-mail de envio',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Senha ou senha de app',
                    helperText: widget.config?.passwordConfigured == true
                        ? 'Deixe vazio para manter a credencial atual.'
                        : null,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _clientId,
                  decoration: const InputDecoration(
                    labelText: 'Client ID OAuth 2.0',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _clientSecret,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Client Secret',
                    helperText: widget.config?.clientSecretConfigured == true
                        ? 'Deixe vazio para manter o atual.'
                        : null,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _refreshToken,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: 'Refresh token',
                    helperText: widget.config?.refreshTokenConfigured == true
                        ? 'Deixe vazio para manter o atual.'
                        : null,
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _fromEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'E-mail remetente',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _fromName,
                      decoration: const InputDecoration(
                        labelText: 'Nome exibido',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
                title: const Text('Habilitar envio'),
                contentPadding: EdgeInsets.zero,
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
            final fromEmail = _fromEmail.text.trim();
            final port = int.tryParse(_port.text.trim());
            if (fromEmail.isEmpty || port == null) return;
            Navigator.of(context).pop(
              MasterEmailSettingInput(
                authMethod: _authMethod,
                smtpHost: _host.text.trim(),
                smtpPort: port,
                username: _username.text.trim(),
                password: _optional(_password),
                clientId: _optional(_clientId),
                clientSecret: _optional(_clientSecret),
                refreshToken: _optional(_refreshToken),
                fromEmail: fromEmail,
                fromName: _fromName.text.trim(),
                enabled: _enabled,
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
