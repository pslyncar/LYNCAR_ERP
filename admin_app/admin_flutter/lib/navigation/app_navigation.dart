import 'package:flutter/material.dart';

enum AppNavigationSection {
  home(
    label: 'Início',
    eyebrow: 'Principal',
    icon: Icons.space_dashboard_outlined,
    selectedIcon: Icons.space_dashboard,
  ),
  operation(
    label: 'Operação',
    eyebrow: 'Dia a dia',
    icon: Icons.shopping_cart_outlined,
    selectedIcon: Icons.shopping_cart,
  ),
  records(
    label: 'Cadastros',
    eyebrow: 'Base da empresa',
    icon: Icons.contact_page_outlined,
    selectedIcon: Icons.contact_page,
  ),
  stock(
    label: 'Estoque',
    eyebrow: 'Estoque e produção',
    icon: Icons.inventory_2_outlined,
    selectedIcon: Icons.inventory_2,
  ),
  finance(
    label: 'Financeiro',
    eyebrow: 'Controle financeiro',
    icon: Icons.account_balance_outlined,
    selectedIcon: Icons.account_balance,
  ),
  fiscal(
    label: 'Fiscal',
    eyebrow: 'Documentos fiscais',
    icon: Icons.receipt_long_outlined,
    selectedIcon: Icons.receipt_long,
  ),
  management(
    label: 'Gestão',
    eyebrow: 'Gestão e canais',
    icon: Icons.insights_outlined,
    selectedIcon: Icons.insights,
  ),
  masterCustomers(
    label: 'Clientes',
    eyebrow: 'Painel Master',
    icon: Icons.apartment_outlined,
    selectedIcon: Icons.apartment,
  ),
  masterCommercial(
    label: 'Comercial',
    eyebrow: 'Painel Master',
    icon: Icons.sell_outlined,
    selectedIcon: Icons.sell,
  ),
  masterAccess(
    label: 'Acessos',
    eyebrow: 'Painel Master',
    icon: Icons.admin_panel_settings_outlined,
    selectedIcon: Icons.admin_panel_settings,
  ),
  masterPdv(
    label: 'PDV Windows',
    eyebrow: 'Painel Master',
    icon: Icons.desktop_windows_outlined,
    selectedIcon: Icons.desktop_windows,
  ),
  masterContent(
    label: 'Conteúdo',
    eyebrow: 'Painel Master',
    icon: Icons.dynamic_feed_outlined,
    selectedIcon: Icons.dynamic_feed,
  ),
  masterOperations(
    label: 'Administração',
    eyebrow: 'Painel Master',
    icon: Icons.tune_outlined,
    selectedIcon: Icons.tune,
  );

  const AppNavigationSection({
    required this.label,
    required this.eyebrow,
    required this.icon,
    required this.selectedIcon,
  });

  final String label;
  final String eyebrow;
  final IconData icon;
  final IconData selectedIcon;
}

List<AppNavigationSection> visibleNavigationSections(
  Iterable<AppNavigationSection> sections,
) {
  final visible = <AppNavigationSection>{};
  for (final section in sections) {
    visible.add(section);
  }
  return [
    for (final section in AppNavigationSection.values)
      if (visible.contains(section)) section,
  ];
}

Map<AppNavigationSection, List<T>> groupNavigationItems<T>(
  Iterable<T> items,
  AppNavigationSection Function(T item) sectionOf,
) {
  final grouped = <AppNavigationSection, List<T>>{};
  for (final item in items) {
    grouped.putIfAbsent(sectionOf(item), () => <T>[]).add(item);
  }
  return grouped;
}
