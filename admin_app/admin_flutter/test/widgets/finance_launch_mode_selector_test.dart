import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/widgets/finance_launch_mode_selector.dart';

void main() {
  testWidgets('changes mode without overflowing on a narrow dialog', (
    tester,
  ) async {
    var selected = 'products';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            child: StatefulBuilder(
              builder: (context, setState) => FinanceLaunchModeSelector(
                selected: selected,
                onChanged: (value) => setState(() => selected = value),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(-180, 0),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Serviço'));
    await tester.pumpAndSettle();

    expect(selected, 'service');
    expect(tester.takeException(), isNull);
  });
}
