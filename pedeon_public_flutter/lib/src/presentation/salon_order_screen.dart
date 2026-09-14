import 'package:flutter/material.dart';

import '../data/salon_edge_service.dart';
import '../domain/catalog_models.dart';
import 'product_detail_dialog.dart';

/// Catálogo próprio do garçom. Não usa o checkout nem a identidade da loja.
class SalonOrderScreen extends StatefulWidget {
  const SalonOrderScreen({
    super.key,
    required this.slug,
    required this.accountType,
    required this.accountNumber,
    required this.service,
    required this.sessionToken,
  });
  final String slug;
  final String accountType;
  final int accountNumber;
  final SalonEdgeService service;
  final String sessionToken;
  @override
  State<SalonOrderScreen> createState() => _SalonOrderScreenState();
}

class _SalonOrderScreenState extends State<SalonOrderScreen> {
  late final Future<CatalogPage> _catalog = widget.service.catalog(
    widget.sessionToken,
  );
  final _search = TextEditingController();
  final Map<String, CartLine> _cart = {};
  int? _categoryId;

  String get _account =>
      '${widget.accountType == 'comanda' ? 'Comanda' : 'Mesa'} ${widget.accountNumber}';
  List<CartLine> get _lines => List.unmodifiable(_cart.values);
  int get _count => _lines.fold(0, (sum, line) => sum + line.quantity);
  double get _total => _lines.fold(0, (sum, line) => sum + line.total);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F6F7),
    appBar: AppBar(
      titleSpacing: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Novo pedido • $_account'),
          Text(
            _count == 0
                ? 'Selecione os itens da rodada'
                : '$_count item(ns) na rodada',
            style: Theme.of(context).textTheme.labelMedium,
          ),
        ],
      ),
    ),
    body: FutureBuilder<CatalogPage>(
      future: _catalog,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (!snapshot.hasData) {
          return Center(
            child: Text(
              'Não foi possível abrir o catálogo: ${snapshot.error ?? ''}',
            ),
          );
        }
        return _SalonCatalog(
          catalog: snapshot.requireData,
          categoryId: _categoryId,
          search: _search.text,
          controller: _search,
          onSearch: (_) => setState(() {}),
          onCategory: (value) => setState(() {
            _categoryId = value;
            _search.clear();
          }),
          onBack: () => setState(() {
            _categoryId = null;
            _search.clear();
          }),
          onProduct: _addProduct,
        );
      },
    ),
    bottomNavigationBar: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: FilledButton.icon(
          key: const Key('review-salon-order'),
          onPressed: _count == 0 ? null : _review,
          icon: const Icon(Icons.fact_check_outlined),
          label: Text(
            _count == 0
                ? 'Adicione produtos para revisar'
                : 'Revisar rodada • ${_money(_total)}',
          ),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        ),
      ),
    ),
  );

  Future<void> _addProduct(CatalogProduct product) async {
    final config = await showProductDetail(
      context,
      product: product,
      imageUrl: product.imageUrl ?? '',
      storeSlug: widget.slug,
    );
    if (config == null || !mounted) return;
    final options = config.selectedOptions.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));
    final notes = config.notes?.trim() ?? '';
    final id =
        '${product.id}|${options.map((item) => '${item.key}:${item.value}').join(',')}|$notes';
    final current = _cart[id];
    setState(
      () => _cart[id] = CartLine(
        id: id,
        product: product,
        quantity: (current?.quantity ?? 0) + config.quantity,
        selectedOptions: Map.unmodifiable(config.selectedOptions),
        customerNotes: notes.isEmpty ? null : notes,
      ),
    );
  }

  void _review() => showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    builder: (_) => _ReviewSheet(
      account: _account,
      lines: _lines,
      total: _total,
      onDecrease: _decrease,
      onRemove: (line) => setState(() => _cart.remove(line.id)),
      onSend: _send,
    ),
  );

  Future<void> _send() async {
    try {
      await widget.service.sendOrder(
        token: widget.sessionToken,
        accountType: widget.accountType,
        accountNumber: widget.accountNumber,
        lines: _lines,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      setState(_cart.clear);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Rodada enviada para a operação.')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Não foi possível enviar: $error')),
      );
    }
  }

  void _decrease(CartLine line) => setState(() {
    if (line.quantity == 1) {
      _cart.remove(line.id);
      return;
    }
    _cart[line.id] = CartLine(
      id: line.id,
      product: line.product,
      quantity: line.quantity - 1,
      selectedOptions: line.selectedOptions,
      customerNotes: line.customerNotes,
    );
  });
}

class _SalonCatalog extends StatelessWidget {
  const _SalonCatalog({
    required this.catalog,
    required this.categoryId,
    required this.search,
    required this.controller,
    required this.onSearch,
    required this.onCategory,
    required this.onBack,
    required this.onProduct,
  });
  final CatalogPage catalog;
  final int? categoryId;
  final String search;
  final TextEditingController controller;
  final ValueChanged<String> onSearch;
  final ValueChanged<int?> onCategory;
  final VoidCallback onBack;
  final ValueChanged<CatalogProduct> onProduct;

  @override
  Widget build(BuildContext context) {
    final query = search.trim().toLowerCase();
    final showingProducts = categoryId != null || query.isNotEmpty;
    final products = catalog.items
        .where(
          (item) =>
              (categoryId == null || item.categoryId == categoryId) &&
              (query.isEmpty ||
                  item.name.toLowerCase().contains(query) ||
                  (item.description ?? '').toLowerCase().contains(query)),
        )
        .toList();
    final category = catalog.categories
        .where((item) => item.id == categoryId)
        .firstOrNull;
    return LayoutBuilder(
      builder: (context, constraints) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
                  child: TextField(
                    key: const Key('salon-product-search'),
                    controller: controller,
                    onChanged: onSearch,
                    decoration: InputDecoration(
                      hintText: 'Buscar produto ou código',
                      prefixIcon: const Icon(Icons.search_rounded),
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
                  child: Row(
                    children: [
                      if (showingProducts)
                        IconButton.filledTonal(
                          onPressed: onBack,
                          tooltip: 'Categorias',
                          icon: const Icon(Icons.arrow_back_rounded),
                        ),
                      if (showingProducts) const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          showingProducts
                              ? (query.isNotEmpty
                                    ? 'Resultados da busca'
                                    : category?.name ?? 'Produtos')
                              : 'Categorias',
                          style: Theme.of(context).textTheme.titleLarge
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!showingProducts)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: constraints.maxWidth < 600
                          ? 190
                          : 230,
                      mainAxisExtent: 138,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: catalog.categories.length,
                    itemBuilder: (_, index) {
                      final item = catalog.categories[index];
                      return _CategoryTile(
                        category: item,
                        count: catalog.items
                            .where((p) => p.categoryId == item.id)
                            .length,
                        onTap: () => onCategory(item.id),
                      );
                    },
                  ),
                )
              else if (products.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: Text('Nenhum produto encontrado.')),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 120),
                  sliver: SliverGrid.builder(
                    gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: constraints.maxWidth < 600
                          ? 260
                          : 300,
                      mainAxisExtent: 174,
                      crossAxisSpacing: 12,
                      mainAxisSpacing: 12,
                    ),
                    itemCount: products.length,
                    itemBuilder: (_, index) => _ProductTile(
                      product: products[index],
                      onTap: () => onProduct(products[index]),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  const _CategoryTile({
    required this.category,
    required this.count,
    required this.onTap,
  });
  final CatalogCategory category;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF075E6F),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(Icons.restaurant_menu_rounded, color: Colors.white),
            const Spacer(),
            Text(
              category.name.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 16,
              ),
            ),
            Text(
              '$count produto(s)',
              style: const TextStyle(color: Color(0xFFBFE7E9)),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.onTap});
  final CatalogProduct product;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: product.available ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.restaurant_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const Spacer(),
                if (!product.available) const Chip(label: Text('Indisponível')),
              ],
            ),
            const Spacer(),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17),
            ),
            if ((product.description ?? '').isNotEmpty)
              Text(
                product.description!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.black54),
              ),
            const SizedBox(height: 8),
            Text(
              _money(product.price),
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w900,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _ReviewSheet extends StatelessWidget {
  const _ReviewSheet({
    required this.account,
    required this.lines,
    required this.total,
    required this.onDecrease,
    required this.onRemove,
    required this.onSend,
  });
  final String account;
  final List<CartLine> lines;
  final double total;
  final ValueChanged<CartLine> onDecrease;
  final ValueChanged<CartLine> onRemove;
  final Future<void> Function() onSend;
  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    heightFactor: .78,
    child: Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          Text(
            'Revisar rodada • $account',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: ListView.separated(
              itemCount: lines.length,
              separatorBuilder: (_, _) => const Divider(),
              itemBuilder: (_, index) {
                final line = lines[index];
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    '${line.quantity}× ${line.product.name}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: line.customerNotes == null
                      ? null
                      : Text('Obs.: ${line.customerNotes}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_money(line.total)),
                      IconButton(
                        onPressed: () => onDecrease(line),
                        icon: const Icon(Icons.remove_circle_outline),
                      ),
                      IconButton(
                        onPressed: () => onRemove(line),
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const Divider(),
          Row(
            children: [
              const Text(
                'Total',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const Spacer(),
              Text(
                _money(total),
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onSend,
              icon: const Icon(Icons.send_rounded),
              label: const Text('Enviar rodada'),
            ),
          ),
        ],
      ),
    ),
  );
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
