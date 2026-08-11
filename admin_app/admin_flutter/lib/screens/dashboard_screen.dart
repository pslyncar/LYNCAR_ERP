import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/company_billing.dart';
import '../models/dashboard_summary.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/browser_redirect.dart';
import '../widgets/error_panel.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, required this.session});

  final Session session;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  DashboardSummary? _summary;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDashboard();
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await _api.getDashboardSummary(widget.session.token);
      setState(() => _summary = summary);
    } on ApiException catch (error) {
      setState(() => _error = error.message);
    } catch (_) {
      setState(() => _error = 'Não foi possível carregar o dashboard.');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _openBillingPayment() async {
    try {
      final billing = await _api.getDashboardBillingPayment(
        widget.session.token,
      );
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => _ClientPixDialog(billing: billing),
      );
      await _loadDashboard();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;

    return ColoredBox(
      color: const Color(0xFFF4F7FB),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
            children: [
              _Header(
                session: widget.session,
                summary: summary,
                onRefresh: _loadDashboard,
              ),
              const SizedBox(height: 20),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                ErrorPanel(message: _error!, onRetry: _loadDashboard)
              else if (summary != null) ...[
                if (summary.isTechnical) ...[
                  _MetricGrid(summary: summary),
                  const SizedBox(height: 18),
                  _DashboardBody(summary: summary),
                  const SizedBox(height: 18),
                  _AlertsPanel(alerts: summary.alerts),
                ] else
                  _ShowcaseDashboard(
                    summary: summary,
                    companyName: widget.session.companyName,
                    apiBaseUrl: widget.session.apiBaseUrl,
                    onOpenPayment: _openBillingPayment,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.session,
    required this.summary,
    required this.onRefresh,
  });

  final Session session;
  final DashboardSummary? summary;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final billingNoticeCount =
        summary?.contents
            .where(
              (item) =>
                  item.contentType == 'billing_overdue' ||
                  item.contentType == 'billing_due',
            )
            .length ??
        0;
    final alertCount = summary?.isTechnical == true
        ? summary?.alerts.length ?? 0
        : billingNoticeCount;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Início',
                style: TextStyle(
                  color: Color(0xFF1D4ED8),
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                summary?.isTechnical == false
                    ? 'Avisos importantes da sua empresa'
                    : 'Resumo operacional da PapezzoSync',
                style: TextStyle(color: Colors.blueGrey.shade500),
              ),
            ],
          ),
        ),
        _TopIconButton(icon: Icons.search, onTap: () {}),
        const SizedBox(width: 8),
        _NotificationButton(alertCount: alertCount),
        const SizedBox(width: 8),
        const _VersionPill(),
        const SizedBox(width: 8),
        _TopIconButton(icon: Icons.refresh, onTap: onRefresh),
      ],
    );
  }
}

class _ShowcaseDashboard extends StatelessWidget {
  const _ShowcaseDashboard({
    required this.summary,
    required this.companyName,
    required this.apiBaseUrl,
    required this.onOpenPayment,
  });

  final DashboardSummary summary;
  final String companyName;
  final String apiBaseUrl;
  final VoidCallback onOpenPayment;

  @override
  Widget build(BuildContext context) {
    final certificates = summary.contents
        .where((item) => item.contentType == 'certificate')
        .toList();
    final overdue = summary.contents
        .where((item) => item.contentType == 'billing_overdue')
        .toList();
    final dueBillings = summary.contents
        .where((item) => item.contentType == 'billing_due')
        .toList();
    final notices = summary.contents
        .where((item) => item.contentType == 'notice')
        .toList();
    final offers = summary.contents
        .where(
          (item) =>
              item.contentType == 'product' ||
              item.contentType == 'affiliate_link',
        )
        .toList();
    final visibleCertificates = summary.hasFiscalCertificate
        ? <DashboardContent>[]
        : certificates;
    final topItems = [
      if (overdue.isNotEmpty) overdue.first,
      if (overdue.isEmpty && dueBillings.isNotEmpty) dueBillings.first,
      if (notices.isNotEmpty) notices.first,
      if (visibleCertificates.isNotEmpty) visibleCertificates.first,
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ShowcaseSection(
          title: companyName,
          items: topItems,
          apiBaseUrl: apiBaseUrl,
          onOpenPayment: onOpenPayment,
          emptyMessage: 'Nenhum aviso publicado no momento.',
        ),
        if (offers.isNotEmpty) ...[
          const SizedBox(height: 18),
          _LyncarStoreSection(items: offers, apiBaseUrl: apiBaseUrl),
        ],
      ],
    );
  }
}

class _LyncarStoreSection extends StatelessWidget {
  const _LyncarStoreSection({required this.items, required this.apiBaseUrl});

  final List<DashboardContent> items;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E2F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x110F172A),
            blurRadius: 28,
            offset: Offset(0, 14),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFF2563EB), Color(0xFF06B6D4)],
                    ),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: const Icon(Icons.storefront, color: Colors.white),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Loja Lyncar',
                        style: TextStyle(
                          color: Color(0xFF0F172A),
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Produtos e ofertas selecionadas para sua empresa.',
                        style: TextStyle(color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1180
                    ? 4
                    : constraints.maxWidth >= 860
                    ? 3
                    : constraints.maxWidth >= 560
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 365,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) => _StoreProductCard(
                    item: items[index],
                    apiBaseUrl: apiBaseUrl,
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StoreProductCard extends StatelessWidget {
  const _StoreProductCard({required this.item, required this.apiBaseUrl});

  final DashboardContent item;
  final String apiBaseUrl;

  @override
  Widget build(BuildContext context) {
    final imageUrl = _publicUrl(apiBaseUrl, item.imageUrl);
    final hasUrl = item.targetUrl != null && item.targetUrl!.trim().isNotEmpty;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE2E8F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x100F172A),
            blurRadius: 16,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StoreImage(
              imageUrl: imageUrl,
              icon: _storeIconForContent(item.contentType),
              height: 190,
            ),
            const SizedBox(height: 12),
            Expanded(child: _StoreInfo(item: item)),
            const SizedBox(height: 10),
            _StoreButton(item: item, hasUrl: hasUrl),
          ],
        ),
      ),
    );
  }
}

class _StoreImage extends StatelessWidget {
  const _StoreImage({
    required this.imageUrl,
    required this.icon,
    required this.height,
  });

  final String? imageUrl;
  final IconData icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: height,
        width: double.infinity,
        color: const Color(0xFFEAF2FF),
        child: imageUrl == null
            ? Icon(icon, size: 42, color: const Color(0xFF2563EB))
            : Image.network(
                imageUrl!,
                fit: BoxFit.cover,
                alignment: Alignment.center,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(icon, size: 42, color: const Color(0xFF2563EB)),
              ),
      ),
    );
  }
}

class _StoreInfo extends StatelessWidget {
  const _StoreInfo({required this.item});

  final DashboardContent item;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if ((item.badge ?? '').isNotEmpty) ...[
          _AlertBadge(label: item.badge!, color: const Color(0xFF2563EB)),
          const SizedBox(height: 10),
        ],
        Text(
          item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: const Color(0xFF0F172A),
            fontSize: 16,
            fontWeight: FontWeight.w900,
            height: 1.15,
          ),
        ),
        if ((item.description ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(
            item.description!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Color(0xFF64748B), height: 1.35),
          ),
        ],
        const SizedBox(height: 10),
        if ((item.priceLabel ?? '').trim().isNotEmpty)
          Text(
            item.priceLabel!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Color(0xFF2563EB),
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
      ],
    );
  }
}

class _StoreButton extends StatelessWidget {
  const _StoreButton({required this.item, required this.hasUrl});

  final DashboardContent item;
  final bool hasUrl;

  @override
  Widget build(BuildContext context) {
    final label = (item.buttonLabel ?? '').isNotEmpty
        ? item.buttonLabel!
        : item.contentType == 'affiliate_link'
        ? 'Abrir oferta'
        : 'Comprar agora';
    final onPressed = hasUrl
        ? () => redirectToUrl(item.targetUrl!, newTab: true)
        : null;
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w900),
        ),
        icon: const Icon(Icons.open_in_new, size: 17),
        label: Text(label),
      ),
    );
  }
}

IconData _storeIconForContent(String type) {
  return switch (type) {
    'affiliate_link' => Icons.link_outlined,
    'product' => Icons.shopping_bag_outlined,
    _ => Icons.storefront_outlined,
  };
}

class _ShowcaseSection extends StatelessWidget {
  const _ShowcaseSection({
    required this.title,
    required this.items,
    required this.apiBaseUrl,
    required this.onOpenPayment,
    this.emptyMessage = 'Nenhum aviso cadastrado no momento.',
  });

  final String title;
  final List<DashboardContent> items;
  final String apiBaseUrl;
  final VoidCallback onOpenPayment;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: items.isEmpty
          ? Text(emptyMessage, style: const TextStyle(color: Color(0xFF64748B)))
          : LayoutBuilder(
              builder: (context, constraints) {
                final columns = constraints.maxWidth >= 1000
                    ? 3
                    : constraints.maxWidth >= 650
                    ? 2
                    : 1;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: items.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    mainAxisExtent: 178,
                    crossAxisSpacing: 14,
                    mainAxisSpacing: 14,
                  ),
                  itemBuilder: (context, index) => _ShowcaseCard(
                    item: items[index],
                    apiBaseUrl: apiBaseUrl,
                    onOpenPayment: onOpenPayment,
                    highlighted: items[index].contentType == 'certificate',
                  ),
                );
              },
            ),
    );
  }
}

class _ShowcaseCard extends StatelessWidget {
  const _ShowcaseCard({
    required this.item,
    required this.apiBaseUrl,
    required this.onOpenPayment,
    this.highlighted = false,
  });

  final DashboardContent item;
  final String apiBaseUrl;
  final VoidCallback onOpenPayment;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final hasUrl = item.targetUrl != null && item.targetUrl!.trim().isNotEmpty;
    final overdue = item.contentType == 'billing_overdue';
    final dueBilling = item.contentType == 'billing_due';
    final isBilling = overdue || dueBilling;
    final color = overdue
        ? const Color(0xFFDC2626)
        : dueBilling
        ? const Color(0xFF2563EB)
        : highlighted
        ? const Color(0xFF38BDF8)
        : const Color(0xFF1E6BE3);
    final imageUrl = _publicUrl(apiBaseUrl, item.imageUrl);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: overdue
            ? const Color(0xFFFFF1F2)
            : dueBilling
            ? const Color(0xFFEFF6FF)
            : highlighted
            ? const Color(0xEE0F172A)
            : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: highlighted ? color : const Color(0xFFE2E8F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (imageUrl == null)
                  Icon(_iconForContent(item.contentType), color: color)
                else
                  ClipRRect(
                    borderRadius: BorderRadius.circular(7),
                    child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) => Icon(
                          _iconForContent(item.contentType),
                          color: color,
                        ),
                      ),
                    ),
                  ),
                const SizedBox(width: 9),
                if ((item.badge ?? '').isNotEmpty)
                  _AlertBadge(label: item.badge!, color: color),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: highlighted ? Colors.white : const Color(0xFF0F172A),
                fontSize: 17,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Text(
                item.description ?? '',
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: highlighted
                      ? const Color(0xFFDCEBFF)
                      : const Color(0xFF64748B),
                  height: 1.3,
                ),
              ),
            ),
            Row(
              children: [
                if ((item.priceLabel ?? '').isNotEmpty)
                  Expanded(
                    child: Text(
                      item.priceLabel!,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                OutlinedButton.icon(
                  onPressed: isBilling
                      ? onOpenPayment
                      : hasUrl
                      ? () => redirectToUrl(item.targetUrl!)
                      : null,
                  icon: const Icon(Icons.open_in_new, size: 16),
                  label: Text(_buttonLabel(item)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _iconForContent(String type) {
    return switch (type) {
      'billing_overdue' => Icons.warning_amber_outlined,
      'billing_due' => Icons.payments_outlined,
      'certificate' => Icons.workspace_premium_outlined,
      'product' => Icons.shopping_bag_outlined,
      'affiliate_link' => Icons.link_outlined,
      _ => Icons.campaign_outlined,
    };
  }

  String _buttonLabel(DashboardContent item) {
    if ((item.buttonLabel ?? '').isNotEmpty) {
      return item.buttonLabel!;
    }
    return switch (item.contentType) {
      'certificate' => 'Comprar A1',
      'affiliate_link' => 'Abrir oferta',
      'product' => 'Comprar',
      _ => 'Abrir',
    };
  }
}

class _ClientPixDialog extends StatelessWidget {
  const _ClientPixDialog({required this.billing});

  final CompanyBilling billing;

  @override
  Widget build(BuildContext context) {
    final qrBase64 = billing.pixQrCodeBase64;
    final qrBytes = qrBase64 == null || qrBase64.isEmpty
        ? null
        : base64Decode(qrBase64);

    return AlertDialog(
      title: const Text('Pagamento da mensalidade'),
      content: SizedBox(
        width: 430,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${billing.companyName} - ${billing.referenceMonth}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 6),
              Text(
                'Valor: R\$ ${billing.amount.toStringAsFixed(2).replaceAll('.', ',')}',
              ),
              Text(
                'Vencimento: ${billing.dueDate.day.toString().padLeft(2, '0')}/${billing.dueDate.month.toString().padLeft(2, '0')}/${billing.dueDate.year}',
              ),
              const SizedBox(height: 14),
              if (qrBytes != null)
                Center(
                  child: Image.memory(
                    qrBytes,
                    width: 220,
                    height: 220,
                    fit: BoxFit.contain,
                  ),
                ),
              if ((billing.pixQrCode ?? '').isNotEmpty) ...[
                const SizedBox(height: 14),
                const Text(
                  'Pix copia e cola',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                SelectableText(billing.pixQrCode!, maxLines: 6),
              ],
              if ((billing.pixTicketUrl ?? '').isNotEmpty) ...[
                const SizedBox(height: 10),
                SelectableText('Link: ${billing.pixTicketUrl!}'),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if ((billing.pixQrCode ?? '').isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: billing.pixQrCode!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código Pix copiado.')),
                );
              }
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copiar Pix'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Fechar'),
        ),
      ],
    );
  }
}

class _TopIconButton extends StatelessWidget {
  const _TopIconButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 38,
      height: 38,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          foregroundColor: const Color(0xFF64748B),
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        ),
        child: Icon(icon, size: 19),
      ),
    );
  }
}

class _NotificationButton extends StatelessWidget {
  const _NotificationButton({required this.alertCount});

  final int alertCount;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        _TopIconButton(icon: Icons.notifications_none, onTap: null),
        if (alertCount > 0)
          Positioned(
            right: -2,
            top: -4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: const Color(0xFFEF4444),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                child: Text(
                  '$alertCount',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _VersionPill extends StatelessWidget {
  const _VersionPill();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.new_releases_outlined,
              size: 16,
              color: Color(0xFF2563EB),
            ),
            const SizedBox(width: 7),
            Text(
              'v1.0.0',
              style: const TextStyle(
                color: Color(0xFF334155),
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _Metric('Clientes', summary.totalClients, Icons.groups_outlined),
      _Metric('Equipamentos', summary.totalEquipments, Icons.layers_outlined),
      _Metric('Online', summary.onlineEquipments, Icons.wifi_tethering),
      _Metric('Offline', summary.offlineEquipments, Icons.wifi_off_outlined),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 980
            ? 4
            : constraints.maxWidth >= 640
            ? 2
            : 1;

        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: metrics.length,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisExtent: 98,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
          ),
          itemBuilder: (context, index) => _MetricTile(metric: metrics[index]),
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({required this.metric});

  final _Metric metric;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE6ECF3)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 3,
            height: double.infinity,
            color: const Color(0xFF1E6BE3),
          ),
          const SizedBox(width: 14),
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFEFF6FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Icon(metric.icon, color: const Color(0xFF1E6BE3), size: 23),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  metric.label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${metric.value}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF0F172A),
                    fontSize: 21,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 960) {
          return Column(
            children: [
              _OperationsPanel(summary: summary),
              const SizedBox(height: 18),
              _OnlinePanel(summary: summary),
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: _OperationsPanel(summary: summary)),
            const SizedBox(width: 18),
            Expanded(flex: 3, child: _OnlinePanel(summary: summary)),
          ],
        );
      },
    );
  }
}

class _OperationsPanel extends StatelessWidget {
  const _OperationsPanel({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Visao operacional',
      actionLabel: 'Hoje',
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF1E6BE3),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Row(
              children: [
                _BlueStat(
                  label: 'Chamados abertos',
                  value: summary.openTickets,
                ),
                _BlueStat(
                  label: 'Em andamento',
                  value: summary.inProgressTickets,
                ),
                _BlueStat(label: 'Concluidos', value: summary.completedTickets),
              ],
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            height: 230,
            width: double.infinity,
            child: CustomPaint(
              painter: _DashboardLinePainter(_chartValues(summary)),
            ),
          ),
        ],
      ),
    );
  }

  List<int> _chartValues(DashboardSummary summary) {
    return [
      summary.totalClients,
      summary.totalEquipments,
      summary.onlineEquipments,
      summary.offlineEquipments,
      summary.openTickets,
      summary.inProgressTickets,
      summary.completedTickets,
      summary.canceledTickets,
    ];
  }
}

class _BlueStat extends StatelessWidget {
  const _BlueStat({required this.label, required this.value});

  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFDCEBFF), fontSize: 12),
            ),
            const SizedBox(height: 5),
            Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OnlinePanel extends StatelessWidget {
  const _OnlinePanel({required this.summary});

  final DashboardSummary summary;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: 'Máquinas',
      child: Column(
        children: [
          SizedBox(
            height: 172,
            child: CustomPaint(
              painter: _DonutPainter(
                online: summary.onlineEquipments,
                offline: summary.offlineEquipments,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${summary.onlineEquipments}',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontSize: 30,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const Text(
                      'Online',
                      style: TextStyle(color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _LegendLine(
            label: 'Online',
            value: summary.onlineEquipments,
            color: const Color(0xFF1E6BE3),
          ),
          const SizedBox(height: 9),
          _LegendLine(
            label: 'Offline',
            value: summary.offlineEquipments,
            color: const Color(0xFF22C5C7),
          ),
        ],
      ),
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.actionLabel});

  final String title;
  final Widget child;
  final String? actionLabel;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: const Color(0xFFE2E8F0)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      color: Color(0xFF334155),
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (actionLabel != null)
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        actionLabel!,
                        style: const TextStyle(
                          color: Color(0xFF64748B),
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }
}

class _LegendLine extends StatelessWidget {
  const _LegendLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ),
        Text(
          '$value',
          style: const TextStyle(
            color: Color(0xFF334155),
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

class _AlertsPanel extends StatelessWidget {
  const _AlertsPanel({required this.alerts});

  final List<DashboardAlert> alerts;

  @override
  Widget build(BuildContext context) {
    final groupedAlerts = _groupAlertsByClient(alerts);

    return _Panel(
      title: 'Avisos por cliente',
      child: alerts.isEmpty
          ? const Text('Nenhum aviso operacional no momento.')
          : Column(
              children: [
                for (var index = 0; index < groupedAlerts.length; index++) ...[
                  _ClientAlertGroup(group: groupedAlerts[index]),
                  if (index < groupedAlerts.length - 1)
                    const Divider(height: 24),
                ],
              ],
            ),
    );
  }

  List<_ClientAlertGroupData> _groupAlertsByClient(
    List<DashboardAlert> alerts,
  ) {
    final groups = <int, _ClientAlertGroupData>{};
    for (final alert in alerts) {
      final group = groups.putIfAbsent(
        alert.clientId,
        () => _ClientAlertGroupData(
          clientId: alert.clientId,
          clientName: alert.clientName,
          alerts: [],
        ),
      );
      group.alerts.add(alert);
    }
    return groups.values.toList();
  }
}

class _ClientAlertGroup extends StatelessWidget {
  const _ClientAlertGroup({required this.group});

  final _ClientAlertGroupData group;

  @override
  Widget build(BuildContext context) {
    final criticalCount = group.alerts
        .where((alert) => alert.severity == 'critical')
        .length;
    final warningCount = group.alerts.length - criticalCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(
                Icons.business_outlined,
                color: Color(0xFF1E6BE3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.clientName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${group.alerts.length} aviso(s) ativo(s)',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            if (criticalCount > 0)
              _AlertBadge(
                label: '$criticalCount crítico(s)',
                color: const Color(0xFFB91C1C),
              ),
            if (warningCount > 0) ...[
              const SizedBox(width: 8),
              _AlertBadge(
                label: '$warningCount aviso(s)',
                color: const Color(0xFFA16207),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        for (final alert in group.alerts) _AlertLine(alert: alert),
      ],
    );
  }
}

class _AlertLine extends StatelessWidget {
  const _AlertLine({required this.alert});

  final DashboardAlert alert;

  @override
  Widget build(BuildContext context) {
    final color = alert.severity == 'critical'
        ? const Color(0xFFB91C1C)
        : const Color(0xFFA16207);

    return Padding(
      padding: const EdgeInsets.only(left: 50, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.report_problem_outlined, color: color, size: 19),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: const TextStyle(color: Color(0xFF334155), height: 1.35),
                children: [
                  TextSpan(
                    text: '${alert.hostname}: ',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  TextSpan(text: alert.message),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertBadge extends StatelessWidget {
  const _AlertBadge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _DashboardLinePainter extends CustomPainter {
  const _DashboardLinePainter(this.values);

  final List<int> values;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..strokeWidth = 1;
    final linePaint = Paint()
      ..color = const Color(0xFF60A5FA)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;
    final fillPaint = Paint()
      ..color = const Color(0x1A60A5FA)
      ..style = PaintingStyle.fill;

    for (var i = 0; i < 5; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }

    final maxValue = values.reduce((a, b) => a > b ? a : b).clamp(1, 999999);
    final points = <Offset>[];
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height - (values[i] / maxValue * (size.height - 18)) - 9;
      points.add(Offset(x, y));
    }

    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fillPath = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();

    canvas.drawPath(fillPath, fillPaint);
    canvas.drawPath(path, linePaint);

    final dotPaint = Paint()..color = const Color(0xFF1E6BE3);
    for (final point in points) {
      canvas.drawCircle(point, 4, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _DashboardLinePainter oldDelegate) {
    return oldDelegate.values != values;
  }
}

class _DonutPainter extends CustomPainter {
  const _DonutPainter({required this.online, required this.offline});

  final int online;
  final int offline;

  @override
  void paint(Canvas canvas, Size size) {
    final total = (online + offline).clamp(1, 999999);
    final center = (Offset.zero & size).center;
    final radius = size.shortestSide / 2 - 12;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final basePaint = Paint()
      ..color = const Color(0xFFE2E8F0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    final onlinePaint = Paint()
      ..color = const Color(0xFF1E6BE3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;
    final offlinePaint = Paint()
      ..color = const Color(0xFF22C5C7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, basePaint);
    final onlineSweep = (online / total) * 6.283185307179586;
    canvas.drawArc(rect, -1.5708, onlineSweep, false, onlinePaint);
    if (offline > 0) {
      canvas.drawArc(
        rect,
        -1.5708 + onlineSweep + 0.12,
        (offline / total) * 6.283185307179586,
        false,
        offlinePaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DonutPainter oldDelegate) {
    return oldDelegate.online != online || oldDelegate.offline != offline;
  }
}

class _ClientAlertGroupData {
  _ClientAlertGroupData({
    required this.clientId,
    required this.clientName,
    required this.alerts,
  });

  final int clientId;
  final String clientName;
  final List<DashboardAlert> alerts;
}

class _Metric {
  const _Metric(this.label, this.value, this.icon);

  final String label;
  final int value;
  final IconData icon;
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
