import 'package:flutter_test/flutter_test.dart';
import 'package:papezzosync_admin/app.dart';

void main() {
  testWidgets('shows login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const PapezzoSyncAdminApp());

    expect(find.text('LOGIN'), findsWidgets);
    expect(find.text('Usuario'), findsOneWidget);
    expect(find.text('Senha'), findsWidgets);
  });
}
