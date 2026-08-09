import 'package:flutter/material.dart';

import '../models/payment_setting.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class MasterPaymentSettingsScreen extends StatefulWidget {
  const MasterPaymentSettingsScreen({super.key, required this.session});

  final Session session;

  @override
  State<MasterPaymentSettingsScreen> createState() =>
      _MasterPaymentSettingsScreenState();
}

class _MasterPaymentSettingsScreenState
    extends State<MasterPaymentSettingsScreen> {
  late final _api = ApiClient(widget.session.apiBaseUrl);
  final _publicKey = TextEditingController();
  final _accessToken = TextEditingController();
  final _webhookUrl = TextEditingController();
  String _environment = 'test';
  bool _active = true;
  bool _loading = true;
  bool _saving = false;
  String? _tokenPreview;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _publicKey.dispose();
    _accessToken.dispose();
    _webhookUrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final setting = await _api.getMercadoPagoSetting(widget.session.token);
      setState(() {
        _environment = setting.environment;
        _publicKey.text = setting.publicKey ?? '';
        _webhookUrl.text = setting.webhookUrl ?? '';
        _tokenPreview = setting.accessTokenPreview;
        _active = setting.active;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final setting = await _api.updateMercadoPagoSetting(
        widget.session.token,
        PaymentSettingInput(
          environment: _environment,
          publicKey: _publicKey.text,
          accessToken: _accessToken.text,
          webhookUrl: _webhookUrl.text,
          active: _active,
        ),
      );
      setState(() {
        _accessToken.clear();
        _tokenPreview = setting.accessTokenPreview;
      });
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Configuração salva.')));
      }
    } on ApiException catch (error) {
      setState(() => _error = error.message);
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
          const Text(
            'Pagamentos',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          const Text(
            'Credenciais Mercado Pago para Pix das mensalidades.',
            style: TextStyle(color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 16),
          if (_error != null) ...[
            ErrorPanel(message: _error!, onRetry: _load),
            const SizedBox(height: 12),
          ],
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : AppCard(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: [
                        SegmentedButton<String>(
                          segments: const [
                            ButtonSegment(
                              value: 'test',
                              label: Text('Teste'),
                              icon: Icon(Icons.science_outlined),
                            ),
                            ButtonSegment(
                              value: 'production',
                              label: Text('Produção'),
                              icon: Icon(Icons.verified_outlined),
                            ),
                          ],
                          selected: {_environment},
                          onSelectionChanged: (value) =>
                              setState(() => _environment = value.first),
                        ),
                        const SizedBox(height: 16),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _active,
                          onChanged: (value) => setState(() => _active = value),
                          title: const Text('Integração ativa'),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _publicKey,
                          decoration: const InputDecoration(
                            labelText: 'Public Key',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _accessToken,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Access Token',
                            helperText: _tokenPreview == null
                                ? 'Nenhum token salvo.'
                                : 'Token salvo: $_tokenPreview. Preencha apenas para trocar.',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _webhookUrl,
                          decoration: const InputDecoration(
                            labelText: 'Webhook URL',
                            hintText:
                                'https://api.seudominio.com/master/billings/mercado-pago/webhook',
                          ),
                        ),
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _saving ? null : _save,
                            icon: const Icon(Icons.save_outlined),
                            label: Text(_saving ? 'Salvando...' : 'Salvar'),
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
