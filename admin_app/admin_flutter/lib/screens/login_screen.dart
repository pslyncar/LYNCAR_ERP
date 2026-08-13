import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/session.dart';
import '../services/api_client.dart';
import '../services/browser_redirect.dart';
import '../widgets/login/login_page.dart';

String get _defaultApiBaseUrl {
  final currentUri = Uri.base;
  final host = currentUri.host;
  if (host == 'erp.lyncar.com.br' || host.endsWith('.lyncar.com.br')) {
    return 'https://api.lyncar.com.br';
  }
  if (host.isNotEmpty && host != 'localhost') {
    return '${currentUri.scheme}://$host:8000';
  }
  if (kIsWeb && _isLocalDevelopmentHost(host)) {
    return const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://127.0.0.1:8000',
    );
  }
  return const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.lyncar.com.br',
  );
}

String get _companyCodeFromHost {
  final host = Uri.base.host.toLowerCase();
  final companyFromQuery = Uri.base.queryParameters['empresa']
      ?.trim()
      .toLowerCase();
  if (_isLocalDevelopmentHost(host) &&
      companyFromQuery != null &&
      companyFromQuery.isNotEmpty) {
    return companyFromQuery;
  }
  if (host == 'erp.lyncar.com.br' ||
      host == 'lyncar.com.br' ||
      host == 'www.lyncar.com.br' ||
      host == 'api.lyncar.com.br' ||
      _isLocalDevelopmentHost(host)) {
    return 'master';
  }
  if (host.isEmpty) {
    return 'master';
  }
  const suffix = '.lyncar.com.br';
  if (host.endsWith(suffix)) {
    return host.substring(0, host.length - suffix.length);
  }
  return host.split('.').first;
}

bool _isLocalDevelopmentHost(String host) {
  if (host.isEmpty) return true;
  return host == 'localhost' ||
      host == '127.0.0.1' ||
      host.startsWith('192.168.');
}

bool get _isMobileApplication {
  if (kIsWeb) return false;
  return defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;
}

bool get _isTestArea {
  return const String.fromEnvironment(
        'APP_ENV',
        defaultValue: 'production',
      ).toLowerCase() ==
      'test';
}

bool get _showTechnicalLoginFields {
  return (kIsWeb && _isLocalDevelopmentHost(Uri.base.host.toLowerCase())) ||
      _isTestArea;
}

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onLogin});

  final ValueChanged<Session> onLogin;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _companyController = TextEditingController(
    text: _companyCodeFromHost,
  );
  late final _apiController = TextEditingController(text: _defaultApiBaseUrl);
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _companyFocus = FocusNode();
  final _apiFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _passwordFocus = FocusNode();

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _companyController.dispose();
    _apiController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _companyFocus.dispose();
    _apiFocus.dispose();
    _emailFocus.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_loading) return;

    final automaticMobileLogin =
        _isMobileApplication && !_showTechnicalLoginFields;
    final companyCode = _showTechnicalLoginFields
        ? _companyController.text.trim().toLowerCase()
        : _companyCodeFromHost;

    if (!_formKey.currentState!.validate()) return;
    if (!automaticMobileLogin && companyCode.isEmpty) {
      setState(() => _error = 'Empresa não identificada.');
      _focusAfterError(_companyFocus);
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    final api = ApiClient(_apiController.text.trim());
    try {
      final session = automaticMobileLogin
          ? await api.loginAutomatically(
              email: _emailController.text.trim(),
              password: _passwordController.text,
            )
          : await api.login(
              companyCode: companyCode,
              email: _emailController.text.trim(),
              password: _passwordController.text,
            );
      if (session.mustChangePassword) {
        if (!mounted) return;
        final changed = await _showFirstPasswordDialog(
          api: api,
          session: session,
          currentPassword: _passwordController.text,
        );
        if (!changed) {
          setState(
            () => _error = 'Troque a senha provisória para acessar o sistema.',
          );
          return;
        }
      }
      TextInput.finishAutofillContext();
      final refreshed = await api.refreshSession(session);
      widget.onLogin(refreshed);
    } on ApiException catch (error) {
      final redirectUrl = _redirectUrlFromLoginError(error);
      if (redirectUrl != null) {
        setState(() => _error = 'Redirecionando para $redirectUrl...');
        redirectToUrl(redirectUrl);
        return;
      }
      final correctedCompany = _companyCodeFromWrongDomainError(error);
      if (_showTechnicalLoginFields && correctedCompany != null) {
        _companyController.text = correctedCompany;
        setState(
          () => _error =
              'Ajustei a empresa local para "$correctedCompany". Confira e tente entrar novamente.',
        );
        return;
      }
      setState(() => _error = error.message);
      if (_showTechnicalLoginFields && _isWrongDomainLoginError(error)) {
        _focusAfterError(_companyFocus);
      }
    } catch (_) {
      setState(() => _error = 'Não foi possível conectar ao servidor.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _focusAfterError(FocusNode focusNode) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      focusNode.requestFocus();
    });
  }

  Future<bool> _showFirstPasswordDialog({
    required ApiClient api,
    required Session session,
    required String currentPassword,
  }) async {
    final newPassword = TextEditingController();
    final confirmPassword = TextEditingController();
    String? error;
    bool saving = false;
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          Future<void> save() async {
            final password = newPassword.text;
            if (password.length < 8) {
              setDialogState(
                () => error = 'A senha precisa ter pelo menos 8 caracteres.',
              );
              return;
            }
            if (password == currentPassword) {
              setDialogState(
                () => error = 'A nova senha deve ser diferente da provisória.',
              );
              return;
            }
            if (password != confirmPassword.text) {
              setDialogState(() => error = 'As senhas não conferem.');
              return;
            }
            setDialogState(() {
              saving = true;
              error = null;
            });
            try {
              await api.changePassword(
                token: session.token,
                currentPassword: currentPassword,
                newPassword: password,
              );
              if (context.mounted) Navigator.of(context).pop(true);
            } on ApiException catch (apiError) {
              setDialogState(() {
                saving = false;
                error = apiError.message;
              });
            } catch (_) {
              setDialogState(() {
                saving = false;
                error = 'Não foi possível trocar a senha.';
              });
            }
          }

          return AlertDialog(
            title: const Text('Crie sua senha'),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Este é o primeiro acesso. Por segurança, escolha uma senha sua antes de entrar.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: newPassword,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'Nova senha'),
                    onSubmitted: (_) => save(),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmPassword,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'Confirmar senha',
                    ),
                    onSubmitted: (_) => save(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      error!,
                      style: const TextStyle(
                        color: Color(0xFFB91C1C),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              FilledButton.icon(
                onPressed: saving ? null : save,
                icon: saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.lock_reset),
                label: const Text('Salvar senha'),
              ),
            ],
          );
        },
      ),
    );
    newPassword.dispose();
    confirmPassword.dispose();
    return result == true;
  }

  String? _redirectUrlFromLoginError(ApiException error) {
    if (_showTechnicalLoginFields) return null;
    final detail = error.data?['detail'];
    if (detail is! Map<String, dynamic>) return null;
    if (detail['code'] != 'login_wrong_domain') return null;
    return detail['access_url']?.toString();
  }

  bool _isWrongDomainLoginError(ApiException error) {
    final detail = error.data?['detail'];
    return detail is Map<String, dynamic> &&
        detail['code'] == 'login_wrong_domain';
  }

  String? _companyCodeFromWrongDomainError(ApiException error) {
    final detail = error.data?['detail'];
    if (detail is! Map<String, dynamic>) return null;
    if (detail['code'] != 'login_wrong_domain') return null;

    for (final key in const ['company_code', 'tenant_code', 'empresa']) {
      final value = detail[key]?.toString().trim().toLowerCase();
      if (value != null && value.isNotEmpty) return value;
    }

    final accessUrl = detail['access_url']?.toString();
    final uri = accessUrl == null ? null : Uri.tryParse(accessUrl);
    final host = uri?.host.toLowerCase();
    const suffix = '.lyncar.com.br';
    if (host != null && host.endsWith(suffix)) {
      final company = host.substring(0, host.length - suffix.length);
      if (company.isNotEmpty && company != 'erp' && company != 'www') {
        return company;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: LoginPage(
        formKey: _formKey,
        companyController: _companyController,
        apiController: _apiController,
        emailController: _emailController,
        passwordController: _passwordController,
        companyFocus: _companyFocus,
        apiFocus: _apiFocus,
        emailFocus: _emailFocus,
        passwordFocus: _passwordFocus,
        showTechnicalFields: _showTechnicalLoginFields,
        loading: _loading,
        error: _error,
        onLogin: _login,
      ),
    );
  }
}
