import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/session.dart';
import '../services/api_client.dart';
import '../services/browser_redirect.dart';

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
  late final _companyController = TextEditingController(
    text: _companyCodeFromHost,
  );
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  late final _apiController = TextEditingController(text: _defaultApiBaseUrl);

  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _companyController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _apiController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    final automaticMobileLogin =
        _isMobileApplication && !_showTechnicalLoginFields;
    final companyCode = _showTechnicalLoginFields
        ? _companyController.text.trim().toLowerCase()
        : _companyCodeFromHost;
    if (!automaticMobileLogin && companyCode.isEmpty) {
      setState(() => _error = 'Empresa não identificada.');
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
            () => _error = 'Troque a senha provisoria para acessar o sistema.',
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
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível conectar ao servidor.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
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
                () => error = 'A nova senha deve ser diferente da provisoria.',
              );
              return;
            }
            if (password != confirmPassword.text) {
              setDialogState(() => error = 'As senhas nao conferem.');
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
                error = 'Nao foi possivel trocar a senha.';
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
                      'Este e o primeiro acesso. Por seguranca, escolha uma senha sua antes de entrar.',
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
    final detail = error.data?['detail'];
    if (detail is! Map<String, dynamic>) return null;
    if (detail['code'] != 'login_wrong_domain') return null;
    return detail['access_url']?.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020817),
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Stack(
            fit: StackFit.expand,
            children: [
              const _LoginBackdrop(),
              _LoginScene(
                companyController: _companyController,
                apiController: _apiController,
                showCompanyField: _showTechnicalLoginFields,
                emailController: _emailController,
                passwordController: _passwordController,
                loading: _loading,
                error: _error,
                onLogin: _login,
              ),
            ],
          );
        },
      ),
    );
  }
}

class _LoginScene extends StatelessWidget {
  const _LoginScene({
    required this.companyController,
    required this.apiController,
    required this.showCompanyField,
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.error,
    required this.onLogin,
  });

  final TextEditingController companyController;
  final TextEditingController apiController;
  final bool showCompanyField;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = constraints.maxHeight;
        final compact = width < 820;

        if (compact) {
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: math.max(520, height - 56),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Image.asset(
                        'assets/brand/lyncar_logo_clean.png',
                        width: (width * 0.58).clamp(220.0, 330.0),
                        fit: BoxFit.contain,
                      ),
                      const SizedBox(height: 18),
                      const _Tagline(fontSize: 11, letterSpacing: 2.6),
                      const SizedBox(height: 28),
                      _LoginCard(
                        width: (width - 40).clamp(320.0, 390.0),
                        companyController: companyController,
                        apiController: apiController,
                        showCompanyField: showCompanyField,
                        emailController: emailController,
                        passwordController: passwordController,
                        loading: loading,
                        error: error,
                        onLogin: onLogin,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        final sidePadding = (width * 0.085).clamp(64.0, 126.0);
        final logoWidth = (width * 0.35).clamp(380.0, 540.0);
        final cardWidth = (width * 0.30).clamp(400.0, 440.0);
        final cardHeight = 446.0 + (error == null ? 0 : 72);
        final cardTop = ((height - cardHeight) / 2).clamp(34.0, 120.0);
        final cardRight = (width * 0.035).clamp(28.0, 62.0);
        final logoTop = (height * 0.13).clamp(42.0, 118.0);
        final logoHeight = logoWidth / 3.36;

        return SafeArea(
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: sidePadding,
                top: logoTop,
                width: logoWidth,
                child: Image.asset(
                  'assets/brand/lyncar_logo_clean.png',
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                left: sidePadding + 10,
                top: logoTop + logoHeight + 18,
                child: const _Tagline(),
              ),
              if (height >= 700)
                Positioned(
                  left: sidePadding * 0.40,
                  width: (width * 0.55).clamp(560.0, 820.0),
                  bottom: 28,
                  child: const _CreditInline(),
                ),
              Positioned(
                right: cardRight,
                top: cardTop,
                child: _LoginCard(
                  width: cardWidth,
                  companyController: companyController,
                  apiController: apiController,
                  showCompanyField: showCompanyField,
                  emailController: emailController,
                  passwordController: passwordController,
                  loading: loading,
                  error: error,
                  onLogin: onLogin,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Tagline extends StatelessWidget {
  const _Tagline({this.fontSize = 15, this.letterSpacing = 4});

  final double fontSize;
  final double letterSpacing;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          letterSpacing: letterSpacing,
        ),
        children: const [
          TextSpan(text: 'TUDO DA SUA EMPRESA. '),
          TextSpan(
            text: 'CONECTADO.',
            style: TextStyle(color: Color(0xFF168CFF)),
          ),
        ],
      ),
    );
  }
}

class _CreditInline extends StatelessWidget {
  const _CreditInline();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(child: Divider(color: Color(0x6687A0C4), thickness: 1)),
        const SizedBox(width: 20),
        const Text(
          'O SITE LYNCAR PERTENCE E FOI PRODUZIDO PELA',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(width: 14),
        Image.asset(
          'assets/brand/lyncar_ps_logo_clean.png',
          width: 38,
          height: 36,
          fit: BoxFit.contain,
        ),
        const SizedBox(width: 8),
        const Text(
          'Lyncar',
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.w800,
            letterSpacing: 0,
          ),
        ),
        const SizedBox(width: 20),
        const Expanded(child: Divider(color: Color(0x6687A0C4), thickness: 1)),
      ],
    );
  }
}

class _LoginBackdrop extends StatelessWidget {
  const _LoginBackdrop();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020817), Color(0xFF061B44), Color(0xFF041125)],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          const Positioned.fill(
            child: CustomPaint(painter: _LyncarBackdropPainter()),
          ),
        ],
      ),
    );
  }
}

class _LyncarBackdropPainter extends CustomPainter {
  const _LyncarBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF020817), Color(0xFF061A43), Color(0xFF081B50)],
        stops: [0, 0.52, 1],
      ).createShader(rect);
    canvas.drawRect(rect, base);

    final rightGlow = Paint()
      ..shader = RadialGradient(
        center: const Alignment(1.0, -0.05),
        radius: 0.92,
        colors: [
          const Color(0xAA083BBD),
          const Color(0x330A3C93),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, rightGlow);

    final leftShadow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          const Color(0xC9000714),
          const Color(0x66000714),
          Colors.transparent,
        ],
      ).createShader(rect);
    canvas.drawRect(rect, leftShadow);

    final yCenter = Offset(size.width * 0.20, size.height * 0.82);
    final yScale = math.min(size.width, size.height) * 0.72;
    final yStroke = math.max(72.0, yScale * 0.18);
    final leftArm = Path()
      ..moveTo(yCenter.dx - yScale * 0.58, yCenter.dy - yScale * 0.40)
      ..lineTo(yCenter.dx - yScale * 0.09, yCenter.dy - yScale * 0.05);
    final rightArm = Path()
      ..moveTo(yCenter.dx + yScale * 0.24, yCenter.dy - yScale * 0.42)
      ..lineTo(yCenter.dx - yScale * 0.09, yCenter.dy - yScale * 0.05)
      ..lineTo(yCenter.dx - yScale * 0.36, yCenter.dy + yScale * 0.62);

    final yShadow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = yStroke * 1.14
      ..color = const Color(0xAA000814)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawPath(leftArm, yShadow);
    canvas.drawPath(rightArm, yShadow);

    final leftArmPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = yStroke
      ..color = const Color(0x1F1C4ED8);
    canvas.drawPath(leftArm, leftArmPaint);

    final rightArmPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = yStroke
      ..shader =
          LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color(0x66234CFF),
              const Color(0xBB0B74FF),
              const Color(0xDD08D9FF),
            ],
          ).createShader(
            Rect.fromLTWH(
              yCenter.dx - yScale * 0.62,
              yCenter.dy - yScale * 0.50,
              yScale,
              yScale * 1.25,
            ),
          );
    canvas.drawPath(rightArm, rightArmPaint);

    final yGlow = Paint()
      ..shader =
          RadialGradient(
            colors: [
              const Color(0x7700C8FF),
              const Color(0x22205DFF),
              Colors.transparent,
            ],
          ).createShader(
            Rect.fromCircle(
              center: Offset(
                yCenter.dx - yScale * 0.15,
                yCenter.dy + yScale * 0.16,
              ),
              radius: yScale * 0.42,
            ),
          )
      ..blendMode = BlendMode.plus;
    canvas.drawCircle(
      Offset(yCenter.dx - yScale * 0.15, yCenter.dy + yScale * 0.16),
      yScale * 0.42,
      yGlow,
    );

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x553B82F6);

    canvas.drawArc(
      Rect.fromLTWH(
        -size.width * 0.12,
        size.height * 0.18,
        size.width * 0.52,
        size.height * 0.76,
      ),
      -1.58,
      3.28,
      false,
      linePaint,
    );
    canvas.drawArc(
      Rect.fromLTWH(
        -size.width * 0.18,
        size.height * 0.08,
        size.width * 0.58,
        size.height * 0.94,
      ),
      -1.42,
      3.0,
      false,
      linePaint..color = const Color(0x333B82F6),
    );

    final nodePaint = Paint()
      ..color = const Color(0xFF159BFF)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 7);
    canvas.drawCircle(
      Offset(size.width * 0.19, size.height * 0.36),
      4.5,
      nodePaint,
    );
    canvas.drawCircle(
      Offset(size.width * 0.34, size.height * 0.80),
      4.2,
      nodePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _LoginCard extends StatefulWidget {
  const _LoginCard({
    required this.width,
    required this.companyController,
    required this.apiController,
    required this.showCompanyField,
    required this.emailController,
    required this.passwordController,
    required this.loading,
    required this.error,
    required this.onLogin,
  });

  final double width;
  final TextEditingController companyController;
  final TextEditingController apiController;
  final bool showCompanyField;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;

  @override
  State<_LoginCard> createState() => _LoginCardState();
}

class _LoginCardState extends State<_LoginCard> {
  bool _showPassword = false;

  @override
  Widget build(BuildContext context) {
    final compact = widget.width < 420;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x38162E4A),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xAA00A6FF), width: 1.2),
        boxShadow: const [
          BoxShadow(
            blurRadius: 46,
            color: Color(0x6600142D),
            offset: Offset(0, 24),
          ),
        ],
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.width,
          maxWidth: widget.width,
          minHeight: compact
              ? (widget.showCompanyField ? 452 : 392)
              : (widget.showCompanyField ? 506 : 438),
        ),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 22 : 34,
            vertical: compact ? 22 : 30,
          ),
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Center(
                  child: Container(
                    width: compact ? 38 : 44,
                    height: compact ? 38 : 44,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0x6638BDF8)),
                      color: const Color(0x22007BFF),
                    ),
                    child: const Icon(
                      Icons.lock_outline,
                      color: Color(0xFF04B7FF),
                    ),
                  ),
                ),
                SizedBox(height: compact ? 12 : 18),
                Text(
                  'LOGIN',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: compact ? 26 : 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0,
                  ),
                ),
                Center(
                  child: Container(
                    margin: EdgeInsets.only(
                      top: compact ? 8 : 10,
                      bottom: compact ? 14 : 26,
                    ),
                    width: 160,
                    height: 2,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Color(0x0000A6FF),
                          Color(0xFF00D5FF),
                          Color(0x0000A6FF),
                        ],
                      ),
                    ),
                  ),
                ),
                if (widget.showCompanyField) ...[
                  TextField(
                    controller: widget.companyController,
                    textInputAction: TextInputAction.next,
                    style: const TextStyle(color: Colors.white),
                    decoration: _loginInputDecoration(
                      label: 'Empresa',
                      hint: 'Ex.: master, padaria, mercado',
                      prefixIcon: Icon(Icons.apartment_outlined),
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 20),
                  TextField(
                    controller: widget.apiController,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.url,
                    style: const TextStyle(color: Colors.white),
                    decoration: _loginInputDecoration(
                      label: 'Servidor API',
                      hint: 'http://192.168.1.55:8000',
                      prefixIcon: Icon(Icons.lan_outlined),
                    ),
                  ),
                  SizedBox(height: compact ? 14 : 20),
                ],
                TextField(
                  controller: widget.emailController,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  style: const TextStyle(color: Colors.white),
                  decoration: _loginInputDecoration(
                    label: 'Usuário',
                    hint: 'E-mail',
                    prefixIcon: Icon(Icons.mail_outline),
                  ),
                ),
                SizedBox(height: compact ? 14 : 24),
                TextField(
                  controller: widget.passwordController,
                  obscureText: !_showPassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.password],
                  onSubmitted: (_) => widget.loading ? null : widget.onLogin(),
                  style: const TextStyle(color: Colors.white),
                  decoration: _loginInputDecoration(
                    label: 'Senha',
                    hint: 'Senha',
                    prefixIcon: Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      tooltip: _showPassword
                          ? 'Ocultar senha'
                          : 'Mostrar senha',
                      onPressed: () =>
                          setState(() => _showPassword = !_showPassword),
                      icon: Icon(
                        _showPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                if (widget.error != null) ...[
                  const SizedBox(height: 14),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFFEF2F2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFECACA)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        widget.error!,
                        style: const TextStyle(
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
                SizedBox(height: compact ? 20 : 42),
                SizedBox(
                  height: compact ? 50 : 56,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF078CFF),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      textStyle: TextStyle(
                        fontSize: compact ? 18 : 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0,
                      ),
                    ),
                    onPressed: widget.loading ? null : widget.onLogin,
                    child: widget.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Color(0xFF082033),
                            ),
                          )
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('LOGIN'),
                              SizedBox(width: 34),
                              Icon(Icons.keyboard_return, size: 26),
                            ],
                          ),
                  ),
                ),
                SizedBox(height: compact ? 14 : 22),
                const Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  children: [
                    Icon(
                      Icons.verified_user_outlined,
                      color: Color(0xFF02B7FF),
                      size: 22,
                    ),
                    Text(
                      'Acesso seguro e protegido.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFE2E8F0),
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _loginInputDecoration({
    required String label,
    required String hint,
    required Widget prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      labelStyle: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      hintStyle: const TextStyle(color: Color(0xFFB9A9CB)),
      prefixIcon: IconTheme(
        data: const IconThemeData(color: Color(0xFFE2E8F0)),
        child: prefixIcon,
      ),
      suffixIcon: suffixIcon == null
          ? null
          : IconTheme(
              data: const IconThemeData(color: Color(0xFFE2E8F0)),
              child: suffixIcon,
            ),
      filled: true,
      fillColor: const Color(0x24006CC7),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFF008DFF), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(7),
        borderSide: const BorderSide(color: Color(0xFF45C7F0), width: 1.4),
      ),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(7)),
    );
  }
}
