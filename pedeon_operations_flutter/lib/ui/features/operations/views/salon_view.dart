import 'package:flutter/material.dart';
import '../../../../domain/models/local_catalog.dart';
import '../view_models/operations_view_model.dart';
import 'checkout_view.dart';
import 'payment_dialog.dart';

class SalonView extends StatefulWidget {
  const SalonView({
    super.key,
    required this.viewModel,
    this.initialTable = '',
    this.initialCommand = '',
    this.counterMode = false,
  });
  final OperationsViewModel viewModel;
  final String initialTable;
  final String initialCommand;
  final bool counterMode;
  @override
  State<SalonView> createState() => _SalonViewState();
}

class _SalonViewState extends State<SalonView> {
  late final TextEditingController table;
  late final TextEditingController command;
  final customer = TextEditingController();
  final search = TextEditingController();
  int? categoryId;
  @override
  void initState() {
    super.initState();
    table = TextEditingController(text: widget.initialTable);
    command = TextEditingController(text: widget.initialCommand);
  }

  @override
  void dispose() {
    table.dispose();
    command.dispose();
    customer.dispose();
    search.dispose();
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
          label: const Text('Carregar catálogo local'),
        ),
      );
    }
    final products = catalog.products
        .where(
          (p) =>
              p.isEnabledFor(
                widget.counterMode ? 'pdv_counter' : 'onsite_waiter',
              ) &&
              (categoryId == null || p.categoryId == categoryId) &&
              (search.text.trim().isEmpty ||
                  p.name.toLowerCase().contains(search.text.toLowerCase())),
        )
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 980;
        final compact = constraints.maxWidth < 700;
        final selectingCategory = compact && categoryId == null;
        final catalogView = Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 10),
              child: wide
                  ? Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        SizedBox(
                          width: 330,
                          child: TextField(
                            controller: search,
                            onChanged: (_) => setState(() {}),
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Código ou produto',
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          onPressed: widget.viewModel.loadCatalog,
                          tooltip: 'Atualizar catálogo local',
                          icon: const Icon(Icons.sync),
                        ),
                      ],
                    )
                  : Row(
                      children: [
                        Expanded(
                          child: Text(
                            _title,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                        ),
                        IconButton(
                          onPressed: widget.viewModel.loadCatalog,
                          tooltip: 'Atualizar catálogo local',
                          icon: const Icon(Icons.sync),
                        ),
                      ],
                    ),
            ),
            if (compact && categoryId != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: () => setState(() => categoryId = null),
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Voltar às categorias',
                    ),
                    Expanded(
                      child: Text(
                        catalog.categories
                            .firstWhere((item) => item.id == categoryId)
                            .name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else if (!compact)
              SizedBox(
                height: 48,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  children: [
                    ChoiceChip(
                      label: const Text('Todos'),
                      selected: categoryId == null,
                      onSelected: (_) => setState(() => categoryId = null),
                    ),
                    const SizedBox(width: 8),
                    for (final category in catalog.categories) ...[
                      ChoiceChip(
                        label: Text(category.name),
                        selected: categoryId == category.id,
                        onSelected: (_) =>
                            setState(() => categoryId = category.id),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            Expanded(
              child: selectingCategory
                  ? GridView.builder(
                      padding: const EdgeInsets.all(14),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            childAspectRatio: 1.7,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                      itemCount: catalog.categories.length,
                      itemBuilder: (_, index) {
                        final category = catalog.categories[index];
                        return Card(
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () =>
                                setState(() => categoryId = category.id),
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.restaurant_menu,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    category.name,
                                    textAlign: TextAlign.center,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    )
                  : wide
                  ? _StaffProductList(products: products, onTap: _configure)
                  : GridView.builder(
                      padding: const EdgeInsets.all(20),
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: constraints.maxWidth >= 700 ? 3 : 2,
                        childAspectRatio: constraints.maxWidth < 500
                            ? .86
                            : 1.16,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                      ),
                      itemCount: products.length,
                      itemBuilder: (_, index) => _ProductCard(
                        product: products[index],
                        onTap: () => _configure(products[index]),
                      ),
                    ),
            ),
          ],
        );
        final cart = AnimatedBuilder(
          animation: widget.viewModel,
          builder: (_, _) => _CartPanel(
            viewModel: widget.viewModel,
            table: table,
            command: command,
            customer: customer,
            counterMode: widget.counterMode,
          ),
        );
        return wide
            ? Row(
                children: [
                  Expanded(child: catalogView),
                  SizedBox(width: 360, child: cart),
                ],
              )
            : Column(
                children: [
                  Expanded(child: catalogView),
                  _MobileCartBar(
                    viewModel: widget.viewModel,
                    onTap: () => showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      builder: (_) =>
                          FractionallySizedBox(heightFactor: .88, child: cart),
                    ),
                  ),
                ],
              );
      },
    );
  }

  String get _title => widget.counterMode
      ? 'Venda rápida no balcão'
      : widget.initialTable.isNotEmpty
      ? 'Mesa ${widget.initialTable}'
      : widget.initialCommand.isNotEmpty
      ? 'Comanda ${widget.initialCommand}'
      : 'Lançamento do garçom';

  Future<void> _configure(CatalogProduct product) async {
    // Produtos sem adicionais não precisam abrir uma segunda tela: o toque no
    // produto já representa a inclusão de uma unidade no pedido.
    if (product.modifierGroups.isEmpty) {
      widget.viewModel.addToCart(
        StaffCartLine(
          product: product,
          quantity: 1,
          optionIds: const {},
          notes: '',
        ),
      );
      return;
    }
    final line = await showModalBottomSheet<StaffCartLine>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ProductConfiguration(product: product),
    );
    if (line != null) widget.viewModel.addToCart(line);
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({required this.product, required this.onTap});
  final CatalogProduct product;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.restaurant_menu,
              size: 34,
              color: Theme.of(context).colorScheme.primary,
            ),
            const Spacer(),
            Text(
              product.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
            ),
            if (product.description.isNotEmpty)
              Text(
                product.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            const SizedBox(height: 8),
            Text(
              _money(product.price),
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _StaffProductList extends StatelessWidget {
  const _StaffProductList({required this.products, required this.onTap});
  final List<CatalogProduct> products;
  final ValueChanged<CatalogProduct> onTap;

  @override
  Widget build(BuildContext context) => ListView.separated(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
    itemCount: products.length,
    separatorBuilder: (_, _) => const SizedBox(height: 8),
    itemBuilder: (_, index) {
      final product = products[index];
      return Card(
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          onTap: () => onTap(product),
          leading: CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primaryContainer,
            child: const Icon(Icons.restaurant_menu),
          ),
          title: Text(
            product.name,
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          subtitle: product.description.isEmpty
              ? null
              : Text(
                  product.description,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _money(product.price),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 10),
              const Icon(Icons.add_circle_outline),
            ],
          ),
        ),
      );
    },
  );
}

class _ProductConfiguration extends StatefulWidget {
  const _ProductConfiguration({required this.product});
  final CatalogProduct product;
  @override
  State<_ProductConfiguration> createState() => _ProductConfigurationState();
}

class _ProductConfigurationState extends State<_ProductConfiguration> {
  final selected = <int>{};
  final notes = TextEditingController();
  int quantity = 1;
  @override
  void dispose() {
    notes.dispose();
    super.dispose();
  }

  bool get valid => widget.product.modifierGroups.every(
    (g) => g.options.where((o) => selected.contains(o.id)).length >= g.minimum,
  );
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(
      left: 20,
      right: 20,
      top: 18,
      bottom: MediaQuery.viewInsetsOf(context).bottom + 20,
    ),
    child: SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.product.name,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
          if (widget.product.description.isNotEmpty)
            Text(widget.product.description),
          const SizedBox(height: 14),
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
                      selected.removeAll(group.options.map((o) => o.id));
                    }
                    if (group.maximum == null ||
                        group.options
                                .where((o) => selected.contains(o.id))
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
          const SizedBox(height: 16),
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
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
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
              child: Text(
                'Adicionar $quantity • ${_money((widget.product.price + widget.product.modifierGroups.expand((g) => g.options).where((o) => selected.contains(o.id)).fold<double>(0, (s, o) => s + o.price)) * quantity)}',
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.viewModel,
    required this.table,
    required this.command,
    required this.customer,
    required this.counterMode,
  });
  final OperationsViewModel viewModel;
  final TextEditingController table, command, customer;
  final bool counterMode;
  @override
  Widget build(BuildContext context) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLowest,
    child: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            Row(
              children: [
                Text(
                  counterMode ? 'Venda de balcão' : 'Pedido no salão',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const Spacer(),
                Text(_money(viewModel.cartTotal)),
              ],
            ),
            const SizedBox(height: 12),
            if (!counterMode)
              _AccountLocation(
                type: table.text.trim().isNotEmpty ? 'Mesa' : 'Comanda',
                value: table.text.trim().isNotEmpty
                    ? table.text.trim()
                    : command.text.trim(),
              ),
            const SizedBox(height: 8),
            TextField(
              controller: customer,
              decoration: const InputDecoration(labelText: 'Nome (opcional)'),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: viewModel.cart.isEmpty
                  ? const Center(child: Text('Adicione itens ao pedido.'))
                  : ListView.builder(
                      itemCount: viewModel.cart.length,
                      itemBuilder: (_, index) {
                        final line = viewModel.cart[index];
                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text('${line.quantity}× ${line.product.name}'),
                          subtitle: line.notes.isEmpty
                              ? null
                              : Text(line.notes),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(_money(line.total)),
                              IconButton(
                                onPressed: () =>
                                    viewModel.removeFromCart(index),
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
              child: Row(
                children: [
                  if (!counterMode)
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed:
                            viewModel.cart.isEmpty || viewModel.submittingOrder
                            ? null
                            : () => _receiveNow(context),
                        icon: const Icon(Icons.point_of_sale_outlined),
                        label: const Text('Receber agora'),
                      ),
                    ),
                  if (!counterMode) const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed:
                          viewModel.cart.isEmpty || viewModel.submittingOrder
                          ? null
                          : () async {
                              final ok = await viewModel.createStaffOrder(
                                sourceChannel: counterMode
                                    ? 'pdv_counter'
                                    : 'onsite_waiter',
                                table: counterMode ? '' : table.text.trim(),
                                command: counterMode ? '' : command.text.trim(),
                                customer: customer.text,
                              );
                              if (ok && context.mounted) {
                                if (counterMode) {
                                  table.clear();
                                  command.clear();
                                }
                                customer.clear();
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Pedido registrado e enviado para produção.',
                                    ),
                                  ),
                                );
                              }
                            },
                      icon: viewModel.submittingOrder
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Enviar pedido'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );

  Future<void> _receiveNow(BuildContext context) async {
    if (viewModel.cashSession == null) {
      final opening = await showDialog<CashOpeningInput>(
        context: context,
        builder: (_) => const CashOpeningDialog(),
      );
      if (opening == null || !context.mounted) return;
      final opened = await viewModel.openCash(
        register: '01',
        openingAmount: opening.openingAmount,
      );
      if (!opened || !context.mounted) return;
    }
    final order = await viewModel.createStaffOrderAndReturn(
      sourceChannel: counterMode ? 'pdv_counter' : 'onsite_waiter',
      table: counterMode ? '' : table.text.trim(),
      command: counterMode ? '' : command.text.trim(),
      customer: customer.text,
    );
    if (order == null || !context.mounted) return;
    final input = await showPaymentDialog(
      context,
      total: order.total,
      title: 'Receber ${order.number}',
    );
    if (input == null || !context.mounted) return;
    final receipt = await viewModel.checkout(
      order,
      method: input.method,
      amountPaid: input.amount,
      authorizationCode: input.authorization,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          receipt == null
              ? viewModel.error ?? 'Não foi possível registrar o pagamento.'
              : 'Pagamento registrado. A mesa continua disponível para novos lançamentos.',
        ),
      ),
    );
  }
}

class _AccountLocation extends StatelessWidget {
  const _AccountLocation({required this.type, required this.value});
  final String type;
  final String value;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primaryContainer,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        Icon(type == 'Mesa' ? Icons.table_restaurant : Icons.receipt_long),
        const SizedBox(width: 10),
        Text(
          '$type $value',
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ],
    ),
  );
}

class _MobileCartBar extends StatelessWidget {
  const _MobileCartBar({required this.viewModel, required this.onTap});
  final OperationsViewModel viewModel;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: FilledButton.icon(
        onPressed: onTap,
        icon: const Icon(Icons.shopping_bag_outlined),
        label: Text(
          '${viewModel.cart.length} item(ns) • ${_money(viewModel.cartTotal)}',
        ),
      ),
    ),
  );
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
