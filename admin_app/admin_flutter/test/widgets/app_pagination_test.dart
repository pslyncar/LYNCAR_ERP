import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:papezzosync_admin/widgets/app_pagination.dart';

void main() {
  testWidgets('shows twenty records per page and changes pages', (
    tester,
  ) async {
    var selectedPage = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPagination(
            currentPage: selectedPage,
            totalItems: 45,
            pageSize: 20,
            itemLabel: 'produtos',
            onPageChanged: (page) => selectedPage = page,
          ),
        ),
      ),
    );

    expect(find.text('Mostrando 1–20 de 45 produtos'), findsOneWidget);
    expect(find.byKey(const Key('app-pagination-page-1')), findsOneWidget);
    expect(find.byKey(const Key('app-pagination-page-2')), findsOneWidget);
    expect(find.byKey(const Key('app-pagination-page-3')), findsOneWidget);

    await tester.tap(find.byKey(const Key('app-pagination-page-2')));
    expect(selectedPage, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fits pagination controls on a narrow layout', (tester) async {
    tester.view.physicalSize = const Size(520, 600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: AppPagination(
            currentPage: 4,
            totalItems: 400,
            itemLabel: 'clientes',
            onPageChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Mostrando 81–100 de 400 clientes'), findsOneWidget);
    expect(find.text('…'), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
