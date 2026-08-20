import 'package:flutter/material.dart';

import '../models/product.dart';
import '../services/api_client.dart';
import '../utils/input_formatters.dart';
import '../models/session.dart';

class PromotionsScreen extends StatefulWidget {
  const PromotionsScreen({super.key, required this.session});

  final Session session;

  @override
  State<PromotionsScreen> createState() => _PromotionsScreenState();
}

class _PromotionsScreenState extends State<PromotionsScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _search = TextEditingController();
  List<Product> _products = [];
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
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final products = await _api.listProducts(widget.session.token);
      if (mounted) setState(() => _products = products);
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Não foi possível carregar preços e promoções.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _search.text.trim().toLowerCase();
    final products = _products.where((product) {
      if (term.isEmpty) return true;
      return '${product.name} ${product.internalCode ?? ''} ${product.barcode ?? ''}'
          .toLowerCase()
          .contains(term);
    }).toList();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1360),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Preços e promoções', style: TextStyle(fontSize: 32, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  const Text('Ofertas são gerenciadas separadamente do cadastro e do estoque.', style: TextStyle(color: Color(0xFF64748B), fontSize: 16)),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search),
                      labelText: 'Buscar produto, código ou EAN',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C), fontWeight: FontWeight.w700)),
                  ],
                  const SizedBox(height: 16),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.separated(
                            itemCount: products.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 10),
                            itemBuilder: (context, index) => _PromotionCard(
                              product: products[index],
                              canEdit: widget.session.can('products:promotions'),
                              onSaved: _load,
                              api: _api,
                              token: widget.session.token,
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PromotionCard extends StatefulWidget {
  const _PromotionCard({required this.product, required this.canEdit, required this.onSaved, required this.api, required this.token});

  final Product product;
  final bool canEdit;
  final Future<void> Function() onSaved;
  final ApiClient api;
  final String token;

  @override
  State<_PromotionCard> createState() => _PromotionCardState();
}

class _PromotionCardState extends State<_PromotionCard> {
  late final _price = TextEditingController(text: widget.product.offerPrice == null ? '' : formatBrazilianMoneyInput(widget.product.offerPrice!));
  late final _start = TextEditingController(text: _dateTime(widget.product.offerStartAt));
  late final _end = TextEditingController(text: _dateTime(widget.product.offerEndAt));
  bool _saving = false;
  String? _error;

  @override
  void dispose() { _price.dispose(); _start.dispose(); _end.dispose(); super.dispose(); }

  Future<void> _save() async {
    final price = _price.text.trim().isEmpty ? null : parseBrazilianNumber(_price.text);
    final start = _parseDateTime(_start.text);
    final end = _parseDateTime(_end.text);
    if (price != null && (start == null || end == null)) {
      setState(() => _error = 'Informe início e fim da oferta.');
      return;
    }
    if (price == null && (_start.text.trim().isNotEmpty || _end.text.trim().isNotEmpty)) {
      setState(() => _error = 'Informe o preço da oferta ou limpe os três campos.');
      return;
    }
    if (price != null && end!.isBefore(start!)) {
      setState(() => _error = 'O fim deve ser posterior ao início.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.api.updateProductPromotion(widget.token, widget.product.id, offerPrice: price, offerStartAt: start, offerEndAt: end);
      await widget.onSaved();
    } on ApiException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(builder: (context, constraints) {
        final wide = constraints.maxWidth >= 850;
        final fields = [
          _input(_price, 'Preço da oferta', money: true),
          _input(_start, 'Início (dd/mm/aaaa hh:mm)'),
          _input(_end, 'Fim (dd/mm/aaaa hh:mm)'),
        ];
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.product.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          Text('Preço normal: ${formatBrazilianMoneyInput(widget.product.salePrice)} • ${widget.product.internalCode ?? widget.product.barcode ?? 'Sem código'}', style: const TextStyle(color: Color(0xFF64748B))),
          const SizedBox(height: 12),
          wide ? Row(children: [for (final field in fields) Expanded(child: Padding(padding: const EdgeInsets.only(right: 10), child: field)), _saveButton()]) : Column(children: [...fields, Align(alignment: Alignment.centerRight, child: _saveButton())]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_error!, style: const TextStyle(color: Color(0xFFB91C1C)))),
        ]);
      }),
    ),
  );

  Widget _input(TextEditingController controller, String label, {bool money = false}) => TextField(
    controller: controller,
    enabled: widget.canEdit && !_saving,
    inputFormatters: money ? const [BrazilianMoneyInputFormatter()] : const [BrazilianDateTimeInputFormatter()],
    decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
  );
  Widget _saveButton() => FilledButton.icon(onPressed: widget.canEdit && !_saving ? _save : null, icon: const Icon(Icons.save_outlined), label: Text(_saving ? 'Salvando...' : 'Salvar'));
}

String _dateTime(DateTime? value) => value == null ? '' : '${value.day.toString().padLeft(2, '0')}/${value.month.toString().padLeft(2, '0')}/${value.year} ${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
DateTime? _parseDateTime(String value) {
  final digits = value.replaceAll(RegExp(r'\D'), '');
  if (digits.length != 12) return null;
  return DateTime.tryParse('${digits.substring(4, 8)}-${digits.substring(2, 4)}-${digits.substring(0, 2)}T${digits.substring(8, 10)}:${digits.substring(10, 12)}:00');
}
