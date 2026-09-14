import 'package:flutter/material.dart';

import '../domain/pedeon_settings.dart';

enum _GroupKind { preparation, addon, catalogProduct }

Future<PedeOnModifierGroup?> showModifierGroupEditor(
  BuildContext context, {
  PedeOnModifierGroup? group,
  required List<PedeOnCatalogProduct> products,
  required Future<List<PedeOnCatalogProduct>> Function(String search)
  searchProducts,
}) => showDialog<PedeOnModifierGroup>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _ModifierGroupEditor(
    group: group,
    products: products,
    searchProducts: searchProducts,
  ),
);

class _ModifierGroupEditor extends StatefulWidget {
  const _ModifierGroupEditor({
    required this.group,
    required this.products,
    required this.searchProducts,
  });
  final PedeOnModifierGroup? group;
  final List<PedeOnCatalogProduct> products;
  final Future<List<PedeOnCatalogProduct>> Function(String search)
  searchProducts;

  @override
  State<_ModifierGroupEditor> createState() => _ModifierGroupEditorState();
}

class _ModifierGroupEditorState extends State<_ModifierGroupEditor> {
  late final name = TextEditingController(text: widget.group?.name ?? '');
  late final description = TextEditingController(
    text: widget.group?.description ?? '',
  );
  late final maximum = TextEditingController(
    text: '${widget.group?.maximumSelections ?? 1}',
  );
  late final options = [...?widget.group?.options];
  late bool active = widget.group?.active ?? true;
  late bool requiredChoice = widget.group == null
      ? true
      : widget.group!.minimumSelections > 0;
  late _GroupKind kind = _inferKind(widget.group);

  @override
  void dispose() {
    name.dispose();
    description.dispose();
    maximum.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 760, maxHeight: 820),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 14, 14),
            child: Row(
              children: [
                const CircleAvatar(child: Icon(Icons.tune_rounded)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.group == null ? 'Nova pergunta' : 'Editar pergunta',
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const Text(
                        'Crie uma vez e ative nos produtos desejados.',
                        style: TextStyle(color: Colors.black54),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                TextField(
                  controller: name,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Nome da pergunta',
                    hintText: 'Ex.: Quer adicionar uma bebida?',
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: description,
                  decoration: const InputDecoration(
                    labelText: 'Orientação ao cliente (opcional)',
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  'O que o cliente vai escolher?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 10),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final cards = [
                      _KindCard(
                        selected: kind == _GroupKind.preparation,
                        icon: Icons.restaurant_rounded,
                        title: 'Preparo',
                        subtitle:
                            'Ponto da carne, sem cebola ou tipo de molho.',
                        onTap: () => _changeKind(_GroupKind.preparation),
                      ),
                      _KindCard(
                        selected: kind == _GroupKind.addon,
                        icon: Icons.add_circle_outline_rounded,
                        title: 'Adicionais',
                        subtitle:
                            'Bacon, queijo e outros extras com ou sem preço.',
                        onTap: () => _changeKind(_GroupKind.addon),
                      ),
                      _KindCard(
                        selected: kind == _GroupKind.catalogProduct,
                        icon: Icons.local_drink_outlined,
                        title: 'Produto do estoque',
                        subtitle:
                            'Bebidas ou produtos já cadastrados, com preço atualizado.',
                        onTap: () => _changeKind(_GroupKind.catalogProduct),
                      ),
                    ];
                    if (constraints.maxWidth < 650) {
                      return Column(
                        children: [
                          for (final card in cards) ...[
                            card,
                            const SizedBox(height: 8),
                          ],
                        ],
                      );
                    }
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (var index = 0; index < cards.length; index++) ...[
                          Expanded(child: cards[index]),
                          if (index < cards.length - 1)
                            const SizedBox(width: 8),
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 14),
                Card.outlined(
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final required = SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Resposta obrigatória'),
                          subtitle: Text(
                            requiredChoice
                                ? 'O cliente precisa responder para adicionar o item.'
                                : 'O cliente pode continuar sem escolher.',
                          ),
                          value: requiredChoice,
                          onChanged: (value) =>
                              setState(() => requiredChoice = value),
                        );
                        final limit = TextField(
                          controller: maximum,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Quantas opções pode escolher?',
                            helperText:
                                'Ex.: 1 para ponto da carne; 5 para adicionais.',
                          ),
                        );
                        if (constraints.maxWidth < 560) {
                          return Column(
                            children: [
                              required,
                              const SizedBox(height: 8),
                              limit,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: required),
                            const SizedBox(width: 16),
                            SizedBox(width: 260, child: limit),
                          ],
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final title = const Text(
                      'Respostas que aparecerão para o cliente',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                      ),
                    );
                    final buttons = <Widget>[
                      if (kind != _GroupKind.catalogProduct)
                        OutlinedButton.icon(
                          key: const Key('modifier-add-manual'),
                          onPressed: _addManual,
                          icon: const Icon(Icons.add_rounded),
                          label: Text(
                            kind == _GroupKind.preparation
                                ? 'Adicionar resposta'
                                : 'Adicionar adicional',
                          ),
                        ),
                      if (kind != _GroupKind.preparation)
                        FilledButton.tonalIcon(
                          onPressed: _addProduct,
                          icon: const Icon(Icons.inventory_2_outlined),
                          label: Text(
                            kind == _GroupKind.catalogProduct
                                ? 'Selecionar produtos'
                                : 'Usar item do estoque',
                          ),
                        ),
                    ];
                    if (constraints.maxWidth < 520) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          title,
                          const SizedBox(height: 10),
                          for (
                            var index = 0;
                            index < buttons.length;
                            index++
                          ) ...[
                            buttons[index],
                            if (index < buttons.length - 1)
                              const SizedBox(height: 8),
                          ],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: title),
                        for (
                          var index = 0;
                          index < buttons.length;
                          index++
                        ) ...[
                          if (index > 0) const SizedBox(width: 8),
                          buttons[index],
                        ],
                      ],
                    );
                  },
                ),
                const SizedBox(height: 10),
                if (options.isEmpty)
                  Card.outlined(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        kind == _GroupKind.preparation
                            ? 'Adicione as respostas: Bem passado, Ao ponto e Mal passado. Essas opções não acrescentam valor.'
                            : kind == _GroupKind.addon
                            ? 'Adicione cada extra e seu valor, ou use um item já cadastrado no estoque.'
                            : 'Pesquise e selecione as bebidas ou outros produtos que poderão acompanhar este item.',
                      ),
                    ),
                  ),
                for (var index = 0; index < options.length; index++)
                  Card.outlined(
                    child: ListTile(
                      leading: Icon(
                        options[index].productId == null
                            ? Icons.edit_note_rounded
                            : Icons.inventory_2_outlined,
                      ),
                      title: Text(options[index].name),
                      subtitle: Text(
                        options[index].productId != null
                            ? 'Produto vinculado • preço atual ${_money(options[index].priceDelta)}'
                            : kind == _GroupKind.preparation
                            ? 'Resposta sem acréscimo'
                            : 'Acréscimo de ${_money(options[index].priceDelta)}',
                      ),
                      trailing: Wrap(
                        children: [
                          if (options[index].productId == null)
                            IconButton(
                              tooltip: 'Editar resposta',
                              onPressed: () => _editManual(index),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                          IconButton(
                            tooltip: 'Remover opção',
                            onPressed: () =>
                                setState(() => options.removeAt(index)),
                            icon: const Icon(Icons.delete_outline_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Pergunta ativa'),
                  subtitle: const Text(
                    'Pode ser utilizado nos produtos vinculados.',
                  ),
                  value: active,
                  onChanged: (value) => setState(() => active = value),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_outlined),
                  label: const Text('Salvar pergunta'),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Future<void> _addProduct() async {
    final product = await showDialog<PedeOnCatalogProduct>(
      context: context,
      builder: (context) => _ProductPickerDialog(
        initialProducts: widget.products,
        searchProducts: widget.searchProducts,
      ),
    );
    if (product == null ||
        options.any((option) => option.productId == product.productId)) {
      return;
    }
    setState(
      () => options.add(
        PedeOnModifierOption(
          name: product.effectiveName,
          priceDelta: product.effectivePrice,
          productId: product.productId,
        ),
      ),
    );
  }

  void _changeKind(_GroupKind value) {
    setState(() {
      kind = value;
      if (value == _GroupKind.preparation) {
        requiredChoice = true;
        maximum.text = '1';
      } else if (value == _GroupKind.catalogProduct) {
        requiredChoice = false;
        maximum.text = '1';
      } else {
        requiredChoice = false;
        maximum.text = '5';
      }
    });
  }

  Future<void> _addManual() async {
    await _showManualEditor();
  }

  Future<void> _editManual(int index) async {
    final result = await _showManualEditor(existing: options[index]);
    if (result != null && mounted) setState(() => options[index] = result);
  }

  Future<PedeOnModifierOption?> _showManualEditor({
    PedeOnModifierOption? existing,
  }) async {
    final optionName = TextEditingController(text: existing?.name ?? '');
    final optionPrice = TextEditingController(
      text: (existing?.priceDelta ?? 0).toStringAsFixed(2).replaceAll('.', ','),
    );
    final result = await showDialog<PedeOnModifierOption>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          existing == null
              ? kind == _GroupKind.preparation
                    ? 'Adicionar resposta'
                    : 'Adicionar adicional'
              : 'Editar resposta',
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: optionName,
              autofocus: true,
              decoration: InputDecoration(
                labelText: kind == _GroupKind.preparation
                    ? 'Resposta'
                    : 'Nome do adicional',
                hintText: kind == _GroupKind.preparation
                    ? 'Ex.: Bem passado'
                    : 'Ex.: Bacon extra',
              ),
            ),
            if (kind != _GroupKind.preparation) ...[
              const SizedBox(height: 12),
              TextField(
                controller: optionPrice,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'Valor que será acrescentado',
                  prefixText: 'R\$ ',
                  helperText: 'Pode ser zero.',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              if (optionName.text.trim().isEmpty) return;
              Navigator.pop(
                context,
                PedeOnModifierOption(
                  name: optionName.text.trim(),
                  priceDelta: kind == _GroupKind.preparation
                      ? 0
                      : double.tryParse(
                              optionPrice.text.replaceAll(',', '.'),
                            ) ??
                            0,
                ),
              );
            },
            child: Text(existing == null ? 'Adicionar' : 'Salvar'),
          ),
        ],
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      optionName.dispose();
      optionPrice.dispose();
    });
    if (existing == null && result != null && mounted) {
      setState(() => options.add(result));
    }
    return result;
  }

  void _save() {
    final min = requiredChoice ? 1 : 0;
    final max = int.tryParse(maximum.text) ?? 1;
    if (name.text.trim().length < 2 ||
        options.isEmpty ||
        max < min ||
        min > options.length) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Revise o nome, as opções e os limites do grupo.'),
        ),
      );
      return;
    }
    Navigator.pop(
      context,
      PedeOnModifierGroup(
        id: widget.group?.id,
        name: name.text.trim(),
        description: description.text.trim(),
        minimumSelections: min,
        maximumSelections: max,
        options: List.unmodifiable(options),
        active: active,
        kind: switch (kind) {
          _GroupKind.preparation => 'observation',
          _GroupKind.addon => 'complement',
          _GroupKind.catalogProduct => 'product',
        },
      ),
    );
  }
}

_GroupKind _inferKind(PedeOnModifierGroup? group) {
  if (group?.kind == 'observation') return _GroupKind.preparation;
  if (group?.kind == 'product') return _GroupKind.catalogProduct;
  if (group?.kind == 'complement') return _GroupKind.addon;
  if (group == null || group.options.isEmpty) return _GroupKind.preparation;
  if (group.options.every((option) => option.productId != null)) {
    return _GroupKind.catalogProduct;
  }
  if (group.minimumSelections == 1 &&
      group.maximumSelections == 1 &&
      group.options.every((option) => option.priceDelta == 0)) {
    return _GroupKind.preparation;
  }
  return _GroupKind.addon;
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle_rounded, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}

class _ProductPickerDialog extends StatefulWidget {
  const _ProductPickerDialog({
    required this.initialProducts,
    required this.searchProducts,
  });

  final List<PedeOnCatalogProduct> initialProducts;
  final Future<List<PedeOnCatalogProduct>> Function(String search)
  searchProducts;

  @override
  State<_ProductPickerDialog> createState() => _ProductPickerDialogState();
}

class _ProductPickerDialogState extends State<_ProductPickerDialog> {
  final search = TextEditingController();
  late List<PedeOnCatalogProduct> products = widget.initialProducts;
  bool loading = false;
  String? error;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> _runSearch() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final result = await widget.searchProducts(search.text);
      if (mounted) setState(() => products = result);
    } catch (_) {
      if (mounted) {
        setState(() => error = 'Não foi possível buscar os produtos.');
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Dialog(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 620, maxHeight: 680),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 18, 12, 12),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    'Selecionar produto do cardápio',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: TextField(
              controller: search,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _runSearch(),
              decoration: InputDecoration(
                labelText: 'Buscar por nome ou código',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: loading ? null : _runSearch,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: products.isEmpty && !loading
                ? const Center(child: Text('Nenhum produto encontrado.'))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                    itemCount: products.length,
                    separatorBuilder: (_, _) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return ListTile(
                        leading: const Icon(Icons.inventory_2_outlined),
                        title: Text(product.effectiveName),
                        subtitle: Text(
                          '${product.internalCode} • ${_money(product.effectivePrice)}',
                        ),
                        onTap: () => Navigator.pop(context, product),
                      );
                    },
                  ),
          ),
        ],
      ),
    ),
  );
}

String _money(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
