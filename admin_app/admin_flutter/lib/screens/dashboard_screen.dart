import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_reorderable_grid_view/widgets/widgets.dart';

import '../models/company_billing.dart';
import '../models/dashboard_summary.dart';
import '../models/product.dart';
import '../models/receivable.dart';
import '../models/sale.dart';
import '../models/session.dart';
import '../services/api_client.dart';
import '../services/app_session_storage.dart';
import '../services/browser_redirect.dart';
import '../widgets/error_panel.dart';
import 'first_access_tour.dart';

const _defaultDashboardSections = <String>[
  'notices',
  'metrics',
  'activities',
  'shortcuts',
  'finance',
];

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({
    super.key,
    required this.session,
    this.onNavigateTo,
    this.searchItems,
  });

  final Session session;
  final ValueChanged<String>? onNavigateTo;
  final List<String> Function()? searchItems;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late final ApiClient _api = ApiClient(widget.session.apiBaseUrl);
  final _layoutStorage = AppSessionStorage();
  DashboardSummary? _summary;
  List<Sale> _todaySales = const [];
  List<Product> _products = const [];
  List<Receivable> _receivables = const [];
  bool _loading = true;
  String? _error;
  List<String> _dashboardSections = List<String>.from(
    _defaultDashboardSections,
  );

  String get _layoutStorageKey =>
      'lyncar.dashboard-layout.v1.${widget.session.companyCode}.${widget.session.userId ?? widget.session.role}';

  @override
  void initState() {
    super.initState();
    _loadDashboard();
    _loadDashboardLayout();
  }

  Future<void> _loadDashboardLayout() async {
    final saved = await _layoutStorage.read(_layoutStorageKey);
    if (!mounted || saved == null || saved.trim().isEmpty) return;
    final savedSections = saved
        .split(',')
        .where(
          (id) => _defaultDashboardSections.contains(
            id.startsWith('!') ? id.substring(1) : id,
          ),
        )
        .toSet();
    final ordered = <String>[
      ...saved.split(',').where(savedSections.contains),
      ..._defaultDashboardSections.where(
        (id) => !savedSections.any(
          (savedId) => savedId.replaceFirst('!', '') == id,
        ),
      ),
    ];
    setState(() => _dashboardSections = ordered);
  }

  Future<void> _saveDashboardLayout(List<String> sections) async {
    setState(() => _dashboardSections = sections);
    await _layoutStorage.write(_layoutStorageKey, sections.join(','));
  }

  Future<void> _openDashboardCustomizer() async {
    final result = await showDialog<List<String>>(
      context: context,
      builder: (context) =>
          _DashboardCustomizerDialog(initialSections: _dashboardSections),
    );
    if (result != null) await _saveDashboardLayout(result);
  }

  Future<void> _loadDashboard() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final summary = await _api.getDashboardSummary(widget.session.token);
      final token = widget.session.token;
      final today = DateTime.now();
      final hasSales =
          widget.session.can('sales:view') ||
          widget.session.can('sales:manual') ||
          widget.session.can('sales:create');
      final hasProducts =
          widget.session.can('products:view') ||
          widget.session.can('stock:view');
      final hasFinance =
          widget.session.can('finance:view') ||
          widget.session.can('finance:receivables:view');

      if (hasSales) {
        try {
          _todaySales = await _api.listSales(
            token,
            limit: 100,
            dateFrom: DateTime(today.year, today.month, today.day),
            dateTo: DateTime(today.year, today.month, today.day),
          );
        } catch (_) {
          _todaySales = const [];
        }
      }
      if (hasProducts) {
        try {
          _products = await _api.listProducts(token, active: true);
        } catch (_) {
          _products = const [];
        }
      }
      if (hasFinance) {
        try {
          _receivables = await _api.listReceivables(token, limit: 200);
        } catch (_) {
          _receivables = const [];
        }
      }
      if (mounted) setState(() => _summary = summary);
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
        builder: (context) => _ClientPixDialog(
          billing: billing,
          api: _api,
          token: widget.session.token,
        ),
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
    final showMonitoringDashboard =
        widget.session.hasModule('monitoring') ||
        widget.session.hasModule('equipments');

    return ColoredBox(
      color: const Color(0xFFF4F7FB),
      child: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadDashboard,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 40),
            children: [
              _Header(
                summary: summary,
                companyName: widget.session.companyName,
                onRefresh: _loadDashboard,
                onNavigateTo: widget.onNavigateTo,
                searchItems: widget.searchItems,
                onCustomize: _openDashboardCustomizer,
              ),
              const SizedBox(height: 12),
              if (_loading)
                const LinearProgressIndicator()
              else if (_error != null)
                ErrorPanel(message: _error!, onRetry: _loadDashboard)
              else if (summary != null) ...[
                if (summary.isTechnical && showMonitoringDashboard) ...[
                  _MetricGrid(summary: summary),
                  const SizedBox(height: 18),
                  _DashboardBody(summary: summary),
                  const SizedBox(height: 18),
                  _AlertsPanel(alerts: summary.alerts),
                ] else
                  _ShowcaseDashboard(
                    summary: summary,
                    session: widget.session,
                    apiBaseUrl: widget.session.apiBaseUrl,
                    onOpenPayment: _openBillingPayment,
                    todaySales: _todaySales,
                    products: _products,
                    receivables: _receivables,
                    onNavigate: widget.onNavigateTo,
                    sections: _dashboardSections,
                    onSectionsReordered: _saveDashboardLayout,
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatefulWidget {
  const _Header({
    required this.summary,
    required this.companyName,
    required this.onRefresh,
    required this.onNavigateTo,
    required this.searchItems,
    required this.onCustomize,
  });

  final DashboardSummary? summary;
  final String companyName;
  final VoidCallback onRefresh;
  final ValueChanged<String>? onNavigateTo;
  final List<String> Function()? searchItems;
  final VoidCallback onCustomize;

  @override
  State<_Header> createState() => _HeaderState();
}

class _HeaderState extends State<_Header> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final billingNoticeCount =
        widget.summary?.contents
            .where(
              (item) =>
                  item.contentType == 'billing_overdue' ||
                  item.contentType == 'billing_due',
            )
            .length ??
        0;
    final alertCount = widget.summary?.isTechnical == true
        ? widget.summary?.alerts.length ?? 0
        : billingNoticeCount;
    final query = _controller.text.trim().toLowerCase();
    final results = query.isEmpty
        ? const <String>[]
        : (widget.searchItems?.call() ?? const <String>[])
              .where((item) => item.toLowerCase().contains(query))
              .take(6)
              .toList();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4, right: 18),
            child: KeyedSubtree(
              key: TourTargets.of(context).company,
              child: Text(
                widget.companyName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Color(0xFF142B61),
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ),
        SizedBox(
          width: 260,
          key: TourTargets.of(context).search,
          child: Column(
            children: [
              SizedBox(
                height: 44,
                child: TextField(
                  controller: _controller,
                  onChanged: (_) => setState(() {}),
                  onSubmitted: (value) {
                    final match = results.isEmpty ? null : results.first;
                    if (match != null) {
                      widget.onNavigateTo?.call(match);
                      _controller.clear();
                      setState(() {});
                    }
                  },
                  decoration: InputDecoration(
                    hintText: 'Buscar no sistema...',
                    prefixIcon: const Icon(Icons.search, size: 21),
                    suffixIcon: query.isEmpty
                        ? null
                        : IconButton(
                            tooltip: 'Limpar busca',
                            onPressed: () {
                              _controller.clear();
                              setState(() {});
                            },
                            icon: const Icon(Icons.close, size: 18),
                          ),
                    filled: true,
                    fillColor: Colors.white,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD9E4F1)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFD9E4F1)),
                    ),
                  ),
                ),
              ),
              if (results.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(top: 4),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD9E4F1)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x180F172A),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      for (final result in results)
                        InkWell(
                          onTap: () {
                            widget.onNavigateTo?.call(result);
                            _controller.clear();
                            setState(() {});
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 9,
                            ),
                            child: Row(
                              children: [
                                const Icon(Icons.search, size: 17),
                                const SizedBox(width: 8),
                                Expanded(child: Text(result)),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        _TopIconButton(
          icon: Icons.dashboard_customize_outlined,
          onTap: widget.onCustomize,
        ),
        const SizedBox(width: 8),
        _NotificationButton(alertCount: alertCount),
        const SizedBox(width: 8),
        const _VersionPill(),
        const SizedBox(width: 8),
        _TopIconButton(icon: Icons.refresh, onTap: widget.onRefresh),
      ],
    );
  }
}

class _ShowcaseDashboard extends StatelessWidget {
  const _ShowcaseDashboard({
    required this.summary,
    required this.session,
    required this.apiBaseUrl,
    required this.onOpenPayment,
    required this.todaySales,
    required this.products,
    required this.receivables,
    required this.sections,
    required this.onSectionsReordered,
    this.onNavigate,
  });

  final DashboardSummary summary;
  final Session session;
  final String apiBaseUrl;
  final VoidCallback onOpenPayment;
  final List<Sale> todaySales;
  final List<Product> products;
  final List<Receivable> receivables;
  final List<String> sections;
  final ValueChanged<List<String>> onSectionsReordered;
  final ValueChanged<String>? onNavigate;

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
    final visibleCertificates = summary.hasFiscalCertificate
        ? <DashboardContent>[]
        : certificates;
    final billingItems = [...overdue, ...dueBillings];
    final dashboardNotices = [...billingItems, ...notices];
    final salesTotal = todaySales
        .where((sale) => sale.status != 'cancelada')
        .fold<double>(0, (total, sale) => total + sale.totalAmount);
    final lowStock = products.where(_isLowStock).length;
    final openReceivables = receivables
        .where((item) => item.balanceAmount > 0.009)
        .toList();
    final receivablesTotal = openReceivables.fold<double>(
      0,
      (total, item) => total + item.balanceAmount,
    );
    final activities = <_ActivityItem>[
      ...todaySales
          .take(5)
          .map(
            (sale) => _ActivityItem(
              icon: Icons.shopping_cart_outlined,
              color: const Color(0xFF059669),
              title: 'Venda concluída',
              subtitle:
                  '${sale.number ?? '#${sale.id}'} - ${_formatMoney(sale.totalAmount)}',
              date: sale.soldAt,
            ),
          ),
      ...products
          .where(_isLowStock)
          .take(3)
          .map(
            (product) => _ActivityItem(
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFFF59E0B),
              title: 'Estoque baixo',
              subtitle:
                  '${product.name} (Estoque: ${_compactNumber(product.stockQuantity)})',
            ),
          ),
    ];
    final quick = <_QuickAction>[
      if (session.can('sales:create'))
        const _QuickAction(
          'Nova venda',
          'Registrar venda',
          'Vendas',
          Icons.shopping_cart_outlined,
          Color(0xFF059669),
        ),
      if (session.can('products:create'))
        const _QuickAction(
          'Cadastrar produto',
          'Incluir no estoque',
          'Estoque',
          Icons.inventory_2_outlined,
          Color(0xFF2563EB),
        ),
      if (session.canUseFiscal && session.can('fiscal:emit'))
        const _QuickAction(
          'Emitir NF-e',
          'Gerar nota fiscal',
          'Notas fiscais',
          Icons.description_outlined,
          Color(0xFF7C3AED),
        ),
      if (session.can('clients:view'))
        const _QuickAction(
          'Clientes',
          'Gerenciar clientes',
          'Clientes',
          Icons.people_alt_outlined,
          Color(0xFFD97706),
        ),
    ];
    final hasFinance =
        session.can('finance:view') || session.can('finance:receivables:view');

    final sectionsById = <String, Widget>{
      'notices': _DashboardNoticePanel(
        items: dashboardNotices,
        onOpenPayment: onOpenPayment,
      ),
      'metrics': KeyedSubtree(
        key: TourTargets.of(context).metrics,
        child: _DashboardMetricsPanel(
          salesTotal: salesTotal,
          receivablesTotal: receivablesTotal,
          lowStock: lowStock,
        ),
      ),
      'activities': KeyedSubtree(
        key: TourTargets.of(context).activities,
        child: _Panel(
          title: 'Atividades recentes',
          child: activities.isEmpty
              ? const Text(
                  'Nenhuma atividade recente encontrada.',
                  style: TextStyle(color: Color(0xFF64748B)),
                )
              : activities.length >= 3
              ? SizedBox(
                  height: 148,
                  child: ListView.separated(
                    primary: false,
                    itemCount: activities.length,
                    separatorBuilder: (_, _) =>
                        const Divider(height: 1, color: Color(0xFFE2E8F0)),
                    itemBuilder: (context, index) =>
                        _ActivityRow(item: activities[index]),
                  ),
                )
              : Column(
                  children: [
                    for (final item in activities) _ActivityRow(item: item),
                  ],
                ),
        ),
      ),
      'shortcuts': KeyedSubtree(
        key: TourTargets.of(context).shortcuts,
        child: _Panel(
          title: 'Atalhos rápidos',
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final item in quick)
                SizedBox(
                  width: 120,
                  child: _QuickActionTile(
                    item: item,
                    onTap: () => onNavigate?.call(item.destination),
                  ),
                ),
            ],
          ),
        ),
      ),
      'finance': KeyedSubtree(
        key: TourTargets.of(context).finance,
        child: hasFinance
            ? _FinancialSummaryPanel(receivables: receivables)
            : const SizedBox.shrink(),
      ),
    };

    final visibleSections = sections
        .where((id) => !id.startsWith('!'))
        .toList();
    final List<Widget> gridChildren = [
      for (final sectionId in visibleSections)
        if (sectionsById[sectionId] case final section?)
          Padding(
            key: ValueKey('dashboard-section-$sectionId'),
            padding: const EdgeInsets.only(bottom: 16),
            child: Stack(
              children: [
                section,
                const Positioned(
                  top: 10,
                  right: 12,
                  child: IgnorePointer(
                    child: Icon(
                      Icons.drag_indicator,
                      size: 20,
                      color: Color(0xFF94A3B8),
                    ),
                  ),
                ),
              ],
            ),
          ),
    ];
    return Column(
      children: [
        ReorderableBuilder<String>(
          longPressDelay: Duration.zero,
          enableScrollingWhileDragging: false,
          feedbackScaleFactor: 1.02,
          dragChildBoxDecoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x330F172A),
                blurRadius: 24,
                offset: Offset(0, 12),
              ),
            ],
          ),
          onReorder: (reorderedListFunction) {
            final reordered = reorderedListFunction(visibleSections);
            reordered.addAll(sections.where((id) => id.startsWith('!')));
            onSectionsReordered(reordered);
          },
          builder: (children) {
            return LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 940;
                if (compact) {
                  return Column(children: children);
                }

                // Use two independent columns instead of a regular grid. A
                // grid makes the shorter card inherit the height of its row
                // neighbour, leaving large empty areas below it.
                final left = <Widget>[];
                final right = <Widget>[];
                for (var index = 0; index < children.length; index++) {
                  (index.isEven ? left : right).add(children[index]);
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Column(children: left)),
                    const SizedBox(width: 16),
                    Expanded(child: Column(children: right)),
                  ],
                );
              },
            );
          },
          children: gridChildren,
        ),
        if (visibleCertificates.isNotEmpty) ...[
          const SizedBox(height: 18),
          _DashboardSectionHeader(
            icon: Icons.workspace_premium_outlined,
            title: 'Recursos para sua empresa',
            subtitle: 'Serviços disponíveis no seu painel Lyncar.',
            count: visibleCertificates.length,
          ),
          const SizedBox(height: 10),
          _ShowcaseSection(
            title: 'Certificados disponíveis',
            items: visibleCertificates,
            apiBaseUrl: apiBaseUrl,
            onOpenPayment: onOpenPayment,
          ),
        ],
      ],
    );
  }
}

// ignore: unused_element, unused_element_parameter
class _DashboardLowerGrid extends StatelessWidget {
  const _DashboardLowerGrid({
    required this.session,
    required this.todaySales,
    required this.products,
    required this.receivables,
    // ignore: unused_element_parameter
    this.onNavigate,
  });

  final Session session;
  final List<Sale> todaySales;
  final List<Product> products;
  final List<Receivable> receivables;
  final ValueChanged<String>? onNavigate;

  @override
  Widget build(BuildContext context) {
    final activities = <_ActivityItem>[
      ...todaySales
          .take(5)
          .map(
            (sale) => _ActivityItem(
              icon: Icons.shopping_cart_outlined,
              color: const Color(0xFF059669),
              title: 'Venda concluída',
              subtitle:
                  '${sale.number ?? '#${sale.id}'} - ${_formatMoney(sale.totalAmount)}',
              date: sale.soldAt,
            ),
          ),
      ...products
          .where(_isLowStock)
          .take(3)
          .map(
            (product) => _ActivityItem(
              icon: Icons.inventory_2_outlined,
              color: const Color(0xFFF59E0B),
              title: 'Estoque baixo',
              subtitle:
                  '${product.name} (Estoque: ${_compactNumber(product.stockQuantity)})',
            ),
          ),
    ];
    final quick = <_QuickAction>[
      if (session.can('sales:create'))
        const _QuickAction(
          'Nova venda',
          'Registrar venda',
          'Vendas',
          Icons.shopping_cart_outlined,
          Color(0xFF059669),
        ),
      if (session.can('products:create'))
        const _QuickAction(
          'Cadastrar produto',
          'Incluir no estoque',
          'Estoque',
          Icons.inventory_2_outlined,
          Color(0xFF2563EB),
        ),
      if (session.canUseFiscal && session.can('fiscal:emit'))
        const _QuickAction(
          'Emitir NF-e',
          'Gerar nota fiscal',
          'Notas fiscais',
          Icons.description_outlined,
          Color(0xFF7C3AED),
        ),
      if (session.can('clients:view'))
        const _QuickAction(
          'Clientes',
          'Gerenciar clientes',
          'Clientes',
          Icons.people_alt_outlined,
          Color(0xFFD97706),
        ),
    ];
    final hasFinance =
        session.can('finance:view') || session.can('finance:receivables:view');
    final left = KeyedSubtree(
      key: TourTargets.of(context).activities,
      child: _Panel(
        title: 'Atividades recentes',
        child: activities.isEmpty
            ? const Text(
                'Nenhuma atividade recente encontrada.',
                style: TextStyle(color: Color(0xFF64748B)),
              )
            : Column(
                children: [
                  for (final item in activities) _ActivityRow(item: item),
                ],
              ),
      ),
    );
    final right = Column(
      children: [
        if (quick.isNotEmpty)
          KeyedSubtree(
            key: TourTargets.of(context).shortcuts,
            child: _Panel(
              title: 'Atalhos rápidos',
              child: Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final item in quick)
                    SizedBox(
                      width: 120,
                      child: _QuickActionTile(
                        item: item,
                        onTap: () => onNavigate?.call(item.destination),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (quick.isNotEmpty && hasFinance) const SizedBox(height: 16),
        if (hasFinance)
          KeyedSubtree(
            key: TourTargets.of(context).finance,
            child: _FinancialSummaryPanel(receivables: receivables),
          ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 940) {
          return Column(children: [left, const SizedBox(height: 16), right]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 3, child: left),
            const SizedBox(width: 16),
            Expanded(flex: 2, child: right),
          ],
        );
      },
    );
  }
}

class _DashboardCustomizerDialog extends StatefulWidget {
  const _DashboardCustomizerDialog({required this.initialSections});

  final List<String> initialSections;

  @override
  State<_DashboardCustomizerDialog> createState() =>
      _DashboardCustomizerDialogState();
}

class _DashboardCustomizerDialogState
    extends State<_DashboardCustomizerDialog> {
  late List<String> _sections = List<String>.from(widget.initialSections);

  String _idAt(int index) {
    final value = _sections[index];
    return value.startsWith('!') ? value.substring(1) : value;
  }

  bool _isVisible(int index) => !_sections[index].startsWith('!');

  String _label(String id) => switch (id) {
    'notices' => 'Central de avisos',
    'metrics' => 'Indicadores do dia',
    'activities' => 'Atividades recentes',
    'shortcuts' => 'Atalhos rápidos',
    'finance' => 'Resumo financeiro',
    _ => id,
  };

  IconData _icon(String id) => switch (id) {
    'notices' => Icons.notifications_active_outlined,
    'metrics' => Icons.insights_outlined,
    'activities' => Icons.history_outlined,
    'shortcuts' => Icons.flash_on_outlined,
    'finance' => Icons.account_balance_wallet_outlined,
    _ => Icons.widgets_outlined,
  };

  void _restoreDefaults() {
    setState(() => _sections = List<String>.from(_defaultDashboardSections));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Personalizar painel'),
      content: SizedBox(
        width: 470,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Arraste para reorganizar. Desative um bloco para removê-lo da tela inicial.',
              style: TextStyle(color: Color(0xFF64748B)),
            ),
            const SizedBox(height: 14),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 330),
              child: ReorderableListView.builder(
                shrinkWrap: true,
                itemCount: _sections.length,
                buildDefaultDragHandles: false,
                onReorderItem: (oldIndex, newIndex) {
                  setState(() {
                    final item = _sections.removeAt(oldIndex);
                    _sections.insert(newIndex, item);
                  });
                },
                itemBuilder: (context, index) {
                  final id = _idAt(index);
                  return ListTile(
                    key: ValueKey(_sections[index]),
                    leading: Icon(_icon(id), color: const Color(0xFF2563EB)),
                    title: Text(
                      _label(id),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Switch(
                          value: _isVisible(index),
                          onChanged: (value) => setState(() {
                            _sections[index] = value ? id : '!$id';
                          }),
                        ),
                        ReorderableDragStartListener(
                          index: index,
                          child: const Padding(
                            padding: EdgeInsets.all(8),
                            child: Icon(Icons.drag_handle),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _restoreDefaults,
          child: const Text('Restaurar padrão'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_sections),
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}

class _ActivityItem {
  const _ActivityItem({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.date,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final DateTime? date;
}

class _ActivityRow extends StatelessWidget {
  const _ActivityRow({required this.item});
  final _ActivityItem item;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Row(
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: .1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(item.icon, color: item.color, size: 20),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.title,
                style: const TextStyle(
                  color: Color(0xFF13233B),
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                item.subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
              ),
            ],
          ),
        ),
        if (item.date != null)
          Text(
            _relativeTime(item.date!),
            style: const TextStyle(color: Color(0xFF71839B), fontSize: 12),
          ),
      ],
    ),
  );
}

class _QuickAction {
  const _QuickAction(
    this.title,
    this.subtitle,
    this.destination,
    this.icon,
    this.color,
  );
  final String title;
  final String subtitle;
  final String destination;
  final IconData icon;
  final Color color;
}

class _QuickActionTile extends StatelessWidget {
  const _QuickActionTile({required this.item, required this.onTap});
  final _QuickAction item;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.transparent,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        decoration: BoxDecoration(
          color: item.color.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: item.color.withValues(alpha: .18)),
        ),
        child: Column(
          children: [
            Icon(item.icon, color: item.color, size: 25),
            const SizedBox(height: 7),
            Text(
              item.title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF13233B),
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            Text(
              item.subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );
}

class _FinancialSummaryPanel extends StatelessWidget {
  const _FinancialSummaryPanel({required this.receivables});
  final List<Receivable> receivables;
  @override
  Widget build(BuildContext context) {
    final open = receivables
        .where((item) => item.balanceAmount > .009)
        .toList();
    final overdue = open
        .where(
          (item) =>
              item.dueDate != null && item.dueDate!.isBefore(DateTime.now()),
        )
        .toList();
    final received = receivables.fold<double>(
      0,
      (total, item) => total + item.paidAmount,
    );
    return _Panel(
      title: 'Resumo financeiro',
      child: Row(
        children: [
          Expanded(
            child: _FinancialValue(
              label: 'A vencer',
              value: _formatMoney(
                open.fold(0, (total, item) => total + item.balanceAmount),
              ),
              count: open.length,
              color: const Color(0xFFD97706),
            ),
          ),
          Expanded(
            child: _FinancialValue(
              label: 'Vencido',
              value: _formatMoney(
                overdue.fold(0, (total, item) => total + item.balanceAmount),
              ),
              count: overdue.length,
              color: const Color(0xFFDC2626),
            ),
          ),
          Expanded(
            child: _FinancialValue(
              label: 'Recebido',
              value: _formatMoney(received),
              color: const Color(0xFF059669),
            ),
          ),
        ],
      ),
    );
  }
}

class _FinancialValue extends StatelessWidget {
  const _FinancialValue({
    required this.label,
    required this.value,
    required this.color,
    this.count,
  });
  final String label;
  final String value;
  final Color color;
  final int? count;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 8),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF64748B))),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: Color(0xFF13233B),
            fontSize: 15,
            fontWeight: FontWeight.w900,
          ),
        ),
        if (count != null)
          Text('$count conta(s)', style: TextStyle(color: color, fontSize: 11)),
      ],
    ),
  );
}

class _DashboardNoticePanel extends StatelessWidget {
  const _DashboardNoticePanel({
    required this.items,
    required this.onOpenPayment,
  });

  final List<DashboardContent> items;
  final VoidCallback onOpenPayment;

  @override
  Widget build(BuildContext context) {
    final visibleItems = items.take(12).toList();
    final panel = _Panel(
      title: 'Central de avisos',
      child: items.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text(
                'Nenhum aviso publicado no momento.',
                style: TextStyle(color: Color(0xFF64748B)),
              ),
            )
          : visibleItems.length >= 3
          ? SizedBox(
              height: 148,
              child: ListView.separated(
                primary: false,
                itemCount: visibleItems.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => _NoticePreviewCard(
                  item: visibleItems[index],
                  onOpenPayment: onOpenPayment,
                ),
              ),
            )
          : Column(
              children: [
                for (var index = 0; index < visibleItems.length; index++)
                  Padding(
                    padding: EdgeInsets.only(top: index == 0 ? 0 : 10),
                    child: _NoticePreviewCard(
                      item: visibleItems[index],
                      onOpenPayment: onOpenPayment,
                    ),
                  ),
              ],
            ),
    );
    return KeyedSubtree(key: TourTargets.of(context).notices, child: panel);
  }
}

class _NoticePreviewCard extends StatefulWidget {
  const _NoticePreviewCard({required this.item, required this.onOpenPayment});

  final DashboardContent item;
  final VoidCallback onOpenPayment;

  @override
  State<_NoticePreviewCard> createState() => _NoticePreviewCardState();
}

class _NoticePreviewCardState extends State<_NoticePreviewCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final overdue = item.contentType == 'billing_overdue';
    final billing = overdue || item.contentType == 'billing_due';
    final color = overdue
        ? const Color(0xFFE11D48)
        : billing
        ? const Color(0xFFF59E0B)
        : const Color(0xFF2563EB);
    final background = overdue
        ? const Color(0xFFFFF1F2)
        : billing
        ? const Color(0xFFFFFBEB)
        : const Color(0xFFEFF6FF);
    final hasAction =
        billing ||
        (item.targetUrl != null && item.targetUrl!.trim().isNotEmpty);
    final onTap = billing
        ? widget.onOpenPayment
        : hasAction
        ? () => redirectToUrl(item.targetUrl!)
        : null;

    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final pulse = overdue ? _pulse.value : 0.0;
        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: overdue
                      ? color.withValues(alpha: .28 + pulse * .42)
                      : color.withValues(alpha: .22),
                  width: overdue ? 1.5 : 1,
                ),
                boxShadow: overdue
                    ? [
                        BoxShadow(
                          color: color.withValues(alpha: .05 + pulse * .10),
                          blurRadius: 10 + pulse * 6,
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Icon(
                    _iconForDashboardContent(item.contentType),
                    color: color,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF172554),
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if ((item.description ?? '').trim().isNotEmpty)
                          Text(
                            item.description!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF526581),
                              fontSize: 12,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (hasAction) Icon(Icons.chevron_right, color: color),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  IconData _iconForDashboardContent(String type) {
    return switch (type) {
      'billing_overdue' => Icons.warning_amber_outlined,
      'billing_due' => Icons.payments_outlined,
      _ => Icons.campaign_outlined,
    };
  }
}

class _DashboardMetricsPanel extends StatelessWidget {
  const _DashboardMetricsPanel({
    required this.salesTotal,
    required this.receivablesTotal,
    required this.lowStock,
  });

  final double salesTotal;
  final double receivablesTotal;
  final int lowStock;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (
        'Vendas hoje',
        _formatMoney(salesTotal),
        salesTotal == 0
            ? 'Nenhuma venda registrada hoje'
            : 'Total vendido no dia',
        Icons.shopping_cart_outlined,
        const Color(0xFF059669),
      ),
      (
        'Contas a receber',
        _formatMoney(receivablesTotal),
        'Valores em aberto',
        Icons.account_balance_wallet_outlined,
        const Color(0xFFD97706),
      ),
      (
        'Estoque baixo',
        '$lowStock produtos',
        lowStock == 0 ? 'Estoque em dia' : 'Requer atenção',
        Icons.inventory_2_outlined,
        const Color(0xFFDC2626),
      ),
    ];

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFD9E3F0)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A102A43),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Use the actual app window for this breakpoint. The reorderable grid
          // can expose a narrower intermediate constraint while laying out an
          // item, even when the visible card is wide enough for one row.
          final compact = MediaQuery.sizeOf(context).width < 900;
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var index = 0; index < metrics.length; index++) ...[
                  if (index > 0)
                    const Divider(height: 1, color: Color(0xFFE2E8F0)),
                  _CompactMetric(item: metrics[index]),
                ],
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: _CompactMetric(item: metrics[0])),
              const SizedBox(
                height: 54,
                child: VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
              ),
              Expanded(child: _CompactMetric(item: metrics[1])),
              const SizedBox(
                height: 54,
                child: VerticalDivider(width: 1, color: Color(0xFFE2E8F0)),
              ),
              Expanded(child: _CompactMetric(item: metrics[2])),
            ],
          );
        },
      ),
    );
  }
}

class _CompactMetric extends StatelessWidget {
  const _CompactMetric({required this.item});

  final (String, String, String, IconData, Color) item;

  @override
  Widget build(BuildContext context) {
    final (label, value, caption, icon, color) = item;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: color.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Padding(
              padding: const EdgeInsets.all(9),
              child: Icon(icon, color: color, size: 21),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF64748B),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF14213D),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  caption,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: color,
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
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

// ignore: unused_element
class _CompanyOverviewCard extends StatelessWidget {
  const _CompanyOverviewCard({
    required this.companyName,
    required this.totalAttentionItems,
  });

  final String companyName;
  final int totalAttentionItems;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      key: TourTargets.of(context).company,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD9E4F1)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0D102A43),
            blurRadius: 18,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F1FF),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.business_outlined,
                  color: Color(0xFF1267D6),
                  size: 30,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Sua empresa',
                      style: TextStyle(
                        color: Color(0xFF637793),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      companyName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF10245B),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      totalAttentionItems == 0
                          ? 'Sua operação está em dia.'
                          : '$totalAttentionItems item(ns) aguardando sua atenção',
                      style: const TextStyle(color: Color(0xFF637793)),
                    ),
                  ],
                ),
              ),
            ],
          );
          return identity;
        },
      ),
    );
  }
}

class _DashboardSectionHeader extends StatelessWidget {
  const _DashboardSectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.count,
  });
  final IconData icon;
  final String title;
  final String subtitle;
  final int count;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, color: const Color(0xFF0F7882), size: 24),
      const SizedBox(width: 10),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 2),
            Text(subtitle, style: const TextStyle(color: Color(0xFF64748B))),
          ],
        ),
      ),
      if (count > 0) _CountBadge(count: count),
    ],
  );
}

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: const Color(0xFFE0F2F1),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      '$count',
      style: const TextStyle(
        color: Color(0xFF0F7882),
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

// Kept for the dedicated Loja route, which still reuses these cards.
// ignore: unused_element
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

bool _isLowStock(Product product) {
  return product.active &&
      product.minimumStock > 0 &&
      product.stockQuantity <= product.minimumStock;
}

String _formatMoney(double value) {
  final fixed = value.toStringAsFixed(2).replaceAll('.', ',');
  return 'R\$ ${fixed.replaceAllMapped(RegExp(r'(?<=\d)(?=(\d{3})+(?!\d))'), (_) => '.')}';
}

String _compactNumber(double value) {
  return value == value.roundToDouble()
      ? value.toInt().toString()
      : value.toStringAsFixed(2);
}

String _relativeTime(DateTime date) {
  final difference = DateTime.now().difference(date);
  if (difference.inMinutes < 1) {
    return 'Agora';
  }
  if (difference.inHours < 1) {
    return 'Há ${difference.inMinutes} min';
  }
  if (difference.inDays == 0) {
    return 'Hoje às ${_twoDigits(date.hour)}:${_twoDigits(date.minute)}';
  }
  if (difference.inDays == 1) {
    return 'Ontem';
  }
  return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}';
}

String _twoDigits(int value) => value.toString().padLeft(2, '0');

class _ShowcaseSection extends StatelessWidget {
  const _ShowcaseSection({
    required this.title,
    required this.items,
    required this.apiBaseUrl,
    required this.onOpenPayment,
  });

  final String title;
  final List<DashboardContent> items;
  final String apiBaseUrl;
  final VoidCallback onOpenPayment;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      title: title,
      child: items.isEmpty
          ? const Text(
              'Nenhum aviso cadastrado no momento.',
              style: TextStyle(color: Color(0xFF64748B)),
            )
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

class _ShowcaseCard extends StatefulWidget {
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
  State<_ShowcaseCard> createState() => _ShowcaseCardState();
}

class _ShowcaseCardState extends State<_ShowcaseCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _overduePulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _overduePulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final hasUrl = item.targetUrl != null && item.targetUrl!.trim().isNotEmpty;
    final overdue = item.contentType == 'billing_overdue';
    final dueBilling = item.contentType == 'billing_due';
    final isBilling = overdue || dueBilling;
    final color = overdue
        ? const Color(0xFFDC2626)
        : dueBilling
        ? const Color(0xFF2563EB)
        : widget.highlighted
        ? const Color(0xFF38BDF8)
        : const Color(0xFF1E6BE3);
    final imageUrl = _publicUrl(widget.apiBaseUrl, item.imageUrl);

    return AnimatedBuilder(
      animation: _overduePulse,
      builder: (context, child) {
        final pulse = overdue ? _overduePulse.value : 0.0;
        return DecoratedBox(
          decoration: BoxDecoration(
            color: overdue
                ? const Color(0xFFFFF1F2)
                : dueBilling
                ? const Color(0xFFEFF6FF)
                : widget.highlighted
                ? const Color(0xEE0F172A)
                : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: overdue
                  ? color.withValues(alpha: .35 + pulse * .45)
                  : widget.highlighted
                  ? color
                  : const Color(0xFFE2E8F0),
              width: overdue ? 1.5 : 1,
            ),
            boxShadow: overdue
                ? [
                    BoxShadow(
                      color: color.withValues(alpha: .06 + pulse * .12),
                      blurRadius: 12 + pulse * 8,
                      spreadRadius: pulse * 1.5,
                    ),
                  ]
                : null,
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
                    color: widget.highlighted
                        ? Colors.white
                        : const Color(0xFF0F172A),
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
                      color: widget.highlighted
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
                          ? widget.onOpenPayment
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
      },
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

class _ClientPixDialog extends StatefulWidget {
  const _ClientPixDialog({
    required this.billing,
    required this.api,
    required this.token,
  });

  final CompanyBilling billing;
  final ApiClient api;
  final String token;

  @override
  State<_ClientPixDialog> createState() => _ClientPixDialogState();
}

class _ClientPixDialogState extends State<_ClientPixDialog> {
  late CompanyBilling _billing = widget.billing;
  Timer? _timer;
  bool _confirmed = false;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _sync());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _sync() async {
    if (_syncing || _confirmed) return;
    _syncing = true;
    try {
      final updated = await widget.api.syncDashboardBillingPayment(
        widget.token,
        _billing.id,
      );
      if (!mounted) return;
      setState(() => _billing = updated);
      if (updated.status == 'paid' || updated.mercadoPagoStatus == 'approved') {
        _timer?.cancel();
        setState(() => _confirmed = true);
        Future<void>.delayed(const Duration(milliseconds: 1600), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } on ApiException {
      // Keep the dialog open while the provider is processing the Pix.
    } finally {
      _syncing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmed) {
      return AlertDialog(
        content: SizedBox(
          width: 430,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 26),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 68),
                SizedBox(height: 14),
                Text(
                  'Pagamento efetuado com sucesso!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                ),
                SizedBox(height: 8),
                Text('Seu acesso continuará disponível normalmente.'),
              ],
            ),
          ),
        ),
      );
    }

    final qrBase64 = _billing.pixQrCodeBase64;
    final qrBytes = qrBase64 == null || qrBase64.isEmpty
        ? null
        : base64Decode(qrBase64);
    final approved = _billing.mercadoPagoStatus == 'approved';

    return AlertDialog(
      title: const Text('Pagar mensalidade'),
      content: SizedBox(
        width: 660,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_billing.companyName} • ${_billing.referenceMonth}',
                style: const TextStyle(
                  color: Color(0xFF475569),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              DecoratedBox(
                decoration: BoxDecoration(
                  color: approved
                      ? const Color(0xFFDCFCE7)
                      : const Color(0xFFFFF7ED),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Icon(
                        approved ? Icons.check_circle_outline : Icons.sync,
                        color: approved
                            ? const Color(0xFF15803D)
                            : const Color(0xFFC2410C),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        approved
                            ? 'Pagamento aprovado'
                            : 'Aguardando pagamento',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (qrBytes != null)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: Image.memory(
                        qrBytes,
                        width: 240,
                        height: 240,
                        fit: BoxFit.contain,
                      ),
                    ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Valor da mensalidade',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                        Text(
                          'R\$ ${(_billing.totalDue ?? _billing.amount).toStringAsFixed(2).replaceAll('.', ',')}',
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (_billing.isOverdue &&
                            (_billing.interestAmount > 0 ||
                                _billing.lateFeeAmount > 0 ||
                                _billing.monetaryCorrectionAmount > 0)) ...[
                          const SizedBox(height: 8),
                          Text(
                            'Valor atualizado após o vencimento',
                            style: TextStyle(
                              color: Color(0xFFDC2626),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        const Text(
                          'Aponte a câmera do banco para o QR Code. A confirmação acontece automaticamente.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if ((_billing.pixQrCode ?? '').isNotEmpty) ...[
                const SizedBox(height: 20),
                const Text(
                  'Pix copia e cola',
                  style: TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: SelectableText(_billing.pixQrCode!, maxLines: 4),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if ((_billing.pixQrCode ?? '').isNotEmpty)
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: _billing.pixQrCode!));
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Código Pix copiado.')),
                );
              }
            },
            icon: const Icon(Icons.copy_outlined),
            label: const Text('Copiar código Pix'),
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
