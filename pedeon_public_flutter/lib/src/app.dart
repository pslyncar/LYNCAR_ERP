import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'data/catalog_api_service.dart';
import 'data/catalog_repository.dart';
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
      GoRoute(path: '/', builder: (_, state) => _storefrontFor(state)),
      GoRoute(path: '/cardapio', builder: (_, state) => _storefrontFor(state)),
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

  Widget _storefrontFor(GoRouterState state) {
    final slug = _slugFromPage(state.uri);
    if (slug == null) return const _AddressRequiredScreen();
    return StorefrontScreen(
      slug: slug,
      repository: _repository,
      initialProductId: int.tryParse(
        state.uri.queryParameters['produto'] ?? '',
      ),
      initialSocialCode: state.uri.queryParameters['social_code'],
    );
  }

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

String? _slugFromPage(Uri uri) {
  const suffix = '.lyncar.com.br';
  final host = uri.host.toLowerCase();
  if (host.endsWith(suffix)) {
    final subdomain = host.substring(0, host.length - suffix.length);
    if (subdomain.isNotEmpty &&
        !subdomain.contains('.') &&
        !{'www', 'api', 'pedeon'}.contains(subdomain)) {
      return subdomain;
    }
  }
  final pathSlug = uri.pathSegments.isNotEmpty ? uri.pathSegments.first : null;
  if (pathSlug == null || pathSlug == 'cardapio' || pathSlug == 'salao') {
    return null;
  }
  return pathSlug;
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
