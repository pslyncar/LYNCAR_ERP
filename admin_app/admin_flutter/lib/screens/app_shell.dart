import 'package:flutter/material.dart';
import 'package:gap/gap.dart';

import '../models/session.dart';
import 'cash_closings_screen.dart';
import 'clients_screen.dart';
import 'companies_screen.dart';
import 'dashboard_contents_screen.dart';
import 'dashboard_screen.dart';
import 'equipments_screen.dart';
import 'finance_screen.dart';
import 'fiscal_documents_screen.dart';
import 'master_access_screen.dart';
import 'master_billing_screen.dart';
import 'master_contracts_screen.dart';
import 'master_payment_settings_screen.dart';
import 'master_pdv_terminals_screen.dart';
import 'master_plans_screen.dart';
import 'master_staff_screen.dart';
import 'master_website_contacts_screen.dart';
import 'pdv_operators_screen.dart';
import 'pdv_screen.dart';
import 'pdv_terminals_screen.dart';
import 'products_screen.dart';
import 'production_orders_screen.dart';
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
  bool _menuHovered = false;

  @override
  Widget build(BuildContext context) {
    final canHoverExpand = MediaQuery.sizeOf(context).width >= 760;
    final extended = canHoverExpand && _menuHovered;
    final isMasterPanel = widget.session.isMasterCompany;
    final destinations = [
      if (isMasterPanel && widget.session.canMaster('master:companies'))
        _Destination(
          label: 'Empresas',
          icon: Icons.apartment_outlined,
          selectedIcon: Icons.apartment,
          screen: CompaniesScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:companies'))
        _Destination(
          label: 'Contatos do site',
          icon: Icons.contact_phone_outlined,
          selectedIcon: Icons.contact_phone,
          screen: MasterWebsiteContactsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:companies'))
        _Destination(
          label: 'Acessos',
          icon: Icons.people_alt_outlined,
          selectedIcon: Icons.people_alt,
          screen: MasterAccessScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:staff'))
        _Destination(
          label: 'Equipe',
          icon: Icons.admin_panel_settings_outlined,
          selectedIcon: Icons.admin_panel_settings,
          screen: MasterStaffScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:pdv_terminals'))
        _Destination(
          label: 'Terminais PDV',
          icon: Icons.devices_other_outlined,
          selectedIcon: Icons.devices_other,
          screen: MasterPdvTerminalsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          label: 'Planos e Segmentos',
          icon: Icons.sell_outlined,
          selectedIcon: Icons.sell,
          screen: MasterPlansScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          label: 'Cobranças',
          icon: Icons.payments_outlined,
          selectedIcon: Icons.payments,
          screen: MasterBillingScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          label: 'Contratos',
          icon: Icons.assignment_outlined,
          selectedIcon: Icons.assignment,
          screen: MasterContractsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:billing'))
        _Destination(
          label: 'Pagamentos',
          icon: Icons.account_balance_wallet_outlined,
          selectedIcon: Icons.account_balance_wallet,
          screen: MasterPaymentSettingsScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:support'))
        _Destination(
          label: 'Suporte',
          icon: Icons.headset_mic_outlined,
          selectedIcon: Icons.headset_mic,
          screen: SupportScreen(session: widget.session),
        ),
      if (isMasterPanel && widget.session.canMaster('master:content'))
        _Destination(
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
            label: 'Início',
            icon: Icons.dashboard_outlined,
            selectedIcon: Icons.dashboard,
            screen: DashboardScreen(session: widget.session),
          ),
        if (widget.session.can('clients:view'))
          _Destination(
            label: 'Clientes',
            icon: Icons.business_outlined,
            selectedIcon: Icons.business,
            screen: ClientsScreen(session: widget.session),
          ),
        if (widget.session.can('equipments:view') ||
            widget.session.can('monitoring:view'))
          _Destination(
            label: 'Máquinas',
            icon: Icons.computer_outlined,
            selectedIcon: Icons.computer,
            screen: EquipmentsScreen(session: widget.session),
          ),
        if (widget.session.can('service_orders:view'))
          _Destination(
            label: 'OS',
            icon: Icons.assignment_outlined,
            selectedIcon: Icons.assignment,
            screen: ServiceOrdersScreen(session: widget.session),
          ),
        if (widget.session.hasModule('sales') &&
            widget.session.can('sales:view'))
          _Destination(
            label: 'Vendas',
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long,
            screen: SalesScreen(session: widget.session),
          ),
        if (widget.session.can('sales:create'))
          _Destination(
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
            label: 'Caixa',
            icon: Icons.account_balance_wallet_outlined,
            selectedIcon: Icons.account_balance_wallet,
            screen: CashClosingsScreen(session: widget.session),
          ),
        if (widget.session.can('finance:view') ||
            widget.session.can('finance:receivables:view') ||
            widget.session.can('finance:payables:view'))
          _Destination(
            label: 'Financeiro',
            icon: Icons.account_balance_outlined,
            selectedIcon: Icons.account_balance,
            screen: FinanceScreen(session: widget.session),
          ),
        if (widget.session.can('products:view') ||
            widget.session.can('stock:view'))
          _Destination(
            label: 'Estoque',
            icon: Icons.inventory_2_outlined,
            selectedIcon: Icons.inventory_2,
            screen: ProductsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('stock_withdrawals') &&
            widget.session.can('stock:withdraw'))
          _Destination(
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
            label: 'Entradas',
            icon: Icons.input_outlined,
            selectedIcon: Icons.input,
            screen: StockEntriesScreen(session: widget.session),
          ),
        if (widget.session.can('suppliers:view') ||
            widget.session.can('suppliers:create') ||
            widget.session.can('suppliers:update'))
          _Destination(
            label: 'Fornecedores',
            icon: Icons.local_shipping_outlined,
            selectedIcon: Icons.local_shipping,
            screen: SuppliersScreen(session: widget.session),
          ),
        if (widget.session.can('production:view') ||
            widget.session.can('production:create'))
          _Destination(
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
            label: 'Contratos',
            icon: Icons.event_note_outlined,
            selectedIcon: Icons.event_note,
            screen: ServiceContractsScreen(session: widget.session),
          ),
        if (widget.session.canUseFiscal &&
            widget.session.can('fiscal:documents:view'))
          _Destination(
            label: 'Notas fiscais',
            icon: Icons.description_outlined,
            selectedIcon: Icons.description,
            screen: FiscalDocumentsScreen(session: widget.session),
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
            label: 'Relatórios',
            icon: Icons.analytics_outlined,
            selectedIcon: Icons.analytics,
            screen: ReportsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('pdv_windows') &&
            widget.session.can('pdv_operators:manage'))
          _Destination(
            label: 'Terminais',
            icon: Icons.devices_other_outlined,
            selectedIcon: Icons.devices_other,
            screen: PdvTerminalsScreen(session: widget.session),
          ),
        if (widget.session.hasModule('pdv_windows') &&
            widget.session.can('pdv_operators:manage'))
          _Destination(
            label: 'Op. PDV',
            icon: Icons.badge_outlined,
            selectedIcon: Icons.badge,
            screen: PdvOperatorsScreen(session: widget.session),
          ),
        if (widget.session.can('users:manage'))
          _Destination(
            label: 'Usuários',
            icon: Icons.manage_accounts_outlined,
            selectedIcon: Icons.manage_accounts,
            screen: UsersScreen(session: widget.session),
          ),
        if (widget.session.hasModule('support'))
          _Destination(
            label: 'Suporte',
            icon: Icons.headset_mic_outlined,
            selectedIcon: Icons.headset_mic,
            screen: SupportScreen(session: widget.session),
          ),
        if (widget.session.hasModule('settings'))
          _Destination(
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

    return Scaffold(
      body: Row(
        children: [
          MouseRegion(
            onEnter: (_) {
              if (canHoverExpand) setState(() => _menuHovered = true);
            },
            onExit: (_) {
              if (canHoverExpand) setState(() => _menuHovered = false);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              width: _pdvFullscreen ? 0 : (extended ? 236 : 68),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF0E1827), Color(0xFF142338)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
                border: Border(right: BorderSide(color: Color(0xFF22395A))),
              ),
              child: Offstage(
                offstage: _pdvFullscreen,
                child: _SideMenu(
                  extended: extended,
                  destinations: destinations,
                  selectedIndex: _selectedIndex,
                  onSelect: (index) {
                    if (_selectedIndex != index) {
                      setState(() => _pdvFullscreen = false);
                    }
                    setState(() => _selectedIndex = index);
                  },
                  onLogoTap: () => setState(() => _selectedIndex = 0),
                  onLogout: widget.onLogout,
                ),
              ),
            ),
          ),
          Expanded(
            child: ColoredBox(
              color: const Color(0xFFF2F6FB),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                child: KeyedSubtree(
                  key: ValueKey(_selectedIndex),
                  child: destinations[_selectedIndex].screen,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SideMenu extends StatelessWidget {
  const _SideMenu({
    required this.extended,
    required this.destinations,
    required this.selectedIndex,
    required this.onSelect,
    required this.onLogoTap,
    required this.onLogout,
  });

  final bool extended;
  final List<_Destination> destinations;
  final int selectedIndex;
  final ValueChanged<int> onSelect;
  final VoidCallback onLogoTap;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final showExtended = extended && constraints.maxWidth >= 180;

        return SafeArea(
          child: Column(
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  14,
                  16,
                  showExtended ? 14 : 10,
                ),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onLogoTap,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.025),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.035),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: showExtended ? 12 : 8,
                        vertical: showExtended ? 12 : 8,
                      ),
                      child: Image.asset(
                        'assets/brand/lyncar_logo_clean.png',
                        width: showExtended ? 112 : 42,
                        height: showExtended ? 58 : 42,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Scrollbar(
                  thumbVisibility: true,
                  thickness: showExtended ? 5 : 3,
                  radius: const Radius.circular(999),
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
                    itemCount: destinations.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 6),
                    itemBuilder: (context, index) {
                      final destination = destinations[index];
                      final selected = index == selectedIndex;
                      return _SideMenuItem(
                        extended: showExtended,
                        selected: selected,
                        icon: selected
                            ? destination.selectedIcon
                            : destination.icon,
                        label: destination.label,
                        onTap: () => onSelect(index),
                      );
                    },
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                child: showExtended
                    ? SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: onLogout,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFB6C2D2),
                            side: const BorderSide(color: Color(0xFF3A4A62)),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.logout, size: 18),
                          label: const Text(
                            'Sair',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      )
                    : IconButton.outlined(
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
        );
      },
    );
  }
}

class _SideMenuItem extends StatelessWidget {
  const _SideMenuItem({
    required this.extended,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final bool extended;
  final bool selected;
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: extended ? '' : label,
      waitDuration: const Duration(milliseconds: 450),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 42,
          padding: EdgeInsets.symmetric(horizontal: extended ? 13 : 0),
          decoration: BoxDecoration(
            gradient: selected
                ? const LinearGradient(
                    colors: [Color(0xFF1E6BE3), Color(0xFF15A7D8)],
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                  )
                : null,
            color: selected ? null : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
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
          child: Row(
            mainAxisAlignment: extended
                ? MainAxisAlignment.start
                : MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: selected ? Colors.white : const Color(0xFF9BAFC7),
                size: 22,
              ),
              if (extended) ...[
                const Gap(13),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: selected ? Colors.white : const Color(0xFFB6C2D2),
                      fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Destination {
  const _Destination({
    required this.label,
    required this.icon,
    required this.selectedIcon,
    required this.screen,
  });

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}
