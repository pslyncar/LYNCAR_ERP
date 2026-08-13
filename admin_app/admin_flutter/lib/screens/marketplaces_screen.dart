import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
      final status = await _api.getMercadoLivreStatus(widget.session.token);
      final products = widget.session.can('marketplaces:products')
          ? await _api.listMercadoLivreProducts(widget.session.token)
          : <MarketplaceProduct>[];
      if (!mounted) return;
      setState(() {
        _status = status;
        _products = products;
      });
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _connectMercadoLivre() async {
    try {
      final auth = await _api.getMercadoLivreAuthUrl(widget.session.token);
      await Clipboard.setData(ClipboardData(text: auth.authUrl));
      await launchUrl(Uri.parse(auth.authUrl), webOnlyWindowName: '_blank');
      if (!mounted) return;
      _showMessage(
        'Abrimos a autorização do Mercado Livre em uma nova aba e copiamos o link. '
        'Depois que autorizar, volte aqui e clique em Atualizar.',
      );
    } on ApiException catch (error) {
      if (!mounted) return;
      _showMessage(error.message);
    }
  }

  Future<void> _showImportDialog() async {
    final linked = await showDialog<bool>(
      context: context,
      builder: (context) => _MercadoLivreImportDialog(
        api: _api,
        token: widget.session.token,
        products: _products,
      ),
    );
    if (linked == true) await _load();
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
    final canConnect = widget.session.can('marketplaces:connect');
    final canManageProducts = widget.session.can('marketplaces:products');
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
            _StatusCard(
              status: _status,
              canConnect: canConnect,
              canManageProducts: canManageProducts,
              onConnect: canConnect ? _connectMercadoLivre : null,
              onImport: _status?.connected == true && canManageProducts
                  ? _showImportDialog
                  : null,
            ),
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
                  if (!canManageProducts)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Text(
                        'Seu perfil pode visualizar a conexão, mas não pode gerenciar produtos do Mercado Livre.',
                      ),
                    )
                  else if (_products.isEmpty)
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
  const _StatusCard({
    required this.status,
    required this.canConnect,
    required this.canManageProducts,
    required this.onConnect,
    required this.onImport,
  });

  final MercadoLivreStatus? status;
  final bool canConnect;
  final bool canManageProducts;
  final VoidCallback? onConnect;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final connected = status?.connected == true;
    final configured = status?.configured == true;
    final message =
        status?.message ??
        (configured
            ? 'Clique em Conectar Mercado Livre para autorizar a conta da loja.'
            : 'Integração Mercado Livre ainda não configurada no servidor.');
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
                  message,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (status?.nickname != null) ...[
                  const SizedBox(height: 8),
                  Text('Conta: ${status!.nickname}'),
                ],
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Chip(
                      label: Text(
                        status?.listingLimit == null
                            ? 'Anúncios: ilimitado'
                            : 'Anúncios: ${status!.enabledListings}/${status!.listingLimit}',
                      ),
                    ),
                    if ((status?.pendingJobs ?? 0) > 0)
                      Chip(label: Text('${status!.pendingJobs} pendente(s)')),
                  ],
                ),
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
            onPressed: configured && canConnect ? onConnect : null,
            icon: const Icon(Icons.login),
            label: Text(
              connected ? 'Reconectar Mercado Livre' : 'Conectar Mercado Livre',
            ),
          ),
          OutlinedButton.icon(
            onPressed: onImport,
            icon: const Icon(Icons.download_outlined),
            label: const Text('Importar anúncios existentes'),
          ),
          if (!canConnect)
            Text(
              'Seu perfil não pode conectar contas.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          if (connected && !canManageProducts)
            Text(
              'Seu perfil não pode importar ou vincular produtos.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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

class _MercadoLivreImportDialog extends StatefulWidget {
  const _MercadoLivreImportDialog({
    required this.api,
    required this.token,
    required this.products,
  });

  final ApiClient api;
  final String token;
  final List<MarketplaceProduct> products;

  @override
  State<_MercadoLivreImportDialog> createState() =>
      _MercadoLivreImportDialogState();
}

class _MercadoLivreImportDialogState extends State<_MercadoLivreImportDialog> {
  late Future<MercadoLivreImportPreview> _future;
  final Map<String, int?> _selectedProducts = {};
  final Set<String> _linking = {};

  @override
  void initState() {
    super.initState();
    _future = widget.api.previewMercadoLivreListings(widget.token);
  }

  Future<void> _link(MercadoLivreImportItem item) async {
    final productId = _selectedProducts[item.listingId] ?? item.localProductId;
    if (productId == null) return;
    setState(() => _linking.add(item.listingId));
    try {
      await widget.api.linkMercadoLivreListing(
        widget.token,
        productId: productId,
        listingId: item.listingId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Mercado Livre'),
          content: Text(error.message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _linking.remove(item.listingId));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Importar anúncios existentes'),
      content: SizedBox(
        width: 820,
        child: FutureBuilder<MercadoLivreImportPreview>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            if (snapshot.hasError) {
              return SizedBox(
                height: 220,
                child: Center(child: Text(snapshot.error.toString())),
              );
            }
            final items = snapshot.data?.results ?? const [];
            if (items.isEmpty) {
              return const SizedBox(
                height: 180,
                child: Center(child: Text('Nenhum anúncio encontrado.')),
              );
            }
            return ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 520),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: items.length,
                separatorBuilder: (context, index) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final selected =
                      _selectedProducts[item.listingId] ?? item.localProductId;
                  final isLinking = _linking.contains(item.listingId);
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.title,
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      item.listingId,
                                      if (item.status != null) item.status!,
                                      if (item.price != null)
                                        _formatCurrency(item.price!),
                                      if (item.availableQuantity != null)
                                        'Estoque ${item.availableQuantity}',
                                      if (item.sellerCustomField != null)
                                        'Código ML ${item.sellerCustomField}',
                                    ].join(' | '),
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (item.alreadyLinked)
                              const Chip(label: Text('Já vinculado')),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<int>(
                                initialValue: selected,
                                isExpanded: true,
                                decoration: const InputDecoration(
                                  labelText: 'Produto do estoque Lyncar',
                                ),
                                items: [
                                  for (final product in widget.products)
                                    DropdownMenuItem(
                                      value: product.productId,
                                      child: Text(
                                        [
                                          product.name,
                                          if (product.internalCode
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true)
                                            product.internalCode!,
                                          if (product.barcode
                                                  ?.trim()
                                                  .isNotEmpty ==
                                              true)
                                            product.barcode!,
                                        ].join(' | '),
                                      ),
                                    ),
                                ],
                                onChanged: item.alreadyLinked
                                    ? null
                                    : (value) => setState(
                                        () =>
                                            _selectedProducts[item.listingId] =
                                                value,
                                      ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.icon(
                              onPressed:
                                  item.alreadyLinked ||
                                      selected == null ||
                                      isLinking
                                  ? null
                                  : () => _link(item),
                              icon: isLinking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.link),
                              label: const Text('Vincular'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Fechar'),
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
