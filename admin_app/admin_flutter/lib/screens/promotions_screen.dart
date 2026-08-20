import 'package:flutter/material.dart';

import '../models/product.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../widgets/app_card.dart';

const _ink = Color(0xFF142033);
const _muted = Color(0xFF64748B);
const _brand = Color(0xFF0C6680);
const _line = Color(0xFFDCE5F0);
const _canvas = Color(0xFFF4F7FB);

enum _PromotionFilter { all, active, scheduled, expired, withoutOffer }

enum _PromotionSort { status, name, discount }

enum _PromotionState { active, scheduled, expired, withoutOffer }

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key, required this.session});
  final Session session;

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  List<Product> _products = [];
  _PromotionFilter _filter = _PromotionFilter.all;
  _PromotionSort _sort = _PromotionSort.status;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _api.listProducts(widget.session.token);
      if (mounted) {
        setState(() => _products = items.where((item) => item.active).toList());
      }
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Não foi possível carregar preços e promoções.',
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<Product> get _visibleProducts {
    final term = _search.text.trim().toLowerCase();
    final items = _products.where((product) {
      final searchable =
          '${product.name} ${product.internalCode ?? ''} ${product.barcode ?? ''}'
              .toLowerCase();
      if (term.isNotEmpty && !searchable.contains(term)) return false;
      final state = _stateOf(product);
      return switch (_filter) {
        _PromotionFilter.all => true,
        _PromotionFilter.active => state == _PromotionState.active,
        _PromotionFilter.scheduled => state == _PromotionState.scheduled,
        _PromotionFilter.expired => state == _PromotionState.expired,
        _PromotionFilter.withoutOffer => state == _PromotionState.withoutOffer,
      };
    }).toList();
    items.sort((a, b) {
      if (_sort == _PromotionSort.name) {
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      if (_sort == _PromotionSort.discount) {
        return _discountOf(b).compareTo(_discountOf(a));
      }
      final byState = _statusOrder(
        _stateOf(a),
      ).compareTo(_statusOrder(_stateOf(b)));
      return byState != 0
          ? byState
          : a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return items;
  }

  Future<void> _edit(Product product) async {
    final saved = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        final editor = _PromotionEditor(
          product: product,
          api: _api,
          token: widget.session.token,
        );
        if (MediaQuery.sizeOf(context).width < 700) {
          return Dialog.fullscreen(child: editor);
        }
        return Dialog(
          insetPadding: const EdgeInsets.all(28),
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 660, maxHeight: 780),
            child: editor,
          ),
        );
      },
    );
    if (saved != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Promoção atualizada com sucesso.')),
    );
    await _load();
  }

  void _startCreating() {
    _search.clear();
    setState(() => _filter = _PromotionFilter.withoutOffer);
    _searchFocus.requestFocus();
  }

  int _count(_PromotionState state) =>
      _products.where((item) => _stateOf(item) == state).length;

  @override
  Widget build(BuildContext context) {
    final products = _visibleProducts;
    return Scaffold(
      backgroundColor: _canvas,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final horizontal = constraints.maxWidth < 720 ? 16.0 : 28.0;
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: Padding(
                  padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _PageHeader(
                        canEdit: widget.session.can('products:promotions'),
                        refreshing: _loading,
                        onCreate: _startCreating,
                        onRefresh: _load,
                      ),
                      const SizedBox(height: 20),
                      _SummaryGrid(
                        counts: {
                          _PromotionFilter.active: _count(
                            _PromotionState.active,
                          ),
                          _PromotionFilter.scheduled: _count(
                            _PromotionState.scheduled,
                          ),
                          _PromotionFilter.expired: _count(
                            _PromotionState.expired,
                          ),
                          _PromotionFilter.withoutOffer: _count(
                            _PromotionState.withoutOffer,
                          ),
                        },
                        selected: _filter,
                        onSelected: (value) => setState(() => _filter = value),
                      ),
                      const SizedBox(height: 16),
                      _Toolbar(
                        search: _search,
                        searchFocus: _searchFocus,
                        filter: _filter,
                        sort: _sort,
                        count: products.length,
                        onChanged: () => setState(() {}),
                        onFilter: (value) => setState(() => _filter = value),
                        onSort: (value) => setState(() => _sort = value),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        _ErrorBanner(message: _error!, onRetry: _load),
                      ],
                      const SizedBox(height: 14),
                      Expanded(
                        child: _loading
                            ? const Center(child: CircularProgressIndicator())
                            : products.isEmpty
                            ? _EmptyState(
                                filtered: _products.isNotEmpty,
                                onClear: () {
                                  _search.clear();
                                  setState(
                                    () => _filter = _PromotionFilter.all,
                                  );
                                },
                              )
                            : Scrollbar(
                                child: ListView.separated(
                                  key: const PageStorageKey('promotions-list'),
                                  padding: const EdgeInsets.only(bottom: 28),
                                  itemCount: products.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) =>
                                      _PromotionTile(
                                        product: products[index],
                                        canEdit: widget.session.can(
                                          'products:promotions',
                                        ),
                                        onEdit: () => _edit(products[index]),
                                      ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.canEdit,
    required this.refreshing,
    required this.onCreate,
    required this.onRefresh,
  });
  final bool canEdit;
  final bool refreshing;
  final VoidCallback onCreate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    const title = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Preços e promoções',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.w900,
            color: _ink,
          ),
        ),
        SizedBox(height: 5),
        Text(
          'Planeje, acompanhe e encerre ofertas sem alterar o estoque.',
          style: TextStyle(color: _muted, fontSize: 16),
        ),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.outlined(
          tooltip: 'Atualizar',
          onPressed: refreshing ? null : onRefresh,
          icon: const Icon(Icons.refresh_rounded),
        ),
        const SizedBox(width: 10),
        FilledButton.icon(
          onPressed: canEdit ? onCreate : null,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Criar oferta'),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (_, constraints) => constraints.maxWidth >= 680
          ? Row(
              children: [
                const Expanded(child: title),
                actions,
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 16), actions],
            ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.counts,
    required this.selected,
    required this.onSelected,
  });
  final Map<_PromotionFilter, int> counts;
  final _PromotionFilter selected;
  final ValueChanged<_PromotionFilter> onSelected;

  @override
  Widget build(BuildContext context) {
    final cards = [
      _SummaryData(
        'Ativas agora',
        _PromotionFilter.active,
        Icons.local_offer_rounded,
        const Color(0xFF0F9F6E),
      ),
      _SummaryData(
        'Agendadas',
        _PromotionFilter.scheduled,
        Icons.event_rounded,
        const Color(0xFF2563EB),
      ),
      _SummaryData(
        'Encerradas',
        _PromotionFilter.expired,
        Icons.history_rounded,
        const Color(0xFFF59E0B),
      ),
      _SummaryData(
        'Sem oferta',
        _PromotionFilter.withoutOffer,
        Icons.sell_outlined,
        const Color(0xFF64748B),
      ),
    ];
    return LayoutBuilder(
      builder: (_, constraints) {
        final columns = constraints.maxWidth >= 1040
            ? 4
            : constraints.maxWidth >= 560
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (final data in cards)
              SizedBox(
                width: width,
                child: _SummaryCard(
                  data: data,
                  count: counts[data.filter] ?? 0,
                  selected: selected == data.filter,
                  onTap: () => onSelected(
                    selected == data.filter
                        ? _PromotionFilter.all
                        : data.filter,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _SummaryData {
  const _SummaryData(this.label, this.filter, this.icon, this.color);
  final String label;
  final _PromotionFilter filter;
  final IconData icon;
  final Color color;
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({
    required this.data,
    required this.count,
    required this.selected,
    required this.onTap,
  });
  final _SummaryData data;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? data.color.withValues(alpha: 0.07) : Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: selected ? data.color : _line,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: Icon(data.icon, color: data.color),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.label,
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      '$count',
                      style: const TextStyle(
                        color: _ink,
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 20, color: data.color),
            ],
          ),
        ),
      ),
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.search,
    required this.searchFocus,
    required this.filter,
    required this.sort,
    required this.count,
    required this.onChanged,
    required this.onFilter,
    required this.onSort,
  });
  final TextEditingController search;
  final FocusNode searchFocus;
  final _PromotionFilter filter;
  final _PromotionSort sort;
  final int count;
  final VoidCallback onChanged;
  final ValueChanged<_PromotionFilter> onFilter;
  final ValueChanged<_PromotionSort> onSort;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (_, constraints) {
          final searchField = TextField(
            controller: search,
            focusNode: searchFocus,
            onChanged: (_) => onChanged(),
            decoration: InputDecoration(
              hintText: 'Buscar produto, código ou EAN',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: search.text.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        search.clear();
                        onChanged();
                      },
                      icon: const Icon(Icons.close_rounded),
                    ),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          );
          final sortField = DropdownButtonFormField<_PromotionSort>(
            initialValue: sort,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Ordenar por',
              prefixIcon: Icon(Icons.swap_vert_rounded),
              border: OutlineInputBorder(),
              isDense: true,
            ),
            items: const [
              DropdownMenuItem(
                value: _PromotionSort.status,
                child: Text('Status'),
              ),
              DropdownMenuItem(value: _PromotionSort.name, child: Text('Nome')),
              DropdownMenuItem(
                value: _PromotionSort.discount,
                child: Text('Maior desconto'),
              ),
            ],
            onChanged: (value) {
              if (value != null) onSort(value);
            },
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (constraints.maxWidth >= 720)
                Row(
                  children: [
                    Expanded(child: searchField),
                    const SizedBox(width: 12),
                    SizedBox(width: 210, child: sortField),
                  ],
                )
              else ...[
                searchField,
                const SizedBox(height: 10),
                sortField,
              ],
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    for (final item in const [
                      ('Todas', _PromotionFilter.all),
                      ('Ativas', _PromotionFilter.active),
                      ('Agendadas', _PromotionFilter.scheduled),
                      ('Encerradas', _PromotionFilter.expired),
                      ('Sem oferta', _PromotionFilter.withoutOffer),
                    ])
                      Padding(
                        padding: const EdgeInsets.only(right: 7),
                        child: ChoiceChip(
                          label: Text(item.$1),
                          selected: filter == item.$2,
                          onSelected: (_) => onFilter(item.$2),
                        ),
                      ),
                    const SizedBox(width: 6),
                    Text(
                      '$count produto${count == 1 ? '' : 's'}',
                      style: const TextStyle(
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PromotionTile extends StatelessWidget {
  const _PromotionTile({
    required this.product,
    required this.canEdit,
    required this.onEdit,
  });
  final Product product;
  final bool canEdit;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final state = _stateOf(product);
    final action = OutlinedButton.icon(
      onPressed: canEdit ? onEdit : null,
      icon: Icon(
        state == _PromotionState.withoutOffer
            ? Icons.add_rounded
            : Icons.edit_outlined,
      ),
      label: Text(
        state == _PromotionState.withoutOffer ? 'Criar oferta' : 'Gerenciar',
      ),
    );
    return AppCard(
      padding: EdgeInsets.zero,
      child: LayoutBuilder(
        builder: (_, constraints) {
          final identity = _ProductIdentity(product: product);
          final pricing = _Pricing(product: product);
          final schedule = _Schedule(product: product, state: state);
          final status = _StatusChip(style: _styleOf(state));
          if (constraints.maxWidth < 850) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: identity),
                      const SizedBox(width: 8),
                      status,
                    ],
                  ),
                  const Divider(height: 24),
                  Wrap(
                    spacing: 28,
                    runSpacing: 14,
                    children: [pricing, schedule],
                  ),
                  const SizedBox(height: 14),
                  Align(alignment: Alignment.centerRight, child: action),
                ],
              ),
            );
          }
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
            child: Row(
              children: [
                Expanded(flex: 5, child: identity),
                Expanded(flex: 3, child: pricing),
                Expanded(flex: 4, child: schedule),
                SizedBox(
                  width: 130,
                  child: Align(alignment: Alignment.centerLeft, child: status),
                ),
                const SizedBox(width: 12),
                action,
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ProductIdentity extends StatelessWidget {
  const _ProductIdentity({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            color: Color(0xFFEAF4F7),
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(Icons.inventory_2_outlined, color: _brand),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                product.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _ink,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                product.internalCode ?? product.barcode ?? 'Sem código',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _muted, fontSize: 13),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Pricing extends StatelessWidget {
  const _Pricing({required this.product});
  final Product product;

  @override
  Widget build(BuildContext context) {
    final discount = _discountOf(product);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'PREÇO',
          style: TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _money(product.offerPrice ?? product.salePrice),
              style: const TextStyle(
                color: _ink,
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            if (discount > 0) ...[
              const SizedBox(width: 7),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: const Color(0xFFDCFCE7),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  child: Text(
                    '${discount.toStringAsFixed(2).replaceAll('.', ',')}% OFF',
                    style: const TextStyle(
                      color: Color(0xFF15803D),
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (product.offerPrice != null)
          Text(
            'normal ${_money(product.salePrice)}',
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              decoration: TextDecoration.lineThrough,
            ),
          ),
      ],
    );
  }
}

class _Schedule extends StatelessWidget {
  const _Schedule({required this.product, required this.state});
  final Product product;
  final _PromotionState state;

  @override
  Widget build(BuildContext context) {
    final text = state == _PromotionState.withoutOffer
        ? 'Nenhum período definido'
        : '${_shortDateTime(product.offerStartAt!)}  →  ${_shortDateTime(product.offerEndAt!)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'PERÍODO',
          style: TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 5),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_today_outlined, size: 16, color: _muted),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                text,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: state == _PromotionState.withoutOffer ? _muted : _ink,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusStyle {
  const _StatusStyle(this.label, this.icon, this.color, this.background);
  final String label;
  final IconData icon;
  final Color color;
  final Color background;
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.style});
  final _StatusStyle style;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: style.background,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(style.icon, size: 15, color: style.color),
            const SizedBox(width: 5),
            Text(
              style.label,
              style: TextStyle(
                color: style.color,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PromotionEditor extends StatefulWidget {
  const _PromotionEditor({
    required this.product,
    required this.api,
    required this.token,
  });
  final Product product;
  final ApiClient api;
  final String token;

  @override
  State<_PromotionEditor> createState() => _PromotionEditorState();
}

class _PromotionEditorState extends State<_PromotionEditor> {
  late final _price = TextEditingController(
    text: widget.product.offerPrice == null
        ? ''
        : formatBrazilianMoneyInput(widget.product.offerPrice!),
  );
  late DateTime? _start = widget.product.offerStartAt;
  late DateTime? _end = widget.product.offerEndAt;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _price.dispose();
    super.dispose();
  }

  double? get _offerPrice =>
      _price.text.trim().isEmpty ? null : parseBrazilianNumber(_price.text);
  double get _discount {
    final price = _offerPrice;
    return price == null || widget.product.salePrice <= 0
        ? 0
        : ((widget.product.salePrice - price) / widget.product.salePrice) * 100;
  }

  Future<void> _pickStart() async {
    final value = await _pickDateTime(context, _start ?? DateTime.now());
    if (value == null) return;
    setState(() {
      _start = value;
      if (_end == null || !_end!.isAfter(value)) {
        _end = value.add(const Duration(days: 7));
      }
    });
  }

  Future<void> _pickEnd() async {
    final value = await _pickDateTime(
      context,
      _end ?? (_start ?? DateTime.now()).add(const Duration(days: 7)),
    );
    if (value != null) setState(() => _end = value);
  }

  void _quickPeriod(int days) {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day, now.hour, now.minute);
    setState(() {
      _start = start;
      _end = start.add(Duration(days: days));
    });
  }

  Future<void> _save() async {
    final price = _offerPrice;
    if (price == null || price <= 0) {
      return _fail('Informe um preço de oferta válido.');
    }
    if (widget.product.salePrice > 0 && price >= widget.product.salePrice) {
      return _fail('O preço promocional deve ser menor que o preço normal.');
    }
    if (_start == null || _end == null) {
      return _fail('Defina o início e o fim da oferta.');
    }
    if (!_end!.isAfter(_start!)) {
      return _fail('O fim deve ser posterior ao início.');
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.api.updateProductPromotion(
        widget.token,
        widget.product.id,
        offerPrice: price,
        offerStartAt: _start,
        offerEndAt: _end,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Não foi possível salvar a promoção.');
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _fail(String message) => setState(() => _error = message);

  Future<void> _endOffer() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Encerrar oferta?'),
        content: const Text(
          'O produto voltará a usar o preço normal imediatamente.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Encerrar'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.api.updateProductPromotion(
        widget.token,
        widget.product.id,
        offerPrice: null,
        offerStartAt: null,
        offerEndAt: null,
      );
      if (mounted) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasOffer = widget.product.offerPrice != null;
    return Material(
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 20, 16, 18),
            child: Row(
              children: [
                const CircleAvatar(
                  backgroundColor: Color(0xFFEAF4F7),
                  child: Icon(Icons.local_offer_outlined, color: _brand),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        hasOffer ? 'Gerenciar oferta' : 'Criar oferta',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        widget.product.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: _muted),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar',
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _canvas,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: _PriceLabel(
                            label: 'Preço normal',
                            value: _money(widget.product.salePrice),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PriceLabel(
                            label: 'Oferta',
                            value: _offerPrice == null
                                ? '—'
                                : _money(_offerPrice!),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PriceLabel(
                            label: 'Desconto',
                            value: _discount > 0
                                ? '${_discount.toStringAsFixed(2).replaceAll('.', ',')}% OFF'
                                : '—',
                            highlight: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _price,
                    enabled: !_saving,
                    keyboardType: TextInputType.number,
                    inputFormatters: const [BrazilianMoneyInputFormatter()],
                    onChanged: (_) => setState(() => _error = null),
                    decoration: const InputDecoration(
                      labelText: 'Preço promocional',
                      prefixText: 'R\$ ',
                      helperText: 'Deve ser menor que o preço normal.',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Período da oferta',
                    style: TextStyle(
                      color: _ink,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 5),
                  const Text(
                    'Escolha um atalho ou defina as datas e horários.',
                    style: TextStyle(color: _muted),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        avatar: const Icon(Icons.today_rounded, size: 17),
                        label: const Text('1 dia'),
                        onPressed: _saving ? null : () => _quickPeriod(1),
                      ),
                      ActionChip(
                        avatar: const Icon(Icons.date_range_rounded, size: 17),
                        label: const Text('7 dias'),
                        onPressed: _saving ? null : () => _quickPeriod(7),
                      ),
                      ActionChip(
                        avatar: const Icon(
                          Icons.calendar_month_rounded,
                          size: 17,
                        ),
                        label: const Text('30 dias'),
                        onPressed: _saving ? null : () => _quickPeriod(30),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  LayoutBuilder(
                    builder: (_, constraints) {
                      final start = _DateTimeField(
                        label: 'Início',
                        value: _start,
                        enabled: !_saving,
                        onTap: _pickStart,
                      );
                      final end = _DateTimeField(
                        label: 'Fim',
                        value: _end,
                        enabled: !_saving,
                        onTap: _pickEnd,
                      );
                      return constraints.maxWidth >= 520
                          ? Row(
                              children: [
                                Expanded(child: start),
                                const SizedBox(width: 12),
                                Expanded(child: end),
                              ],
                            )
                          : Column(
                              children: [
                                start,
                                const SizedBox(height: 12),
                                end,
                              ],
                            );
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    _InlineError(message: _error!),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Wrap(
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 8,
              children: [
                if (hasOffer)
                  TextButton.icon(
                    onPressed: _saving ? null : _endOffer,
                    icon: const Icon(Icons.stop_circle_outlined),
                    label: const Text('Encerrar oferta'),
                  ),
                TextButton(
                  onPressed: _saving ? null : () => Navigator.pop(context),
                  child: const Text('Cancelar'),
                ),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_rounded),
                  label: Text(_saving ? 'Salvando...' : 'Salvar oferta'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PriceLabel extends StatelessWidget {
  const _PriceLabel({
    required this.label,
    required this.value,
    this.highlight = false,
  });
  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: _muted,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
      Text(
        value,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: highlight ? const Color(0xFF15803D) : _ink,
          fontSize: 18,
          fontWeight: FontWeight.w900,
        ),
      ),
    ],
  );
}

class _DateTimeField extends StatelessWidget {
  const _DateTimeField({
    required this.label,
    required this.value,
    required this.enabled,
    required this.onTap,
  });
  final String label;
  final DateTime? value;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onTap : null,
    borderRadius: BorderRadius.circular(8),
    child: InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.event_outlined),
        suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        border: const OutlineInputBorder(),
        enabled: enabled,
      ),
      child: Text(
        value == null ? 'Selecionar data e hora' : _fullDateTime(value!),
        style: TextStyle(color: value == null ? _muted : _ink),
      ),
    ),
  );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => _InlineError(
    message: message,
    trailing: TextButton(
      onPressed: onRetry,
      child: const Text('Tentar novamente'),
    ),
  );
}

class _InlineError extends StatelessWidget {
  const _InlineError({required this.message, this.trailing});
  final String message;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFFECACA)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFB91C1C)),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            message,
            style: const TextStyle(
              color: Color(0xFF991B1B),
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        ?trailing,
      ],
    ),
  );
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.filtered, required this.onClear});
  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 430),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircleAvatar(
            radius: 34,
            backgroundColor: Color(0xFFEAF4F7),
            child: Icon(Icons.local_offer_outlined, size: 34, color: _brand),
          ),
          const SizedBox(height: 14),
          Text(
            filtered
                ? 'Nenhum produto encontrado'
                : 'Nenhum produto disponível',
            style: const TextStyle(
              color: _ink,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            filtered
                ? 'Ajuste a busca ou limpe os filtros para ver outros produtos.'
                : 'Cadastre produtos ativos para começar a criar ofertas.',
            textAlign: TextAlign.center,
            style: const TextStyle(color: _muted),
          ),
          if (filtered) ...[
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: onClear,
              icon: const Icon(Icons.filter_alt_off_outlined),
              label: const Text('Limpar filtros'),
            ),
          ],
        ],
      ),
    ),
  );
}

_PromotionState _stateOf(Product product) {
  if (product.offerPrice == null ||
      product.offerStartAt == null ||
      product.offerEndAt == null) {
    return _PromotionState.withoutOffer;
  }
  final now = DateTime.now();
  if (now.isBefore(product.offerStartAt!)) return _PromotionState.scheduled;
  if (now.isAfter(product.offerEndAt!)) return _PromotionState.expired;
  return _PromotionState.active;
}

_StatusStyle _styleOf(_PromotionState state) => switch (state) {
  _PromotionState.active => const _StatusStyle(
    'Ativa',
    Icons.bolt_rounded,
    Color(0xFF047857),
    Color(0xFFD1FAE5),
  ),
  _PromotionState.scheduled => const _StatusStyle(
    'Agendada',
    Icons.schedule_rounded,
    Color(0xFF1D4ED8),
    Color(0xFFDBEAFE),
  ),
  _PromotionState.expired => const _StatusStyle(
    'Encerrada',
    Icons.history_rounded,
    Color(0xFFB45309),
    Color(0xFFFEF3C7),
  ),
  _PromotionState.withoutOffer => const _StatusStyle(
    'Sem oferta',
    Icons.remove_rounded,
    Color(0xFF475569),
    Color(0xFFF1F5F9),
  ),
};

int _statusOrder(_PromotionState state) => switch (state) {
  _PromotionState.active => 0,
  _PromotionState.scheduled => 1,
  _PromotionState.expired => 2,
  _PromotionState.withoutOffer => 3,
};

double _discountOf(Product product) {
  final offer = product.offerPrice;
  if (offer == null || product.salePrice <= 0 || offer >= product.salePrice) {
    return 0;
  }
  return ((product.salePrice - offer) / product.salePrice) * 100;
}

Future<DateTime?> _pickDateTime(BuildContext context, DateTime initial) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: initial,
    firstDate: DateTime(now.year - 3),
    lastDate: DateTime(now.year + 10, 12, 31),
    helpText: 'Selecione a data',
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(initial),
    helpText: 'Selecione o horário',
  );
  if (time == null) return null;
  return DateTime(date.year, date.month, date.day, time.hour, time.minute);
}

String _money(double value) => 'R\$ ${formatBrazilianMoneyInput(value)}';
String _shortDateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
String _fullDateTime(DateTime value) =>
    '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} às ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
