import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/salon_edge_service.dart';
import 'salon_order_screen.dart';

/// Fluxo local do salão: autentica o garçom no Edge e só depois abre as mesas.
/// O site público nunca é usado para esta operação.
class SalonLocalFlowScreen extends StatefulWidget {
  const SalonLocalFlowScreen({
    super.key,
    required this.slug,
    this.initialAccountNumber,
  });

  final String slug;
  final int? initialAccountNumber;

  @override
  State<SalonLocalFlowScreen> createState() => _SalonLocalFlowScreenState();
}

class _SalonLocalFlowScreenState extends State<SalonLocalFlowScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _service = SalonEdgeService();
  String? _token;
  String? _userName;
  int? _accountNumber;
  String? _error;
  bool _loading = false;

  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final token = _token;
    final accountNumber = _accountNumber;
    if (token != null && accountNumber != null) {
      return SalonOrderScreen(
        slug: widget.slug,
        accountType: 'mesa',
        accountNumber: accountNumber,
        service: _service,
        sessionToken: token,
      );
    }
    if (token != null) {
      return SalonEntryScreen(
        slug: widget.slug,
        onAccountSelected: (type, number) => setState(() {
          _accountNumber = number;
        }),
      );
    }
    return _LoginScreen(
      code: _code,
      pin: _pin,
      userName: _userName,
      error: _error,
      loading: _loading,
      onSubmit: _login,
    );
  }

  Future<void> _login() async {
    if (_code.text.trim().isEmpty || _pin.text.isEmpty) {
      setState(() => _error = 'Informe o código e o PIN do garçom.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final token = await _service.login(_code.text.trim(), _pin.text);
      if (!mounted) return;
      setState(() {
        _token = token;
        _userName = _code.text.trim();
        _loading = false;
        _accountNumber = widget.initialAccountNumber;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }
}

class _LoginScreen extends StatelessWidget {
  const _LoginScreen({
    required this.code,
    required this.pin,
    required this.userName,
    required this.error,
    required this.loading,
    required this.onSubmit,
  });

  final TextEditingController code;
  final TextEditingController pin;
  final String? userName;
  final String? error;
  final bool loading;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PedeOn salão')),
    body: Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Icon(Icons.table_restaurant_rounded, size: 56),
                  const SizedBox(height: 12),
                  Text('Entrar no salão', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('A operação é local e passa pelo Edge desta loja.'),
                  const SizedBox(height: 24),
                  TextField(
                    key: const Key('salon-code'),
                    controller: code,
                    textCapitalization: TextCapitalization.characters,
                    decoration: const InputDecoration(labelText: 'Código do garçom'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    key: const Key('salon-pin'),
                    controller: pin,
                    obscureText: true,
                    decoration: const InputDecoration(labelText: 'PIN'),
                    onSubmitted: (_) => onSubmit(),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 16),
                    Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    onPressed: loading ? null : onSubmit,
                    icon: loading
                        ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.login_rounded),
                    label: Text(loading ? 'Validando…' : 'Entrar'),
                  ),
                  if (userName != null) Text(userName!),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class SalonEntryScreen extends StatefulWidget {
  const SalonEntryScreen({
    super.key,
    required this.slug,
    this.onAccountSelected,
  });

  final String slug;
  final void Function(String accountType, int accountNumber)? onAccountSelected;

  @override
  State<SalonEntryScreen> createState() => _SalonEntryScreenState();
}

class _SalonEntryScreenState extends State<SalonEntryScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('PedeOn salão')),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 850
                ? 6
                : constraints.maxWidth >= 560
                ? 4
                : 3;
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Text(
                  'Contas do salão',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 6),
                const Text(
                  'Mesas e comandas usam a mesma conta. Selecione o número para lançar o pedido.',
                ),
                const SizedBox(height: 24),
                Text(
                  'Escolha a mesa ou comanda',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.25,
                  ),
                  itemCount: 30,
                  itemBuilder: (context, index) {
                    final number = index + 1;
                    return Card(
                      key: Key('salon-account-$number'),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => _openAccount(number),
                        child: Center(
                          child: Text(
                            'Mesa / comanda $number',
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _openAccount(int number) {
    final callback = widget.onAccountSelected;
    if (callback != null) {
      callback('mesa', number);
      return;
    }
    context.go('/${widget.slug}/salao/mesa/$number');
  }
}
