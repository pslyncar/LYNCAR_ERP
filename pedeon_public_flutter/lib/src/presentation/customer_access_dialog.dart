import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'storefront_view_model.dart';

Future<bool?> showCustomerAccessDialog(
  BuildContext context, {
  required StorefrontViewModel viewModel,
}) => showDialog<bool>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _CustomerAccessDialog(viewModel: viewModel),
);

class _CustomerAccessDialog extends StatefulWidget {
  const _CustomerAccessDialog({required this.viewModel});
  final StorefrontViewModel viewModel;

  @override
  State<_CustomerAccessDialog> createState() => _CustomerAccessDialogState();
}

class _CustomerAccessDialogState extends State<_CustomerAccessDialog> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _phone = TextEditingController();
  final _password = TextEditingController();
  bool _registering = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _phone.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _error = null);
    try {
      if (_registering) {
        await widget.viewModel.registerCustomer(
          name: _name.text,
          email: _email.text,
          password: _password.text,
          phone: _phone.text,
        );
      } else {
        await widget.viewModel.loginCustomer(
          email: _email.text,
          password: _password.text,
        );
      }
      if (mounted) Navigator.of(context).pop(true);
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    }
  }

  void _socialUnavailable(String provider) {
    setState(
      () => _error =
          'O acesso com $provider precisa das credenciais oficiais da loja. '
          'Use o cadastro direto do PedeOn enquanto essa integração é configurada.',
    );
  }

  Future<void> _googleLogin() async {
    setState(() => _error = null);
    try {
      final url = await widget.viewModel.startGoogleLogin();
      await launchUrl(Uri.parse(url), mode: LaunchMode.platformDefault);
    } catch (exception) {
      if (mounted) setState(() => _error = exception.toString());
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(_registering ? 'Criar conta no PedeOn' : 'Entrar no PedeOn'),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _registering
                    ? 'Crie sua conta para acompanhar seus pedidos.'
                    : 'Entre para finalizar o pedido e acompanhar seu status.',
              ),
              const SizedBox(height: 18),
              if (_registering)
                TextFormField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Nome'),
                  validator: (value) => value == null || value.trim().length < 2
                      ? 'Informe seu nome.'
                      : null,
                ),
              if (_registering) const SizedBox(height: 10),
              TextFormField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'E-mail'),
                validator: (value) => value == null || !value.contains('@')
                    ? 'Informe um e-mail válido.'
                    : null,
              ),
              if (_registering) const SizedBox(height: 10),
              if (_registering)
                TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Telefone (opcional)',
                  ),
                ),
              const SizedBox(height: 10),
              TextFormField(
                controller: _password,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Senha'),
                validator: (value) => value == null || value.length < 8
                    ? 'A senha deve ter pelo menos 8 caracteres.'
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: TextStyle(color: Colors.red.shade700)),
              ],
              const SizedBox(height: 16),
              FilledButton(
                onPressed: widget.viewModel.authLoading ? null : _submit,
                child: Text(_registering ? 'Criar conta' : 'Entrar'),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() {
                  _registering = !_registering;
                  _error = null;
                }),
                child: Text(
                  _registering ? 'Já tenho uma conta' : 'Ainda não tenho conta',
                ),
              ),
              const Divider(height: 24),
              OutlinedButton.icon(
                onPressed: widget.viewModel.authLoading ? null : _googleLogin,
                icon: const Icon(Icons.g_mobiledata),
                label: const Text('Continuar com Google'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _socialUnavailable('Facebook'),
                icon: const Icon(Icons.facebook),
                label: const Text('Continuar com Facebook'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () => _socialUnavailable('Apple'),
                icon: const Icon(Icons.apple),
                label: const Text('Continuar com Apple'),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.of(context).pop(false),
        child: const Text('Cancelar'),
      ),
    ],
  );
}
