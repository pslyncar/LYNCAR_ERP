import 'package:flutter/material.dart';

import '../models/dashboard_summary.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/browser_redirect.dart';
import '../widgets/error_panel.dart';

class ClientStoreScreen extends StatefulWidget {
  const ClientStoreScreen({super.key, required this.session});
  final Session session;
  @override
  State<ClientStoreScreen> createState() => _ClientStoreScreenState();
}

class _ClientStoreScreenState extends State<ClientStoreScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  List<DashboardContent> _items = const [];
  Object? _error;
  bool _loading = true;

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
      final summary = await _api.getDashboardSummary(widget.session.token);
      if (!mounted) return;
      setState(() {
        _items = summary.contents
            .where(
              (e) =>
                  e.contentType == 'product' ||
                  e.contentType == 'affiliate_link',
            )
            .toList();
        _loading = false;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error;
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF4F7FB),
    body: RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(28, 28, 28, 40),
        children: [
          Text(
            'Loja Lyncar',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: const Color(0xFF14213D),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Recursos e soluções para sua empresa',
            style: TextStyle(color: Colors.blueGrey.shade600, fontSize: 16),
          ),
          const SizedBox(height: 24),
          if (_loading)
            const Center(
              child: Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
            )
          else if (_error != null)
            ErrorPanel(
              message: 'Não foi possível carregar a Loja Lyncar.',
              onRetry: _load,
            )
          else if (_items.isEmpty)
            _empty(context)
          else
            LayoutBuilder(
              builder: (context, c) {
                final cols = c.maxWidth >= 1100
                    ? 3
                    : c.maxWidth >= 650
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: cols,
                    crossAxisSpacing: 18,
                    mainAxisSpacing: 18,
                    childAspectRatio: 1.45,
                  ),
                  itemBuilder: (_, i) => _card(_items[i]),
                );
              },
            ),
        ],
      ),
    ),
  );

  Widget _empty(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.storefront_outlined,
            size: 48,
            color: Colors.blueGrey.shade300,
          ),
          const SizedBox(height: 12),
          const Text(
            'Nenhum recurso disponível no momento',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            'Quando houver produtos ou extensões para sua empresa, eles aparecerão aqui.',
            style: TextStyle(color: Colors.blueGrey.shade600),
          ),
        ],
      ),
    ),
  );
  Widget _card(DashboardContent item) => Card(
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: item.targetUrl == null
          ? null
          : () => redirectToUrl(item.targetUrl!),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _StoreImage(
            imageUrl: _publicUrl(widget.session.apiBaseUrl, item.imageUrl),
            icon: item.contentType == 'affiliate_link'
                ? Icons.extension_outlined
                : Icons.shopping_bag_outlined,
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  if (item.description?.isNotEmpty == true) ...[
                    const SizedBox(height: 6),
                    Text(
                      item.description!,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.blueGrey.shade600),
                    ),
                  ],
                  const Spacer(),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (item.priceLabel?.isNotEmpty == true)
                        Text(
                          item.priceLabel!,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF167A8B),
                          ),
                        ),
                      if (item.targetUrl != null)
                        const Icon(
                          Icons.arrow_forward,
                          color: Color(0xFF167A8B),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _StoreImage extends StatelessWidget {
  const _StoreImage({required this.imageUrl, required this.icon});

  final String? imageUrl;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 170,
      child: DecoratedBox(
        decoration: const BoxDecoration(color: Color(0xFFEAF2FF)),
        child: imageUrl == null
            ? Icon(icon, size: 48, color: const Color(0xFF167A8B))
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(icon, size: 48, color: const Color(0xFF167A8B)),
              ),
      ),
    );
  }
}

String? _publicUrl(String apiBaseUrl, String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) return null;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  final base = apiBaseUrl.endsWith('/')
      ? apiBaseUrl.substring(0, apiBaseUrl.length - 1)
      : apiBaseUrl;
  final path = trimmed.startsWith('/') ? trimmed : '/$trimmed';
  return '$base$path';
}
