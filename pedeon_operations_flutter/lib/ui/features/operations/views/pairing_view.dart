import 'package:flutter/material.dart';
import '../../../../data/services/saved_login_store.dart';
import '../view_models/operations_view_model.dart';

class PairingView extends StatefulWidget {
  const PairingView({super.key, required this.viewModel});
  final OperationsViewModel viewModel;
  @override
  State<PairingView> createState() => _PairingViewState();
}

class _PairingViewState extends State<PairingView> {
  final email = TextEditingController();
  final password = TextEditingController();
  final pairingCode = TextEditingController();
  int? selectedTerminalId;
  bool rememberLogin = false;
  SavedLogin? selectedLogin;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    pairingCode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.transparent,
    body: Stack(
      fit: StackFit.expand,
      children: [
        Image.asset(
          'assets/brand/pedeon_login_background.png',
          fit: BoxFit.cover,
        ),
        Container(color: const Color(0x300C2538)),
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Card(
                color: const Color(0xB80C2538),
                elevation: 18,
                shadowColor: const Color(0x99000000),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                  side: const BorderSide(color: Color(0x66FFFFFF)),
                ),
                child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.point_of_sale_rounded,
                    size: 56,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Entrar no PedeOn',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Use o mesmo acesso da Lyncar. A ativação deste PDV será feita automaticamente.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xE6FFFFFF)),
                  ),
                  const SizedBox(height: 24),
                  Autocomplete<SavedLogin>(
                    displayStringForOption: (item) => item.email,
                    optionsBuilder: (value) {
                      final query = value.text.trim().toLowerCase();
                      return widget.viewModel.savedLogins.where(
                        (item) => query.isEmpty || item.email.toLowerCase().contains(query),
                      );
                    },
                    onSelected: (item) {
                      selectedLogin = item;
                      email.text = item.email;
                      password.text = item.password;
                      rememberLogin = true;
                    },
                    fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
                      if (controller.text != email.text) controller.text = email.text;
                      return TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: TextInputType.emailAddress,
                        onChanged: (value) => email.text = value,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Usuário / e-mail',
                          labelStyle: const TextStyle(color: Color(0xDDFFFFFF)),
                          prefixIcon: const Icon(Icons.person_outline_rounded),
                          prefixIconColor: Colors.white,
                          suffixIconColor: Colors.white,
                          filled: true,
                          fillColor: const Color(0x26FFFFFF),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Color(0xB3FFFFFF)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: const BorderSide(color: Colors.white, width: 2),
                          ),
                          suffixIcon: widget.viewModel.savedLogins.isEmpty
                              ? null
                              : const Icon(Icons.arrow_drop_down_rounded),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: password,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      labelText: 'Senha',
                      prefixIcon: Icon(Icons.lock_outline_rounded),
                      labelStyle: TextStyle(color: Color(0xDDFFFFFF)),
                      prefixIconColor: Colors.white,
                      filled: true,
                      fillColor: Color(0x26FFFFFF),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: Color(0xB3FFFFFF)),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(14)),
                        borderSide: BorderSide(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Checkbox(
                        value: rememberLogin,
                        onChanged: (value) => setState(
                          () => rememberLogin = value ?? false,
                        ),
                      ),
                      const Text(
                        'Lembrar usuário e senha',
                        style: TextStyle(color: Colors.white),
                      ),
                      const Spacer(),
                      if (selectedLogin != null)
                        IconButton(
                          tooltip: 'Remover acesso salvo',
                          onPressed: () async {
                            await widget.viewModel.removeSavedLogin(selectedLogin!.email);
                            setState(() {
                              selectedLogin = null;
                              rememberLogin = false;
                              password.clear();
                            });
                          },
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.white),
                        ),
                    ],
                  ),
                  if (widget.viewModel.terminalChoices.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      initialValue: selectedTerminalId,
                      decoration: const InputDecoration(
                        labelText: 'PDV autorizado',
                        prefixIcon: Icon(Icons.point_of_sale_rounded),
                      ),
                      items: [
                        for (final item in widget.viewModel.terminalChoices)
                          DropdownMenuItem(
                            value: item['id'] as int,
                            child: Text(
                              '${item['device_label'] ?? 'Caixa'} · ${item['cash_register_number']}',
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => selectedTerminalId = value),
                    ),
                  ],
                  if (widget.viewModel.error case final error?) ...[
                    const SizedBox(height: 12),
                    Text(
                      error,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: () async {
                      await widget.viewModel.login(
                        email.text.trim(),
                        password.text,
                        terminalId: selectedTerminalId,
                      );
                      if (widget.viewModel.error == null) {
                        await widget.viewModel.rememberLogin(
                          email: email.text.trim(),
                          password: password.text,
                          remember: rememberLogin,
                        );
                      }
                    },
                    icon: const Icon(Icons.login_rounded),
                    label: const Padding(
                      padding: EdgeInsets.all(14),
                      child: Text('Entrar'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(color: Color(0x66FFFFFF)),
                  const SizedBox(height: 12),
                  const Text(
                    'Outro computador nesta loja?',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Digite o código exibido pelo Edge para conectar este dispositivo.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xCCFFFFFF)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: pairingCode,
                    textCapitalization: TextCapitalization.characters,
                    style: const TextStyle(color: Colors.white, letterSpacing: 2),
                    decoration: const InputDecoration(
                      labelText: 'Código do Edge',
                      labelStyle: TextStyle(color: Color(0xDDFFFFFF)),
                      prefixIcon: Icon(Icons.key_rounded),
                      prefixIconColor: Colors.white,
                      filled: true,
                      fillColor: Color(0x26FFFFFF),
                    ),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: () => widget.viewModel.pairWithCode(pairingCode.text),
                    icon: const Icon(Icons.link_rounded),
                    label: const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Conectar por código'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        ),
      ),
      ],
    ),
  );
}
