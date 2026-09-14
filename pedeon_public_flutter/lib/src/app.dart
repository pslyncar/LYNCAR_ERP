import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/catalog_api_service.dart';
import 'data/catalog_repository.dart';
import 'data/salon_edge_service.dart';
import 'presentation/salon_entry_screen.dart';
import 'presentation/salon_order_screen.dart';
import 'presentation/storefront_screen.dart';

class PedeOnPublicApp extends StatefulWidget {
  const PedeOnPublicApp({super.key, this.repository});
  final CatalogRepository? repository;

  @override
  State<PedeOnPublicApp> createState() => _PedeOnPublicAppState();
}

class _PedeOnPublicAppState extends State<PedeOnPublicApp> {
  late final CatalogRepository _repository =
      widget.repository ?? HttpCatalogRepository(CatalogApiService());
  late final GoRouter _router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => const _AddressRequiredScreen()),
      GoRoute(
        path: '/:slug/salao',
        builder: (_, state) =>
            _SalonLoginScreen(slug: state.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/:slug/salao/:accountType/:accountNumber',
        builder: (_, state) {
          final accountNumber = int.tryParse(
            state.pathParameters['accountNumber'] ?? '',
          );
          if (accountNumber == null || accountNumber < 1) {
            return const _AddressRequiredScreen();
          }
          return _SalonLoginScreen(
            slug: state.pathParameters['slug']!,
            accountType: state.pathParameters['accountType']!,
            accountNumber: accountNumber,
          );
        },
      ),
      GoRoute(
        path: '/:slug',
        builder: (_, state) => StorefrontScreen(
          slug: state.pathParameters['slug']!,
          repository: _repository,
          initialProductId: int.tryParse(
            state.uri.queryParameters['produto'] ?? '',
          ),
          initialSocialCode: state.uri.queryParameters['social_code'],
        ),
      ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final base = ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF075E6F),
        primary: const Color(0xFF075E6F),
        secondary: const Color(0xFFF29A3F),
        surface: const Color(0xFFFFFBF6),
      ),
      useMaterial3: true,
    );
    return MaterialApp.router(
      title: 'PedeOn by Lyncar',
      debugShowCheckedModeBanner: false,
      routerConfig: _router,
      theme: base.copyWith(
        textTheme: GoogleFonts.manropeTextTheme(base.textTheme),
        scaffoldBackgroundColor: const Color(0xFFF8F5F0),
        cardTheme: const CardThemeData(
          elevation: 0,
          color: Colors.white,
          margin: EdgeInsets.zero,
        ),
      ),
    );
  }
}

class _SalonLoginScreen extends StatefulWidget {
  const _SalonLoginScreen({
    required this.slug,
    this.accountType,
    this.accountNumber,
  });
  final String slug;
  final String? accountType;
  final int? accountNumber;
  @override
  State<_SalonLoginScreen> createState() => _SalonLoginScreenState();
}

class _SalonLoginScreenState extends State<_SalonLoginScreen> {
  final _code = TextEditingController();
  final _pin = TextEditingController();
  final _service = SalonEdgeService();
  bool _loading = false;
  @override
  void dispose() {
    _code.dispose();
    _pin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PedeOn Salão')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Acesso do garçom',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              const Text(
                'Use o código e o PIN do garçom. Este acesso não permite caixa ou configurações.',
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _code,
                decoration: const InputDecoration(
                  labelText: 'Código do garçom',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pin,
                obscureText: true,
                onSubmitted: (_) => _login(),
                decoration: const InputDecoration(labelText: 'PIN'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _loading ? null : _login,
                child: Text(_loading ? 'Entrando...' : 'Entrar no salão'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  Future<void> _login() async {
    setState(() => _loading = true);
    try {
      final token = await _service.login(_code.text.trim(), _pin.text);
      if (!mounted) return;
      if (widget.accountNumber != null && widget.accountType != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SalonOrderScreen(
              slug: widget.slug,
              accountType: widget.accountType!,
              accountNumber: widget.accountNumber!,
              service: _service,
              sessionToken: token,
            ),
          ),
        );
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (entryContext) => SalonEntryScreen(
              slug: widget.slug,
              onAccountSelected: (type, number) =>
                  Navigator.of(entryContext).push(
                    MaterialPageRoute(
                      builder: (_) => SalonOrderScreen(
                        slug: widget.slug,
                        accountType: type,
                        accountNumber: number,
                        service: _service,
                        sessionToken: token,
                      ),
                    ),
                  ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('$error')));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

class _AddressRequiredScreen extends StatelessWidget {
  const _AddressRequiredScreen();

  @override
  Widget build(BuildContext context) => const Scaffold(
    body: Center(
      child: Padding(
        padding: EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.storefront_rounded, size: 64),
            SizedBox(height: 16),
            Text('Abra o endereço do cardápio da sua loja.'),
            SizedBox(height: 8),
            Text('PedeOn by Lyncar'),
          ],
        ),
      ),
    ),
  );
}
