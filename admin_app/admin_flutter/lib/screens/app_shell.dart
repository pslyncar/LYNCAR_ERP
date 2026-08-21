import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:gap/gap.dart';

import '../models/session.dart';
import '../navigation/app_navigation.dart';
import 'cash_closings_screen.dart';
import 'clients_screen.dart';
import 'companies_screen.dart';
import 'dashboard_contents_screen.dart';
import 'dashboard_screen.dart';
import 'equipments_screen.dart';
import 'finance_screen.dart';
import 'fiscal_documents_screen.dart';
import 'emitir_nota_fiscal_screen.dart';
import 'master_access_screen.dart';
import 'master_billing_screen.dart';
import 'master_contracts_screen.dart';
import 'master_integrations_screen.dart';
import 'master_payment_settings_screen.dart';
import 'master_pdv_terminals_screen.dart';
import 'master_plans_screen.dart';
import 'master_staff_screen.dart';
import 'master_website_contacts_screen.dart';
import 'marketplaces_screen.dart';
import 'pdv_operators_screen.dart';
import 'pdv_screen.dart';
import 'pdv_terminals_screen.dart';
import 'products_screen.dart';
import 'production_orders_screen.dart';
import 'promotions_screen.dart';
import 'reports_screen.dart';
import 'sales_screen.dart';
import 'settings_screen.dart';
import 'service_orders_screen.dart';
import 'service_contracts_screen.dart';
import 'stock_entries_screen.dart';
import 'stock_withdrawals_screen.dart';
import 'support_screen.dart';
import 'suppliers_screen.dart';
import 'users_screen.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    required this.session,
    required this.onLogout,
    required this.onPdvCashOpenChanged,
  });

  final Session session;
  final VoidCallback onLogout;
  final ValueChanged<bool> onPdvCashOpenChanged;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;
  bool _pdvFullscreen = false;
  bool _navigationPanelOpen = false;
  bool _issuingFiscalDocument = false;
  AppNavigationSection? _browsedSection;
  final _navigationSearchController = TextEditingController();
  final _navigationSearchFocusNode = FocusNode();

  @override
  void dispose() {
    _navigationSearchController.dispose();
    _navigationSearchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isMasterPanel = widget.session.isMasterCompany;
    final destinations = [
      if (isMasterPanel && widget.session.canMaster('master:companies'))
        _Destination(
          category: AppNavigationSection.masterCustomers,
          label: 'Empresas',
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment,
          screen: CompaniesScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:companies'))
        _Destination(
          category: AppNavigationSection.masterCustomers,
          label: 'Contatos do site',
          icon: Icons.contact_phone_outlined,
          selectedIcon: Icons.contact_phone,
          screen: MasterWebsiteContactsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:companies'))
        _Destination(
          category: AppNavigationSection.masterAccess,
          label: 'Acessos',
          icon: Icons.people_alt_outlined,
          selectedIcon: Icons.people_alt,
          screen: MasterAccessScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:staff'))
        _Destination(
          category: AppNavigationSection.masterAccess,
          label: 'Equipe',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          screen: MasterStaffScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:pdv_terminals'))
        _Destination(
          category: AppNavigationSection.masterPdv,
          label: 'Terminais PDV',
          icon: Icons.devices_other_outlined,
          selectedIcon: Icons.devices_other,
          screen: MasterPdvTerminalsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          category: AppNavigationSection.masterCommercial,
          label: 'Planos e Segmentos',
          icon: Icons.sell_outlined,
          selectedIcon: Icons.sell,
          screen: MasterPlansScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          category: AppNavigationSection.masterCommercial,
          label: 'Cobranças',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments,
          screen: MasterBillingScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          category: AppNavigationSection.masterCommercial,
          label: 'Contratos',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment,
          screen: MasterContractsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          category: AppNavigationSection.masterCommercial,
          label: 'Pagamentos',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          screen: MasterPaymentSettingsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:integrations'))
        _Destination(
          category: AppNavigationSection.masterOperations,
          label: 'Configurações',
          icon: Icons.settings_outlined,
          selectedIcon: Icons.settings,
          screen: MasterIntegrationsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:support'))
        _Destination(
          category: AppNavigationSection.masterOperations,
          label: 'Suporte',
          icon: Icons.headset_mic_outlined,
          selectedIcon: Icons.headset_mic,
          screen: SupportScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:content'))
        _Destination(
          category: AppNavigationSection.masterContent,
          label: 'Avisos',
          icon: Icons.campaign_outlined,
          selectedIcon: Icons.campaign,
          screen: DashboardContentsScreen(
            session: widget.session,
            title: 'Avisos',
            subtitle: 'Comunicados exibidos no topo da dashboard dos clientes',
            allowedTypes: const ['notice'],
            defaultType: 'notice',
          ),
        ),
      if (isMasterPanel && widget.session.canMaster('master:content'))
        _Destination(
          category: AppNavigationSection.masterContent,
          label: 'Certificados',
          icon: Icons.workspace_premium_outlined,
          selectedIcon: Icons.workspace_premium,
          screen: DashboardContentsScreen(
            session: widget.session,
            title: 'Certificados',
            subtitle: 'Ofertas e links de venda de Certificado Digital A1',
            allowedTypes: const ['certificate'],
            defaultType: 'certificate',
          ),
        ),
      if (isMasterPanel && widget.session.canMaster('master:content'))
        _Destination(
          category: AppNavigationSection.masterContent,
          label: 'Loja',
          icon: Icons.storefront_outlined,
          selectedIcon: Icons.storefront,
          screen: DashboardContentsScreen(
            session: widget.session,
            title: 'Loja',
            subtitle: 'Produtos proprios, afiliados e links para WhatsApp',
            allowedTypes: const ['product', 'affiliate_link'],
            defaultType: 'product',
          ),
        ),
      if (!isMasterPanel) ...[
        if (widget.session.can('dashboard:view'))
          _Destination(
            category: AppNavigationSection.home,
            label: 'Início',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: DashboardScreen(session: widget.session),
          ),
        if (widget.session.can('clients:view'))
          _Destination(
            category: AppNavigationSection.records,
            label: 'Clientes',
            icon: Icons.business_outlined,
            selectedIcon: Icons.business,
            screen: ClientsScreen(session: widget.session),
          ),
        if (widget.session.can('equipments:view') ||
            widget.session.can('monitoring:view'))
          _Destination(
            category: AppNavigationSection.records,
            label: 'Máquinas',
            icon: Icons.computer_outlined,
            selectedIcon: Icons.computer,
            screen: EquipmentsScreen(session: widget.session),
          ),
        if (widget.session.can('service_orders:view'))
          _Destination(
            category: AppNavigationSection.operation,
            label: 'OS',
            icon: Icons.assignment_outlined,
            selectedIcon: Icons.assignment,
            screen: ServiceOrdersScreen(session: widget.session),
          ),
        if (widget.session.hasModule('sales') &&
            (widget.session.can('sales:view') ||
                widget.session.can('sales:manual')))
          _Destination(
            category: AppNavigationSection.operation,
            label: 'Vendas',
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            screen: SalesScreen(session: widget.session),
          ),
        if (widget.session.can('sales:create'))
          _Destination(
            category: AppNavigationSection.operation,
            label: 'PDV',
            icon: Icons.point_of_sale_outlined,
            selectedIcon: Icons.point_of_sale,
            screen: PdvScreen(
              session: widget.session,
              fullscreen: _pdvFullscreen,
              onPdvCashOpenChanged: widget.onPdvCashOpenChanged,
              onPdvFullscreenChanged: (value) {
                setState(() => _pdvFullscreen = value);
              },
            ),
          ),
        if (widget.session.hasModule('cash_closings') &&
            widget.session.can('sales:view'))
          _Destination(
            category: AppNavigationSection.operation,
            label: 'Caixa e tesouraria',
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet,
            screen: CashClosingsScreen(session: widget.session),
          ),
        if (widget.session.can('finance:view') ||
            widget.session.can('finance:receivables:view') ||
            widget.session.can('finance:payables:view'))
          _Destination(
            category: AppNavigationSection.finance,
            label: 'Financeiro',
            icon: Icons.account_balance_outlined,
            selectedIcon: Icons.account_balance,
            screen: FinanceScreen(session: widget.session),
          ),
        if (widget.session.can('products:view') ||
            widget.session.can('stock:view'))
          _Destination(
            category: AppNavigationSection.stock,
            label: 'Estoque',
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            screen: ProductsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('product_promotions') &&
            widget.session.can('products:promotions'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Promoções',
            icon: Icons.sell_outlined,
            selectedIcon: Icons.sell,
            screen: PromotionsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('marketplaces') &&
            widget.session.can('marketplaces:view'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Marketplaces',
            icon: Icons.storefront_outlined,
            selectedIcon: Icons.storefront,
            screen: MarketplacesScreen(session: widget.session),
          ),
        if (widget.session.hasModule('stock_withdrawals') &&
            widget.session.can('stock:withdraw'))
          _Destination(
            category: AppNavigationSection.stock,
            label: 'Baixas',
            icon: Icons.remove_shopping_cart_outlined,
            selectedIcon: Icons.remove_shopping_cart_outlined,
            screen: StockWithdrawalsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('stock_entries') &&
            (widget.session.can('stock:entries:view') ||
                widget.session.can('stock:entries:create') ||
                widget.session.can('stock:entries:confirm')))
          _Destination(
            category: AppNavigationSection.stock,
            label: 'Entradas',
            icon: Icons.input_outlined,
            selectedIcon: Icons.input,
            screen: StockEntriesScreen(session: widget.session),
          ),
        if (widget.session.can('suppliers:view') ||
            widget.session.can('suppliers:create') ||
            widget.session.can('suppliers:update'))
          _Destination(
            category: AppNavigationSection.records,
            label: 'Fornecedores',
            icon: Icons.local_shipping_outlined,
            selectedIcon: Icons.local_shipping,
            screen: SuppliersScreen(session: widget.session),
          ),
        if (widget.session.can('production:view') ||
            widget.session.can('production:create'))
          _Destination(
            category: AppNavigationSection.stock,
            label: 'Produção',
            icon: Icons.precision_manufacturing_outlined,
            selectedIcon: Icons.precision_manufacturing,
            screen: ProductionOrdersScreen(session: widget.session),
          ),
        if (widget.session.can('service_contracts:view') ||
            widget.session.can('service_contracts:manage') ||
            widget.session.can('service_contracts:appointments') ||
            widget.session.can('service_contracts:billing'))
          _Destination(
            category: AppNavigationSection.operation,
            label: 'Contratos',
            icon: Icons.event_note_outlined,
            selectedIcon: Icons.event_note,
            screen: ServiceContractsScreen(session: widget.session),
          ),
        if (widget.session.canUseFiscal &&
            widget.session.can('fiscal:documents:view'))
          _Destination(
            category: AppNavigationSection.fiscal,
            label: 'Notas fiscais',
            icon: Icons.description_outlined,
            selectedIcon: Icons.description,
            screen: _issuingFiscalDocument
                ? EmitirNotaFiscalScreen(
                    session: widget.session,
                    onBack: () =>
                        setState(() => _issuingFiscalDocument = false),
                  )
                : FiscalDocumentsScreen(
                    session: widget.session,
                    onStartIssue: () =>
                        setState(() => _issuingFiscalDocument = true),
                  ),
          ),
        if (widget.session.can('products:view') ||
            widget.session.can('stock:view') ||
            widget.session.can('sales:view') ||
            widget.session.can('finance:view') ||
            widget.session.can('finance:receivables:view') ||
            widget.session.can('finance:payables:view') ||
            widget.session.can('stock:entries:view') ||
            widget.session.can('clients:view'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Relatórios',
            icon: Icons.analytics_outlined,
            selectedIcon: Icons.analytics,
            screen: ReportsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('pdv_windows') &&
            widget.session.can('pdv_operators:manage'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Terminais',
            icon: Icons.devices_other_outlined,
            selectedIcon: Icons.devices_other,
            screen: PdvTerminalsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('pdv_windows') &&
            widget.session.can('pdv_operators:manage'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Op. PDV',
            icon: Icons.badge_outlined,
            selectedIcon: Icons.badge,
            screen: PdvOperatorsScreen(session: widget.session),
          ),
        if (widget.session.can('users:manage'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Usuários',
            icon: Icons.manage_accounts_outlined,
            selectedIcon: Icons.manage_accounts,
            screen: UsersScreen(session: widget.session),
          ),
        if (widget.session.hasModule('support'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Suporte',
            icon: Icons.headset_mic_outlined,
            selectedIcon: Icons.headset_mic,
            screen: SupportScreen(session: widget.session),
          ),
        if (widget.session.hasModule('settings'))
          _Destination(
            category: AppNavigationSection.management,
            label: 'Configurações',
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            screen: SettingsScreen(session: widget.session),
          ),
      ],
    ];

    if (destinations.isEmpty) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.lock_outline, size: 42),
                const SizedBox(height: 12),
                const Text(
                  'Usuário sem acessos liberados.',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: widget.onLogout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Sair'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_selectedIndex >= destinations.length) {
      _selectedIndex = 0;
    }

    final selectedDestination = destinations[_selectedIndex];
    final visibleSections = visibleNavigationSections(
      destinations.map((destination) => destination.category),
    );
    final browsedSection = visibleSections.contains(_browsedSection)
        ? _browsedSection!
        : selectedDestination.category;
    final indexedDestinations = [
      for (var index = 0; index < destinations.length; index++)
        _IndexedDestination(index: index, destination: destinations[index]),
    ];
    final groupedDestinations = groupNavigationItems(
      indexedDestinations,
      (item) => item.destination.category,
    );

    void selectDestination(int index) {
      final destination = destinations[index];
      setState(() {
        if (_selectedIndex != index) _pdvFullscreen = false;
        _selectedIndex = index;
        _browsedSection = destination.category;
        _navigationPanelOpen = false;
      });
    }

    final content = ColoredBox(
      color: const Color(0xFFF2F6FB),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: KeyedSubtree(
          key: ValueKey(_selectedIndex),
          child: selectedDestination.screen,
        ),
      ),
    );

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
          setState(() => _navigationPanelOpen = true);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navigationSearchFocusNode.requestFocus();
          });
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          body: LayoutBuilder(
            builder: (context, constraints) {
              final usePersistentPanel = constraints.maxWidth >= 1180;
              final rail = _PrimaryNavigationRail(
                sections: visibleSections,
                selectedSection: browsedSection,
                onSelect: (section) {
                  final sectionDestinations =
                      groupedDestinations[section] ??
                      const <_IndexedDestination>[];
                  if (sectionDestinations.length == 1) {
                    selectDestination(sectionDestinations.single.index);
                    return;
                  }
                  setState(() {
                    _browsedSection = section;
                    _navigationPanelOpen = true;
                    _navigationSearchController.clear();
                  });
                },
                onLogoTap: () => selectDestination(0),
                onLogout: widget.onLogout,
              );
              final panel = _NavigationSectionPanel(
                section: browsedSection,
                destinations: groupedDestinations,
                selectedIndex: _selectedIndex,
                searchController: _navigationSearchController,
                searchFocusNode: _navigationSearchFocusNode,
                onClose: () => setState(() => _navigationPanelOpen = false),
                onSelect: selectDestination,
              );

              if (_pdvFullscreen) return content;

              if (usePersistentPanel) {
                return Row(
                  children: [
                    rail,
                    AnimatedSize(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: Alignment.centerLeft,
                      child: _navigationPanelOpen
                          ? SizedBox(width: 276, child: panel)
                          : const SizedBox.shrink(),
                    ),
                    Expanded(child: content),
                  ],
                );
              }

              return Stack(
                children: [
                  Row(
                    children: [
                      rail,
                      Expanded(child: content),
                    ],
                  ),
                  if (_navigationPanelOpen) ...[
                    Positioned.fill(
                      left: 72,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () =>
                            setState(() => _navigationPanelOpen = false),
                        child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.18),
                        ),
                      ),
                    ),
                    Positioned(
                      left: 72,
                      top: 0,
                      bottom: 0,
                      width: 276,
                      child: Material(
                        elevation: 18,
                        shadowColor: const Color(0x55081524),
                        child: panel,
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

class _PrimaryNavigationRail extends StatelessWidget {
  const _PrimaryNavigationRail({
    required this.sections,
    required this.selectedSection,
    required this.onSelect,
    required this.onLogoTap,
    required this.onLogout,
  });

  final List<AppNavigationSection> sections;
  final AppNavigationSection selectedSection;
  final ValueChanged<AppNavigationSection> onSelect;
  final VoidCallback onLogoTap;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF0E1827), Color(0xFF142338)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border(right: BorderSide(color: Color(0xFF22395A))),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: onLogoTap,
                child: Container(
                  width: 52,
                  height: 58,
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.025),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.04),
                    ),
                  ),
                  child: Image.asset(
                    'assets/brand/lyncar_logo_clean.png',
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                itemCount: sections.length,
                separatorBuilder: (_, _) => const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final section = sections[index];
                  final selected = section == selectedSection;
                  return _PrimarySectionButton(
                    section: section,
                    selected: selected,
                    onTap: () => onSelect(section),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: IconButton.outlined(
                tooltip: 'Sair',
                onPressed: onLogout,
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFFB6C2D2),
                  side: const BorderSide(color: Color(0xFF3A4A62)),
                ),
                icon: const Icon(Icons.logout),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PrimarySectionButton extends StatelessWidget {
  const _PrimarySectionButton({
    required this.section,
    required this.selected,
    required this.onTap,
  });

  final AppNavigationSection section;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: section.label,
      waitDuration: const Duration(milliseconds: 350),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 50,
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF1E6BE3), Color(0xFF15A7D8)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            borderRadius: BorderRadius.circular(15),
            boxShadow: selected
                ? const [
                    BoxShadow(
                      color: Color(0x331E6BE3),
                      blurRadius: 16,
                      offset: Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Icon(
            selected ? section.selectedIcon : section.icon,
            color: selected ? Colors.white : const Color(0xFF9BAFC7),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _NavigationSectionPanel extends StatefulWidget {
  const _NavigationSectionPanel({
    required this.section,
    required this.destinations,
    required this.selectedIndex,
    required this.searchController,
    required this.searchFocusNode,
    required this.onClose,
    required this.onSelect,
  });

  final AppNavigationSection section;
  final Map<AppNavigationSection, List<_IndexedDestination>> destinations;
  final int selectedIndex;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final VoidCallback onClose;
  final ValueChanged<int> onSelect;

  @override
  State<_NavigationSectionPanel> createState() =>
      _NavigationSectionPanelState();
}

class _NavigationSectionPanelState extends State<_NavigationSectionPanel> {
  @override
  void initState() {
    super.initState();
    widget.searchController.addListener(_refreshSearch);
  }

  @override
  void didUpdateWidget(covariant _NavigationSectionPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.searchController != widget.searchController) {
      oldWidget.searchController.removeListener(_refreshSearch);
      widget.searchController.addListener(_refreshSearch);
    }
  }

  @override
  void dispose() {
    widget.searchController.removeListener(_refreshSearch);
    super.dispose();
  }

  void _refreshSearch() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final query = widget.searchController.text.trim().toLowerCase();
    final visibleDestinations = query.isEmpty
        ? widget.destinations[widget.section] ?? const <_IndexedDestination>[]
        : widget.destinations.values
              .expand((items) => items)
              .where(
                (item) => item.destination.label.toLowerCase().contains(query),
              )
              .toList();

    return ColoredBox(
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          query.isEmpty ? widget.section.eyebrow : 'NAVEGAÇÃO',
                          style: const TextStyle(
                            color: Color(0xFF1672D2),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                        const Gap(4),
                        Text(
                          query.isEmpty ? widget.section.label : 'Resultados',
                          style: const TextStyle(
                            color: Color(0xFF13233B),
                            fontSize: 22,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recolher menu',
                    onPressed: widget.onClose,
                    icon: const Icon(Icons.keyboard_double_arrow_left),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
              child: TextField(
                controller: widget.searchController,
                focusNode: widget.searchFocusNode,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'Buscar uma tela',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: query.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: Text(
                            'Ctrl K',
                            style: TextStyle(
                              color: Color(0xFF6D7D91),
                              fontSize: 10,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        )
                      : IconButton(
                          tooltip: 'Limpar busca',
                          onPressed: widget.searchController.clear,
                          icon: const Icon(Icons.close, size: 18),
                        ),
                  filled: true,
                  fillColor: const Color(0xFFF5F8FC),
                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD9E3EF)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFD9E3EF)),
                  ),
                ),
              ),
            ),
            Expanded(
              child: visibleDestinations.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text(
                          'Nenhuma tela liberada encontrada.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF74859B)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
                      itemCount: visibleDestinations.length,
                      separatorBuilder: (_, _) => const Gap(5),
                      itemBuilder: (context, index) {
                        final item = visibleDestinations[index];
                        final destination = item.destination;
                        final selected = item.index == widget.selectedIndex;
                        return _DestinationButton(
                          destination: destination,
                          selected: selected,
                          showCategory: query.isNotEmpty,
                          onTap: () => widget.onSelect(item.index),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestinationButton extends StatelessWidget {
  const _DestinationButton({
    required this.destination,
    required this.selected,
    required this.showCategory,
    required this.onTap,
  });

  final _Destination destination;
  final bool selected;
  final bool showCategory;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE8F3FF) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 20,
              color: selected
                  ? const Color(0xFF0967C6)
                  : const Color(0xFF657990),
            ),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    destination.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected
                          ? const Color(0xFF075DB3)
                          : const Color(0xFF35485F),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                  if (showCategory)
                    Text(
                      destination.category.label,
                      style: const TextStyle(
                        color: Color(0xFF8796A9),
                        fontSize: 10,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: selected
                  ? const Color(0xFF0967C6)
                  : const Color(0xFF9AA8B8),
            ),
          ],
        ),
      ),
    );
  }
}

class _IndexedDestination {
  const _IndexedDestination({required this.index, required this.destination});

  final int index;
  final _Destination destination;
}

class _Destination {
  const _Destination({
    required this.category,
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final AppNavigationSection category;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}
