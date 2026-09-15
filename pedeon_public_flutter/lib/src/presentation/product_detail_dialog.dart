import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../domain/catalog_models.dart';

class ProductConfiguration {
  const ProductConfiguration({
    required this.quantity,
    required this.selectedOptions,
    this.notes,
  });

  final int quantity;
  final Map<int, int> selectedOptions;
  final String? notes;
}

Future<ProductConfiguration?> showProductDetail(
  BuildContext context, {
  required CatalogProduct product,
  required String imageUrl,
  required String storeSlug,
  ProductConfiguration? initialConfiguration,
}) {
  final compact = MediaQuery.sizeOf(context).width < 700;
  final content = _ProductDetail(
    product: product,
    imageUrl: imageUrl,
    storeSlug: storeSlug,
    initialConfiguration: initialConfiguration,
  );
  if (compact) {
    return showDialog<ProductConfiguration>(
      context: context,
      useSafeArea: true,
      barrierColor: Colors.black54,
      builder: (_) => Dialog.fullscreen(child: content),
    );
  }
  return showDialog<ProductConfiguration>(
    context: context,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(28),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 780),
        child: content,
      ),
    ),
  );
}

class _ProductDetail extends StatefulWidget {
  const _ProductDetail({
    required this.product,
    required this.imageUrl,
    required this.storeSlug,
    this.initialConfiguration,
  });

  final CatalogProduct product;
  final String imageUrl;
  final String storeSlug;
  final ProductConfiguration? initialConfiguration;

  @override
  State<_ProductDetail> createState() => _ProductDetailState();
}

class _ProductDetailState extends State<_ProductDetail> {
  final _notes = TextEditingController();
  final Map<int, int> _selected = {};
  int _quantity = 1;
  bool _showErrors = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialConfiguration;
    if (initial == null) return;
    _quantity = initial.quantity;
    _selected.addAll(initial.selectedOptions);
    _notes.text = initial.notes ?? '';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  bool _validGroup(ModifierGroup group) {
    final count = group.options.fold(
      0,
      (total, option) => total + (_selected[option.id] ?? 0),
    );
    return count >= group.minimumSelections &&
        (group.maximumSelections == null || count <= group.maximumSelections!);
  }

  bool get _isValid => widget.product.modifierGroups.every(_validGroup);

  double get _unitTotal =>
      widget.product.price +
      widget.product.modifierGroups.fold(0, (groupTotal, group) {
        return groupTotal +
            group.options.fold(0, (optionTotal, option) {
              return optionTotal +
                  option.priceDelta * (_selected[option.id] ?? 0);
            });
      });

  int get _maximumQuantity {
    var maximum = 99;
    for (final group in widget.product.modifierGroups) {
      for (final option in group.options) {
        if ((_selected[option.id] ?? 0) > 0 &&
            option.availableQuantity != null &&
            option.availableQuantity! < maximum) {
          maximum = option.availableQuantity!;
        }
      }
    }
    return maximum.clamp(1, 99);
  }

  @override
  Widget build(BuildContext context) => ScaffoldMessenger(
    child: Scaffold(
      backgroundColor: Colors.white,
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LayoutBuilder(
                  builder: (context, constraints) {
                    final aspectRatio = constraints.maxWidth < 700
                        ? 1.2
                        : 16 / 9;
                    return AspectRatio(
                      aspectRatio: aspectRatio,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          widget.imageUrl.isEmpty
                              ? const ColoredBox(
                                  color: Color(0xFFF1ECE4),
                                  child: Icon(
                                    Icons.restaurant_rounded,
                                    size: 72,
                                  ),
                                )
                              : InkWell(
                                  onTap: _showFullscreenImage,
                                  child: Hero(
                                    tag: 'product-image-${widget.product.id}',
                                    child: Image.network(
                                      widget.imageUrl,
                                      fit: BoxFit.cover,
                                      alignment: Alignment.center,
                                      errorBuilder: (_, _, _) =>
                                          const ColoredBox(
                                            color: Color(0xFFF1ECE4),
                                            child: Icon(
                                              Icons.restaurant_rounded,
                                              size: 72,
                                            ),
                                          ),
                                    ),
                                  ),
                                ),
                          Positioned.fill(
                            child: SafeArea(
                              child: Stack(
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(left: 16),
                                      child: _ImageOverlayButton(
                                        tooltip: 'Voltar',
                                        icon: Icons.arrow_back_rounded,
                                        onPressed: () => Navigator.pop(context),
                                      ),
                                    ),
                                  ),
                                  Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: const EdgeInsets.fromLTRB(
                                        0,
                                        16,
                                        16,
                                        0,
                                      ),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Builder(
                                            builder: (shareContext) =>
                                                _ImageOverlayButton(
                                                  tooltip: 'Compartilhar',
                                                  icon: Icons.ios_share_rounded,
                                                  onPressed: () =>
                                                      _share(shareContext),
                                                ),
                                          ),
                                          if (widget.imageUrl.isNotEmpty) ...[
                                            const SizedBox(height: 12),
                                            _ImageOverlayButton(
                                              key: const Key(
                                                'fullscreen-product-image',
                                              ),
                                              tooltip: 'Ampliar foto',
                                              icon: Icons.fullscreen_rounded,
                                              onPressed: _showFullscreenImage,
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 22, 24, 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.product.name,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if ((widget.product.description ?? '').isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          widget.product.description!,
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 16,
                          ),
                        ),
                      ],
                      const SizedBox(height: 10),
                      Text(
                        _currency(widget.product.price),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          for (final group in widget.product.modifierGroups)
            SliverToBoxAdapter(child: _group(group)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 120),
              child: TextField(
                key: const Key('product-notes'),
                controller: _notes,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  hintText: 'Ex.: retirar cebola, cortar ao meio...',
                  alignLabelWithHint: true,
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE5E7EB))),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final quantityPicker = _QuantityPicker(
                value: _quantity,
                onDecrease: _quantity > 1
                    ? () => setState(() => _quantity--)
                    : null,
                onIncrease: _quantity < 99 && _quantity < _maximumQuantity
                    ? () => setState(() => _quantity++)
                    : null,
              );
              final addButton = FilledButton(
                key: const Key('add-configured-product'),
                onPressed: _submit,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    _quantity == 1
                        ? 'Adicionar 1 item • ${_currency(_unitTotal)}'
                        : 'Adicionar $_quantity itens • ${_currency(_unitTotal * _quantity)}',
                  ),
                ),
              );
              if (constraints.maxWidth < 430) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    quantityPicker,
                    const SizedBox(height: 10),
                    addButton,
                  ],
                );
              }
              return Row(
                children: [
                  quantityPicker,
                  const SizedBox(width: 14),
                  Expanded(child: addButton),
                ],
              );
            },
          ),
        ),
      ),
    ),
  );

  Widget _group(ModifierGroup group) {
    final invalid = _showErrors && !_validGroup(group);
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      group.name,
                      style: const TextStyle(
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    if ((group.description ?? '').isNotEmpty)
                      Text(
                        group.description!,
                        style: const TextStyle(color: Colors.black54),
                      ),
                  ],
                ),
              ),
              Chip(
                label: Text(
                  group.minimumSelections > 0 ? 'Obrigatório' : 'Opcional',
                ),
              ),
            ],
          ),
          if (invalid)
            Text(
              'Escolha ${group.minimumSelections == group.maximumSelections ? group.minimumSelections : 'de ${group.minimumSelections} a ${group.maximumSelections ?? 'várias'}'} opção(ões).',
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          const SizedBox(height: 8),
          for (final option in group.options)
            _ModifierTile(
              option: option,
              quantity: _selected[option.id] ?? 0,
              singleChoice: group.maximumSelections == 1,
              onTap: () => _toggle(group, option),
            ),
        ],
      ),
    );
  }

  void _toggle(ModifierGroup group, ModifierOption option) {
    setState(() {
      final current = _selected[option.id] ?? 0;
      if (group.maximumSelections == 1) {
        for (final item in group.options) {
          _selected.remove(item.id);
        }
        if (current == 0) _selected[option.id] = 1;
        if (_quantity > _maximumQuantity) _quantity = _maximumQuantity;
        return;
      }
      final groupTotal = group.options.fold(
        0,
        (total, item) => total + (_selected[item.id] ?? 0),
      );
      if (current > 0) {
        _selected.remove(option.id);
      } else if (group.maximumSelections == null ||
          groupTotal < group.maximumSelections!) {
        _selected[option.id] = 1;
      }
      if (_quantity > _maximumQuantity) _quantity = _maximumQuantity;
    });
  }

  void _submit() {
    if (!_isValid) {
      setState(() => _showErrors = true);
      return;
    }
    final notes = _notes.text.trim();
    Navigator.pop(
      context,
      ProductConfiguration(
        quantity: _quantity,
        selectedOptions: Map.unmodifiable(_selected),
        notes: notes.isEmpty ? null : notes,
      ),
    );
  }

  Future<void> _share(BuildContext context) async {
    final uri = Uri.base.replace(
      path: '/${widget.storeSlug}',
      queryParameters: {'produto': '${widget.product.id}'},
    );
    final text = '${widget.product.name} — ${_currency(widget.product.price)}';
    if (Uri.base.scheme != 'https') {
      await _copyProductLink(context, uri);
      return;
    }
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: widget.product.name,
          text: text,
          uri: uri,
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (_) {
      if (context.mounted) await _copyProductLink(context, uri);
    }
  }

  Future<void> _copyProductLink(BuildContext context, Uri uri) async {
    await Clipboard.setData(ClipboardData(text: '$uri'));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Link do produto copiado.')));
  }

  Future<void> _showFullscreenImage() {
    if (widget.imageUrl.isEmpty) return Future.value();
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 1,
                maxScale: 4,
                child: Center(
                  child: Hero(
                    tag: 'product-image-${widget.product.id}',
                    child: Image.network(widget.imageUrl, fit: BoxFit.contain),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Align(
                alignment: Alignment.topLeft,
                child: IconButton.filled(
                  tooltip: 'Fechar foto',
                  onPressed: () => Navigator.pop(dialogContext),
                  icon: const Icon(Icons.close_rounded),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ImageOverlayButton extends StatelessWidget {
  const _ImageOverlayButton({
    required this.tooltip,
    required this.icon,
    required this.onPressed,
    super.key,
  });

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filled(
    tooltip: tooltip,
    onPressed: onPressed,
    icon: Icon(icon),
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withValues(alpha: .58),
      foregroundColor: Colors.white,
    ),
  );
}

class _ModifierTile extends StatelessWidget {
  const _ModifierTile({
    required this.option,
    required this.quantity,
    required this.singleChoice,
    required this.onTap,
  });

  final ModifierOption option;
  final int quantity;
  final bool singleChoice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Card.outlined(
    child: ListTile(
      onTap: onTap,
      title: Text(option.name),
      subtitle: option.priceDelta > 0 || option.availableQuantity != null
          ? Text(
              [
                if (option.priceDelta > 0) '+ ${_currency(option.priceDelta)}',
                if (option.availableQuantity != null)
                  '${option.availableQuantity} disponível(is)',
              ].join(' • '),
            )
          : null,
      trailing: Icon(
        quantity > 0
            ? singleChoice
                  ? Icons.radio_button_checked_rounded
                  : Icons.check_box_rounded
            : singleChoice
            ? Icons.radio_button_off_rounded
            : Icons.check_box_outline_blank_rounded,
      ),
    ),
  );
}

class _QuantityPicker extends StatelessWidget {
  const _QuantityPicker({
    required this.value,
    required this.onDecrease,
    required this.onIncrease,
  });
  final int value;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Quantidade do item',
    value: '$value',
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'Quantidade',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
        ),
        const SizedBox(width: 10),
        Container(
          decoration: BoxDecoration(
            color: const Color(0xFFF7F8FA),
            border: Border.all(color: const Color(0xFFD1D5DB)),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                key: const Key('decrease-product-quantity'),
                tooltip: 'Diminuir quantidade',
                onPressed: onDecrease,
                icon: const Icon(Icons.remove_rounded),
              ),
              SizedBox(
                width: 28,
                child: Text(
                  '$value',
                  key: const Key('product-quantity'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              IconButton(
                key: const Key('increase-product-quantity'),
                tooltip: 'Aumentar quantidade',
                onPressed: onIncrease,
                icon: const Icon(Icons.add_rounded),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

String _currency(double value) =>
    'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
