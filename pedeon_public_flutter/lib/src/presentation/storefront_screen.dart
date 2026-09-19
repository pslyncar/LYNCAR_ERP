import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:go_router/go_router.dart';

import '../data/catalog_repository.dart';
import '../domain/catalog_models.dart';
import '../domain/customer_auth.dart';
import 'checkout_dialog.dart';
import 'customer_access_dialog.dart';
import 'product_detail_dialog.dart';
import 'storefront_view_model.dart';

class StorefrontScreen extends StatefulWidget {
  const StorefrontScreen({
    required this.slug,
    required this.repository,
    this.initialProductId,
    this.initialCustomer,
    this.initialSocialCode,
    this.initialSocialProvider,
    super.key,
  });

  final String slug;
  final CatalogRepository repository;
  final int? initialProductId;
  final CustomerSession? initialCustomer;
  final String? initialSocialCode;
  final String? initialSocialProvider;

  @override
  State<StorefrontScreen> createState() => _StorefrontScreenState();
}

class _StorefrontScreenState extends State<StorefrontScreen> {
  late final StorefrontViewModel viewModel;
  bool _initialProductHandled = false;
  int _feedbackSequence = 0;
  Timer? _feedbackTimer;

  @override
  void initState() {
    super.initState();
    viewModel = StorefrontViewModel(
      slug: widget.slug,
      repository: widget.repository,
    );
    viewModel.customer = widget.initialCustomer;
    viewModel.load().then((_) async {
      final code = widget.initialSocialCode;
      if (code != null && code.isNotEmpty) {
        try {
          await viewModel.exchangeSocialCode(
            code,
            widget.initialSocialProvider ?? 'google',
          );
          if (mounted) GoRouter.of(context).go(_storefrontRoute());
        } catch (_) {
          // The view model exposes the error in the storefront state.
        }
      }
      _openInitialProduct();
    });
  }

  @override
  void dispose() {
    _feedbackTimer?.cancel();
    viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: viewModel,
    builder: (context, _) {
      if (viewModel.loading && viewModel.store == null) {
        return const _LoadingStorefront();
      }
      if (viewModel.error != null && viewModel.store == null) {
        return _ErrorStorefront(
          message: viewModel.error!,
          onRetry: viewModel.load,
        );
      }
      final store = viewModel.store;
      if (store == null) return const SizedBox.shrink();
      final compact = MediaQuery.sizeOf(context).width < 700;
      final theme = _storeTheme(context, store);
      return Theme(
        data: theme,
        child: Scaffold(
          body: _CatalogBody(
            viewModel: viewModel,
            onOpenCart: () => _openCart(context),
            onAdd: (product) => _addProduct(context, product),
            onCustomerAccess: () => _openCustomerAccess(context),
          ),
          floatingActionButton: !compact && viewModel.itemCount > 0
              ? FloatingActionButton.extended(
                  key: const Key('open-cart-floating'),
                  onPressed: () => _openCart(context),
                  icon: Badge(
                    label: Text('${viewModel.itemCount}'),
                    child: const Icon(Icons.shopping_bag_outlined),
                  ),
                  label: Text('Ver pedido • ${_currency(viewModel.subtotal)}'),
                )
              : null,
          bottomNavigationBar: compact && viewModel.itemCount > 0
              ? _MobileCartBar(
                  count: viewModel.itemCount,
                  subtotal: viewModel.subtotal,
                  onTap: () => _openCart(context),
                )
              : null,
        ),
      );
    },
  );

  ThemeData _storeTheme(BuildContext context, Storefront store) {
    final raw = store.accentColor.replaceFirst('#', '');
    final parsed = int.tryParse(raw, radix: 16);
    final seed = parsed == null
        ? const Color(0xFF075E6F)
        : Color(0xFF000000 | (parsed | 0xFF000000));
    final brightness = store.darkMode ? Brightness.dark : Brightness.light;
    return Theme.of(context).copyWith(
      brightness: brightness,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: brightness,
      ).copyWith(primary: seed, secondary: seed),
      scaffoldBackgroundColor: store.darkMode
          ? const Color(0xFF191919)
          : const Color(0xFFF8F7F3),
    );
  }

  Future<void> _addProduct(BuildContext context, CatalogProduct product) async {
    final configuration = await showProductDetail(
      context,
      product: product,
      imageUrl: viewModel.imageUrl(product.imageUrl),
      storeSlug: widget.slug,
    );
    if (configuration == null || !context.mounted) return;
    viewModel.addConfigured(
      product: product,
      quantity: configuration.quantity,
      selectedOptions: configuration.selectedOptions,
      customerNotes: configuration.notes,
    );
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    final feedbackSequence = ++_feedbackSequence;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
          content: Text(
            configuration.quantity == 1
                ? '${product.name} foi adicionado.'
                : '${configuration.quantity}× ${product.name} foram adicionados com a mesma configuração.',
          ),
          action: SnackBarAction(
            label: 'Ver carrinho',
            onPressed: () => _openCart(context),
          ),
        ),
      );
    _feedbackTimer?.cancel();
    _feedbackTimer = Timer(const Duration(milliseconds: 2400), () {
      if (!mounted || feedbackSequence != _feedbackSequence) return;
      ScaffoldMessenger.maybeOf(context)?.removeCurrentSnackBar();
    });
  }

  Future<void> _openInitialProduct() async {
    final productId = widget.initialProductId;
    if (_initialProductHandled || productId == null || !mounted) return;
    _initialProductHandled = true;
    CatalogProduct? product = viewModel.products
        .where((item) => item.id == productId)
        .firstOrNull;
    product ??= await widget.repository.loadProduct(widget.slug, productId);
    if (!mounted || product == null || !product.available) return;
    await _addProduct(context, product);
  }

  Future<void> _openCustomerAccess(BuildContext context) async {
    final customer = viewModel.customer;
    if (customer == null) {
      await showCustomerAccessDialog(context, viewModel: viewModel);
      return;
    }
    final action = await showModalBottomSheet<_CustomerMenuAction>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(customerDisplayName(customer.name)),
              subtitle: Text(customer.email),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.logout_rounded),
              title: const Text('Sair'),
              onTap: () =>
                  Navigator.of(context).pop(_CustomerMenuAction.logout),
            ),
          ],
        ),
      ),
    );
    if (action == _CustomerMenuAction.logout) {
      await viewModel.logoutCustomer();
      if (!context.mounted) return;
      GoRouter.of(context).go(_storefrontRoute());
    }
  }

  String _storefrontRoute() {
    final host = Uri.base.host.toLowerCase();
    if (host.endsWith('.lyncar.com.br') &&
        !{'www', 'api', 'pedeon'}.contains(host.split('.').first)) {
      return '/cardapio';
    }
    return '/${widget.slug}';
  }

  Future<void> _editLine(BuildContext context, CartLine line) async {
    final configuration = await showProductDetail(
      context,
      product: line.product,
      imageUrl: viewModel.imageUrl(line.product.imageUrl),
      storeSlug: widget.slug,
      initialConfiguration: ProductConfiguration(
        quantity: line.quantity,
        selectedOptions: line.selectedOptions,
        notes: line.customerNotes,
      ),
    );
    if (configuration == null) return;
    viewModel.replaceConfigured(
      original: line,
      quantity: configuration.quantity,
      selectedOptions: configuration.selectedOptions,
      customerNotes: configuration.notes,
    );
  }

  Future<void> _openCart(BuildContext context) {
    if (MediaQuery.sizeOf(context).width < 700) {
      return showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        showDragHandle: true,
        backgroundColor: Colors.white,
        constraints: const BoxConstraints(maxWidth: 680),
        builder: (_) => ListenableBuilder(
          listenable: viewModel,
          builder: (_, _) => SizedBox(
            height: MediaQuery.sizeOf(context).height * .82,
            child: _CartPanel(
              viewModel: viewModel,
              onEdit: (line) => _editLine(context, line),
            ),
          ),
        ),
      );
    }
    return showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fechar carrinho',
      barrierColor: Colors.black45,
      transitionDuration: const Duration(milliseconds: 240),
      transitionBuilder: (_, animation, _, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
      pageBuilder: (_, _, _) => Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.white,
          child: SafeArea(
            left: false,
            child: SizedBox(
              width: 440,
              height: double.infinity,
              child: ListenableBuilder(
                listenable: viewModel,
                builder: (_, _) => _CartPanel(
                  viewModel: viewModel,
                  onEdit: (line) => _editLine(context, line),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogBody extends StatefulWidget {
  const _CatalogBody({
    required this.viewModel,
    required this.onOpenCart,
    required this.onAdd,
    required this.onCustomerAccess,
  });
  final StorefrontViewModel viewModel;
  final VoidCallback onOpenCart;
  final ValueChanged<CatalogProduct> onAdd;
  final VoidCallback onCustomerAccess;

  @override
  State<_CatalogBody> createState() => _CatalogBodyState();
}

class _CatalogBodyState extends State<_CatalogBody> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _sectionKeys = {};
  List<_CatalogSection> _currentSections = const [];
  bool _programmaticScroll = false;
  bool _categoryUpdateScheduled = false;

  StorefrontViewModel get viewModel => widget.viewModel;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateActiveCategory);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_updateActiveCategory)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final store = viewModel.store!;
    final sections = _sections();
    _currentSections = sections;
    final compact = MediaQuery.sizeOf(context).width < 700;
    return RefreshIndicator.adaptive(
      onRefresh: viewModel.load,
      child: CustomScrollView(
        key: const Key('catalog-scroll'),
        controller: _scrollController,
        physics: compact
            ? const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              )
            : null,
        scrollCacheExtent: ScrollCacheExtent.pixels(compact ? 650 : 900),
        slivers: [
          SliverToBoxAdapter(
            child: _StoreHero(
              store: store,
              viewModel: viewModel,
              onOpenCart: widget.onOpenCart,
              onCustomerAccess: widget.onCustomerAccess,
            ),
          ),
          if (sections.any((section) => section.category != null))
            SliverPersistentHeader(
              pinned: true,
              delegate: _CategoryHeaderDelegate(
                categories: sections
                    .map((section) => section.category)
                    .whereType<CatalogCategory>()
                    .toList(growable: false),
                selectedCategory: viewModel.selectedCategory,
                onTap: _scrollToCategory,
              ),
            ),
          if (viewModel.loading)
            const SliverToBoxAdapter(
              child: LinearProgressIndicator(minHeight: 2),
            ),
          if (viewModel.products.isEmpty && !viewModel.loading)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: _EmptyCatalog(),
            ),
          for (
            var sectionIndex = 0;
            sectionIndex < sections.length;
            sectionIndex++
          ) ...[
            SliverToBoxAdapter(
              child: _CategorySectionTitle(
                key: _sectionKeys.putIfAbsent(
                  sections[sectionIndex].key,
                  GlobalKey.new,
                ),
                title: sections[sectionIndex].title,
                itemCount: sections[sectionIndex].products.length,
              ),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                0,
                MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
                sectionIndex == sections.length - 1 ? 120 : 28,
              ),
              sliver: SliverGrid.builder(
                itemCount: sections[sectionIndex].products.length,
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 350,
                  mainAxisExtent: 390,
                  crossAxisSpacing: 18,
                  mainAxisSpacing: 18,
                ),
                itemBuilder: (context, index) {
                  final product = sections[sectionIndex].products[index];
                  return _ProductCard(
                    key: ValueKey('catalog-product-${product.id}'),
                    product: product,
                    imageUrl: viewModel.imageUrl(product.imageUrl),
                    onAdd: widget.onAdd,
                  );
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<_CatalogSection> _sections() {
    final productsByCategory = <int?, List<CatalogProduct>>{};
    for (final product in viewModel.products) {
      productsByCategory.putIfAbsent(product.categoryId, () => []).add(product);
    }
    final sections = <_CatalogSection>[];
    for (final category in viewModel.categories) {
      final products = productsByCategory.remove(category.id) ?? const [];
      if (products.isNotEmpty) {
        sections.add(_CatalogSection(category: category, products: products));
      }
    }
    final uncategorized = productsByCategory.remove(null) ?? const [];
    if (uncategorized.isNotEmpty) {
      sections.add(_CatalogSection(products: uncategorized));
    }
    return sections;
  }

  Future<void> _scrollToCategory(String? slug) async {
    final sections = _currentSections;
    final target = slug == null
        ? sections.firstOrNull
        : sections
              .where((section) => section.category?.slug == slug)
              .firstOrNull;
    if (target == null) {
      viewModel.selectCategory(slug);
      return;
    }
    final targetContext = _sectionKeys[target.key]?.currentContext;
    if (targetContext != null) {
      _programmaticScroll = true;
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeOutCubic,
        alignment: .08,
      );
    }
    viewModel.selectCategory(slug);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _programmaticScroll = false;
    });
  }

  void _updateActiveCategory() {
    if (_programmaticScroll || !_scrollController.hasClients) return;
    if (_categoryUpdateScheduled) return;
    _categoryUpdateScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _categoryUpdateScheduled = false;
      if (!mounted || _programmaticScroll || !_scrollController.hasClients) {
        return;
      }
      _resolveActiveCategory();
    });
  }

  void _resolveActiveCategory() {
    String? active;
    var closestTop = double.negativeInfinity;
    for (final section in _currentSections) {
      final sectionContext = _sectionKeys[section.key]?.currentContext;
      final renderBox = sectionContext?.findRenderObject() as RenderBox?;
      if (renderBox == null || !renderBox.attached) continue;
      final top = renderBox.localToGlobal(Offset.zero).dy;
      if (top <= 170 && top > closestTop) {
        closestTop = top;
        active = section.category?.slug;
      }
    }
    if (closestTop == double.negativeInfinity) {
      active = _currentSections.firstOrNull?.category?.slug;
    }
    viewModel.selectCategory(active);
  }
}

class _CatalogSection {
  const _CatalogSection({required this.products, this.category});
  final CatalogCategory? category;
  final List<CatalogProduct> products;
  int get key => category?.id ?? -1;
  String get title => category?.name ?? 'Outros produtos';
}

class _CategorySectionTitle extends StatelessWidget {
  const _CategorySectionTitle({
    required this.title,
    required this.itemCount,
    super.key,
  });
  final String title;
  final int itemCount;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
      28,
      MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
      14,
    ),
    child: Row(
      children: [
        Expanded(
          child: Text(
            title,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.w900,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        Text(
          '$itemCount ${itemCount == 1 ? 'item' : 'itens'}',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    ),
  );
}

class _StoreHero extends StatelessWidget {
  const _StoreHero({
    required this.store,
    required this.viewModel,
    required this.onOpenCart,
    required this.onCustomerAccess,
  });
  final Storefront store;
  final StorefrontViewModel viewModel;
  final VoidCallback onOpenCart;
  final VoidCallback onCustomerAccess;

  @override
  Widget build(BuildContext context) {
    final compact = MediaQuery.sizeOf(context).width < 600;
    final coverUrl = store.coverUrl;
    final scheme = Theme.of(context).colorScheme;
    final pageBackground = Theme.of(context).scaffoldBackgroundColor;
    return ColoredBox(
      color: pageBackground,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1280),
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 16 : 32,
                14,
                compact ? 16 : 32,
                0,
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      if (!compact)
                        Expanded(
                          child: _DeliveryLink(store: store, scheme: scheme),
                        )
                      else
                        Expanded(
                          child: _DeliveryLink(store: store, scheme: scheme),
                        ),
                      if (!compact)
                        SizedBox(
                          width: 360,
                          child: _CatalogSearch(viewModel: viewModel),
                        ),
                      const SizedBox(width: 12),
                      _CustomerAccessButton(
                        customer: viewModel.customer,
                        compact: compact,
                        onPressed: onCustomerAccess,
                      ),
                      const SizedBox(width: 8),
                      IconButton.filledTonal(
                        key: const Key('open-cart-header'),
                        tooltip: 'Abrir carrinho',
                        onPressed: onOpenCart,
                        style: IconButton.styleFrom(
                          backgroundColor: scheme.primary,
                          foregroundColor: Colors.white,
                        ),
                        icon: viewModel.itemCount > 0
                            ? Badge(
                                label: Text('${viewModel.itemCount}'),
                                child: const Icon(Icons.shopping_bag_outlined),
                              )
                            : const Icon(Icons.shopping_bag_outlined),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      // Em telas largas, a altura acompanha a largura da capa
                      // em vez de usar uma altura fixa que recorta a imagem.
                      final heroHeight = compact
                          ? 240.0
                          : (constraints.maxWidth / 3.2)
                                .clamp(390.0, 520.0)
                                .toDouble();
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(compact ? 22 : 28),
                        child: SizedBox(
                          height: heroHeight,
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              if (coverUrl != null && coverUrl.isNotEmpty)
                                Image.network(
                                  viewModel.imageUrl(coverUrl),
                                  fit: BoxFit.cover,
                                  alignment: Alignment.center,
                                  errorBuilder: (_, _, _) =>
                                      ColoredBox(color: scheme.primary),
                                ),
                              if (coverUrl == null || coverUrl.isEmpty)
                                ColoredBox(color: scheme.primary),
                              ColoredBox(
                                color: Colors.black.withValues(
                                  alpha: compact ? .25 : .35,
                                ),
                              ),
                              Positioned(
                                left: compact ? 18 : 34,
                                right: compact ? 18 : 34,
                                bottom: compact ? 18 : 28,
                                child: _StoreIdentity(
                                  store: store,
                                  viewModel: viewModel,
                                  compact: compact,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  if (compact) ...[
                    const SizedBox(height: 12),
                    _CatalogSearch(viewModel: viewModel),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CatalogSearch extends StatelessWidget {
  const _CatalogSearch({required this.viewModel});
  final StorefrontViewModel viewModel;

  @override
  Widget build(BuildContext context) => TextField(
    key: const Key('catalog-search'),
    onChanged: viewModel.setSearch,
    decoration: InputDecoration(
      hintText: 'Buscar no cardápio',
      prefixIcon: const Icon(Icons.search_rounded),
      filled: true,
      fillColor: Theme.of(context).colorScheme.surface,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(28),
        borderSide: BorderSide.none,
      ),
    ),
  );
}

class _DeliveryLink extends StatelessWidget {
  const _DeliveryLink({required this.store, required this.scheme});
  final Storefront store;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        border: Border.all(color: scheme.outline.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(28),
      ),
      child: Text(
        store.deliveryFee == null
            ? 'Calcular taxa e tempo de entrega'
            : 'Entrega ${store.deliveryFee == 0 ? 'grátis' : _currency(store.deliveryFee!)}',
        style: TextStyle(color: scheme.onSurface, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

class _StoreIdentity extends StatelessWidget {
  const _StoreIdentity({
    required this.store,
    required this.viewModel,
    required this.compact,
  });
  final Storefront store;
  final StorefrontViewModel viewModel;
  final bool compact;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      _StoreLogo(
        url: viewModel.imageUrl(store.logoUrl),
        name: store.displayName,
        compact: compact,
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              store.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white,
                fontSize: compact ? 22 : 30,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              store.acceptingOrders
                  ? 'Aberto'
                  : 'Fechado no momento • pedidos pausados',
              style: TextStyle(
                color: store.acceptingOrders
                    ? const Color(0xFFAEF4C7)
                    : const Color(0xFFFFD5A8),
                fontWeight: FontWeight.w700,
              ),
            ),
            if (!compact &&
                (store.deliveryFee != null || store.deliveryMinutesMin != null))
              Padding(
                padding: const EdgeInsets.only(top: 9),
                child: Wrap(
                  spacing: 8,
                  children: [
                    if (store.deliveryFee != null)
                      _HeroInfoChip(
                        icon: Icons.delivery_dining_outlined,
                        label: store.deliveryFee == 0
                            ? 'Entrega grátis'
                            : _currency(store.deliveryFee!),
                      ),
                    if (store.deliveryMinutesMin != null)
                      _HeroInfoChip(
                        icon: Icons.schedule_outlined,
                        label:
                            '${store.deliveryMinutesMin}–${store.deliveryMinutesMax ?? store.deliveryMinutesMin} min',
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

class _HeroInfoChip extends StatelessWidget {
  const _HeroInfoChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Chip(
    avatar: Icon(icon, size: 17, color: Colors.white70),
    label: Text(label),
    labelStyle: const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w700,
    ),
    backgroundColor: Colors.black.withValues(alpha: .28),
    side: BorderSide.none,
  );
}

class _CustomerAccessButton extends StatelessWidget {
  const _CustomerAccessButton({
    required this.customer,
    required this.compact,
    required this.onPressed,
  });

  final CustomerSession? customer;
  final bool compact;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final foreground = dark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    final background = dark
        ? Colors.white.withValues(alpha: .14)
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final label = customer == null
        ? 'Entrar'
        : customerDisplayName(customer!.name);
    if (compact) {
      return IconButton.filledTonal(
        key: const Key('customer-access-button'),
        tooltip: label,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
        ),
        icon: const Icon(Icons.person_outline),
      );
    }
    return TextButton.icon(
      key: const Key('customer-access-button'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: foreground,
        backgroundColor: background,
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 10 : 14,
          vertical: 12,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
      ),
      icon: const Icon(Icons.person_outline, size: 20),
      label: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}

enum _CustomerMenuAction { logout }

String customerDisplayName(String name) {
  final parts = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((part) => part.isEmpty);
  if (parts.length <= 2) return parts.join(' ');
  return '${parts.first} ${parts[1]}';
}

class _CategoryHeaderDelegate extends SliverPersistentHeaderDelegate {
  _CategoryHeaderDelegate({
    required this.categories,
    required this.selectedCategory,
    required this.onTap,
  });
  final List<CatalogCategory> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onTap;

  @override
  double get minExtent => 78;
  @override
  double get maxExtent => 78;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => Material(
    color: Theme.of(context).scaffoldBackgroundColor,
    elevation: overlapsContent ? 2 : 0,
    child: _CategoryNavigation(
      categories: categories,
      selectedCategory: selectedCategory,
      onTap: onTap,
    ),
  );

  @override
  bool shouldRebuild(covariant _CategoryHeaderDelegate oldDelegate) => true;
}

class _CategoryNavigation extends StatefulWidget {
  const _CategoryNavigation({
    required this.categories,
    required this.selectedCategory,
    required this.onTap,
  });
  final List<CatalogCategory> categories;
  final String? selectedCategory;
  final ValueChanged<String?> onTap;

  @override
  State<_CategoryNavigation> createState() => _CategoryNavigationState();
}

class _CategoryNavigationState extends State<_CategoryNavigation> {
  final Map<String, GlobalKey> _chipKeys = {};
  final GlobalKey _viewportKey = GlobalKey();
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _CategoryNavigation oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _revealSelected());
    }
  }

  void _revealSelected() {
    if (!mounted) return;
    final selected = widget.selectedCategory;
    if (selected == null) return;
    final key = _chipKeys[selected];
    final chipContext = key?.currentContext;
    final viewportContext = _viewportKey.currentContext;
    final chipBox = chipContext?.findRenderObject() as RenderBox?;
    final viewportBox = viewportContext?.findRenderObject() as RenderBox?;
    if (!_controller.hasClients || chipBox == null || viewportBox == null) {
      return;
    }
    final chipLeft = chipBox.localToGlobal(Offset.zero).dx;
    final viewportLeft = viewportBox.localToGlobal(Offset.zero).dx;
    final target =
        (_controller.offset +
                chipLeft -
                viewportLeft -
                (viewportBox.size.width - chipBox.size.width) / 2)
            .clamp(0.0, _controller.position.maxScrollExtent);
    _controller.animateTo(
      target,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) => ListView(
    key: _viewportKey,
    controller: _controller,
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
    scrollDirection: Axis.horizontal,
    children: [
      for (final category in widget.categories) ...[
        if (category != widget.categories.first) const SizedBox(width: 8),
        KeyedSubtree(
          key: _chipKeys.putIfAbsent(category.slug, GlobalKey.new),
          child: _CategoryChip(
            label: category.name,
            selected: widget.selectedCategory == category.slug,
            onTap: () => widget.onTap(category.slug),
          ),
        ),
      ],
    ],
  );
}

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ChoiceChip(
    label: Text(label),
    selected: selected,
    onSelected: (_) => onTap(),
    showCheckmark: false,
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
    labelStyle: TextStyle(
      fontWeight: FontWeight.w700,
      color: selected ? Colors.white : null,
    ),
    selectedColor: Theme.of(context).colorScheme.primary,
    backgroundColor: Colors.white,
    side: const BorderSide(color: Color(0xFFE4DED5)),
  );
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.imageUrl,
    required this.onAdd,
    super.key,
  });
  final CatalogProduct product;
  final String imageUrl;
  final ValueChanged<CatalogProduct> onAdd;

  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
    child: InkWell(
      onTap: product.available ? () => onAdd(product) : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: _ProductImage(url: imageUrl, available: product.available),
          ),
          Padding(
            padding: const EdgeInsets.all(17),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  product.description?.trim().isNotEmpty == true
                      ? product.description!
                      : 'Preparado para você',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF6E7474),
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (product.onOffer)
                            Text(
                              _currency(product.normalPrice),
                              style: const TextStyle(
                                decoration: TextDecoration.lineThrough,
                                color: Colors.black45,
                                fontSize: 12,
                              ),
                            ),
                          Text(
                            _currency(product.price),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontSize: 19,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      key: Key('add-product-${product.id}'),
                      tooltip: product.available ? 'Adicionar' : 'Indisponível',
                      onPressed: product.available
                          ? () => onAdd(product)
                          : null,
                      icon: const Icon(Icons.add_rounded),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProductImage extends StatelessWidget {
  const _ProductImage({required this.url, required this.available});
  final String url;
  final bool available;
  @override
  Widget build(BuildContext context) => Stack(
    fit: StackFit.expand,
    children: [
      if (url.isEmpty)
        const ColoredBox(
          color: Color(0xFFF1ECE4),
          child: Icon(
            Icons.bakery_dining_rounded,
            size: 58,
            color: Color(0xFFB9AEA0),
          ),
        )
      else
        Image.network(
          url,
          fit: BoxFit.cover,
          alignment: Alignment.center,
          cacheWidth: (350 * MediaQuery.devicePixelRatioOf(context)).round(),
          filterQuality: FilterQuality.low,
          errorBuilder: (_, _, _) => const ColoredBox(
            color: Color(0xFFF1ECE4),
            child: Icon(Icons.bakery_dining_rounded, size: 58),
          ),
        ),
      if (!available)
        Container(
          color: Colors.white70,
          alignment: Alignment.center,
          child: const Chip(label: Text('Indisponível')),
        ),
    ],
  );
}

class _StoreLogo extends StatelessWidget {
  const _StoreLogo({
    required this.url,
    required this.name,
    required this.compact,
  });
  final String url;
  final String name;
  final bool compact;
  @override
  Widget build(BuildContext context) {
    final size = compact ? 68.0 : 86.0;
    return Container(
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(compact ? 20 : 24),
      ),
      child: Padding(
        padding: EdgeInsets.all(compact ? 4 : 6),
        child: url.isEmpty
            ? Image.asset(
                'assets/images/pedeon_default.png',
                fit: BoxFit.contain,
              )
            : Image.network(
                url,
                fit: BoxFit.contain,
                cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                    .round(),
                filterQuality: FilterQuality.low,
                errorBuilder: (_, _, _) => Image.asset(
                  'assets/images/pedeon_default.png',
                  fit: BoxFit.contain,
                ),
              ),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({required this.viewModel, required this.onEdit});
  final StorefrontViewModel viewModel;
  final ValueChanged<CartLine> onEdit;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(22),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Expanded(
              child: Text(
                'Seu pedido',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
              ),
            ),
            Badge(
              label: Text('${viewModel.itemCount}'),
              child: const Icon(Icons.shopping_bag_outlined),
            ),
          ],
        ),
        const SizedBox(height: 18),
        Expanded(
          child: viewModel.cart.isEmpty
              ? const Center(
                  child: Text(
                    'Seu carrinho está vazio.',
                    style: TextStyle(color: Colors.black54),
                  ),
                )
              : ListView.separated(
                  itemCount: viewModel.cart.length,
                  separatorBuilder: (_, _) => const Divider(height: 26),
                  itemBuilder: (context, index) {
                    final line = viewModel.cart[index];
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                line.product.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 5),
                              for (final label in line.modifierLabels)
                                Text(
                                  label,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: Colors.black54,
                                  ),
                                ),
                              if ((line.customerNotes ?? '').isNotEmpty)
                                Text(
                                  'Obs.: ${line.customerNotes}',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              Text(
                                _currency(line.total),
                                style: TextStyle(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            _QuantityControl(
                              line: line,
                              onAdd: viewModel.increaseLine,
                              onDecrease: viewModel.decreaseLine,
                            ),
                            PopupMenuButton<String>(
                              key: Key('cart-line-actions-${line.id}'),
                              tooltip: 'Ações deste item',
                              onSelected: (value) {
                                switch (value) {
                                  case 'edit':
                                    onEdit(line);
                                  case 'duplicate':
                                    viewModel.increaseLine(line);
                                  case 'remove':
                                    viewModel.removeLine(line);
                                }
                              },
                              itemBuilder: (_) => const [
                                PopupMenuItem(
                                  value: 'edit',
                                  child: ListTile(
                                    leading: Icon(Icons.tune_rounded),
                                    title: Text('Editar personalização'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'duplicate',
                                  child: ListTile(
                                    leading: Icon(Icons.copy_rounded),
                                    title: Text('Adicionar outro igual'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'remove',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline_rounded),
                                    title: Text('Remover'),
                                  ),
                                ),
                              ],
                              icon: const Icon(Icons.more_horiz_rounded),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
        ),
        const Divider(height: 28),
        if (viewModel.lastQuote?.deliveryFee case final fee? when fee > 0) ...[
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Entrega',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              Text(
                _currency(fee),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Subtotal',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            Text(
              _currency(viewModel.subtotal),
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w900),
            ),
          ],
        ),
        if (viewModel.lastQuote?.deliveryFee case final fee? when fee > 0) ...[
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              Text(
                _currency(viewModel.lastQuote!.total),
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        if (viewModel.store!.acceptingOrders)
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              key: const Key('review-cart'),
              onPressed: viewModel.cart.isEmpty ? null : () => _review(context),
              icon: const Icon(Icons.arrow_forward_rounded),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 14),
                child: Text('Revisar pedido'),
              ),
            ),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1E5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Text(
              'A loja está fechada no momento. Tente novamente mais tarde.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        const SizedBox(height: 12),
        const Center(
          child: Text(
            'PedeOn by Lyncar',
            style: TextStyle(
              color: Colors.black45,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    ),
  );

  Future<void> _review(BuildContext context) async {
    if (!viewModel.store!.acceptingOrders) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => FutureBuilder<CartQuote>(
        future: viewModel.confirmQuote(),
        builder: (_, snapshot) {
          if (snapshot.hasError) {
            return AlertDialog(
              icon: const Icon(Icons.sync_problem_rounded),
              title: const Text('O cardápio mudou'),
              content: Text(snapshot.error.toString()),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Voltar ao cardápio'),
                ),
              ],
            );
          }
          if (!snapshot.hasData) {
            return const AlertDialog(
              content: SizedBox(
                height: 90,
                child: Center(child: CircularProgressIndicator()),
              ),
            );
          }
          final quote = snapshot.data!;
          return AlertDialog(
            icon: Icon(
              quote.minimumOrderReached
                  ? Icons.verified_rounded
                  : Icons.info_outline_rounded,
            ),
            title: const Text('Pedido atualizado'),
            content: Text(
              quote.minimumOrderReached
                  ? 'Subtotal ${_currency(quote.subtotal)}. Confira seus dados para continuar.'
                  : 'O pedido mínimo é ${_currency(quote.minimumOrderAmount)}. Adicione mais itens para continuar.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Continuar escolhendo'),
              ),
              if (quote.minimumOrderReached)
                FilledButton(
                  key: const Key('continue-checkout'),
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    showCheckoutDialog(
                      context,
                      viewModel: viewModel,
                      quote: quote,
                    );
                  },
                  child: const Text('Continuar'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _QuantityControl extends StatelessWidget {
  const _QuantityControl({
    required this.line,
    required this.onAdd,
    required this.onDecrease,
  });
  final CartLine line;
  final ValueChanged<CartLine> onAdd;
  final ValueChanged<CartLine> onDecrease;
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: const Color(0xFFF3EFE9),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          onPressed: () => onDecrease(line),
          icon: const Icon(Icons.remove_rounded),
          visualDensity: VisualDensity.compact,
        ),
        Text(
          '${line.quantity}',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        IconButton(
          onPressed: () => onAdd(line),
          icon: const Icon(Icons.add_rounded),
          visualDensity: VisualDensity.compact,
        ),
      ],
    ),
  );
}

class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar({
    required this.count,
    required this.subtotal,
    required this.onTap,
  });
  final int count;
  final double subtotal;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 10),
      child: FilledButton(
        onPressed: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Row(
            children: [
              Badge(
                label: Text('$count'),
                child: const Icon(Icons.shopping_bag_outlined),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Ver pedido',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              Text(
                _currency(subtotal),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _LoadingStorefront extends StatelessWidget {
  const _LoadingStorefront();
  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ErrorStorefront extends StatelessWidget {
  const _ErrorStorefront({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.storefront_outlined, size: 62),
              const SizedBox(height: 18),
              const Text(
                'Não encontramos este cardápio',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _EmptyCatalog extends StatelessWidget {
  const _EmptyCatalog();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.search_off_rounded, size: 52, color: Colors.black38),
          SizedBox(height: 12),
          Text(
            'Nenhum produto encontrado.',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

String _currency(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
