import 'package:flutter/material.dart';

class NewLoginScreen extends StatelessWidget {
  const NewLoginScreen({
    super.key,
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.emailFocus,
    required this.passwordFocus,
    required this.loading,
    required this.error,
    required this.onLogin,
    required this.onComingSoon,
    required this.showTechnicalFields,
    required this.companyController,
    required this.apiController,
    required this.companyFocus,
    required this.apiFocus,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;
  final VoidCallback onComingSoon;
  final bool showTechnicalFields;
  final TextEditingController companyController;
  final TextEditingController apiController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;

  static const _page = Color(0xFFF8FBFE);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _page,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 900;
          if (compact) {
            return _FormPanel(
              formKey: formKey,
              emailController: emailController,
              passwordController: passwordController,
              emailFocus: emailFocus,
              passwordFocus: passwordFocus,
              loading: loading,
              error: error,
              onLogin: onLogin,
              onComingSoon: onComingSoon,
              showTechnicalFields: showTechnicalFields,
              companyController: companyController,
              apiController: apiController,
              companyFocus: companyFocus,
              apiFocus: apiFocus,
              compact: true,
            );
          }

          return Row(
            children: [
              Expanded(
                flex: constraints.maxWidth >= 1200 ? 57 : 52,
                child: const _BrandPanel(),
              ),
              Expanded(
                flex: constraints.maxWidth >= 1200 ? 43 : 48,
                child: _FormPanel(
                  formKey: formKey,
                  emailController: emailController,
                  passwordController: passwordController,
                  emailFocus: emailFocus,
                  passwordFocus: passwordFocus,
                  loading: loading,
                  error: error,
                  onLogin: onLogin,
                  onComingSoon: onComingSoon,
                  showTechnicalFields: showTechnicalFields,
                  companyController: companyController,
                  apiController: apiController,
                  companyFocus: companyFocus,
                  apiFocus: apiFocus,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  static const _navy = Color(0xFF071C37);
  static const _navyLight = Color(0xFF102F55);
  static const _accent = Color(0xFF5EA2F5);

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_navyLight, _navy],
        ),
      ),
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: -110,
            top: -80,
            child: Transform.rotate(
              angle: -.55,
              child: Container(
                width: 260,
                height: 580,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: .08),
                  borderRadius: BorderRadius.circular(60),
                ),
              ),
            ),
          ),
          Positioned(
            left: -180,
            bottom: -220,
            child: Container(
              width: 620,
              height: 330,
              decoration: BoxDecoration(
                color: _accent.withValues(alpha: .06),
                borderRadius: BorderRadius.circular(100),
              ),
            ),
          ),
          Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 360,
                  height: 220,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        _accent.withValues(alpha: .18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/brand/lyncar_logo_clean.png',
                      width: 250,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) => const Text(
                        'Lyncar',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 52,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    Container(
                      width: 42,
                      height: 2,
                      decoration: BoxDecoration(
                        color: _accent,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Seu negócio no controle.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFFE7F1FC),
                        fontSize: 19,
                        fontWeight: FontWeight.w500,
                        letterSpacing: .2,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Image.asset(
          'assets/brand/lyncar_logo_clean.png',
          width: 142,
          height: 42,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => const Text(
            'Lyncar',
            style: TextStyle(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Container(
          height: 30,
          width: 1,
          margin: const EdgeInsets.symmetric(horizontal: 20),
          color: const Color(0xFF58708E),
        ),
        const Text(
          'SISTEMA DE GESTÃO EMPRESARIAL',
          style: TextStyle(
            color: Color(0xFFA9BED7),
            fontSize: 11,
            letterSpacing: 1.3,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _Feature extends StatelessWidget {
  const _Feature({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: const Color(0xFF1D5A9B).withValues(alpha: .38),
            borderRadius: BorderRadius.circular(13),
          ),
          child: SizedBox(
            width: 48,
            height: 48,
            child: Icon(icon, color: const Color(0xFF65AAFA), size: 24),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFFE7F0FA),
            fontSize: 14,
            height: 1.3,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _DashboardPreview extends StatelessWidget {
  const _DashboardPreview();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -.075,
      alignment: Alignment.bottomLeft,
      child: Container(
        height: 230,
        width: double.infinity,
        margin: const EdgeInsets.only(left: 46),
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: const Color(0xFF0B2545),
          border: Border.all(
            color: const Color(0xFF5C91CA).withValues(alpha: .7),
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x55000000),
              blurRadius: 22,
              offset: Offset(0, 16),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 96,
              decoration: BoxDecoration(
                color: const Color(0xFF071C37),
                borderRadius: BorderRadius.circular(10),
              ),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Lyncar',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 20),
                  for (final item in const [
                    'Início',
                    'Vendas',
                    'Estoque',
                    'Financeiro',
                    'Clientes',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Text(
                        item,
                        style: const TextStyle(
                          color: Color(0xFFB8CCE4),
                          fontSize: 8,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 15),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Visão geral',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _PreviewCard(
                        label: 'Vendas hoje',
                        value: 'R\$ 2.611,78',
                        color: const Color(0xFF2D8FDE),
                      ),
                      const SizedBox(width: 9),
                      _PreviewCard(
                        label: 'Produtos',
                        value: '1.482',
                        color: const Color(0xFF55C99A),
                      ),
                    ],
                  ),
                  const SizedBox(height: 13),
                  Container(
                    height: 7,
                    width: 220,
                    decoration: BoxDecoration(
                      color: const Color(0xFF23456B),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    height: 7,
                    width: 170,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1B3B60),
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewCard extends StatelessWidget {
  const _PreviewCard({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: const Color(0xFF122F53),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(color: Color(0xFFB8CCE4), fontSize: 9),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Motto extends StatelessWidget {
  const _Motto();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 36, child: Divider(color: Color(0xFF5EA2F5))),
        SizedBox(height: 12),
        Text(
          'ORGANIZAR\nCONTROLAR\nEVOLUIR',
          style: TextStyle(
            color: Color(0xFFAEC3DE),
            fontSize: 10,
            height: 1.65,
            letterSpacing: 1.8,
          ),
        ),
      ],
    );
  }
}

class _FormPanel extends StatelessWidget {
  const _FormPanel({
    required this.formKey,
    required this.emailController,
    required this.passwordController,
    required this.emailFocus,
    required this.passwordFocus,
    required this.loading,
    required this.error,
    required this.onLogin,
    required this.onComingSoon,
    required this.showTechnicalFields,
    required this.companyController,
    required this.apiController,
    required this.companyFocus,
    required this.apiFocus,
    this.compact = false,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;
  final VoidCallback onComingSoon;
  final bool showTechnicalFields;
  final TextEditingController companyController;
  final TextEditingController apiController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;
  final bool compact;

  static const _primary = Color(0xFF15529A);
  static const _text = Color(0xFF0A1730);
  static const _secondary = Color(0xFF526A89);
  static const _border = Color(0xFFD3DDEA);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compactHeight = constraints.maxHeight < 800;
              // Keep the access form high on the panel now that the unused
              // theme control is gone. The form scrolls only when necessary.
              final topPadding = compactHeight ? 42.0 : 48.0;
              final sectionGap = compactHeight ? 18.0 : 25.0;

              return SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(
                  compact ? 24 : 40,
                  topPadding,
                  compact ? 24 : 40,
                  28,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: (constraints.maxHeight - topPadding - 28).clamp(
                      0.0,
                      double.infinity,
                    ),
                  ),
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 462),
                      child: Form(
                        key: formKey,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'Acesse sua conta',
                              style: TextStyle(
                                color: _text,
                                fontSize: compactHeight ? 30 : 36,
                                height: 1.15,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -.7,
                              ),
                            ),
                            SizedBox(height: compactHeight ? 8 : 14),
                            Text(
                              'Entre para continuar no Lyncar e gerenciar\nsua empresa com mais eficiência.',
                              style: TextStyle(
                                color: _secondary,
                                fontSize: compactHeight ? 14 : 17,
                                height: compactHeight ? 1.3 : 1.45,
                              ),
                            ),
                            SizedBox(height: compactHeight ? 20 : 35),
                            if (showTechnicalFields) ...[
                              _TechnicalSettings(
                                companyController: companyController,
                                apiController: apiController,
                                companyFocus: companyFocus,
                                apiFocus: apiFocus,
                              ),
                              SizedBox(height: compactHeight ? 14 : 22),
                            ],
                            const _FieldLabel('Usuário'),
                            SizedBox(height: compactHeight ? 5 : 8),
                            _LoginField(
                              controller: emailController,
                              focusNode: emailFocus,
                              hintText: 'Digite seu usuário',
                              icon: Icons.person_outline_rounded,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [
                                AutofillHints.username,
                                AutofillHints.email,
                              ],
                              validator: (value) =>
                                  value == null || value.trim().isEmpty
                                  ? 'Informe seu usuário.'
                                  : null,
                              onSubmitted: (_) => passwordFocus.requestFocus(),
                              compact: compactHeight,
                            ),
                            SizedBox(height: sectionGap),
                            const _FieldLabel('Senha'),
                            SizedBox(height: compactHeight ? 5 : 8),
                            _PasswordField(
                              controller: passwordController,
                              focusNode: passwordFocus,
                              onSubmitted: (_) => onLogin(),
                              compact: compactHeight,
                            ),
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: onComingSoon,
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFF0867D9),
                                  padding: EdgeInsets.only(
                                    top: compactHeight ? 5 : 12,
                                    bottom: 2,
                                  ),
                                ),
                                child: const Text(
                                  'Esqueci minha senha',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              _ErrorBanner(message: error!),
                            ],
                            SizedBox(height: compactHeight ? 10 : 18),
                            _PrimaryButton(
                              loading: loading,
                              onPressed: onLogin,
                              compact: compactHeight,
                            ),
                            SizedBox(height: compactHeight ? 14 : 28),
                            const _OrDivider(),
                            SizedBox(height: compactHeight ? 12 : 22),
                            OutlinedButton.icon(
                              onPressed: onComingSoon,
                              icon: const Icon(
                                Icons.qr_code_scanner_rounded,
                                size: 21,
                              ),
                              label: const Text('Entrar com código de acesso'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: Size.fromHeight(
                                  compactHeight ? 50 : 62,
                                ),
                                foregroundColor: _primary,
                                side: const BorderSide(
                                  color: _border,
                                  width: 1.4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(9),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            SizedBox(height: compactHeight ? 12 : 32),
                            const Center(
                              child: Text(
                                'Lyncar ERP  •  Ambiente seguro',
                                style: TextStyle(
                                  color: _secondary,
                                  fontSize: 13.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _TechnicalSettings extends StatelessWidget {
  const _TechnicalSettings({
    required this.companyController,
    required this.apiController,
    required this.companyFocus,
    required this.apiFocus,
  });

  final TextEditingController companyController;
  final TextEditingController apiController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;

  @override
  Widget build(BuildContext context) {
    return ExpansionTile(
      tilePadding: EdgeInsets.zero,
      childrenPadding: EdgeInsets.zero,
      title: const Text(
        'Configuração técnica local',
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: Color(0xFF526A89),
        ),
      ),
      children: [
        _LoginField(
          controller: companyController,
          focusNode: companyFocus,
          hintText: 'Empresa',
          icon: Icons.business_outlined,
        ),
        const SizedBox(height: 10),
        _LoginField(
          controller: apiController,
          focusNode: apiFocus,
          hintText: 'Servidor API',
          icon: Icons.hub_outlined,
          keyboardType: TextInputType.url,
        ),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: Color(0xFF111827),
      fontSize: 16,
      fontWeight: FontWeight.w600,
    ),
  );
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.icon,
    this.keyboardType,
    this.autofillHints,
    this.validator,
    this.onSubmitted,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final IconData icon;
  final TextInputType? keyboardType;
  final Iterable<String>? autofillHints;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: onSubmitted,
      style: const TextStyle(color: Color(0xFF182A46), fontSize: 17),
      decoration: _decoration(hintText, icon, compact: compact),
    );
  }
}

class _PasswordField extends StatefulWidget {
  const _PasswordField({
    required this.controller,
    required this.focusNode,
    required this.onSubmitted,
    this.compact = false,
  });
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onSubmitted;
  final bool compact;
  @override
  State<_PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<_PasswordField> {
  bool _obscure = true;
  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: widget.focusNode,
      obscureText: _obscure,
      autofillHints: const [AutofillHints.password],
      validator: (value) =>
          value == null || value.isEmpty ? 'Informe sua senha.' : null,
      onFieldSubmitted: widget.onSubmitted,
      style: const TextStyle(color: Color(0xFF182A46), fontSize: 17),
      decoration:
          _decoration(
            'Digite sua senha',
            Icons.lock_outline_rounded,
            compact: widget.compact,
          ).copyWith(
            suffixIcon: IconButton(
              tooltip: _obscure ? 'Mostrar senha' : 'Ocultar senha',
              onPressed: () => setState(() => _obscure = !_obscure),
              icon: Icon(
                _obscure
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                size: 22,
              ),
            ),
          ),
    );
  }
}

InputDecoration _decoration(
  String hint,
  IconData icon, {
  bool compact = false,
}) {
  const border = Color(0xFFD3DDEA);
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFF7186A4), fontSize: 16),
    prefixIcon: Icon(icon, color: Color(0xFF607898), size: 22),
    filled: true,
    fillColor: Colors.white,
    contentPadding: EdgeInsets.symmetric(
      horizontal: 17,
      vertical: compact ? 12 : 18,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFF1E62B6), width: 1.5),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFFB91C1C)),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(9),
      borderSide: const BorderSide(color: Color(0xFFB91C1C), width: 1.5),
    ),
  );
}

class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.loading,
    required this.onPressed,
    this.compact = false,
  });
  final bool loading;
  final VoidCallback onPressed;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF123F7D), Color(0xFF15529A)],
        ),
        borderRadius: BorderRadius.circular(9),
      ),
      child: ElevatedButton(
        onPressed: loading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          disabledBackgroundColor: Colors.transparent,
          minimumSize: Size.fromHeight(compact ? 52 : 68),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
        ),
        child: loading
            ? const SizedBox(
                width: 23,
                height: 23,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2.5,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Entrar',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
                  ),
                  SizedBox(width: 15),
                  Icon(Icons.arrow_forward_rounded, size: 25),
                ],
              ),
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();
  @override
  Widget build(BuildContext context) => const Row(
    children: [
      Expanded(child: Divider(color: Color(0xFFD3DDEA))),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: 17),
        child: Text(
          'ou',
          style: TextStyle(color: Color(0xFF7186A4), fontSize: 15),
        ),
      ),
      Expanded(child: Divider(color: Color(0xFFD3DDEA))),
    ],
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F0),
      border: Border.all(color: const Color(0xFFF2B8B8)),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Row(
      children: [
        const Icon(
          Icons.error_outline_rounded,
          color: Color(0xFFB91C1C),
          size: 20,
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF991B1B),
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    ),
  );
}
