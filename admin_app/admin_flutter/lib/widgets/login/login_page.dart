import 'package:flutter/material.dart';

class LoginPage extends StatelessWidget {
  const LoginPage({
    super.key,
    required this.formKey,
    required this.companyController,
    required this.apiController,
    required this.emailController,
    required this.passwordController,
    required this.companyFocus,
    required this.apiFocus,
    required this.emailFocus,
    required this.passwordFocus,
    required this.showTechnicalFields,
    required this.loading,
    required this.error,
    required this.onLogin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController companyController;
  final TextEditingController apiController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool showTechnicalFields;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xFF06101F)),
      child: Stack(
        children: [
          const Positioned.fill(child: _LoginBackground()),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 900;
                final content = compact
                    ? _CompactLoginLayout(
                        formKey: formKey,
                        companyController: companyController,
                        apiController: apiController,
                        emailController: emailController,
                        passwordController: passwordController,
                        companyFocus: companyFocus,
                        apiFocus: apiFocus,
                        emailFocus: emailFocus,
                        passwordFocus: passwordFocus,
                        showTechnicalFields: showTechnicalFields,
                        loading: loading,
                        error: error,
                        onLogin: onLogin,
                      )
                    : _WideLoginLayout(
                        formKey: formKey,
                        companyController: companyController,
                        apiController: apiController,
                        emailController: emailController,
                        passwordController: passwordController,
                        companyFocus: companyFocus,
                        apiFocus: apiFocus,
                        emailFocus: emailFocus,
                        passwordFocus: passwordFocus,
                        showTechnicalFields: showTechnicalFields,
                        loading: loading,
                        error: error,
                        onLogin: onLogin,
                      );
                return AnimatedSwitcher(
                  duration: const Duration(milliseconds: 220),
                  child: content,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _WideLoginLayout extends StatelessWidget {
  const _WideLoginLayout({
    required this.formKey,
    required this.companyController,
    required this.apiController,
    required this.emailController,
    required this.passwordController,
    required this.companyFocus,
    required this.apiFocus,
    required this.emailFocus,
    required this.passwordFocus,
    required this.showTechnicalFields,
    required this.loading,
    required this.error,
    required this.onLogin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController companyController;
  final TextEditingController apiController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool showTechnicalFields;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 72, vertical: 34),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: MediaQuery.sizeOf(context).height - 68,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.centerLeft,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 650),
                  child: const _BrandPanel(),
                ),
              ),
            ),
            const SizedBox(width: 44),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 470, minWidth: 430),
              child: _LoginPanel(
                formKey: formKey,
                companyController: companyController,
                apiController: apiController,
                emailController: emailController,
                passwordController: passwordController,
                companyFocus: companyFocus,
                apiFocus: apiFocus,
                emailFocus: emailFocus,
                passwordFocus: passwordFocus,
                showTechnicalFields: showTechnicalFields,
                loading: loading,
                error: error,
                onLogin: onLogin,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactLoginLayout extends StatelessWidget {
  const _CompactLoginLayout({
    required this.formKey,
    required this.companyController,
    required this.apiController,
    required this.emailController,
    required this.passwordController,
    required this.companyFocus,
    required this.apiFocus,
    required this.emailFocus,
    required this.passwordFocus,
    required this.showTechnicalFields,
    required this.loading,
    required this.error,
    required this.onLogin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController companyController;
  final TextEditingController apiController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool showTechnicalFields;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 20),
              Image.asset(
                'assets/brand/lyncar_logo_clean.png',
                height: 78,
                fit: BoxFit.contain,
              ),
              const SizedBox(height: 28),
              _LoginPanel(
                formKey: formKey,
                companyController: companyController,
                apiController: apiController,
                emailController: emailController,
                passwordController: passwordController,
                companyFocus: companyFocus,
                apiFocus: apiFocus,
                emailFocus: emailFocus,
                passwordFocus: passwordFocus,
                showTechnicalFields: showTechnicalFields,
                loading: loading,
                error: error,
                onLogin: onLogin,
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Image.asset(
          'assets/brand/lyncar_logo_clean.png',
          width: 520,
          fit: BoxFit.contain,
        ),
        const SizedBox(height: 26),
        const Text(
          'TUDO DA SUA EMPRESA. CONECTADO.',
          style: TextStyle(
            color: Color(0xFFE6F5FF),
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: 3.2,
          ),
        ),
        const SizedBox(height: 30),
        Container(
          width: 360,
          height: 1,
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0x0000AEFF), Color(0xFF00AEFF)],
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginPanel extends StatefulWidget {
  const _LoginPanel({
    required this.formKey,
    required this.companyController,
    required this.apiController,
    required this.emailController,
    required this.passwordController,
    required this.companyFocus,
    required this.apiFocus,
    required this.emailFocus,
    required this.passwordFocus,
    required this.showTechnicalFields,
    required this.loading,
    required this.error,
    required this.onLogin,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController companyController;
  final TextEditingController apiController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;
  final FocusNode emailFocus;
  final FocusNode passwordFocus;
  final bool showTechnicalFields;
  final bool loading;
  final String? error;
  final VoidCallback onLogin;

  @override
  State<_LoginPanel> createState() => _LoginPanelState();
}

class _LoginPanelState extends State<_LoginPanel> {
  final _passwordVisibilityFocus = FocusNode(skipTraversal: true);
  bool _showPassword = false;
  late bool _showEnvironment = widget.showTechnicalFields;

  @override
  void dispose() {
    _passwordVisibilityFocus.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _LoginPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.showTechnicalFields && widget.showTechnicalFields) {
      _showEnvironment = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final dense = widget.showTechnicalFields && viewportHeight < 820;
    final panelPadding = dense
        ? const EdgeInsets.fromLTRB(28, 24, 28, 24)
        : const EdgeInsets.fromLTRB(34, 32, 34, 28);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xF20A1B33),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x5500A7FF), width: 1.1),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000A16),
            blurRadius: 42,
            offset: Offset(0, 28),
          ),
        ],
      ),
      child: Padding(
        padding: panelPadding,
        child: AutofillGroup(
          child: Form(
            key: widget.formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _LoginHeader(dense: dense),
                SizedBox(height: dense ? 12 : 18),
                if (widget.showTechnicalFields) ...[
                  _EnvironmentToggle(
                    expanded: _showEnvironment,
                    company: widget.companyController.text,
                    api: widget.apiController.text,
                    onTap: () =>
                        setState(() => _showEnvironment = !_showEnvironment),
                  ),
                  AnimatedCrossFade(
                    firstChild: const SizedBox.shrink(),
                    secondChild: Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _EnvironmentFields(
                        companyController: widget.companyController,
                        apiController: widget.apiController,
                        companyFocus: widget.companyFocus,
                        apiFocus: widget.apiFocus,
                        emailFocus: widget.emailFocus,
                      ),
                    ),
                    crossFadeState: _showEnvironment
                        ? CrossFadeState.showSecond
                        : CrossFadeState.showFirst,
                    duration: const Duration(milliseconds: 180),
                  ),
                  SizedBox(height: dense ? 10 : 14),
                ],
                _LoginTextField(
                  controller: widget.emailController,
                  focusNode: widget.emailFocus,
                  nextFocus: widget.passwordFocus,
                  label: 'Usuário',
                  hint: 'E-mail',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [
                    AutofillHints.username,
                    AutofillHints.email,
                  ],
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Informe o usuário.'
                      : null,
                ),
                SizedBox(height: dense ? 10 : 14),
                _LoginTextField(
                  controller: widget.passwordController,
                  focusNode: widget.passwordFocus,
                  label: 'Senha',
                  hint: 'Sua senha',
                  icon: Icons.lock_outline,
                  obscureText: !_showPassword,
                  autofillHints: const [AutofillHints.password],
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => widget.onLogin(),
                  suffixIcon: IconButton(
                    tooltip: _showPassword ? 'Ocultar senha' : 'Mostrar senha',
                    focusNode: _passwordVisibilityFocus,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      foregroundColor: const Color(0xFFE3F2FF),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      fixedSize: const Size(44, 44),
                    ),
                    onPressed: () {
                      setState(() => _showPassword = !_showPassword);
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted) widget.passwordFocus.requestFocus();
                      });
                    },
                    icon: Icon(
                      _showPassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                    ),
                  ),
                  validator: (value) => value == null || value.isEmpty
                      ? 'Informe a senha.'
                      : null,
                ),
                SizedBox(height: dense ? 12 : 18),
                if (widget.error != null) ...[
                  _ErrorBox(message: widget.error!),
                  const SizedBox(height: 10),
                ],
                SizedBox(
                  height: dense ? 50 : 54,
                  child: FilledButton.icon(
                    onPressed: widget.loading ? null : widget.onLogin,
                    icon: widget.loading
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.login_rounded),
                    label: Text(widget.loading ? 'Entrando...' : 'Entrar'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF1398F8),
                      disabledBackgroundColor: const Color(0xFF2D5C82),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      textStyle: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                if (!widget.showTechnicalFields) const _ProtectedAccess(),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EnvironmentToggle extends StatelessWidget {
  const _EnvironmentToggle({
    required this.expanded,
    required this.company,
    required this.api,
    required this.onTap,
  });

  final bool expanded;
  final String company;
  final String api;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0x2613A8FF),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.tune_rounded,
                color: Color(0xFF7DD3FC),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Ambiente local: $company  |  $api',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFFD9E7F5),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Icon(
                expanded
                    ? Icons.keyboard_arrow_up_rounded
                    : Icons.keyboard_arrow_down_rounded,
                color: const Color(0xFFD9E7F5),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvironmentFields extends StatelessWidget {
  const _EnvironmentFields({
    required this.companyController,
    required this.apiController,
    required this.companyFocus,
    required this.apiFocus,
    required this.emailFocus,
  });

  final TextEditingController companyController;
  final TextEditingController apiController;
  final FocusNode companyFocus;
  final FocusNode apiFocus;
  final FocusNode emailFocus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _LoginTextField(
          controller: companyController,
          focusNode: companyFocus,
          nextFocus: apiFocus,
          label: 'Empresa',
          hint: 'Ex.: master',
          icon: Icons.apartment_outlined,
          compact: true,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Informe a empresa.'
              : null,
        ),
        const SizedBox(height: 10),
        _LoginTextField(
          controller: apiController,
          focusNode: apiFocus,
          nextFocus: emailFocus,
          label: 'Servidor API',
          hint: 'http://127.0.0.1:8000',
          icon: Icons.hub_outlined,
          keyboardType: TextInputType.url,
          compact: true,
          validator: (value) => value == null || value.trim().isEmpty
              ? 'Informe o servidor.'
              : null,
        ),
      ],
    );
  }
}

class _ProtectedAccess extends StatelessWidget {
  const _ProtectedAccess();

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.verified_user_outlined, color: Color(0xFF38BDF8), size: 20),
        SizedBox(width: 8),
        Flexible(
          child: Text(
            'Acesso protegido',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFD9E7F5),
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginHeader extends StatelessWidget {
  const _LoginHeader({required this.dense});

  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: dense ? 44 : 52,
          height: dense ? 44 : 52,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: const Color(0x1A38BDF8),
            border: Border.all(color: const Color(0x6638BDF8)),
          ),
          child: Icon(
            Icons.lock_outline_rounded,
            color: const Color(0xFF38BDF8),
            size: dense ? 24 : 27,
          ),
        ),
        SizedBox(height: dense ? 10 : 16),
        Text(
          'Bem-vindo',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: dense ? 26 : 30,
            fontWeight: FontWeight.w900,
            letterSpacing: 0,
          ),
        ),
        SizedBox(height: dense ? 4 : 8),
        const Text(
          'Acesse sua operação LYNCAR',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Color(0xFFAFC3D8),
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _LoginTextField extends StatelessWidget {
  const _LoginTextField({
    required this.controller,
    required this.focusNode,
    required this.label,
    required this.hint,
    required this.icon,
    this.nextFocus,
    this.keyboardType,
    this.obscureText = false,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.suffixIcon,
    this.validator,
    this.onSubmitted,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? nextFocus;
  final String label;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final bool obscureText;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final ValueChanged<String>? onSubmitted;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      keyboardType: keyboardType,
      obscureText: obscureText,
      textInputAction: textInputAction,
      autofillHints: autofillHints,
      validator: validator,
      onFieldSubmitted: (value) {
        if (onSubmitted != null) {
          onSubmitted!(value);
          return;
        }
        nextFocus?.requestFocus();
      },
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w700,
      ),
      cursorColor: const Color(0xFF7DD3FC),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon),
        suffixIcon: suffixIcon,
        isDense: compact,
        contentPadding: EdgeInsets.symmetric(
          horizontal: 14,
          vertical: compact ? 14 : 18,
        ),
        filled: true,
        fillColor: const Color(0x66132544),
        labelStyle: const TextStyle(
          color: Color(0xFFE3F2FF),
          fontWeight: FontWeight.w800,
        ),
        hintStyle: const TextStyle(color: Color(0xFF8FA7BF)),
        prefixIconColor: const Color(0xFFE3F2FF),
        suffixIconColor: const Color(0xFFE3F2FF),
        errorStyle: const TextStyle(
          color: Color(0xFFFFB4B4),
          fontWeight: FontWeight.w700,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1C8FE3), width: 1.2),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF70D4FF), width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFF7A7A), width: 1.4),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFFFFB4B4), width: 1.6),
        ),
      ),
    );
  }
}

class _ErrorBox extends StatelessWidget {
  const _ErrorBox({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0x33EF4444),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0x99FCA5A5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: Color(0xFFFFC4C4), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Color(0xFFFFE1E1),
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginBackground extends StatelessWidget {
  const _LoginBackground();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF020817), Color(0xFF061A3C), Color(0xFF092456)],
        ),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: Opacity(
              opacity: 0.18,
              child: Image.asset(
                'assets/brand/lyncar_y_detail.png',
                fit: BoxFit.cover,
                alignment: Alignment.bottomLeft,
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.84, -0.62),
                  radius: 0.9,
                  colors: [
                    const Color(0xFF0C6FDD).withValues(alpha: 0.32),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    const Color(0xFF020817).withValues(alpha: 0.24),
                    Colors.transparent,
                    const Color(0xFF031331).withValues(alpha: 0.38),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
