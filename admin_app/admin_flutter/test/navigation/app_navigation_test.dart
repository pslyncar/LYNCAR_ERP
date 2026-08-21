import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/navigation/app_navigation.dart';

void main() {
  group('app navigation grouping', () {
    test('shows only sections that have already-authorized destinations', () {
      final sections = visibleNavigationSections(const [
        AppNavigationSection.fiscal,
        AppNavigationSection.home,
        AppNavigationSection.fiscal,
      ]);

      expect(sections, const [
        AppNavigationSection.home,
        AppNavigationSection.fiscal,
      ]);
      expect(sections, isNot(contains(AppNavigationSection.finance)));
    });

    test('preserves every destination exactly once while grouping', () {
      const destinations = [
        ('PDV', AppNavigationSection.operation),
        ('Clientes', AppNavigationSection.records),
        ('Notas fiscais', AppNavigationSection.fiscal),
        ('Vendas', AppNavigationSection.operation),
      ];

      final grouped = groupNavigationItems(
        destinations,
        (destination) => destination.$2,
      );
      final regrouped = grouped.values.expand((items) => items).toList();

      expect(regrouped, hasLength(destinations.length));
      expect(regrouped.toSet(), destinations.toSet());
      expect(grouped[AppNavigationSection.operation]?.map((item) => item.$1), [
        'PDV',
        'Vendas',
      ]);
    });
  });
}
