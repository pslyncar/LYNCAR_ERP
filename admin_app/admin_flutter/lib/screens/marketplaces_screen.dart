import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/marketplace.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../widgets/app_card.dart';
import '../widgets/error_panel.dart';

class MarketplacesScreen extends StatefulWidget {
  const MarketplacesScreen({super.key, required this.session});

  final Session session;

  @override
  State<MarketplacesScreen> createState() => _MarketplacesScreenState();
}

class _MarketplacesScreenState extends State<MarketplacesScreen> {
  late final _api = ApiClient(widget.session.apiBaseUrl);

  MercadoLivreStatus? _status;
  List<MarketplaceProduct> _products = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.getMercadoLivreStatus(widget.session.token),
        _api.listMercadoLivreProducts(widget.session.token),
      ]);
      setState(() {
        _status = results[0] as MercadoLivreStatus;
        _products = results[1] as List<MarketplaceProduct>;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _copyAuthUrl() async {
    try {
      final auth = await _api.getMercadoLivreAuthUrl(widget.session.token);
      await Clipboard.setData(ClipboardData(text: auth.authUrl));
      if (!mounted) return;
      _showMessage('Link de conexão copiado.');
    } on ApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  Future<void> _updateProduct(
    MarketplaceProduct product,
    Map<String, dynamic> payload,
  ) async {
    try {
      final listing = await _api.updateMercadoLivreProduct(
        widget.session.token,
        product.productId,
        payload,
      );
      setState(() {
        _products = [
          for (final item in _products)
            if (item.productId == product.productId)
              MarketplaceProduct(
                productId: item.productId,
                name: item.name,
                internalCode: item.internalCode,
                barcode: item.barcode,
                salePrice: item.salePrice,
                stockQuantity: item.stockQuantity,
                active: item.active,
                listing: listing,
              )
            else
              item,
        ];
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  void _showMessage(String message) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mercado Livre'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Marketplaces', style: theme.textTheme.headlineMedium),
                    const SizedBox(height: 6),
                    Text(
                      'Mercado Livre, estoque e produtos publicados',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton.outlined(
                tooltip: 'Atualizar',
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_error != null)
            ErrorPanel(message: _error!, onRetry: _load)
          else if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(48),
                child: CircularProgressIndicator(),
              ),
            )
          else ...[
            _StatusCard(status: _status, onConnect: _copyAuthUrl),
            const SizedBox(height: 16),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Produtos do estoque',
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'O estoque do produto continua sendo a base. Marque somente o que deve ir para o Mercado Livre.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_products.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text('Nenhum produto encontrado.'),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 760;
                        return Column(
                          children: [
                            for (final product in _products)
                              _ProductListingTile(
                                product: product,
                                compact: compact,
                                onChanged: (payload) =>
                                    _updateProduct(product, payload),
                              ),
                          ],
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.status, required this.onConnect});

  final MercadoLivreStatus? status;
  final VoidCallback onConnect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = status?.connected == true;
    final configured = status?.configured == true;
    return AppCard(
      child: Wrap(
        spacing: 18,
        runSpacing: 18,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.10),
            child: Icon(
              Icons.storefront,
              color: theme.colorScheme.primary,
              size: 30,
            ),
          ),
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 260, maxWidth: 680),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mercado Livre',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  status?.message ?? 'Carregando configuracao.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (status?.nickname != null) ...[
                  const SizedBox(height: 8),
                  Text('Conta: ${status!.nickname}'),
                ],
              ],
            ),
          ),
          Chip(
            avatar: Icon(
              connected ? Icons.check_circle_outline : Icons.info_outline,
              size: 18,
            ),
            label: Text(connected ? 'Conectado' : 'Não conectado'),
          ),
          FilledButton.icon(
            onPressed: configured ? onConnect : null,
            icon: const Icon(Icons.link),
            label: const Text('Copiar link de conexão'),
          ),
        ],
      ),
    );
  }
}

class _ProductListingTile extends StatelessWidget {
  const _ProductListingTile({
    required this.product,
    required this.compact,
    required this.onChanged,
  });

  final MarketplaceProduct product;
  final bool compact;
  final ValueChanged<Map<String, dynamic>> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final listing = product.listing;
    final title = listing.title?.trim().isNotEmpty == true
        ? listing.title!.trim()
        : product.name;
    final codes = [
      if (product.internalCode?.trim().isNotEmpty == true)
        'Código ${product.internalCode}',
      if (product.barcode?.trim().isNotEmpty == true)
        'Barras ${product.barcode}',
    ].join(' | ');
    final controls = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        FilterChip(
          selected: listing.enabled,
          avatar: Icon(listing.enabled ? Icons.check : Icons.close, size: 18),
          label: Text(listing.enabled ? 'Publicado' : 'Não publicar'),
          onSelected: (value) =>
              onChanged(listing.toUpdateJson(enabled: value)),
        ),
        FilterChip(
          selected: listing.syncStock,
          label: const Text('Sincronizar estoque'),
          onSelected: listing.enabled
              ? (value) => onChanged(listing.toUpdateJson(syncStock: value))
              : null,
        ),
        FilterChip(
          selected: listing.syncPrice,
          label: const Text('Sincronizar preço'),
          onSelected: listing.enabled
              ? (value) => onChanged(listing.toUpdateJson(syncPrice: value))
              : null,
        ),
      ],
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
        ),
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ProductInfo(product: product, title: title, codes: codes),
                const SizedBox(height: 12),
                controls,
              ],
            )
          : Row(
              children: [
                Expanded(
                  child: _ProductInfo(
                    product: product,
                    title: title,
                    codes: codes,
                  ),
                ),
                const SizedBox(width: 16),
                controls,
              ],
            ),
    );
  }
}

class _ProductInfo extends StatelessWidget {
  const _ProductInfo({
    required this.product,
    required this.title,
    required this.codes,
  });

  final MarketplaceProduct product;
  final String title;
  final String codes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          [
            if (codes.isNotEmpty) codes,
            'Estoque ${_formatDecimal(product.stockQuantity)}',
            _formatCurrency(product.salePrice),
          ].join(' | '),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

String _formatCurrency(double value) {
  return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
}

String _formatDecimal(double value) {
  final text = value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(2);
  return text.replaceAll('.', ',');
}
