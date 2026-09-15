import 'package:flutter/material.dart';

import '../../../../domain/models/local_catalog.dart';
import '../view_models/operations_view_model.dart';

class CounterSaleView extends StatefulWidget {
  const CounterSaleView({super.key, required this.viewModel});

  final OperationsViewModel viewModel;

  @override
  State<CounterSaleView> createState() => _CounterSaleViewState();
}

class _CounterSaleViewState extends State<CounterSaleView> {
  final search = TextEditingController();
  final customer = TextEditingController();
  final searchFocus = FocusNode();
  int? categoryId;

  @override
  void dispose() {
    search.dispose();
    customer.dispose();
    searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final catalog = widget.viewModel.catalog;
    if (catalog == null) {
      return Center(
        child: FilledButton.icon(
          onPressed: widget.viewModel.loadCatalog,
          icon: const Icon(Icons.sync),
          label: const Text('Carregar catálogo do balcão'),
        ),
      );
    }
    final counterProducts = catalog.products
        .where((product) => product.isEnabledFor('pdv_counter'))
        .toList(growable: false);
    final categoryIds = counterProducts.map((p) => p.categoryId).toSet();
    final categories = catalog.categories
        .where((category) => categoryIds.contains(category.id))
        .toList(growable: false);
    final query = search.text.trim().toLowerCase();
    final products = counterProducts
        .where((product) {
          final inCategory =
              categoryId == null || product.categoryId == categoryId;
          final matches =
              query.isEmpty ||
              product.name.toLowerCase().contains(query) ||
              '${product.id}'.contains(query);
          return inCategory && matches;
        })
        .toList(growable: false);

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 1020;
        final sale = _CurrentSale(
          viewModel: widget.viewModel,
          customer: customer,
        );
        final catalogPane = _CounterCatalog(
          wide: wide,
          categories: categories,
          products: products,
          selectedCategoryId: categoryId,
          search: search,
          searchFocus: searchFocus,
          query: query,
          onSearchChanged: () => setState(() {}),
          onCategorySelected: (id) => setState(() => categoryId = id),
          onClearSearch: () {
            search.clear();
            setState(() {});
            searchFocus.requestFocus();
          },
          onRefresh: widget.viewModel.loadCatalog,
          onSelectProduct: _addProduct,
        );
        if (wide) {
          return Row(
            children: [
              Expanded(child: catalogPane),
              SizedBox(width: 410, child: sale),
            ],
          );
        }
        return Column(
          children: [
            Expanded(child: catalogPane),
            SafeArea(
              top: false,
              child: ListTile(
                title: Text('${widget.viewModel.cart.length} item(ns)'),
                subtitle: Text(_money(widget.viewModel.cartTotal)),
                trailing: FilledButton(
                  onPressed: () => showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    useSafeArea: true,
                    builder: (_) =>
                        FractionallySizedBox(heightFactor: .9, child: sale),
                  ),
                  child: const Text('Ver venda'),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _addProduct(CatalogProduct product) async {
    if (product.modifierGroups.isEmpty) {
      widget.viewModel.addToCart(
        StaffCartLine(product: product, quantity: 1, optionIds: const {}),
      );
      search.clear();
      setState(() {});
      searchFocus.requestFocus();
      return;
    }
    final line = await showModalBottomSheet<StaffCartLine>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _CounterProductOptions(product: product),
    );
    if (line != null) widget.viewModel.addToCart(line);
    searchFocus.requestFocus();
  }
}

class _CounterCatalog extends StatelessWidget {
  const _CounterCatalog({
    required this.wide,
    required this.categories,
    required this.products,
    required this.selectedCategoryId,
    required this.search,
    required this.searchFocus,
    required this.query,
    required this.onSearchChanged,
    required this.onCategorySelected,
    required this.onClearSearch,
    required this.onRefresh,
    required this.onSelectProduct,
  });

  final bool wide;
  final List<CatalogCategory> categories;
  final List<CatalogProduct> products;
  final int? selectedCategoryId;
  final TextEditingController search;
  final FocusNode searchFocus;
  final String query;
  final VoidCallback onSearchChanged;
  final ValueChanged<int?> onCategorySelected;
  final VoidCallback onClearSearch;
  final VoidCallback onRefresh;
  final ValueChanged<CatalogProduct> onSelectProduct;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final searchField = TextField(
      controller: search,
      focusNode: searchFocus,
      autofocus: true,
      onChanged: (_) => onSearchChanged(),
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        labelText: 'Código, EAN ou produto',
        hintText: 'F2 para buscar',
        prefixIcon: const Icon(Icons.qr_code_scanner_outlined),
        suffixIcon: query.isEmpty
            ? null
            : IconButton(
                tooltip: 'Limpar busca',
                onPressed: onClearSearch,
                icon: const Icon(Icons.close),
              ),
      ),
    );

    final categoryMenu = _CounterCategoryMenu(
      categories: categories,
      selectedCategoryId: selectedCategoryId,
      onCategorySelected: onCategorySelected,
      compact: !wide,
    );

    final productList = Expanded(
      child: products.isEmpty
          ? const Center(child: Text('Nenhum produto ativo no estoque.'))
          : _CounterProductList(products: products, onSelect: onSelectProduct),
    );

    return ColoredBox(
      color: colorScheme.surfaceContainerLow,
      child: Column(
        children: [
          Container(
            color: colorScheme.surface,
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            child: Row(
              children: [
                Icon(Icons.point_of_sale_outlined, color: colorScheme.primary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PDV • Balcão',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        'Produtos ativos do estoque do ERP',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Atualizar catálogo local',
                  onPressed: onRefresh,
                  icon: const Icon(Icons.sync),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.all(20), child: searchField),
          if (wide)
            Expanded(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(width: 210, child: categoryMenu),
                  const VerticalDivider(width: 1),
                  Expanded(child: productList),
                ],
              ),
            )
          else ...[
            SizedBox(height: 48, child: categoryMenu),
            productList,
          ],
        ],
      ),
    );
  }
}

class _CounterCategoryMenu extends StatelessWidget {
  const _CounterCategoryMenu({
    required this.categories,
    required this.selectedCategoryId,
    required this.onCategorySelected,
    required this.compact,
  });

  final List<CatalogCategory> categories;
  final int? selectedCategoryId;
  final ValueChanged<int?> onCategorySelected;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    if (compact) {
      return ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        children: [
          ChoiceChip(
            avatar: const Icon(Icons.apps_outlined, size: 18),
            label: const Text('Todos'),
            selected: selectedCategoryId == null,
            onSelected: (_) => onCategorySelected(null),
          ),
          const SizedBox(width: 8),
          for (final category in categories) ...[
            ChoiceChip(
              label: Text(category.name),
              selected: selectedCategoryId == category.id,
              onSelected: (_) => onCategorySelected(category.id),
            ),
            const SizedBox(width: 8),
          ],
        ],
      );
    }
    return Material(
      color: Theme.of(context).colorScheme.surface,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 10),
            child: Text(
              'CATEGORIAS',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.1,
              ),
            ),
          ),
          _CounterCategoryTile(
            icon: Icons.apps_outlined,
            label: 'Todos os produtos do estoque',
            selected: selectedCategoryId == null,
            onTap: () => onCategorySelected(null),
          ),
          for (final category in categories)
            _CounterCategoryTile(
              icon: Icons.sell_outlined,
              label: category.name,
              selected: selectedCategoryId == category.id,
              onTap: () => onCategorySelected(category.id),
            ),
        ],
      ),
    );
  }
}

class _CounterCategoryTile extends StatelessWidget {
  const _CounterCategoryTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 4),
    child: ListTile(
      dense: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      selected: selected,
      selectedTileColor: Theme.of(context).colorScheme.primaryContainer,
      leading: Icon(icon),
      title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      onTap: onTap,
    ),
  );
}

class _CounterProductList extends StatelessWidget {
  const _CounterProductList({required this.products, required this.onSelect});
  final List<CatalogProduct> products;
  final ValueChanged<CatalogProduct> onSelect;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
    itemCount: products.length + 1,
    separatorBuilder: (_, index) =>
        index == 0 ? const SizedBox() : const Divider(height: 1),
    itemBuilder: (_, index) {
      if (index == 0) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(12, 8, 12, 10),
          child: Row(
            children: [
              SizedBox(width: 82, child: Text('CÓDIGO')),
              Expanded(child: Text('PRODUTO')),
              SizedBox(
                width: 98,
                child: Text('PREÇO', textAlign: TextAlign.right),
              ),
              SizedBox(width: 48),
            ],
          ),
        );
      }
      final product = products[index - 1];
      return InkWell(
        onTap: () => onSelect(product),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 82,
                child: Text(
                  '#${product.id}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    if (product.description.isNotEmpty)
                      Text(
                        product.description,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                  ],
                ),
              ),
              SizedBox(
                width: 98,
                child: Text(
                  _money(product.price),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: 'Adicionar',
                onPressed: () => onSelect(product),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
        ),
      );
    },
  );
}

class _CurrentSale extends StatelessWidget {
  const _CurrentSale({required this.viewModel, required this.customer});
  final OperationsViewModel viewModel;
  final TextEditingController customer;

  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        children: [
          Row(
            children: [
              Text(
                'Venda atual',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const Spacer(),
              Text(
                _money(viewModel.cartTotal),
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: customer,
            decoration: const InputDecoration(
              labelText: 'Cliente (opcional)',
              prefixIcon: Icon(Icons.person_outline),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: viewModel.cart.isEmpty
                ? const Center(
                    child: Text('Leia um produto ou toque no catálogo.'),
                  )
                : ListView.separated(
                    itemCount: viewModel.cart.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (_, index) {
                      final line = viewModel.cart[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    line.product.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  if (line.notes.isNotEmpty)
                                    Text(
                                      line.notes,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  Text(_money(line.total)),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  viewModel.changeCartQuantity(index, -1),
                              icon: const Icon(Icons.remove_circle_outline),
                            ),
                            Text(
                              '${line.quantity}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            IconButton(
                              onPressed: () =>
                                  viewModel.changeCartQuantity(index, 1),
                              icon: const Icon(Icons.add_circle_outline),
                            ),
                            IconButton(
                              onPressed: () => viewModel.removeFromCart(index),
                              icon: const Icon(Icons.delete_outline),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: viewModel.cart.isEmpty || viewModel.submittingOrder
                  ? null
                  : () async {
                      final ok = await viewModel.createStaffOrder(
                        sourceChannel: 'pdv_counter',
                        table: '',
                        command: '',
                        customer: customer.text.trim(),
                      );
                      if (context.mounted && ok) {
                        customer.clear();
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Pedido de balcão enviado para produção.',
                            ),
                          ),
                        );
                      }
                    },
              icon: const Icon(Icons.send),
              label: const Text('Enviar para preparo'),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CounterProductOptions extends StatefulWidget {
  const _CounterProductOptions({required this.product});
  final CatalogProduct product;
  @override
  State<_CounterProductOptions> createState() => _CounterProductOptionsState();
}

class _CounterProductOptionsState extends State<_CounterProductOptions> {
  final selected = <int>{};
  final notes = TextEditingController();
  int quantity = 1;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  bool get valid => widget.product.modifierGroups.every(
    (group) =>
        group.options.where((option) => selected.contains(option.id)).length >=
        group.minimum,
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      20,
      18,
      20,
      MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.product.name,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          for (final group in widget.product.modifierGroups) ...[
            Text(
              group.name,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
            Text(
              group.minimum > 0
                  ? 'Escolha pelo menos ${group.minimum}'
                  : 'Opcional',
            ),
            for (final option in group.options)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(option.name),
                secondary: option.price == 0
                    ? null
                    : Text('+ ${_money(option.price)}'),
                value: selected.contains(option.id),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    if (group.maximum == 1) {
                      selected.removeAll(
                        group.options.map((option) => option.id),
                      );
                    }
                    if (group.maximum == null ||
                        group.options
                                .where((option) => selected.contains(option.id))
                                .length <
                            group.maximum!) {
                      selected.add(option.id);
                    }
                  } else {
                    selected.remove(option.id);
                  }
                }),
              ),
            const Divider(),
          ],
          TextField(
            controller: notes,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Observação do item (opcional)',
            ),
          ),
          Row(
            children: [
              const Text(
                'Quantidade',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              IconButton(
                onPressed: quantity > 1
                    ? () => setState(() => quantity--)
                    : null,
                icon: const Icon(Icons.remove),
              ),
              Text(
                '$quantity',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              IconButton(
                onPressed: () => setState(() => quantity++),
                icon: const Icon(Icons.add),
              ),
            ],
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: valid
                  ? () => Navigator.pop(
                      context,
                      StaffCartLine(
                        product: widget.product,
                        quantity: quantity,
                        optionIds: Set.of(selected),
                        notes: notes.text.trim(),
                      ),
                    )
                  : null,
              child: Text('Adicionar $quantity item(ns)'),
            ),
          ),
        ],
      ),
    ),
  );
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
